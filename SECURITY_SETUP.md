# Security Setup

## Supabase Secrets Configuration

Configure these secrets in Supabase Dashboard → Project Settings → Edge Functions → Secrets:

1. `SUPABASE_URL` = `https://YOUR_PROJECT_REF.supabase.co`
2. `SUPABASE_SERVICE_ROLE_KEY` = `YOUR_SERVICE_ROLE_KEY`

## Required for:
- `20251004_schedule_slow_query_sampler.sql` - Cron job that calls the slow-query-sampler function

## Important:
- Rotate the service role key immediately if it was exposed
- Never commit actual keys to version control
