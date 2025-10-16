// supabase/functions/_shared/rateLimitGuard.ts
// Rate limiting utility using Postgres as storage
// Checks against remote_config limits and user activity

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export type RateLimitType = 
  | 'visits_per_day' 
  | 'list_add_per_day' 
  | 'follow_per_day'
  | 'visits_update_per_hour'; 

interface RateLimitResult {
  allowed: boolean;
  limit: number;
  current: number;
  resetAt: Date;
  retryAfter?: number; // seconds until reset
}

/**
 * Check if user has exceeded rate limit for a specific action
 * Returns rate limit status and retry-after seconds if blocked
 */
export async function rateLimitGuard(
  supabase: SupabaseClient,
  userId: string,
  limitType: RateLimitType
): Promise<RateLimitResult> {
  
  // Check if rate limiting is enabled
  const { data: configData } = await supabase
    .from('remote_config')
    .select('value')
    .eq('key', 'rate_limits_on')
    .single();

  const rateLimitsEnabled = configData?.value?.enabled ?? true;
  
  if (!rateLimitsEnabled) {
    // Rate limiting disabled - always allow
    return {
      allowed: true,
      limit: 999999,
      current: 0,
      resetAt: new Date(Date.now() + 24 * 60 * 60 * 1000)
    };
  }

  // Get rate limit configuration
  const { data: limitsConfig } = await supabase
    .from('remote_config')
    .select('value')
    .eq('key', 'rate_limits_on')
    .single();

  const limits = limitsConfig?.value?.limits ?? {
    visits_per_day: 30,
    list_add_per_day: 100,
    follow_per_day: 200
  };

  const limit = limits[limitType] ?? 30;

  // Calculate window boundaries (last 24 hours)
  const now = new Date();
  const windowStart = new Date(now.getTime() - 24 * 60 * 60 * 1000);
  const resetAt = new Date(now.getTime() + 24 * 60 * 60 * 1000);

  // Count user's actions in the current window
  let current = 0;

  switch (limitType) {
    case 'visits_per_day': {
      const { count } = await supabase
        .from('visits')
        .select('*', { count: 'exact', head: true })
        .eq('user_id', userId)
        .gte('created_at', windowStart.toISOString());
      current = count ?? 0;
      break;
    }

    case 'list_add_per_day': {
      const { count } = await supabase
        .from('list_items')
        .select('*', { count: 'exact', head: true })
        .eq('added_by', userId)
        .gte('created_at', windowStart.toISOString());
      current = count ?? 0;
      break;
    }

    case 'follow_per_day': {
      const { count } = await supabase
        .from('follows')
        .select('*', { count: 'exact', head: true })
        .eq('follower_id', userId)
        .gte('created_at', windowStart.toISOString());
      current = count ?? 0;
      break;
    }
  }

  const allowed = current < limit;
  
  // Calculate seconds until oldest action expires (for Retry-After header)
  let retryAfter: number | undefined;
  if (!allowed) {
    // Find oldest action in window
    let oldestCreatedAt: string | null = null;

    switch (limitType) {
      case 'visits_per_day': {
        const { data } = await supabase
          .from('visits')
          .select('created_at')
          .eq('user_id', userId)
          .gte('created_at', windowStart.toISOString())
          .order('created_at', { ascending: true })
          .limit(1)
          .single();
        oldestCreatedAt = data?.created_at ?? null;
        break;
      }

      case 'list_add_per_day': {
        const { data } = await supabase
          .from('list_items')
          .select('created_at')
          .eq('added_by', userId)
          .gte('created_at', windowStart.toISOString())
          .order('created_at', { ascending: true })
          .limit(1)
          .single();
        oldestCreatedAt = data?.created_at ?? null;
        break;
      }

      case 'follow_per_day': {
        const { data } = await supabase
          .from('follows')
          .select('created_at')
          .eq('follower_id', userId)
          .gte('created_at', windowStart.toISOString())
          .order('created_at', { ascending: true })
          .limit(1)
          .single();
        oldestCreatedAt = data?.created_at ?? null;
        break;
      }

      case 'visits_update_per_hour': {
        const windowStart = new Date(now.getTime() - 60 * 60 * 1000); // 1 hour
        const { count } = await supabase
          .from('visits')
          .select('*', { count: 'exact', head: true })
          .eq('user_id', userId)
          .gte('updated_at', windowStart.toISOString());
        current = count ?? 0;
        break;
      }
    }

    if (oldestCreatedAt) {
      const oldestTime = new Date(oldestCreatedAt).getTime();
      const expiresAt = oldestTime + (24 * 60 * 60 * 1000);
      retryAfter = Math.ceil((expiresAt - now.getTime()) / 1000);
    }
  }

  return {
    allowed,
    limit,
    current,
    resetAt,
    retryAfter
  };
}

/**
 * Helper to return a 429 response with proper headers
 */
export function rateLimitResponse(result: RateLimitResult): Response {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'X-RateLimit-Limit': result.limit.toString(),
    'X-RateLimit-Remaining': Math.max(0, result.limit - result.current).toString(),
    'X-RateLimit-Reset': Math.floor(result.resetAt.getTime() / 1000).toString(),
  };

  if (result.retryAfter) {
    headers['Retry-After'] = result.retryAfter.toString();
  }

  return new Response(
    JSON.stringify({
      error: 'Rate limit exceeded',
      message: `You have reached the limit of ${result.limit} actions per day. Please try again later.`,
      limit: result.limit,
      current: result.current,
      resetAt: result.resetAt.toISOString(),
      retryAfter: result.retryAfter
    }),
    { 
      status: 429,
      headers
    }
  );
}

/**
 * USAGE EXAMPLE:
 * 
 * import { rateLimitGuard, rateLimitResponse } from '../_shared/rateLimitGuard.ts';
 * 
 * // In your Edge Function (e.g., POST /visits):
 * const userId = 'user-uuid-from-auth';
 * 
 * const rateLimitCheck = await rateLimitGuard(
 *   supabase,
 *   userId,
 *   'visits_per_day'
 * );
 * 
 * if (!rateLimitCheck.allowed) {
 *   return rateLimitResponse(rateLimitCheck);
 * }
 * 
 * // Proceed with creating the visit
 * const { data, error } = await supabase
 *   .from('visits')
 *   .insert({ user_id: userId, ... });
 */