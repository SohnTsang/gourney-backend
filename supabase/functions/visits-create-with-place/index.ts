// supabase/functions/visits-create-with-place/index.ts
// Week 6 Step 6: Create visit with optional place creation
// Handles: existing place, API place (auto-approved), manual place (pending)

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-api-version',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

interface VisitRequest {
  // Scenario A: Existing place
  place_id?: string;
  
  // Scenario B: New place from API
  google_place_data?: {
    google_place_id: string;
    name: string;
    name_en?: string;
    name_ja?: string;
    name_zh?: string;
    address: string;
    city: string;
    ward?: string;
    lat: number;
    lng: number;
    categories?: string[];
    price_level?: number;
    phone?: string;
    website?: string;
    opening_hours?: any;
    rating?: number;
    user_ratings_total?: number;
    photos?: string[];
  };
  
  // Scenario C: Manual place entry
  manual_place?: {
    name: string;
    name_en?: string;
    name_ja?: string;
    name_zh?: string;
    lat: number;
    lng: number;
    city?: string;
    ward?: string;
    categories?: string[];
  };
  
  // Visit data (common to all scenarios)
  rating?: number;
  comment?: string;
  photo_urls?: string[];
  visibility: 'public' | 'friends' | 'private';
  visited_at?: string;
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

    const body: VisitRequest = await req.json();
    const serviceClient = createClient(supabaseUrl, supabaseServiceKey);

    // Validation: Must provide exactly ONE place source
    const placeSourceCount = [
      !!body.place_id,
      !!body.google_place_data,
      !!body.manual_place
    ].filter(Boolean).length;

