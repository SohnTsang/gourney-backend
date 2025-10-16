// supabase/functions/slow-query-sampler/index.ts
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const handler = async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Verify service role authentication
    const authHeader = req.headers.get('Authorization');
    if (!authHeader || !authHeader.includes(Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized - service role required' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    
    const supabase = createClient(supabaseUrl, supabaseKey);

    console.log('Starting slow query sample...');

    const { data: slowQueries, error } = await supabase.rpc('get_slow_queries', {
      threshold_ms: 500,
      limit_results: 50
    });

    if (error) {
      console.error('Error fetching slow queries:', error);
      
      if (error.message.includes('function public.get_slow_queries')) {
        return new Response(
          JSON.stringify({ 
            error: 'RPC function not found', 
            message: 'Run migration: 20251004_slow_query_rpc.sql',
            details: error.message 
          }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
      
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const queryCount = slowQueries?.length || 0;
    console.log(`Found ${queryCount} slow queries`);

    if (slowQueries && queryCount > 0) {
      const alerts = slowQueries.map((q: any) => 
        `Query: ${q.query.substring(0, 100)}... | Avg: ${Math.round(q.mean_exec_time_ms)}ms | Calls: ${q.calls}`
      );

      const { error: insertError } = await supabase
        .from('monitor_logs')
        .insert({
          alert_count: queryCount,
          alerts: alerts,
          metrics: {
            threshold_ms: 500,
            slow_query_count: queryCount,
            sample_time: new Date().toISOString(),
            queries: slowQueries.slice(0, 10)
          }
        });

      if (insertError) {
        console.error('Error logging to monitor_logs:', insertError);
      } else {
        console.log('Successfully logged slow queries to monitor_logs');
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        slow_query_count: queryCount,
        threshold_ms: 500,
        sampled_at: new Date().toISOString(),
        queries: slowQueries || []
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );

  } catch (error) {
    console.error('Slow query sampler error:', error);
    return new Response(
      JSON.stringify({ 
        error: 'Internal server error',
        message: error.message,
        stack: error.stack
      }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
};

serve(handler);