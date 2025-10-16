// supabase/functions/pushWorker/index.ts
// STUB for Week 1 - Empty loop that logs but doesn't process
// Full implementation in Week 6 with queue processing

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-api-version',
};

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

    // STUB: Check how many jobs are in the queue but don't process them
    const { count } = await supabase
      .from('push_queue')
      .select('*', { count: 'exact', head: true })
      .eq('status', 'queued')
      .lte('deliver_after', new Date().toISOString());

    console.log('[STUB] pushWorker - Queue check:', {
      queued_count: count,
      timestamp: new Date().toISOString(),
      note: 'Not processing - stub only'
    });

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Push worker stub - checked queue but did not process',
        queued_count: count,
        processed: 0,
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
    console.error('Error in pushWorker stub:', error);
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
 * WEEK 1 STUB - This is a placeholder
 * 
 * Week 6 will implement:
 * - Pull due jobs (status='queued' AND deliver_after <= now)
 * - For each job:
 *   - Fetch user's device tokens (matching env)
 *   - Check quiet_hours using device tz
 *   - If in quiet hours, skip and reschedule
 *   - Rate-limit friend_visit (max 1/hour per recipient)
 *   - Call sendPush to send actual APNs
 *   - On success: status='sent'
 *   - On transient error: increment tries, exponential backoff
 *   - On 410/Unregistered: delete device token
 *   - On permanent error or max tries: status='failed'
 * - Run on cron schedule (e.g., every 1 minute)
 */