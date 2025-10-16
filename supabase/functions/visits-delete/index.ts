// supabase/functions/visits-delete/index.ts

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
          error: {
            code: 'METHOD_NOT_ALLOWED',
            message: 'Only DELETE method allowed',
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

    const url = new URL(req.url)
    const visitId = url.searchParams.get('visit_id')

    if (!visitId) {
      return new Response(
        JSON.stringify({
          error: {
            code: 'VALIDATION_ERROR',
            message: 'visit_id query parameter required',
            field: 'visit_id',
            status: 400
          }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    if (!uuidRegex.test(visitId)) {
      return new Response(
        JSON.stringify({
          error: {
            code: 'VALIDATION_ERROR',
            message: 'Invalid visit_id format',
            field: 'visit_id',
            status: 400
          }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // Rate limit check
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString()
    const { data: rateLimitData } = await supabaseAdmin
      .from('visit_rate_limit')
      .select('id')
      .eq('user_id', user.id)
      .eq('action_type', 'delete')
      .gte('created_at', oneHourAgo)

    if (rateLimitData && rateLimitData.length >= 20) {
      return new Response(
        JSON.stringify({
          error: {
            code: 'RATE_LIMIT_EXCEEDED',
            message: 'Rate limit exceeded: 20 deletes per hour',
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

    // FIXED: Check if visit exists AND is owned by current user
    const { data: existingVisit, error: fetchError } = await supabase
      .from('visits')
      .select('id, user_id')
      .eq('id', visitId)
      .single()

    if (fetchError || !existingVisit) {
      return new Response(
        JSON.stringify({
          error: {
            code: 'NOT_FOUND',
            message: 'Visit not found or access denied',
            status: 404
          }
        }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // FIXED: Explicit ownership check before attempting delete
    if (existingVisit.user_id !== user.id) {
      return new Response(
        JSON.stringify({
          error: {
            code: 'FORBIDDEN',
            message: 'You do not have permission to delete this visit',
            status: 403
          }
        }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Now delete (we know user owns it)
    const { error: deleteError, count } = await supabase
      .from('visits')
      .delete({ count: 'exact' })
      .eq('id', visitId)

    if (deleteError) {
      console.error('Delete error:', deleteError)
      return new Response(
        JSON.stringify({
          error: {
            code: 'INTERNAL_ERROR',
            message: 'Failed to delete visit',
            status: 500
          }
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // FIXED: Check that something was actually deleted
    if (count === 0) {
      return new Response(
        JSON.stringify({
          error: {
            code: 'NOT_FOUND',
            message: 'Visit not found or access denied',
            status: 404
          }
        }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Log rate limit action
    await supabaseAdmin
      .from('visit_rate_limit')
      .insert({
        user_id: user.id,
        action_type: 'delete',
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