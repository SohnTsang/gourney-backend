import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { rateLimitGuard, rateLimitResponse } from "../_shared/rateLimitGuard.ts";

serve(async (req) => {
  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Test with one of your test users
    const userId = '11111111-1111-1111-1111-111111111111'; // Alice from RLS tests
    
    const result = await rateLimitGuard(
      supabase,
      userId,
      'visits_per_day'
    );

    if (!result.allowed) {
      return rateLimitResponse(result);
    }

    return new Response(JSON.stringify({
      message: 'Rate limit check passed',
      result
    }), {
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (error) {
    return new Response(JSON.stringify({ 
      error: error instanceof Error ? error.message : 'Unknown error' 
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
});