    if (placeSourceCount === 0) {
      return new Response(
        JSON.stringify({ 
          error: 'Validation failed',
          message: 'Must provide one of: place_id, google_place_data, or manual_place'
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (placeSourceCount > 1) {
      return new Response(
        JSON.stringify({ 
          error: 'Validation failed',
          message: 'Cannot provide multiple place sources. Choose one.'
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validation: Photo URLs
    if (body.photo_urls) {
      if (body.photo_urls.length > 3) {
        return new Response(
          JSON.stringify({ 
            error: 'Validation failed',
            message: 'Maximum 3 photos allowed per visit'
          }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      // Validate each photo URL
      const userPhotosPrefix = `${supabaseUrl}/storage/v1/object/public/user-photos/${user.id}/`;
      for (const photoUrl of body.photo_urls) {
        if (!photoUrl.startsWith(userPhotosPrefix)) {
          return new Response(
            JSON.stringify({ 
              error: 'Validation failed',
              message: 'Photo URLs must be from user-photos storage bucket'
            }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        }
      }
    }

    // Validation: Comment
    if (body.comment && body.comment.length > 1000) {
      return new Response(
        JSON.stringify({ 
          error: 'Validation failed',
          message: 'Comment must be 1000 characters or less'
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validation: Photo OR Comment required
    if (!body.photo_urls?.length && !body.comment?.trim()) {
      return new Response(
        JSON.stringify({ 
          error: 'Validation failed',
          message: 'Either photo or comment is required'
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validation: Rating (optional, but if provided must be 1-5)
    if (body.rating !== undefined && (body.rating < 1 || body.rating > 5)) {
      return new Response(
        JSON.stringify({ 
          error: 'Validation failed',
          message: 'Rating must be between 1 and 5'
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validation: Visibility
    if (!['public', 'friends', 'private'].includes(body.visibility)) {
      return new Response(
        JSON.stringify({ 
          error: 'Validation failed',
          message: 'Visibility must be public, friends, or private'
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Rate limiting: 30 visits per day
    const oneDayAgo = new Date();
    oneDayAgo.setDate(oneDayAgo.getDate() - 1);

    const { count: visitCount } = await serviceClient
      .from('visits')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', user.id)
      .gte('created_at', oneDayAgo.toISOString());

    if (visitCount !== null && visitCount >= 30) {
      return new Response(
        JSON.stringify({ 
          error: 'Rate limit exceeded',
          message: 'Maximum 30 visits per day. Please try again tomorrow.',
          limit: 30,
          current: visitCount,
        }),
        { 
          status: 429,
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json',
            'Retry-After': '86400'
          }
        }
      );
    }

    // PLACE RESOLUTION: Determine final place_id
    let finalPlaceId: string | null = null;
    let createdNewPlace = false;

    // SCENARIO A: Existing place
    if (body.place_id) {
      console.log('Scenario A: Using existing place');
      
      const { data: existingPlace } = await serviceClient
        .from('places')
        .select('id')
        .eq('id', body.place_id)
        .single();

      if (!existingPlace) {
        return new Response(
          JSON.stringify({ error: 'Place not found' }),
          { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      finalPlaceId = body.place_id;
      createdNewPlace = false;
    }

    // SCENARIO B: New place from Google API
    if (body.google_place_data) {
      console.log('Scenario B: Creating place from Google API data');

      const googleData = body.google_place_data;

      // Check if place already exists by google_place_id
      const { data: existingPlace } = await serviceClient
        .from('places')
        .select('id')
        .eq('google_place_id', googleData.google_place_id)
        .maybeSingle();

      if (existingPlace) {
        console.log('Place already exists in database, using existing');
        finalPlaceId = existingPlace.id;
        createdNewPlace = false;
      } else {
        // Create new place (auto-approved from trusted API source)
        // Use ST_SetSRID for proper PostGIS geometry
        const { data: newPlace, error: placeError } = await serviceClient
          .rpc('upsert_place', {
            p_provider: 'google',
            p_provider_place_id: googleData.google_place_id,
            p_name_ja: googleData.name_ja || null,
            p_name_en: googleData.name_en || googleData.name,
            p_name_zh: googleData.name_zh || null,
            p_postal_code: null,
            p_prefecture_code: null,
            p_prefecture_name: null,
            p_ward: googleData.ward || null,
            p_city: googleData.city,
            p_lat: googleData.lat,
            p_lng: googleData.lng,
            p_price_level: googleData.price_level || null,
            p_categories: googleData.categories || [],
          });

        if (placeError || !newPlace) {
          console.error('Failed to create place:', placeError);
          return new Response(
            JSON.stringify({ 
              error: 'Failed to create place',
              message: placeError?.message 
            }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        }

        // Update google_place_id, created_by, moderation_status, and attributes
        const { error: updateError } = await serviceClient
          .from('places')
          .update({
            google_place_id: googleData.google_place_id,
            created_by: user.id,
            moderation_status: 'approved',
            attributes: {
              phone: googleData.phone,
              website: googleData.website,
              opening_hours: googleData.opening_hours,
              rating: googleData.rating,
              user_ratings_total: googleData.user_ratings_total,
              photos: googleData.photos,
            },
          })
          .eq('id', newPlace);

        if (updateError) {
          console.error('Failed to update place metadata:', updateError);
        }

        finalPlaceId = newPlace;
        createdNewPlace = true;
        console.log('Created new place from Google API:', newPlace);
      }
    }

    // SCENARIO C: Manual place entry
    if (body.manual_place) {
      console.log('Scenario C: Creating manual place entry');

      const manualData = body.manual_place;

      // Validate manual place data
      if (!manualData.name || manualData.name.trim().length === 0) {
        return new Response(
          JSON.stringify({ 
            error: 'Validation failed',
            message: 'Place name is required for manual entry'
          }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      if (!manualData.lat || !manualData.lng || 
          manualData.lat < -90 || manualData.lat > 90 ||
          manualData.lng < -180 || manualData.lng > 180) {
        return new Response(
          JSON.stringify({ 
            error: 'Validation failed',
            message: 'Valid coordinates required for manual entry'
          }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      // Duplicate detection: Check for nearby places with similar names
      const { data: nearbyPlaces, error: rpcError } = await serviceClient
        .rpc('find_nearby_places', {
          p_lat: manualData.lat,
          p_lng: manualData.lng,
          p_radius_meters: 50,
          p_name_query: manualData.name,
        });

      if (rpcError) {
        console.error('RPC error in find_nearby_places:', rpcError);
      }

      if (nearbyPlaces && nearbyPlaces.length > 0) {
        // Filter by high similarity (>0.6 threshold)
        const duplicates = nearbyPlaces.filter((p: any) => p.similarity_score > 0.6);
        
        if (duplicates.length > 0) {
          return new Response(
            JSON.stringify({ 
              error: 'Possible duplicate',
              message: 'A similar place exists nearby. Please review.',
              nearby_places: duplicates.map((p: any) => ({
                id: p.id,
                name: p.name,
                distance_meters: Math.round(p.distance_meters),
                similarity_score: p.similarity_score,
              })),
            }),
            { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        }
      }

      // Create manual place (pending moderation)
      const providerPlaceId = `ugc_${user.id}_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;

      // Determine name language automatically
      const hasEnglish = /^[a-zA-Z\s\-']+$/.test(manualData.name);
      const hasJapanese = /[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF]/.test(manualData.name);

      const { data: newPlace, error: placeError } = await serviceClient
        .rpc('upsert_place', {
          p_provider: 'ugc',
          p_provider_place_id: providerPlaceId,
          p_name_ja: manualData.name_ja || (hasJapanese ? manualData.name : null),
          p_name_en: manualData.name_en || (hasEnglish ? manualData.name : null),
          p_name_zh: manualData.name_zh || null,
          p_postal_code: null,
          p_prefecture_code: null,
          p_prefecture_name: null,
          p_ward: manualData.ward || null,
          p_city: manualData.city || null,
          p_lat: manualData.lat,
          p_lng: manualData.lng,
          p_price_level: null,
          p_categories: manualData.categories || [],
        });

      if (placeError || !newPlace) {
        console.error('Failed to create manual place:', placeError);
        return new Response(
          JSON.stringify({ 
            error: 'Failed to create place',
            message: placeError?.message 
          }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      // Update moderation status and metadata
      const { error: updateError } = await serviceClient
        .from('places')
        .update({
          created_by: user.id,
          moderation_status: 'pending',
          submission_notes: `Manual entry by user ${user.id}`,
        })
        .eq('id', newPlace);

      if (updateError) {
        console.error('Failed to update place moderation status:', updateError);
      }

      finalPlaceId = newPlace;
      createdNewPlace = true;
      console.log('Created manual place (pending):', newPlace);
    }

    if (!finalPlaceId) {
      return new Response(
        JSON.stringify({ error: 'Failed to determine place' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // CREATE VISIT
    const { data: newVisit, error: visitError } = await serviceClient
      .from('visits')
      .insert({
        user_id: user.id,
        place_id: finalPlaceId,
        rating: body.rating,
        comment: body.comment?.trim() || null,
        photo_urls: body.photo_urls || [],
        visibility: body.visibility,
        visited_at: body.visited_at || new Date().toISOString(),
        created_new_place: createdNewPlace,
      })
      .select('id')
      .single();

    if (visitError || !newVisit) {
      console.error('Failed to create visit:', visitError);
      return new Response(
        JSON.stringify({ 
          error: 'Failed to create visit',
          message: visitError?.message 
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // CREATE ACTIVITY ENTRY
    // CREATE ACTIVITY ENTRY
    const { error: activityError } = await serviceClient
      .from('activity')
      .insert({
        type: 'visit',
        subject_id: newVisit.id,
        actor_id: user.id,
        visibility: body.visibility,
      });

    if (activityError) {
      console.error('Failed to create activity:', activityError);
      // Don't fail the whole request, activity is secondary
    }

    // Calculate points earned
    // Scenario A (existing place): +2 points (from trigger)
    // Scenario B (new API place): +5 points (2 from trigger + 3 bonus immediate)
    // Scenario C (new manual place): +2 points immediate (3 bonus after approval)
    let pointsEarned = 2; // Base points for visit
    
    if (createdNewPlace) {
      // Check if the place was auto-approved (API source) or pending (manual)
      const { data: placeCheck } = await serviceClient
        .from('places')
        .select('moderation_status')
        .eq('id', finalPlaceId)
        .single();
      
      if (placeCheck && placeCheck.moderation_status === 'approved') {
        // API place: auto-approved, +3 bonus immediately
        pointsEarned = 5;
      } else {
        // Manual place: pending, +2 now, +3 after approval
        pointsEarned = 2;
      }
    }

    console.log(`Visit created successfully: ${newVisit.id}, Points: ${pointsEarned}`);

    return new Response(
      JSON.stringify({
        message: 'Visit created successfully',
        visit_id: newVisit.id,
        place_id: finalPlaceId,
        created_new_place: createdNewPlace,
        points_earned: pointsEarned,
        moderation_note: body.manual_place 
          ? 'Manual place pending approval. You will earn bonus +3 points once approved.'
          : null,
      }),
      {
        status: 201,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    );

  } catch (error) {
    console.error('Visit creation error:', error);
    return new Response(
      JSON.stringify({ 
        error: 'Failed to create visit',
        message: error.message,
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    );
  }
});