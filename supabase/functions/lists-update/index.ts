// supabase/functions/lists-update/index.ts

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

    if (req.method !== 'PATCH') {
      return new Response(
        JSON.stringify({
          error: { code: 'METHOD_NOT_ALLOWED', message: 'Only PATCH allowed', status: 405 }
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

    // Get list ID from query param
    const url = new URL(req.url)
    const listId = url.searchParams.get('list_id')

    if (!listId) {
      return new Response(
        JSON.stringify({
          error: { code: 'VALIDATION_ERROR', message: 'list_id query parameter required', field: 'list_id', status: 400 }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Parse body
    const body = await req.json()
    const { title, description, visibility } = body

    // Validation
    if (title !== undefined) {
      if (!title || title.length === 0) {
        return new Response(
          JSON.stringify({
            error: { code: 'VALIDATION_ERROR', message: 'Title cannot be empty', field: 'title', status: 400 }
          }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
        )
      }
      if (title.length > 100) {
        return new Response(
          JSON.stringify({
            error: { code: 'VALIDATION_ERROR', message: 'Title max 100 chars', field: 'title', status: 400 }
          }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
        )
      }
    }

    if (description !== undefined && description !== null && description.length > 500) {
      return new Response(
        JSON.stringify({
          error: { code: 'VALIDATION_ERROR', message: 'Description max 500 chars', field: 'description', status: 400 }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    if (visibility !== undefined && !['public', 'friends', 'private'].includes(visibility)) {
      return new Response(
        JSON.stringify({
          error: { code: 'VALIDATION_ERROR', message: 'Invalid visibility', field: 'visibility', status: 400 }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Fetch existing list to check ownership
    const { data: existingList, error: fetchError } = await supabase
      .from('lists')
      .select('id, user_id, visibility, is_system')
      .eq('id', listId)
      .single()

    if (fetchError || !existingList) {
      return new Response(
        JSON.stringify({
          error: { code: 'NOT_FOUND', message: 'List not found or access denied', status: 404 }
        }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Check ownership
    if (existingList.user_id !== user.id) {
      return new Response(
        JSON.stringify({
          error: { code: 'FORBIDDEN', message: 'You do not own this list', status: 403 }
        }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Prevent updating system lists
    if (existingList.is_system) {
      return new Response(
        JSON.stringify({
          error: { code: 'FORBIDDEN', message: 'Cannot modify system lists', status: 403 }
        }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Build update object (only include provided fields)
    const updates: any = {}
    if (title !== undefined) updates.title = title
    if (description !== undefined) updates.description = description
    if (visibility !== undefined) updates.visibility = visibility

    if (Object.keys(updates).length === 0) {
      return new Response(
        JSON.stringify({
          error: { code: 'VALIDATION_ERROR', message: 'No fields to update', status: 400 }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Update list
    const { data: updatedList, error: updateError } = await supabase
      .from('lists')
      .update(updates)
      .eq('id', listId)
      .select()
      .single()

    if (updateError) {
      console.error('Update error:', updateError)
      return new Response(
        JSON.stringify({
          error: { code: 'INTERNAL_ERROR', message: 'Failed to update list', status: 500 }
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // CRITICAL: If visibility changed, propagate to activity entries
    if (visibility !== undefined && visibility !== existingList.visibility) {
      // Get all list_items for this list
      const { data: listItems } = await supabase
        .from('list_items')
        .select('id')
        .eq('list_id', listId)

      if (listItems && listItems.length > 0) {
        const itemIds = listItems.map(item => item.id)
        
        // Update activity visibility for all list_add entries
        const { error: activityUpdateError } = await supabase
          .from('activity')
          .update({ visibility: visibility })
          .eq('type', 'list_add')
          .in('subject_id', itemIds)

        if (activityUpdateError) {
          console.error('Activity update error:', activityUpdateError)
          // Not critical enough to fail the request, but log it
        }
      }
    }

    return new Response(
      JSON.stringify(updatedList),
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