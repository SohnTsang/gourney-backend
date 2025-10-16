// supabase/functions/visits-history/index.ts

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

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

    if (req.method !== 'GET') {
      return new Response(
        JSON.stringify({
          error: {
            code: 'METHOD_NOT_ALLOWED',
            message: 'Only GET method allowed',
            status: 405
          }
        }),
        { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
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

    // Parse URL parameters
    const url = new URL(req.url)
    const handle = url.searchParams.get('handle')
    const limit = Math.min(parseInt(url.searchParams.get('limit') || '20'), 50)
    const cursorCreatedAt = url.searchParams.get('cursor_created_at')
    const cursorId = url.searchParams.get('cursor_id')

    if (!handle) {
      return new Response(
        JSON.stringify({
          error: {
            code: 'VALIDATION_ERROR',
            message: 'handle query parameter required',
            field: 'handle',
            status: 400
          }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Get the target user by handle
    const { data: targetUser, error: userError } = await supabase
      .from('users')
      .select('id')
      .eq('handle', handle)
      .is('deleted_at', null)
      .single()

    if (userError || !targetUser) {
      return new Response(
        JSON.stringify({
          error: {
            code: 'NOT_FOUND',
            message: 'User not found',
            status: 404
          }
        }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Check relationship: owner, friend, or stranger
    const isOwner = targetUser.id === user.id
    const { data: followData } = await supabase
      .from('follows')
      .select('follower_id')
      .eq('follower_id', user.id)
      .eq('followee_id', targetUser.id)
      .single()
    
    const isFriend = !!followData

    // Check if blocked
    const { data: blockData } = await supabase
      .from('user_blocks')
      .select('blocker_id')
      .or(`blocker_id.eq.${user.id},blocker_id.eq.${targetUser.id}`)
      .or(`blockee_id.eq.${user.id},blockee_id.eq.${targetUser.id}`)
      .limit(1)

    if (blockData && blockData.length > 0) {
      // Blocked - return empty array
      return new Response(
        JSON.stringify({
          visits: [],
          next_cursor: null
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Determine visibility filter based on relationship
    let visibilityFilter: string[]
    if (isOwner) {
      visibilityFilter = ['public', 'friends', 'private']
    } else if (isFriend) {
      visibilityFilter = ['public', 'friends']
    } else {
      visibilityFilter = ['public']
    }

    // Build query
    let query = supabase
      .from('visits')
      .select(`
        id,
        rating,
        comment,
        photo_urls,
        visibility,
        visited_at,
        created_at,
        place:places(
          id,
          name_en,
          name_ja,
          name_zh,
          city,
          ward,
          categories,
          lat,
          lng
        )
      `)
      .eq('user_id', targetUser.id)
      .in('visibility', visibilityFilter)
      .order('visited_at', { ascending: false })
      .order('id', { ascending: false })
      .limit(limit + 1)

    // Cursor pagination
    if (cursorCreatedAt && cursorId) {
      query = query.or(
        `visited_at.lt.${cursorCreatedAt},and(visited_at.eq.${cursorCreatedAt},id.lt.${cursorId})`
      )
    }

    const { data: visits, error: visitsError } = await query

    if (visitsError) {
      console.error('Visits query error:', visitsError)
      return new Response(
        JSON.stringify({
          error: {
            code: 'INTERNAL_ERROR',
            message: 'Failed to fetch visits',
            status: 500
          }
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Handle pagination
    const hasMore = visits.length > limit
    const visitsToReturn = hasMore ? visits.slice(0, limit) : visits
    
    let nextCursor = null
    if (hasMore) {
      const lastVisit = visitsToReturn[visitsToReturn.length - 1]
      nextCursor = {
        cursor_created_at: lastVisit.visited_at,
        cursor_id: lastVisit.id
      }
    }

    return new Response(
      JSON.stringify({
        visits: visitsToReturn,
        next_cursor: nextCursor
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
    )

  } catch (error) {
    console.error('Unexpected error:', error)
    return new Response(
      JSON.stringify({
        error: {
          code: 'INTERNAL_ERROR',
          message: 'An unexpected error occurred',
          status: 500
        }
      }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
    )
  }
})