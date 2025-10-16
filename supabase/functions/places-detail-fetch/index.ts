// supabase/functions/places-detail-fetch/index.ts
// Week 6 Step 5: Fetch full place details from Google Places API
// Used when user taps a search result to see full info before adding visit

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-api-version',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

interface DetailRequest {
  google_place_id: string;
  db_place_id?: string; // If already exists in DB, return cached data
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
    
    // Verify token
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

    const { google_place_id, db_place_id }: DetailRequest = await req.json();

    // Validation
    if (!google_place_id || google_place_id.trim().length === 0) {
      return new Response(
        JSON.stringify({ error: 'google_place_id is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log(`Fetching details for Google Place ID: ${google_place_id}`);

    const serviceClient = createClient(supabaseUrl, supabaseServiceKey);

    // OPTIMIZATION: Check if place already exists in DB with full data
    if (db_place_id) {
      console.log('Checking database for cached place data...');
      
      const { data: cachedPlace } = await serviceClient
        .from('places')
        .select('*')
        .eq('id', db_place_id)
        .single();

      if (cachedPlace && cachedPlace.google_place_id === google_place_id) {
        console.log('Found cached place in database');
        
        // Return cached data (no API call needed)
        return new Response(
          JSON.stringify({
            place: {
              id: cachedPlace.id,
              google_place_id: cachedPlace.google_place_id,
              name: cachedPlace.name_en || cachedPlace.name_ja || cachedPlace.name_zh,
              name_en: cachedPlace.name_en,
              name_ja: cachedPlace.name_ja,
              name_zh: cachedPlace.name_zh,
              address: cachedPlace.address,
              city: cachedPlace.city,
              ward: cachedPlace.ward,
              lat: cachedPlace.lat,
              lng: cachedPlace.lng,
              categories: cachedPlace.categories,
              price_level: cachedPlace.price_level,
              phone: cachedPlace.attributes?.phone,
              website: cachedPlace.attributes?.website,
              opening_hours: cachedPlace.attributes?.opening_hours,
              rating: cachedPlace.attributes?.rating,
              user_ratings_total: cachedPlace.attributes?.user_ratings_total,
              photos: cachedPlace.attributes?.photos,
            },
            source: 'database',
            cached: true,
          }),
          {
            status: 200,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          }
        );
      }
    }

    // Not in DB or no db_place_id provided - fetch from Google API
    if (!googleApiKey) {
      return new Response(
        JSON.stringify({ error: 'Google Places API not configured' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log('Fetching from Google Places API...');

    const googleUrl = `https://places.googleapis.com/v1/places/${google_place_id}`;
    const googleResponse = await fetch(googleUrl, {
      method: 'GET',
      headers: {
        'X-Goog-Api-Key': googleApiKey,
        'X-Goog-FieldMask': [
          'id',
          'displayName',
          'formattedAddress',
          'location',
          'addressComponents',
          'types',
          'primaryTypeDisplayName',
          'nationalPhoneNumber',
          'internationalPhoneNumber',
          'websiteUri',
          'regularOpeningHours',
          'rating',
          'userRatingCount',
          'priceLevel',
          'photos'
        ].join(','),
      },
    });

    // Replace this section (around line 140):
    if (!googleResponse.ok) {
      const errorText = await googleResponse.text();
      console.error('Google Places API error:', googleResponse.status, errorText);
      
      if (googleResponse.status === 404) {
        return new Response(
          JSON.stringify({ error: 'Place not found' }),
          { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
      
      // NEW: Handle 400 (invalid format) as 404 too
      if (googleResponse.status === 400) {
        return new Response(
          JSON.stringify({ error: 'Place not found or invalid place ID' }),
          { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
      
      return new Response(
        JSON.stringify({ 
          error: 'Failed to fetch place details',
          message: 'Google Places API error'
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const googleData = await googleResponse.json();
    console.log('Received place details from Google');

    // Extract city and ward from address components
    let city = '';
    let ward = '';
    
    if (googleData.addressComponents) {
      for (const component of googleData.addressComponents) {
        if (component.types.includes('locality')) {
          city = component.longText || component.shortText;
        }
        if (component.types.includes('sublocality_level_1')) {
          ward = component.longText || component.shortText;
        }
      }
    }

    // Map Google types to our categories
    const categories = googleData.types || [];
    
    // Map price level (Google uses PRICE_LEVEL_INEXPENSIVE, etc.)
    let priceLevel = null;
    if (googleData.priceLevel) {
      const priceLevelMap: { [key: string]: number } = {
        'PRICE_LEVEL_FREE': 0,
        'PRICE_LEVEL_INEXPENSIVE': 1,
        'PRICE_LEVEL_MODERATE': 2,
        'PRICE_LEVEL_EXPENSIVE': 3,
        'PRICE_LEVEL_VERY_EXPENSIVE': 4,
      };
      priceLevel = priceLevelMap[googleData.priceLevel] ?? null;
    }

    // Extract opening hours
    let openingHours = null;
    if (googleData.regularOpeningHours?.weekdayDescriptions) {
      openingHours = {
        weekday_text: googleData.regularOpeningHours.weekdayDescriptions,
        open_now: googleData.regularOpeningHours.openNow,
      };
    }

    // Get photo URLs (first 5 photos)
    const photos: string[] = [];
    if (googleData.photos && googleData.photos.length > 0) {
      for (const photo of googleData.photos.slice(0, 5)) {
        if (photo.name) {
          photos.push(
            `https://places.googleapis.com/v1/${photo.name}/media?key=${googleApiKey}&maxHeightPx=800&maxWidthPx=800`
          );
        }
      }
    }

    // Prepare place data
    const placeData = {
      google_place_id: googleData.id,
      name: googleData.displayName?.text || '',
      name_en: googleData.displayName?.text || '', // Google doesn't provide language-specific names
      name_ja: null,
      name_zh: null,
      address: googleData.formattedAddress || '',
      city: city,
      ward: ward,
      lat: googleData.location?.latitude,
      lng: googleData.location?.longitude,
      categories: categories,
      price_level: priceLevel,
      phone: googleData.internationalPhoneNumber || googleData.nationalPhoneNumber,
      website: googleData.websiteUri,
      opening_hours: openingHours,
      rating: googleData.rating,
      user_ratings_total: googleData.userRatingCount,
      photos: photos,
    };

    return new Response(
      JSON.stringify({
        place: placeData,
        source: 'google',
        cached: false,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    );

  } catch (error) {
    console.error('Place detail fetch error:', error);
    return new Response(
      JSON.stringify({ 
        error: 'Failed to fetch place details',
        message: error.message,
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    );
  }
});