// supabase/functions/places-search-external/index.ts
// HYBRID SEARCH: Database → Apple (iOS native) → Google
// Week 7: Fixed parameter names

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-api-version',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed. Use POST.' }), {
      status: 405,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const googleApiKey = Deno.env.get('GOOGLE_PLACES_API_KEY');

  try {
    // ========================================
    // AUTH CHECK
    // ========================================
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Authentication required' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    const token = authHeader.replace('Bearer ', '');
    const verifyResponse = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: {
        'Authorization': `Bearer ${token}`,
        'apikey': supabaseAnonKey
      }
    });

    if (!verifyResponse.ok) {
      return new Response(JSON.stringify({ error: 'Invalid or expired token' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    const user = await verifyResponse.json();
    if (!user || !user.id) {
      return new Response(JSON.stringify({ error: 'Authentication required' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // ========================================
    // VALIDATE REQUEST
    // ========================================
    const { query, lat, lng, limit = 5 } = await req.json();

    if (!query || query.trim().length === 0) {
      return new Response(JSON.stringify({ error: 'Query is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    if (!lat || !lng || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return new Response(JSON.stringify({ error: 'Valid coordinates required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    if (limit < 1 || limit > 10) {
      return new Response(JSON.stringify({ error: 'Limit must be between 1 and 10' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    console.log(`🔍 [Search] Query: "${query}" near (${lat}, ${lng}), limit: ${limit}`);

    const serviceClient = createClient(supabaseUrl, supabaseServiceKey);
    let results: any[] = [];
    let source = 'none';

    // ========================================
    // TIER 1: DATABASE SEARCH (Existing Places)
    // ========================================
    console.log('📊 [Tier 1] Searching database...');
    
    try {
      // ✅ FIX: Use correct parameter names
      const { data: dbPlaces, error: dbError } = await serviceClient.rpc('search_places', {
        p_search_text: query,        // ✅ Correct: p_search_text (not p_query)
        p_category: null,
        p_price_level: null,
        p_lat: lat,
        p_lng: lng,
        p_radius_meters: 5000,       // ✅ Correct: p_radius_meters (not p_radius)
        p_cursor_created_at: null,
        p_cursor_id: null,
        p_limit: limit
      });

      if (dbError) {
        console.error('❌ [Tier 1] Database error:', dbError);
      } else if (dbPlaces && dbPlaces.length > 0) {
        console.log(`✅ [Tier 1] Found ${dbPlaces.length} database results`);
        
        for (const place of dbPlaces) {
          results.push({
            source: 'database',
            googlePlaceId: place.google_place_id,
            applePlaceId: place.apple_place_id,
            nameEn: place.name_en,
            nameJa: place.name_ja,
            nameZh: place.name_zh,
            lat: place.lat,
            lng: place.lng,
            formattedAddress: place.formatted_address || `${place.ward || ''} ${place.city || ''}`.trim(),
            categories: place.categories || [],
            photoUrls: place.photo_urls || [],
            existsInDb: true,
            dbPlaceId: place.id
          });
        }
        
        source = 'database';
        
        if (results.length >= limit) {
          console.log(`✅ [Tier 1] Database provided ${results.length} results - returning early!`);
          return new Response(JSON.stringify({
            results: results.slice(0, limit),
            count: results.length,
            source: 'database',
            message: `Found ${results.length} places from your network.`
          }), {
            status: 200,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          });
        }
      } else {
        console.log('ℹ️ [Tier 1] No database results');
      }
    } catch (error) {
      console.error('❌ [Tier 1] Database search error:', error);
    }

    // ========================================
    // TIER 2: APPLE MAPKIT (Handled by iOS)
    // ========================================
    console.log('🍎 [Tier 2] Apple MapKit search handled by iOS client');

    // ========================================
    // TIER 3: GOOGLE PLACES API (Last Resort)
    // ========================================
    if (googleApiKey && results.length < limit) {
      console.log(`🌍 [Tier 3] Searching Google Places (need ${limit - results.length} more)...`);
      
      try {
        const googleUrl = 'https://places.googleapis.com/v1/places:searchText';
        const googleResponse = await fetch(googleUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': googleApiKey,
            'X-Goog-FieldMask': 'places.id,places.displayName,places.formattedAddress,places.location,places.photos'
          },
          body: JSON.stringify({
            textQuery: query,
            locationBias: {
              circle: {
                center: { latitude: lat, longitude: lng },
                radius: 5000
              }
            },
            maxResultCount: limit - results.length,
            languageCode: 'ja'
          })
        });

        if (googleResponse.ok) {
          const googleData = await googleResponse.json();
          const places = googleData.places || [];
          console.log(`✅ [Tier 3] Google returned ${places.length} results`);

          for (const place of places) {
            const { data: existing } = await serviceClient
              .from('places')
              .select('id')
              .eq('google_place_id', place.id)
              .maybeSingle();

            results.push({
              source: 'google',
              googlePlaceId: place.id,
              applePlaceId: null,
              nameEn: place.displayName?.text || '',
              nameJa: null,
              nameZh: null,
              lat: place.location?.latitude,
              lng: place.location?.longitude,
              formattedAddress: place.formattedAddress || '',
              categories: [],
              photoUrls: place.photos?.[0]?.name 
                ? [`https://places.googleapis.com/v1/${place.photos[0].name}/media?key=${googleApiKey}&maxHeightPx=400&maxWidthPx=400`]
                : [],
              existsInDb: !!existing,
              dbPlaceId: existing?.id || null
            });
          }

          source = results.length === places.length ? 'google' : 'hybrid';
        } else {
          const errorText = await googleResponse.text();
          console.error('❌ [Tier 3] Google Places API error:', googleResponse.status, errorText);
        }
      } catch (error) {
        console.error('❌ [Tier 3] Google Places API error:', error);
      }
    }

    // ========================================
    // RETURN RESULTS
    // ========================================
    const finalResults = results.slice(0, limit);
    console.log(`✅ [Search] Returning ${finalResults.length} total results`);
    console.log(`   Database: ${finalResults.filter(r => r.source === 'database').length}`);
    console.log(`   Google: ${finalResults.filter(r => r.source === 'google').length}`);

    let message = '';
    if (finalResults.length === 0) {
      message = 'No places found. You can add it manually by dropping a pin on the map.';
    } else if (finalResults.length === 1) {
      message = 'Found 1 place. Tap to see details.';
    } else {
      message = `Found ${finalResults.length} places. Select one to continue.`;
    }

    return new Response(JSON.stringify({
      results: finalResults,
      count: finalResults.length,
      source,
      message
    }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });

  } catch (error) {
    console.error('❌ [Search] Fatal error:', error);
    return new Response(JSON.stringify({
      error: 'Search failed',
      message: error.message,
      results: [],
      count: 0,
      source: 'none'
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
});