import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

interface PlaceInput {
  provider: 'apple' | 'google' | 'ugc';
  provider_place_id: string;
  name_ja?: string;
  name_en?: string;
  name_zh?: string;
  lat: number;
  lng: number;
  postal_code?: string;
  prefecture_code?: string;
  prefecture_name?: string;
  ward?: string;
  city?: string;
  categories?: string[];
  price_level?: number;
  hours?: Array<{
    weekday: number;
    open_time: string;
    close_time: string;
    notes?: string;
  }>;
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, serviceKey);

    const { places }: { places: PlaceInput[] } = await req.json();

    if (!places || !Array.isArray(places) || places.length === 0) {
      return new Response(
        JSON.stringify({ error: 'Places array required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const results = {
      inserted: 0,
      errors: [] as string[]
    };

    for (const place of places) {
      try {
        if (!place.provider || !place.provider_place_id || !place.lat || !place.lng) {
          results.errors.push(`Missing required fields for ${place.name_en || 'unknown'}`);
          continue;
        }

        if (!['apple', 'google', 'ugc'].includes(place.provider)) {
          results.errors.push(`Invalid provider: ${place.provider}`);
          continue;
        }

        if (place.lat < -90 || place.lat > 90 || place.lng < -180 || place.lng > 180) {
          results.errors.push(`Invalid coordinates for ${place.name_en}`);
          continue;
        }

        // Use RPC to insert with proper geography handling
        const { data: placeId, error: placeError } = await supabase
          .rpc('upsert_place', {
            p_provider: place.provider,
            p_provider_place_id: place.provider_place_id,
            p_name_ja: place.name_ja || null,
            p_name_en: place.name_en || null,
            p_name_zh: place.name_zh || null,
            p_postal_code: place.postal_code || null,
            p_prefecture_code: place.prefecture_code || null,
            p_prefecture_name: place.prefecture_name || null,
            p_ward: place.ward || null,
            p_city: place.city || null,
            p_lat: place.lat,
            p_lng: place.lng,
            p_price_level: place.price_level || null,
            p_categories: place.categories || []
          });

        if (placeError) {
          results.errors.push(`Place RPC error: ${placeError.message}`);
          continue;
        }

        if (!placeId) {
          results.errors.push(`Failed to upsert place: ${place.name_en}`);
          continue;
        }

        results.inserted++;

        // Upsert hours if provided
        if (place.hours && place.hours.length > 0) {
          for (const hour of place.hours) {
            if (hour.weekday < 0 || hour.weekday > 6) {
              results.errors.push(`Invalid weekday ${hour.weekday} for ${place.name_en}`);
              continue;
            }

            const { error: hourError } = await supabase
              .from('place_hours')
              .upsert({
                place_id: placeId,
                weekday: hour.weekday,
                open_time: hour.open_time,
                close_time: hour.close_time,
                notes: hour.notes || null
              }, {
                onConflict: 'place_id,weekday'
              });

            if (hourError) {
              results.errors.push(`Hours error for ${place.name_en}: ${hourError.message}`);
            }
          }
        }

      } catch (error) {
        results.errors.push(`Exception: ${error.message}`);
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        inserted: results.inserted,
        errors: results.errors,
        total_processed: places.length
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );

  } catch (error) {
    console.error('Upsert error:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );
  }
});