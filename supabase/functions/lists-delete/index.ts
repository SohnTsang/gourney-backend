// supabase/functions/lists-delete/index.ts

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

    if (req.method !== 'DELETE') {
      return new Response(
        JSON.stringify({
          error: { code: 'METHOD_NOT_ALLOWED', message: 'Only DELETE allowed', status: 405 }
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

    // Rate limit check (10 deletes per hour)
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString()
    const { data: rateLimitData } = await supabaseAdmin
      .from('visit_rate_limit')
      .select('id')
      .eq('user_id', user.id)
      .eq('action_type', 'list_delete')
      .gte('created_at', oneHourAgo)

    if (rateLimitData && rateLimitData.length >= 10) {
      return new Response(
        JSON.stringify({
          error: {
            code: 'RATE_LIMIT_EXCEEDED',
            message: 'Rate limit exceeded: 10 list deletions per hour',
            status: 429
          }
        }),
        { 
          status: 429, 
          headers: { 
            ...corsHeaders, 
            'Content-Type': 'application/json',
            'Retry-After': '3600'
          } 
        }
      )
    }

    // Fetch list to check ownership and if it's a system list
    const { data: existingList, error: fetchError } = await supabase
      .from('lists')
      .select('id, user_id, is_system, title')
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

    // Prevent deleting system/default lists
    if (existingList.is_system) {
      return new Response(
        JSON.stringify({
          error: { 
            code: 'FORBIDDEN', 
            message: 'Cannot delete default system lists (Want to Try, Favorites)', 
            status: 403 
          }
        }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Get all list_items for this list before deletion
    const { data: listItems } = await supabase
      .from('list_items')
      .select('id')
      .eq('list_id', listId)

    // Delete the list (CASCADE will delete list_items automatically)
    const { error: deleteError, count } = await supabase
      .from('lists')
      .delete({ count: 'exact' })
      .eq('id', listId)

    if (deleteError) {
      console.error('Delete error:', deleteError)
      return new Response(
        JSON.stringify({
          error: { code: 'INTERNAL_ERROR', message: 'Failed to delete list', status: 500 }
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    if (count === 0) {
      return new Response(
        JSON.stringify({
          error: { code: 'NOT_FOUND', message: 'List not found or already deleted', status: 404 }
        }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Delete corresponding activity entries for list_add
    // (Activity entries reference list_item.id as subject_id)
    if (listItems && listItems.length > 0) {
      const itemIds = listItems.map(item => item.id)
      
      await supabaseAdmin
        .from('activity')
        .delete()
        .eq('type', 'list_add')
        .in('subject_id', itemIds)
    }

    // Log rate limit action
    await supabaseAdmin
      .from('visit_rate_limit')
      .insert({
        user_id: user.id,
        action_type: 'list_delete',
        ip_address: req.headers.get('x-forwarded-for') || 'unknown'
      })

    return new Response(null, { 
      status: 204, 
      headers: corsHeaders 
    })

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