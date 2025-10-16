// supabase/functions/lists-detail/index.ts

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

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

    const url = new URL(req.url)
    const pathParts = url.pathname.split('/')
    const listId = pathParts[pathParts.length - 1]

    if (!listId || listId === 'lists-detail') {
      return new Response(
        JSON.stringify({
          error: { code: 'VALIDATION_ERROR', message: 'List ID required', status: 400 }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    const limit = Math.min(parseInt(url.searchParams.get('limit') || '20'), 50)

    // Fetch list (RLS enforces visibility)
    const { data: list, error: listError } = await supabase
      .from('lists')
      .select(`
        id,
        title,
        description,
        visibility,
        is_system,
        user_id,
        created_at,
        users!lists_user_id_fkey (
          id,
          handle,
          display_name,
          avatar_url
        )
      `)
      .eq('id', listId)
      .single()

    if (listError || !list) {
      return new Response(
        JSON.stringify({
          error: { code: 'NOT_FOUND', message: 'List not found or access denied', status: 404 }
        }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Count items
    const { count: itemCount } = await supabase
      .from('list_items')
      .select('*', { count: 'exact', head: true })
      .eq('list_id', listId)

    // Fetch items
    const { data: items, error: itemsError } = await supabase
      .from('list_items')
      .select(`
        id,
        place_id,
        note,
        added_by,
        created_at,
        places!list_items_place_id_fkey (
          id,
          name_en,
          name_ja,
          name_zh,
          city,
          ward,
          categories,
          price_level,
          lat,
          lng
        )
      `)
      .eq('list_id', listId)
      .order('created_at', { ascending: false })
      .limit(limit + 1)

    if (itemsError) {
      console.error('Items error:', itemsError)
      return new Response(
        JSON.stringify({
          error: { code: 'INTERNAL_ERROR', message: 'Failed to fetch list items', status: 500 }
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    const hasMore = items && items.length > limit
    const itemsToReturn = hasMore ? items.slice(0, limit) : (items || [])

    // Get visit stats for places
    const placeIds = itemsToReturn.map(item => item.place_id).filter(Boolean)
    let statsMap = new Map()
    
    if (placeIds.length > 0) {
      const { data: placeStats } = await supabase
        .from('visits')
        .select('place_id, rating')
        .in('place_id', placeIds)
        .is('deleted_at', null)

      if (placeStats) {
        placeStats.forEach(visit => {
          if (!statsMap.has(visit.place_id)) {
            statsMap.set(visit.place_id, { ratings: [], count: 0 })
          }
          const stats = statsMap.get(visit.place_id)
          stats.ratings.push(visit.rating)
          stats.count++
        })
      }
    }

    const formattedItems = itemsToReturn.map(item => ({
      id: item.id,
      place_id: item.place_id,
      note: item.note,
      added_at: item.created_at,
      added_by: item.added_by,
      place: item.places ? {
        id: item.places.id,
        name_en: item.places.name_en,
        name_ja: item.places.name_ja,
        name_zh: item.places.name_zh,
        city: item.places.city,
        ward: item.places.ward,
        categories: item.places.categories,
        price_level: item.places.price_level,
        lat: item.places.lat,
        lng: item.places.lng,
        avg_rating: statsMap.has(item.place_id) 
          ? statsMap.get(item.place_id).ratings.reduce((a, b) => a + b, 0) / statsMap.get(item.place_id).ratings.length 
          : null,
        visit_count: statsMap.get(item.place_id)?.count || 0
      } : null
    }))

    return new Response(
      JSON.stringify({
        list: {
          id: list.id,
          title: list.title,
          description: list.description,
          visibility: list.visibility,
          is_system: list.is_system,
          owner_id: list.user_id,
          owner_handle: list.users?.handle || 'unknown',
          owner_display_name: list.users?.display_name || null,
          owner_avatar_url: list.users?.avatar_url || null,
          created_at: list.created_at,
          item_count: itemCount || 0
        },
        items: formattedItems,
        next_cursor: hasMore && itemsToReturn.length > 0 ? itemsToReturn[itemsToReturn.length - 1].created_at : null
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
    )

  } catch (error) {
    console.error('Unexpected error:', error)
    return new Response(
      JSON.stringify({
        error: { code: 'INTERNAL_ERROR', message: 'Internal server error', status: 500 }
      }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
    )
  }
})