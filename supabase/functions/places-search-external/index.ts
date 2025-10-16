// supabase/functions/places-search-external/index.ts
// Week 6: Google Places API search with database fallback
// NO APPLE MAPS API (not needed for iOS)

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-api-version',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

interface SearchRequest {
  query: string;
  lat: number;
  lng: number;
  limit?: number;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed. Use POST.' }),
      { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const googleApiKey = Deno.env.get('GOOGLE_PLACES_API_KEY');

  try {
    // Auth check
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Authentication required' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const token = authHeader.replace('Bearer ', '');
    
    // Verify token with Supabase
    const verifyResponse = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: {
        'Authorization': `Bearer ${token}`,
        'apikey': supabaseAnonKey,
      },
    });

    if (!verifyResponse.ok) {
      return new Response(
        JSON.stringify({ error: 'Invalid or expired token' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const user = await verifyResponse.json();
    if (!user || !user.id) {
      return new Response(
        JSON.stringify({ error: 'Authentication required' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const { query, lat, lng, limit = 5 }: SearchRequest = await req.json();

    // Validation
    if (!query || query.trim().length === 0) {
      return new Response(
        JSON.stringify({ error: 'Query is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!lat || !lng || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return new Response(
        JSON.stringify({ error: 'Valid coordinates required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (limit < 1 || limit > 10) {
      return new Response(
        JSON.stringify({ error: 'Limit must be between 1 and 10' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log(`Searching for "${query}" near (${lat}, ${lng}), limit: ${limit}`);

    let results: any[] = [];
    let source = 'none';
    const serviceClient = createClient(supabaseUrl, supabaseServiceKey);

    // Step 1: Try Google Places API
    if (googleApiKey && results.length < limit) {
      console.log('Trying Google Places API...');
      
      try {
        const googleUrl = 'https://places.googleapis.com/v1/places:searchText';
        const googleResponse = await fetch(googleUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': googleApiKey,
            'X-Goog-FieldMask': 'places.id,places.displayName,places.formattedAddress,places.location,places.photos',
          },
          body: JSON.stringify({
            textQuery: query,
            locationBias: {
              circle: {
                center: { latitude: lat, longitude: lng },
                radius: 5000,
              },
            },
            maxResultCount: limit,
            languageCode: 'ja',
          }),
        });

        if (googleResponse.ok) {
          const googleData = await googleResponse.json();
          const places = googleData.places || [];

          console.log(`Google returned ${places.length} results`);

          for (const place of places.slice(0, limit)) {
            // Check if place exists in DB by google_place_id
            const { data: existing } = await serviceClient
              .from('places')
              .select('id')
              .eq('google_place_id', place.id)
              .maybeSingle();

            results.push({
              source: 'google',
              external_id: place.id,
              name: place.displayName?.text || '',
              address: place.formattedAddress || '',
              lat: place.location?.latitude,
              lng: place.location?.longitude,
              photo_url: place.photos?.[0]?.name 
                ? `https://places.googleapis.com/v1/${place.photos[0].name}/media?key=${googleApiKey}&maxHeightPx=400&maxWidthPx=400`
                : null,
              exists_in_db: !!existing,
              db_place_id: existing?.id || null,
            });
          }

          if (results.length > 0) {
            source = 'google';
          }
        } else {
          const errorText = await googleResponse.text();
          console.error('Google Places API error:', googleResponse.status, errorText);
        }
      } catch (error) {
        console.error('Google Places API error:', error);
      }
    }

    // Step 2: Database fallback if still need more results
    if (results.length < limit) {
      console.log('Trying database fallback...');
      
      const { data: dbPlaces } = await serviceClient.rpc('search_places_nearby', {
        search_query: query,
        user_lat: lat,
        user_lng: lng,
        radius_meters: 5000,
        result_limit: limit - results.length,
      });

      if (dbPlaces && dbPlaces.length > 0) {
        console.log(`Database returned ${dbPlaces.length} results`);
        
        for (const place of dbPlaces) {
          results.push({
            source: 'database',
            external_id: null,
            name: place.name_en || place.name_ja || place.name_zh || '',
            address: `${place.ward || ''} ${place.city || ''}`.trim(),
            lat: place.lat,
            lng: place.lng,
            photo_url: null,
            exists_in_db: true,
            db_place_id: place.id,
          });
        }

        source = results.length === dbPlaces.length ? 'database' : 'mixed';
      }
    }

    // Generate user-friendly message
    let message = '';
    if (results.length === 0) {
      message = 'No places found. You can add it manually by dropping a pin on the map.';
    } else if (results.length === 1) {
      message = 'Found 1 place. Tap to see details.';
    } else {
      message = `Found ${results.length} places. Select one to continue.`;
    }

    return new Response(
      JSON.stringify({
        results: results.slice(0, limit),
        count: Math.min(results.length, limit),
        source,
        message,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    );
  } catch (error) {
    console.error('Search error:', error);
    return new Response(
      JSON.stringify({ 
        error: 'Search failed',
        message: error.message,
        results: [],
        count: 0,
        source: 'none',
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    );
  }
});