// supabase/functions/signupGuard/index.ts
// Per-IP signup throttle using Postgres
// Prevents abuse by limiting signups to 10/hour per IP

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-api-version',
};

const SIGNUP_LIMIT = 10;        // Max signups per window
const WINDOW_MINUTES = 60;      // 1 hour window

interface SignupCheckResponse {
  allowed: boolean;
  limit: number;
  current: number;
  retryAfter?: number; // seconds
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Get client IP address
    let clientIp = req.headers.get('x-forwarded-for')?.split(',')[0].trim() 
                 || req.headers.get('x-real-ip')
                 || 'unknown';

    // Allow override from request body (for testing)
    const body = await req.json().catch(() => ({}));
    if (body.ip) {
      clientIp = body.ip;
    }

    if (clientIp === 'unknown') {
      return new Response(
        JSON.stringify({ error: 'Unable to determine IP address' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Calculate window start time (1 hour ago)
    const windowStart = new Date();
    windowStart.setMinutes(windowStart.getMinutes() - WINDOW_MINUTES);

    // First, clean up old entries (older than 2 hours)
    const cleanupTime = new Date();
    cleanupTime.setMinutes(cleanupTime.getMinutes() - (WINDOW_MINUTES * 2));
    
    await supabase
      .from('signup_throttle')
      .delete()
      .lt('created_at', cleanupTime.toISOString());

    // Count signups from this IP in the current window
    const { count } = await supabase
      .from('signup_throttle')
      .select('*', { count: 'exact', head: true })
      .eq('ip_address', clientIp)
      .gte('created_at', windowStart.toISOString());

    const currentCount = count ?? 0;
    const allowed = currentCount < SIGNUP_LIMIT;

    let retryAfter: number | undefined;
    
    if (!allowed) {
      // Find oldest signup in window to calculate retry time
      const { data: oldestSignup } = await supabase
        .from('signup_throttle')
        .select('created_at')
        .eq('ip_address', clientIp)
        .gte('created_at', windowStart.toISOString())
        .order('created_at', { ascending: true })
        .limit(1)
        .single();

      if (oldestSignup) {
        const oldestTime = new Date(oldestSignup.created_at).getTime();
        const expiresAt = oldestTime + (WINDOW_MINUTES * 60 * 1000);
        retryAfter = Math.ceil((expiresAt - Date.now()) / 1000);
      }
    } else {
      // Record this signup attempt
      await supabase
        .from('signup_throttle')
        .insert({
          ip_address: clientIp,
          created_at: new Date().toISOString()
        });
    }

    const response: SignupCheckResponse = {
      allowed,
      limit: SIGNUP_LIMIT,
      current: currentCount,
      retryAfter
    };

    const status = allowed ? 200 : 429;
    const headers: Record<string, string> = {
      ...corsHeaders,
      'Content-Type': 'application/json',
      'X-RateLimit-Limit': SIGNUP_LIMIT.toString(),
      'X-RateLimit-Remaining': Math.max(0, SIGNUP_LIMIT - currentCount).toString(),
    };

    if (retryAfter) {
      headers['Retry-After'] = retryAfter.toString();
    }

    return new Response(
      JSON.stringify(response),
      { status, headers }
    );

  } catch (error) {
    console.error('Error in signupGuard:', error);
    return new Response(
      JSON.stringify({ 
        error: error instanceof Error ? error.message : 'Unknown error',
        // Fail open - allow signup on error
        allowed: true,
        limit: SIGNUP_LIMIT,
        current: 0
      }),
      { 
        status: 200,
        headers: { 
          ...corsHeaders, 
          'Content-Type': 'application/json' 
        } 
      }
    );
  }
});

/**
 * REQUIRES MIGRATION:
 * Run this SQL to create the signup_throttle table:
 * 
 * CREATE TABLE IF NOT EXISTS public.signup_throttle (
 *   id bigserial PRIMARY KEY,
 *   ip_address text NOT NULL,
 *   created_at timestamptz NOT NULL DEFAULT now()
 * );
 * 
 * CREATE INDEX idx_signup_throttle_ip_time ON public.signup_throttle(ip_address, created_at DESC);
 * 
 * -- Enable RLS but no policies (service_role only)
 * ALTER TABLE public.signup_throttle ENABLE ROW LEVEL SECURITY;
 * ALTER TABLE public.signup_throttle FORCE ROW LEVEL SECURITY;
 */