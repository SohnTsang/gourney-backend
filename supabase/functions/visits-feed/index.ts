import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { encodeCursor, decodeCursor } from '../_shared/cursor.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Check API version
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

    const url = new URL(req.url)
    const limit = Math.min(parseInt(url.searchParams.get('limit') || '20'), 50)
    const cursorParam = url.searchParams.get('cursor')
    
    let cursorCreatedAt = null
    let cursorId = null
    
    if (cursorParam) {
      try {
        const decoded = await decodeCursor(cursorParam)
        cursorCreatedAt = decoded.created_at
        cursorId = parseInt(decoded.id) // activity.id is bigint
      } catch (e) {
        return new Response(
          JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Invalid cursor', status: 400 }}),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
        )
      }
    }

    const { data, error } = await supabase.rpc('get_activity_feed', {
      p_limit: limit + 1, // Fetch one extra to check if there's a next page
      p_cursor_created_at: cursorCreatedAt,
      p_cursor_id: cursorId
    })

    if (error) {
      console.error('Feed query error:', error)
      return new Response(
        JSON.stringify({ error: { code: 'INTERNAL_ERROR', message: 'Failed to fetch feed', status: 500 }}),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    const hasMore = data.length > limit
    const activities = data.slice(0, limit)
    
    let nextCursor = null
    if (hasMore && activities.length > 0) {
      const lastItem = activities[activities.length - 1]
      nextCursor = await encodeCursor({
        created_at: lastItem.activity_created_at,
        id: lastItem.activity_id.toString()
      })
    }

    // Transform to nested structure
    const formattedActivities = activities.map(row => ({
      activity_id: row.activity_id,
      type: row.activity_type,
      created_at: row.activity_created_at,
      actor: {
        id: row.actor_id,
        handle: row.actor_handle,
        display_name: row.actor_display_name,
        avatar_url: row.actor_avatar_url
      },
      visit: row.visit_id ? {
        id: row.visit_id,
        rating: row.visit_rating,
        comment: row.visit_comment,
        photo_urls: row.visit_photo_urls,
        visited_at: row.visit_visited_at,
        place: {
          id: row.place_id,
          name_en: row.place_name_en,
          name_ja: row.place_name_ja,
          city: row.place_city,
          ward: row.place_ward,
          categories: row.place_categories
        }
      } : null
    }))

    return new Response(
      JSON.stringify({
        activities: formattedActivities,
        next_cursor: nextCursor
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
    )

  } catch (error) {
    console.error('Unexpected error:', error)
    return new Response(
      JSON.stringify({ error: { code: 'INTERNAL_ERROR', message: 'Internal server error', status: 500 }}),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
    )
  }
})