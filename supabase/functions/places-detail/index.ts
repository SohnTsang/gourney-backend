import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { withApiVersion } from '../_shared/apiVersionGuard.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-api-version',
};

const handler = async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // Only allow GET
  if (req.method !== 'GET') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed. Use GET.' }),
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

    // Extract place ID from URL path
    // URL format: /v1/places-detail/[place-id]
    const url = new URL(req.url);
    const pathParts = url.pathname.split('/');
    const placeId = pathParts[pathParts.length - 1];

    if (!placeId || placeId === 'places-detail') {
      return new Response(
        JSON.stringify({ error: 'Place ID required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Get place details
    const { data: place, error: placeError } = await supabase
      .from('places')
      .select('*')
      .eq('id', placeId)
      .single();

    if (placeError || !place) {
      return new Response(
        JSON.stringify({ error: 'Place not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Get place hours (all weekdays)
    const { data: hours } = await supabase
      .from('place_hours')
      .select('*')
      .eq('place_id', placeId)
      .order('weekday', { ascending: true });

    // Get recent friend visits (last 3)
    // RLS automatically filters to only show:
    // - User's own visits
    // - Public visits from non-blocked users
    // - Friends-only visits from friends who haven't blocked user
    const { data: recentVisits } = await supabase
      .from('visits')
      .select(`
        id,
        rating,
        comment,
        photo_urls,
        visited_at,
        visibility,
        created_at,
        user:users!visits_user_id_fkey(
          id,
          handle,
          display_name,
          avatar_url
        )
      `)
      .eq('place_id', placeId)
      .order('created_at', { ascending: false })
      .limit(3);

    // Calculate average rating from all visits (if available)
    // Note: This is simplified - in production you might want a materialized view
    const { data: ratingData } = await supabase
      .from('visits')
      .select('rating')
      .eq('place_id', placeId);

    let averageRating = null;
    let visitCount = 0;
    
    if (ratingData && ratingData.length > 0) {
      const sum = ratingData.reduce((acc, v) => acc + v.rating, 0);
      averageRating = (sum / ratingData.length).toFixed(1);
      visitCount = ratingData.length;
    }

    return new Response(
      JSON.stringify({
        place: {
          ...place,
          average_rating: averageRating ? parseFloat(averageRating) : null,
          visit_count: visitCount
        },
        hours: hours || [],
        recent_visits: recentVisits || []
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );

  } catch (error) {
    console.error('Place detail error:', error);
    return new Response(
          JSON.stringify({ 
            error: { 
              code: 'INTERNAL_ERROR', 
              message: 'Internal server error', 
              status: 500 
            }
          }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
    );
  }
};

serve(withApiVersion(handler));