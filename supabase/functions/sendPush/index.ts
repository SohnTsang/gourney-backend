// supabase/functions/sendPush/index.ts
// STUB for Week 1 - Push notification placeholder
// Full implementation in Week 6 with APNs integration

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-api-version',
};

interface PushRequest {
  userId: string;
  type: 'new_follower' | 'friend_visit';
  payload: Record<string, unknown>;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body: PushRequest = await req.json();
    
    // STUB: Log the request but don't actually send push
    console.log('[STUB] sendPush called:', {
      userId: body.userId,
      type: body.type,
      payload: body.payload,
      timestamp: new Date().toISOString()
    });

    // Return success (stub always succeeds)
    return new Response(
      JSON.stringify({
        success: true,
        message: 'Push notification stub - logged but not sent',
        userId: body.userId,
        type: body.type
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
    console.error('Error in sendPush stub:', error);
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
 * - Fetch user's device tokens from devices table
 * - Check quiet_hours and timezone
 * - Send actual APNs HTTP/2 request with token auth
 * - Handle 410/Unregistered responses
 * - Update push_queue status
 */