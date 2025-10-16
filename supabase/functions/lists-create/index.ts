// supabase/functions/lists-create/index.ts
// POST /lists-create
// Creates a new list (respects remote_config for rate limits)

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

    // ===== RATE LIMITING (checks remote_config) =====
    // Check if rate limiting is enabled
    const { data: configData } = await supabase
      .from('remote_config')
      .select('value')
      .eq('key', 'rate_limits_on')
      .maybeSingle()

    const rateLimitsEnabled = configData?.value?.enabled ?? true
    const listsPerDayLimit = configData?.value?.limits?.lists_per_day ?? 10

    if (rateLimitsEnabled) {
      // Count lists created in last 24 hours
      const windowStart = new Date(Date.now() - 24 * 60 * 60 * 1000)
      
      const { count } = await supabase
        .from('lists')
        .select('*', { count: 'exact', head: true })
        .eq('user_id', user.id)
        .gte('created_at', windowStart.toISOString())

      if (count !== null && count >= listsPerDayLimit) {
        // Calculate retry-after
        const { data: oldestList } = await supabase
          .from('lists')
          .select('created_at')
          .eq('user_id', user.id)
          .gte('created_at', windowStart.toISOString())
          .order('created_at', { ascending: true })
          .limit(1)
          .maybeSingle()

        let retryAfter = 86400 // 24 hours default
        if (oldestList) {
          const oldestTime = new Date(oldestList.created_at).getTime()
          const expiresAt = oldestTime + (24 * 60 * 60 * 1000)
          retryAfter = Math.ceil((expiresAt - Date.now()) / 1000)
        }

        return new Response(
          JSON.stringify({
            error: {
              code: 'RATE_LIMIT_EXCEEDED',
              message: `Rate limit exceeded: ${listsPerDayLimit} lists per day`,
              status: 429
            }
          }),
          { 
            status: 429, 
            headers: { 
              ...corsHeaders, 
              'Content-Type': 'application/json',
              'Retry-After': retryAfter.toString()
            }
          }
        )
      }
    }
    // ===== END RATE LIMITING =====

    // Parse request body
    const body = await req.json()
    const { title, description, visibility } = body

    // Validation
    if (!title || typeof title !== 'string') {
      return new Response(
        JSON.stringify({
          error: { code: 'VALIDATION_ERROR', message: 'title is required', status: 400 }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    if (title.length > 100) {
      return new Response(
        JSON.stringify({
          error: { code: 'VALIDATION_ERROR', message: 'Title max 100 chars', status: 400 }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    if (description && description.length > 500) {
      return new Response(
        JSON.stringify({
          error: { code: 'VALIDATION_ERROR', message: 'Description max 500 chars', status: 400 }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    if (visibility && !['public', 'friends', 'private'].includes(visibility)) {
      return new Response(
        JSON.stringify({
          error: { code: 'VALIDATION_ERROR', message: 'Invalid visibility', status: 400 }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Create list
    const { data: list, error: insertError } = await supabase
      .from('lists')
      .insert({
        user_id: user.id,
        title: title.trim(),
        description: description?.trim() || null,
        visibility: visibility || 'public',
        is_system: false
      })
      .select()
      .single()

    if (insertError) {
      console.error('List insert error:', insertError)
      return new Response(
        JSON.stringify({
          error: { code: 'INTERNAL_ERROR', message: 'Failed to create list', status: 500 }
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    return new Response(
      JSON.stringify(list),
      { status: 201, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
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