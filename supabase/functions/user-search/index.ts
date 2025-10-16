// supabase/functions/user-search/index.ts
// GET /user-search?q=query&limit=20&offset=0
// Search users by handle or display name with smart ranking

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Validate API version
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

    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')

    if (!supabaseUrl || !supabaseAnonKey) {
      return new Response(
        JSON.stringify({ 
          error: { 
            code: 'INTERNAL_ERROR', 
            message: 'Server configuration error', 
            status: 500 
          }
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Auth is optional for search - users can search without logging in
    const authHeader = req.headers.get('Authorization')
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: authHeader ? { Authorization: authHeader } : {} }
    })

    // Get current user if authenticated (for is_following flag)
    let currentUserId: string | null = null
    if (authHeader) {
      const { data: { user } } = await supabase.auth.getUser()
      currentUserId = user?.id || null
    }

    // Parse query parameters
    const url = new URL(req.url)
    const query = url.searchParams.get('q')
    const limit = Math.min(Math.max(1, parseInt(url.searchParams.get('limit') || '20')), 50)
    const offset = Math.max(0, parseInt(url.searchParams.get('offset') || '0'))

    if (!query) {
      return new Response(
        JSON.stringify({ 
          error: { 
            code: 'VALIDATION_ERROR', 
            message: 'q query parameter is required', 
            status: 400 
          }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Return empty results for very short queries
    if (query.length < 2) {
      return new Response(
        JSON.stringify({
          users: [],
          total_count: 0,
          limit,
          offset
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Call the database RPC function
    const { data, error } = await supabase.rpc('search_users', {
      p_query: query,
      p_limit: limit,
      p_offset: offset
    })

    if (error) {
      console.error('Search RPC error:', error)
      return new Response(
        JSON.stringify({ 
          error: { 
            code: 'INTERNAL_ERROR', 
            message: 'Search failed', 
            status: 500 
          }
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // RPC returns a jsonb object with status
    if (data.status && data.status !== 200) {
      return new Response(
        JSON.stringify({ 
          error: { 
            code: 'VALIDATION_ERROR', 
            message: data.detail || data.error || 'Invalid query', 
            status: data.status 
          }
        }),
        { status: data.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    return new Response(
      JSON.stringify({
        users: data.users || [],
        total_count: data.total_count || 0,
        limit: data.limit || limit,
        offset: data.offset || offset
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
    )

  } catch (error) {
    console.error('User search error:', error)
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