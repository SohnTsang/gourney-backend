import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

/**
 * Monitor Worker - Stub for performance monitoring
 * Will track p95 latencies and queue backlogs
 * 
 * In production, this would:
 * 1. Check p95 latencies for /feed and /places/search
 * 2. Monitor push_queue backlog
 * 3. Send alerts via webhook when thresholds exceeded
 */

interface MonitorConfig {
  latencyThresholdMs: number;
  latencyDurationMinutes: number;
  queueBacklogThreshold: number;
  queueAgeThresholdMinutes: number;
  alertWebhook?: string;
}

const DEFAULT_CONFIG: MonitorConfig = {
  latencyThresholdMs: 800,
  latencyDurationMinutes: 10,
  queueBacklogThreshold: 1000,
  queueAgeThresholdMinutes: 10
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Get config from remote_config (or use defaults)
    const { data: configData } = await supabase
      .from('remote_config')
      .select('config')
      .single();
    
    const monitorConfig = configData?.config?.monitoring || DEFAULT_CONFIG;
    
    const alerts: string[] = [];
    
    // 1. Check push_queue backlog
    const { data: queueStats } = await supabase
      .rpc('get_push_queue_stats');
    
    if (queueStats) {
      const { total_queued, oldest_minutes } = queueStats;
      
      if (total_queued > monitorConfig.queueBacklogThreshold) {
        alerts.push(
          `⚠️ Push queue backlog: ${total_queued} items (threshold: ${monitorConfig.queueBacklogThreshold})`
        );
      }
      
      if (oldest_minutes > monitorConfig.queueAgeThresholdMinutes) {
        alerts.push(
          `⚠️ Push queue delay: oldest job ${oldest_minutes}min old (threshold: ${monitorConfig.queueAgeThresholdMinutes}min)`
        );
      }
    }
    
    // 2. Check API latencies (stub - would read from metrics table)
    // In production, this would query a metrics table populated by edge functions
    const mockLatencyCheck = {
      feed_p95: 650,
      search_p95: 720,
      threshold: monitorConfig.latencyThresholdMs
    };
    
    if (mockLatencyCheck.feed_p95 > monitorConfig.latencyThresholdMs) {
      alerts.push(
        `⚠️ /feed p95 latency: ${mockLatencyCheck.feed_p95}ms (threshold: ${monitorConfig.latencyThresholdMs}ms)`
      );
    }
    
    if (mockLatencyCheck.search_p95 > monitorConfig.latencyThresholdMs) {
      alerts.push(
        `⚠️ /places/search p95 latency: ${mockLatencyCheck.search_p95}ms (threshold: ${monitorConfig.latencyThresholdMs}ms)`
      );
    }
    
    // 3. Log results
    const timestamp = new Date().toISOString();
    console.log('Monitor check completed', {
      timestamp,
      alerts: alerts.length,
      queueStats,
      latencyCheck: mockLatencyCheck
    });
    
    // 4. Send alerts if any (stub - would use webhook)
    if (alerts.length > 0 && monitorConfig.alertWebhook) {
      // In production: await sendWebhookAlert(monitorConfig.alertWebhook, alerts);
      console.warn('ALERTS TRIGGERED:', alerts);
    }
    
    // 5. Store monitor result for dashboard
    await supabase.from('monitor_logs').insert({
      timestamp,
      alert_count: alerts.length,
      alerts: alerts.length > 0 ? alerts : null,
      metrics: {
        queue_backlog: queueStats?.total_queued || 0,
        queue_age_minutes: queueStats?.oldest_minutes || 0,
        feed_p95: mockLatencyCheck.feed_p95,
        search_p95: mockLatencyCheck.search_p95
      }
    });
    
    return new Response(
      JSON.stringify({
        success: true,
        timestamp,
        alerts,
        metrics: {
          queue: queueStats,
          latency: mockLatencyCheck
        }
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    );
  } catch (error) {
    console.error('Monitor worker error:', error);
    return new Response(
      JSON.stringify({
        error: error.message,
        timestamp: new Date().toISOString()
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      }
    );
  }
});

/**
 * Helper function to create the monitoring stats RPC
 * Add this to your migrations:
 * 
 * CREATE OR REPLACE FUNCTION get_push_queue_stats()
 * RETURNS TABLE(total_queued bigint, oldest_minutes numeric)
 * LANGUAGE plpgsql
 * SECURITY DEFINER
 * AS $$
 * BEGIN
 *   RETURN QUERY
 *   SELECT 
 *     COUNT(*) as total_queued,
 *     EXTRACT(EPOCH FROM (NOW() - MIN(created_at)))/60 as oldest_minutes
 *   FROM push_queue
 *   WHERE status = 'queued';
 * END;
 * $$;
 */