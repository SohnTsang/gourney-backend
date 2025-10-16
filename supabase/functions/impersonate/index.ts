// supabase/functions/impersonate/index.ts
// STUB for Week 1 - Admin impersonation placeholder
// Full implementation in Week 6 with proper admin auth checking

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-api-version',
};

interface ImpersonateRequest {
  target_user_id: string;
  admin_email?: string; // Optional for Week 1 testing
  reason?: string;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Parse request
    const body: ImpersonateRequest = await req.json();
    const { target_user_id, admin_email, reason } = body;

    if (!target_user_id) {
      return new Response(
        JSON.stringify({ error: 'target_user_id is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // WEEK 1 STUB: Use provided admin_email or default
    // Week 6 will extract this from validated JWT
    const adminUser = {
      id: 'stub-admin-id',
      email: admin_email || 'admin@test.com'
    };

    // Verify target user exists
    const { data: targetUser, error: userError } = await supabase
      .from('users')
      .select('id, handle, display_name')
      .eq('id', target_user_id)
      .single();

    if (userError || !targetUser) {
      return new Response(
        JSON.stringify({ error: 'Target user not found', details: userError?.message }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Log to admin_audit table
    const { error: auditError } = await supabase
      .from('admin_audit')
      .insert({
        admin_user: adminUser.id,
        action: 'impersonate',
        details: {
          target_user_id,
          target_handle: targetUser.handle,
          admin_email: adminUser.email,
          reason: reason || 'TestFlight support',
          timestamp: new Date().toISOString(),
          note: 'Week 1 stub - no JWT validation'
        }
      });

    if (auditError) {
      console.error('Failed to log audit:', auditError);
    }

    // STUB: Log but don't actually create impersonation session
    console.log('[STUB] Impersonation requested:', {
      admin_email: adminUser.email,
      target_user_id,
      target_handle: targetUser.handle,
      reason,
      timestamp: new Date().toISOString()
    });

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Impersonation stub - logged to admin_audit but no session created',
        admin_user: adminUser.email,
        target_user: {
          id: targetUser.id,
          handle: targetUser.handle,
          display_name: targetUser.display_name
        },
        note: 'Week 1 stub - full implementation in Week 6'
      }),
      { 
        status: 200,
        headers: { 
          ...corsHeaders, 
          'Content-Type': 'application/json' 
        } 
      }
    );

  } catch (error) {
    console.error('Error in impersonate stub:', error);
    return new Response(
      JSON.stringify({ 
        error: error instanceof Error ? error.message : 'Unknown error',
        success: false
      }),
      { 
        status: 500,
        headers: { 
          ...corsHeaders, 
          'Content-Type': 'application/json' 
        } 
      }
    );
  }
});

/**
 * WEEK 1 STUB - No authentication required
 * 
 * Week 6 will implement:
 * - Proper JWT validation with admin role checking
 * - Create actual impersonation session/token for target user
 * - Set session expiration (e.g., 1 hour)
 * - Return session token that iOS app can use
 * 
 * USAGE (Week 1 stub):
 * POST /functions/v1/impersonate
 * Body: {
 *   "target_user_id": "11111111-1111-1111-1111-111111111111",
 *   "admin_email": "your@email.com",
 *   "reason": "TestFlight support - testing feature"
 * }
 */