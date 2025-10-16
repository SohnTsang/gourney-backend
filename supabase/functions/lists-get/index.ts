// supabase/functions/lists-get/index.ts

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  try {
    // Version check
    const apiVersion = req.headers.get('X-API-Version')
    if (apiVersion !== 'v1') {
      return new Response(
        JSON.stringify({ error: 'Invalid API version' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Auth
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    )

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser()
    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid token' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Parse query parameters
    const url = new URL(req.url)
    const limit = Math.min(parseInt(url.searchParams.get('limit') || '20'), 50)
    const cursor = url.searchParams.get('cursor')

    // Build query
    let query = supabaseClient
      .from('lists')
      .select('id, title, description, visibility, created_at, user_id')
      .eq('user_id', user.id)
      .order('created_at', { ascending: false })
      .order('id', { ascending: false })
      .limit(limit)

    // Apply cursor if provided
    if (cursor) {
      try {
        const decoded = JSON.parse(atob(cursor))
        query = query.or(`created_at.lt.${decoded.created_at},and(created_at.eq.${decoded.created_at},id.lt.${decoded.id})`)
      } catch (e) {
        return new Response(
          JSON.stringify({ error: 'Invalid cursor' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    }

    const { data: lists, error: listsError } = await query

    if (listsError) {
      console.error('Query error:', listsError)
      return new Response(
        JSON.stringify({ error: 'Failed to fetch lists' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get item counts for each list
    const listIds = lists.map(l => l.id)
    let itemCounts: Record<string, number> = {}

    if (listIds.length > 0) {
      const { data: counts } = await supabaseClient
        .from('list_items')
        .select('list_id')
        .in('list_id', listIds)

      if (counts) {
        itemCounts = counts.reduce((acc, item) => {
          acc[item.list_id] = (acc[item.list_id] || 0) + 1
          return acc
        }, {} as Record<string, number>)
      }
    }

    // Add item counts to lists
    const listsWithCounts = lists.map(list => ({
      ...list,
      item_count: itemCounts[list.id] || 0
    }))

    // Generate next cursor
    let nextCursor = null
    if (lists.length === limit) {
      const lastList = lists[lists.length - 1]
      nextCursor = btoa(JSON.stringify({
        created_at: lastList.created_at,
        id: lastList.id
      }))
    }

    return new Response(
      JSON.stringify({ 
        lists: listsWithCounts,
        next_cursor: nextCursor
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})