// supabase/functions/lists-add-item/index.ts

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

    // Get list ID from query parameter (changed from path)
    const url = new URL(req.url)
    const listId = url.searchParams.get('list_id')

    if (!listId) {
      return new Response(
        JSON.stringify({ error: 'list_id query parameter required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Parse body
    const body = await req.json()
    const { place_id, note } = body

    // Validation
    if (!place_id || typeof place_id !== 'string') {
      return new Response(
        JSON.stringify({ error: 'place_id is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (note && note.length > 200) {
      return new Response(
        JSON.stringify({ error: 'Note must be 200 characters or less' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify list exists and user owns it
    const { data: list, error: listError } = await supabaseClient
      .from('lists')
      .select('id, user_id')
      .eq('id', listId)
      .single()

    if (listError || !list) {
      return new Response(
        JSON.stringify({ error: 'List not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (list.user_id !== user.id) {
      return new Response(
        JSON.stringify({ error: 'Not authorized to modify this list' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify place exists
    const { data: place, error: placeError } = await supabaseClient
      .from('places')
      .select('id')
      .eq('id', place_id)
      .single()

    if (placeError || !place) {
      return new Response(
        JSON.stringify({ error: 'Place not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check if item already exists in list
    const { data: existingItem } = await supabaseClient
      .from('list_items')
      .select('id')
      .eq('list_id', listId)
      .eq('place_id', place_id)
      .maybeSingle()

    if (existingItem) {
      return new Response(
        JSON.stringify({ error: 'Place already in list' }),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Add item to list
    const { data: listItem, error: insertError } = await supabaseClient
      .from('list_items')
      .insert({
        list_id: listId,
        place_id: place_id,
        added_by: user.id,
        note: note?.trim() || null
      })
      .select(`
        id,
        note,
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
      .single()

    if (insertError) {
      console.error('Insert error:', insertError)
      console.error('Insert error details:', JSON.stringify(insertError, null, 2))
      return new Response(
        JSON.stringify({ 
          error: 'Failed to add item to list',
          details: insertError.message,
          code: insertError.code
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({ item: listItem }),
      { status: 201, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})