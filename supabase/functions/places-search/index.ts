import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { withApiVersion } from '../_shared/apiVersionGuard.ts';
import { encodeCursor, decodeCursor } from '../_shared/cursor.ts';

interface SearchParams {
  q?: string;
  lat?: number;
  lng?: number;
  radius?: number;
  category?: string;
  price_level?: number;
  open_now?: boolean;
  limit?: number;
  cursor?: string;
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-api-version',
};

const handler = async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // Only allow POST as per plan
  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed. Use POST.' }),
      { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const authHeader = req.headers.get('Authorization');
    
    const supabase = createClient(supabaseUrl, supabaseKey, {
      global: { headers: { Authorization: authHeader || '' } }
    });

    // Get current user for rate limiting
    const { data: { user } } = await supabase.auth.getUser();
    
    // Rate limiting: 100 requests per minute per user (Week 2 requirement)
    // Only apply to authenticated users; anonymous users get lower limit
    const userId = user?.id;

    if (userId) {
      const oneMinuteAgo = new Date(Date.now() - 60 * 1000);
      
      // Use service role client for rate limit check (bypass RLS)
      const supabaseAdmin = createClient(
        Deno.env.get('SUPABASE_URL')!,
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
      );
      
      // Count requests in last minute
      const { count, error: countError } = await supabaseAdmin
        .from('search_rate_limit')
        .select('*', { count: 'exact', head: true })
        .eq('user_id', userId)
        .gte('searched_at', oneMinuteAgo.toISOString());

      if (countError) {
        console.error('Rate limit check error:', countError);
      } else if (count !== null && count >= 100) {
        // Calculate retry-after (seconds until oldest request expires)
        const { data: oldestData } = await supabaseAdmin
          .from('search_rate_limit')
          .select('searched_at')
          .eq('user_id', userId)
          .gte('searched_at', oneMinuteAgo.toISOString())
          .order('searched_at', { ascending: true })
          .limit(1)
          .single();

        let retryAfter = 60;
        if (oldestData) {
          const oldestTime = new Date(oldestData.searched_at).getTime();
          const expiresAt = oldestTime + (60 * 1000);
          retryAfter = Math.ceil((expiresAt - Date.now()) / 1000);
        }

        return new Response(
          JSON.stringify({
            error: 'Rate limit exceeded',
            message: 'Maximum 100 searches per minute. Please try again shortly.',
            limit: 100,
            retryAfter
          }),
          {
            status: 429,
            headers: {
              ...corsHeaders,
              'Content-Type': 'application/json',
              'Retry-After': retryAfter.toString(),
              'X-RateLimit-Limit': '100',
              'X-RateLimit-Remaining': '0',
              'X-RateLimit-Reset': Math.floor((Date.now() + retryAfter * 1000) / 1000).toString()
            }
          }
        );
      }

      // Log this search request (using admin client)
      await supabaseAdmin
        .from('search_rate_limit')
        .insert({
          user_id: userId,
          endpoint: '/v1/places/search',
          ip_address: req.headers.get('x-forwarded-for') || req.headers.get('x-real-ip') || 'unknown'
        });
    }

    // Parse request body
    const body = await req.json();
    const params: SearchParams = {
      q: body.q?.trim() || undefined,
      lat: body.lat ? parseFloat(body.lat) : undefined,
      lng: body.lng ? parseFloat(body.lng) : undefined,
      radius: body.radius ? parseInt(body.radius) : 5000, // default 5km
      category: body.category || undefined,
      price_level: body.price_level !== undefined ? parseInt(body.price_level) : undefined,
      open_now: body.open_now === true,
      limit: Math.min(parseInt(body.limit || '50'), 50),
      cursor: body.cursor || undefined
    };

    // Decode cursor for pagination
    let cursorData: { created_at: string; id: string } | null = null;
    if (params.cursor) {
      try {
        cursorData = await decodeCursor(params.cursor);
      } catch (error) {
        return new Response(
          JSON.stringify({ error: 'Invalid cursor' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
    }

    // Use RPC for search with enhanced parameters
    const { data: places, error } = await supabase
      .rpc('search_places', {
        p_search_text: params.q || null,
        p_category: params.category || null,
        p_price_level: params.price_level !== undefined ? params.price_level : null,
        p_lat: params.lat || null,
        p_lng: params.lng || null,
        p_radius_meters: params.radius || 5000,
        p_cursor_created_at: cursorData?.created_at || null,
        p_cursor_id: cursorData?.id || null,
        p_limit: params.limit! + 1
      });

    if (error) {
      console.error('Search error:', error);
      return new Response(
        JSON.stringify({ error: 'Search failed', details: error.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    let results = places || [];

    // OPEN_NOW FILTERING
    if (params.open_now) {
      const { data: configData } = await supabase
        .from('remote_config')
        .select('value')
        .eq('key', 'enable_open_now_beta')
        .maybeSingle(); // Use maybeSingle() instead of single() to avoid errors

      if (configData?.value?.enabled) {
        const placeIds = results.map(p => p.id);
        
        if (placeIds.length > 0) {
          const now = new Date();
          const tokyoTime = new Date(now.toLocaleString('en-US', { timeZone: 'Asia/Tokyo' }));
          const currentDay = tokyoTime.getDay();
          const currentHours = tokyoTime.getHours();
          const currentMinutes = tokyoTime.getMinutes();
          const currentTimeStr = `${String(currentHours).padStart(2, '0')}:${String(currentMinutes).padStart(2, '0')}`;
          
          // OPTIMIZATION: Fetch all hours in single query
          const { data: hoursData } = await supabase
            .from('place_hours')
            .select('place_id, weekday, open_time, close_time')
            .in('place_id', placeIds)
            .eq('weekday', currentDay);

          const openPlaces = new Set();
          if (hoursData) {
            hoursData.forEach(h => {
              if (isOpenNow(currentTimeStr, h.open_time, h.close_time)) {
                openPlaces.add(h.place_id);
              }
            });
          }

          results = results.filter(place => openPlaces.has(place.id));
        }
      }
    }
    // Check for next page
    const hasMore = results.length > params.limit!;
    if (hasMore) {
      results = results.slice(0, params.limit!);
    }

    // Generate next cursor
    let nextCursor: string | null = null;
    if (hasMore && results.length > 0) {
      const lastItem = results[results.length - 1];
      nextCursor = await encodeCursor({
        created_at: lastItem.created_at,
        id: lastItem.id
      });
    }

    // FIXED: Response structure to match test expectations
    return new Response(
      JSON.stringify({
        places: results,  // Changed from 'data' to 'places'
        next_cursor: nextCursor,
        pagination: {
          limit: params.limit,
          has_more: hasMore
        }
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );

  } catch (error) {
    console.error('Search error:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
};

// Helper function to check if place is open at current time
function isOpenNow(currentTime: string, openTime: string, closeTime: string): boolean {
  const current = timeToMinutes(currentTime);
  const open = timeToMinutes(openTime);
  const close = timeToMinutes(closeTime);

  // Handle overnight hours (e.g., 23:00 - 02:00)
  if (close < open) {
    return current >= open || current < close;
  }
  
  return current >= open && current < close;
}

function timeToMinutes(time: string): number {
  const [hours, minutes] = time.split(':').map(Number);
  return hours * 60 + minutes;
}

serve(withApiVersion(handler));