-- 20251004_slow_query_rpc.sql
-- FINAL FIX: pg_stat_statements is in gis schema on Supabase


CREATE OR REPLACE FUNCTION public.get_slow_queries(
  threshold_ms numeric DEFAULT 500,
  limit_results int DEFAULT 50
)
RETURNS TABLE(
  query text,
  calls bigint,
  mean_exec_time_ms numeric,
  max_exec_time_ms numeric,
  total_exec_time_ms numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = gis, public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    pss.query::text,
    pss.calls,
    round((pss.mean_exec_time)::numeric, 2) as mean_exec_time_ms,
    round((pss.max_exec_time)::numeric, 2) as max_exec_time_ms,
    round((pss.total_exec_time)::numeric, 2) as total_exec_time_ms
  FROM gis.pg_stat_statements pss
  WHERE pss.mean_exec_time > threshold_ms
    AND pss.query NOT LIKE '%pg_stat_statements%'
  ORDER BY pss.mean_exec_time DESC
  LIMIT limit_results;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_slow_queries TO service_role;

COMMENT ON FUNCTION public.get_slow_queries IS 
  'Returns queries with mean execution time above threshold (default 500ms). Used by slow-query-sampler cron job.';