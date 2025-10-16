import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { rateLimitGuard, rateLimitResponse } from '../_shared/rateLimitGuard.ts'
import { validatePhotoUrls } from '../_shared/photoUrlValidator.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
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

    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: { code: 'UNAUTHORIZED', message: 'Invalid token', status: 401 }}),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Rate limit: 50 updates/hour
    const rateLimitCheck = await rateLimitGuard(supabase, user.id, 'visits_update_per_hour')
    if (!rateLimitCheck.allowed) {
      return rateLimitResponse(rateLimitCheck)
    }

    // Get visit_id from URL query parameter
    const url = new URL(req.url)
    const visitId = url.searchParams.get('visit_id')

    if (!visitId) {
      return new Response(
        JSON.stringify({ 
          error: { 
            code: 'VALIDATION_ERROR', 
            message: 'visit_id query parameter required', 
            status: 400 
          }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Parse request body
    const body = await req.json()
    const { rating, comment, photo_urls, visibility } = body

    // Build update object (only include fields that were provided)
    const updates: Record<string, any> = {}

    // Validate rating if provided
    if (rating !== undefined) {
      if (rating < 1 || rating > 5) {
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
      updates.rating = rating
    }

    // Validate comment if provided
    if (comment !== undefined) {
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
      updates.comment = comment || null
    }

    // Validate photo URLs if provided
    if (photo_urls !== undefined) {
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
      updates.photo_urls = photo_urls || []
    }

    // Validate visibility if provided
    if (visibility !== undefined) {
      if (!['public', 'friends', 'private'].includes(visibility)) {
        return new Response(
          JSON.stringify({ 
            error: { 
              code: 'VALIDATION_ERROR', 
              message: 'Visibility must be public, friends, or private', 
              field: 'visibility', 
              status: 400 
            }
          }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
        )
      }
      updates.visibility = visibility
    }

    // Check if there are any updates
    if (Object.keys(updates).length === 0) {
      return new Response(
        JSON.stringify({ 
          error: { 
            code: 'VALIDATION_ERROR', 
            message: 'No valid fields to update', 
            status: 400 
          }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Update visit (RLS ensures only owner can update)
    const { data: visit, error: updateError } = await supabase
      .from('visits')
      .update(updates)
      .eq('id', visitId)
      .eq('user_id', user.id) // Extra safety check
      .select()
      .single()

    if (updateError || !visit) {
      // Check if visit doesn't exist or doesn't belong to user
      const { data: existingVisit } = await supabase
        .from('visits')
        .select('id, user_id')
        .eq('id', visitId)
        .single()

      if (!existingVisit) {
        return new Response(
          JSON.stringify({ 
            error: { 
              code: 'NOT_FOUND', 
              message: 'Visit not found', 
              status: 404 
            }
          }),
          { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
        )
      }

      if (existingVisit.user_id !== user.id) {
        return new Response(
          JSON.stringify({ 
            error: { 
              code: 'FORBIDDEN', 
              message: 'Cannot update another user\'s visit', 
              status: 403 
            }
          }),
          { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
        )
      }

      console.error('Visit update error:', updateError)
      return new Response(
        JSON.stringify({ 
          error: { 
            code: 'INTERNAL_ERROR', 
            message: 'Failed to update visit', 
            status: 500 
          }
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // CRITICAL: If visibility changed, update corresponding activity entry
    if (visibility !== undefined) {
      const { error: activityError } = await supabase
        .from('activity')
        .update({ visibility })
        .eq('type', 'visit')
        .eq('subject_id', visitId)

      if (activityError) {
        console.error('Activity visibility update error:', activityError)
        // Don't fail the request, but log it
      }
    }

    // Get place details for response
    const { data: place } = await supabase
      .from('places')
      .select('id, name_en, name_ja, city, ward, categories, lat, lng')
      .eq('id', visit.place_id)
      .single()

    return new Response(
      JSON.stringify({
        ...visit,
        place
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
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