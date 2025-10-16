import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { rateLimitGuard, rateLimitResponse } from '../_shared/rateLimitGuard.ts'
import { validatePhotoUrls } from '../_shared/photoUrlValidator.ts'

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Check API version (simple version - just verify header exists)
    const apiVersion = req.headers.get('X-API-Version')
    if (!apiVersion || apiVersion !== 'v1') {
      return new Response(
        JSON.stringify({ 
          error: { 
            code: 'INVALID_API_VERSION', 
            message: 'X-API-Version: v1 header required', 
            status: 400 
          }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Auth check
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: { code: 'UNAUTHORIZED', message: 'Missing auth token', status: 401 }}),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader }}}
    )

    // Get authenticated user
    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: { code: 'UNAUTHORIZED', message: 'Invalid token', status: 401 }}),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Rate limit: 30 visits/day
    const rateLimitCheck = await rateLimitGuard(supabase, user.id, 'visits_per_day')
    if (!rateLimitCheck.allowed) {
      return rateLimitResponse(rateLimitCheck)
    }

    // Parse request body
    const body = await req.json()
    const { place_id, rating, comment, photo_urls, visibility = 'public', visited_at } = body

    // Validation: place_id required
    if (!place_id) {
      return new Response(
        JSON.stringify({ 
          error: { 
            code: 'VALIDATION_ERROR', 
            message: 'place_id required', 
            field: 'place_id', 
            status: 400 
          }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Validation: rating 1-5
    if (!rating || rating < 1 || rating > 5) {
      return new Response(
        JSON.stringify({ 
          error: { 
            code: 'VALIDATION_ERROR', 
            message: 'Rating must be 1-5', 
            field: 'rating', 
            status: 400 
          }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Validation: comment ≤1000 chars
    if (comment && comment.length > 1000) {
      return new Response(
        JSON.stringify({ 
          error: { 
            code: 'VALIDATION_ERROR', 
            message: 'Comment max 1000 chars', 
            field: 'comment', 
            status: 400 
          }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Validation: photo URLs
    if (photo_urls) {
      const photoValidation = await validatePhotoUrls(
        photo_urls,
        Deno.env.get('SUPABASE_URL')!,
        'user-photos'
      )
      
      if (!photoValidation.valid) {
        return new Response(
          JSON.stringify({ 
            error: { 
              code: 'VALIDATION_ERROR', 
              message: photoValidation.reason || 'Invalid photo URLs', 
              field: 'photo_urls', 
              status: 400 
            }
          }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
        )
      }
    }

    // Check place exists
    const { data: place, error: placeError } = await supabase
      .from('places')
      .select('id, name_en, name_ja, city, ward, categories, lat, lng')
      .eq('id', place_id)
      .single()

    if (placeError || !place) {
      return new Response(
        JSON.stringify({ 
          error: { 
            code: 'NOT_FOUND', 
            message: 'Place not found', 
            status: 404 
          }
        }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Insert visit
    const { data: visit, error: visitError } = await supabase
      .from('visits')
      .insert({
        user_id: user.id,
        place_id,
        rating,
        comment: comment || null,
        photo_urls: photo_urls || [],
        visibility,
        visited_at: visited_at || new Date().toISOString()
      })
      .select()
      .single()

    if (visitError) {
      console.error('Visit insert error:', visitError)
      return new Response(
        JSON.stringify({ 
          error: { 
            code: 'INTERNAL_ERROR', 
            message: 'Failed to create visit', 
            status: 500 
          }
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Insert activity entry (CRITICAL - must succeed)
    const { error: activityError } = await supabase
      .from('activity')
      .insert({
        type: 'visit',
        subject_id: visit.id,
        actor_id: user.id,
        visibility: visit.visibility
      })

    if (activityError) {
      console.error('Activity insert error:', activityError)
      // Rollback: delete the visit we just created
      await supabase.from('visits').delete().eq('id', visit.id)
      
      return new Response(
        JSON.stringify({ 
          error: { 
            code: 'INTERNAL_ERROR', 
            message: 'Failed to create activity entry', 
            status: 500 
          }
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Return visit with place details
    return new Response(
      JSON.stringify({
        ...visit,
        place
      }),
      { 
        status: 201, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )

  } catch (error) {
    console.error('Unexpected error:', error)
    return new Response(
      JSON.stringify({ 
        error: { 
          code: 'INTERNAL_ERROR', 
          message: 'Internal server error', 
          status: 500 
        }
      }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
    )
  }
})