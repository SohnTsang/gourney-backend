// supabase/functions/ugc-places-submit/index.ts
// Week 6 Step 3: FIXED UTF-8 handling for CJK characters

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { corsHeaders } from '../_shared/cors.ts';

interface SubmitPlaceRequest {
  name_en?: string;
  name_ja?: string;
  name_zh?: string;
  address?: string;
  city?: string;
  ward?: string;
  lat: number;
  lng: number;
  categories?: string[];
  price_level?: number;
  submitted_photo_url?: string;
  submission_notes?: string;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

  try {
    // Get JWT from Authorization header
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(
        JSON.stringify({
          error: 'Unauthorized',
          message: 'Authorization header required',
        }),
        {
          status: 401,
          headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
        }
      );
    }

    // Extract JWT token
    const token = authHeader.replace('Bearer ', '');

    // Verify token by calling Supabase auth API directly
    const verifyResponse = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: {
        'Authorization': `Bearer ${token}`,
        'apikey': supabaseAnonKey,
      },
    });

    if (!verifyResponse.ok) {
      console.error('Auth verification failed:', verifyResponse.status);
      return new Response(
        JSON.stringify({
          error: 'Unauthorized',
          message: 'Invalid or expired token',
        }),
        {
          status: 401,
          headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
        }
      );
    }

    const user = await verifyResponse.json();
    if (!user || !user.id) {
      return new Response(
        JSON.stringify({
          error: 'Unauthorized',
          message: 'Authentication required to submit places',
        }),
        {
          status: 401,
          headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
        }
      );
    }

    console.log('Authenticated user:', user.id);

    // Parse request body with proper UTF-8 handling
    const bodyText = await req.text();
    const body: SubmitPlaceRequest = JSON.parse(bodyText);

    // Log received names for debugging
    console.log('Received names:', {
      name_en: body.name_en,
      name_ja: body.name_ja,
      name_zh: body.name_zh,
    });

    // Validation
    const errors: string[] = [];

    // Name validation: must have at least one name (en, ja, or zh)
    const hasName = (body.name_en && body.name_en.trim().length > 0) ||
                    (body.name_ja && body.name_ja.trim().length > 0) ||
                    (body.name_zh && body.name_zh.trim().length > 0);

    if (!hasName) {
      errors.push('At least one name (name_en, name_ja, or name_zh) is required');
    }

    // Validate name lengths if provided
    if (body.name_en && body.name_en.length > 200) {
      errors.push('name_en must be 200 characters or less');
    }
    if (body.name_ja && body.name_ja.length > 200) {
      errors.push('name_ja must be 200 characters or less');
    }
    if (body.name_zh && body.name_zh.length > 200) {
      errors.push('name_zh must be 200 characters or less');
    }

    // Coordinates are required (from GPS/API)
    if (body.lat === undefined || body.lng === undefined) {
      errors.push('lat and lng are required');
    }

    if (body.lat !== undefined && (body.lat < -90 || body.lat > 90)) {
      errors.push('lat must be between -90 and 90');
    }

    if (body.lng !== undefined && (body.lng < -180 || body.lng > 180)) {
      errors.push('lng must be between -180 and 180');
    }

    // Optional field validations
    if (body.categories && body.categories.length > 5) {
      errors.push('maximum 5 categories allowed');
    }

    if (body.price_level !== undefined && (body.price_level < 0 || body.price_level > 4)) {
      errors.push('price_level must be between 0 and 4');
    }

    if (body.submission_notes && body.submission_notes.length > 500) {
      errors.push('submission_notes must be 500 characters or less');
    }

    // Validate photo URL if provided
    if (body.submitted_photo_url) {
      const expectedPrefix = `${supabaseUrl}/storage/v1/object/public/user-photos/`;
      
      if (!body.submitted_photo_url.startsWith(expectedPrefix)) {
        errors.push('submitted_photo_url must be from user-photos storage bucket');
      }
    }

    if (errors.length > 0) {
      return new Response(
        JSON.stringify({ error: 'Validation failed', errors }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
        }
      );
    }

    // Create service role client for database operations
    const serviceClient = createClient(supabaseUrl, supabaseServiceKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    });

    // Check rate limit: 10 submissions per day per user
    const oneDayAgo = new Date();
    oneDayAgo.setDate(oneDayAgo.getDate() - 1);

    const { count: submissionCount, error: countError } = await serviceClient
      .from('places')
      .select('*', { count: 'exact', head: true })
      .eq('created_by', user.id)
      .gte('created_at', oneDayAgo.toISOString());

    if (countError) {
      console.error('Rate limit check error:', countError);
      return new Response(
        JSON.stringify({ 
          error: 'Internal error checking rate limit',
          details: countError.message 
        }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
        }
      );
    }

    if (submissionCount && submissionCount >= 10) {
      return new Response(
        JSON.stringify({
          error: 'Rate limit exceeded',
          message: 'You can submit up to 10 places per day',
          limit: 10,
          current: submissionCount,
        }),
        {
          status: 429,
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json; charset=utf-8',
            'Retry-After': '86400',
          },
        }
      );
    }

    // Generate unique provider_place_id
    const providerPlaceId = `ugc_${user.id}_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;

    console.log('Calling upsert_ugc_place RPC with user:', user.id);
    console.log('Names being inserted:', {
      name_en: body.name_en || null,
      name_ja: body.name_ja || null,
      name_zh: body.name_zh || null,
    });

    // Insert place with moderation_status = 'pending'
    const { data: placeId, error: insertError } = await serviceClient.rpc('upsert_ugc_place', {
      p_provider: 'ugc',
      p_provider_place_id: providerPlaceId,
      p_name_en: body.name_en || null,
      p_name_ja: body.name_ja || null,
      p_name_zh: body.name_zh || null,
      p_city: body.city || null,
      p_ward: body.ward || null,
      p_lat: body.lat,
      p_lng: body.lng,
      p_categories: body.categories || null,
      p_price_level: body.price_level || null,
      p_created_by: user.id,
      p_submitted_photo_url: body.submitted_photo_url || null,
      p_submission_notes: body.submission_notes || null,
    });

    if (insertError) {
      console.error('Insert error:', insertError);
      return new Response(
        JSON.stringify({ 
          error: 'Failed to submit place', 
          details: insertError.message,
          hint: insertError.hint,
          code: insertError.code
        }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
        }
      );
    }

    console.log('Place submitted successfully:', placeId);

    return new Response(
      JSON.stringify({
        message: 'Place submitted successfully',
        place_id: placeId,
        status: 'pending',
        note: 'Your submission will be reviewed by our team. You will earn +3 points when approved.',
      }),
      {
        status: 201,
        headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
      }
    );
  } catch (error) {
    console.error('Unexpected error:', error);
    return new Response(
      JSON.stringify({ 
        error: 'Internal server error', 
        message: error.message,
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
      }
    );
  }
});