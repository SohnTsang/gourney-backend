// supabase/functions/suggested-follows/index.ts
// GET /suggested-follows?limit=20
// Returns personalized follow suggestions based on friends-of-friends and top active users

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

    // Auth required for suggestions
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ 
          error: { 
            code: 'UNAUTHORIZED', 
            message: 'Authentication required', 
            status: 401 
          }
        }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
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

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } }
    })

    // Verify authentication
    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) {
      console.error('Auth verification failed:', authError)
      return new Response(
        JSON.stringify({ 
          error: { 
            code: 'UNAUTHORIZED', 
            message: 'Invalid or expired token', 
            status: 401 
          }
        }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Parse query parameters
    const url = new URL(req.url)
    const limit = Math.min(Math.max(1, parseInt(url.searchParams.get('limit') || '20')), 50)

    console.log(`Getting suggestions for user ${user.id}, limit: ${limit}`)

    // Call the database RPC function
    const { data, error } = await supabase.rpc('get_suggested_follows', {
      p_limit: limit
    })

    if (error) {
      console.error('Suggested follows RPC error:', error)
      return new Response(
        JSON.stringify({ 
          error: { 
            code: 'INTERNAL_ERROR', 
            message: 'Failed to get suggestions', 
            status: 500,
            detail: error.message
          }
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    // Check if RPC returned an error status (the function returns jsonb with status field)
    if (data && typeof data === 'object' && 'status' in data) {
      if (data.status === 401) {
        return new Response(
          JSON.stringify({ 
            error: { 
              code: 'UNAUTHORIZED', 
              message: data.error || 'Authentication required', 
              status: 401 
            }
          }),
          { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
        )
      }
      
      if (data.status !== 200) {
        console.error('RPC returned error status:', data)
        return new Response(
          JSON.stringify({ 
            error: { 
              code: 'INTERNAL_ERROR', 
              message: data.error || 'Failed to get suggestions', 
              status: data.status 
            }
          }),
          { status: data.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
        )
      }
    }

    // Success case
    const suggestions = data?.suggestions || []
    console.log(`Found ${suggestions.length} suggestions`)

    return new Response(
      JSON.stringify({
        suggestions: suggestions
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
    )

  } catch (error) {
    console.error('Suggested follows error:', error)
    return new Response(
      JSON.stringify({ 
        error: { 
          code: 'INTERNAL_ERROR', 
          message: 'Internal server error', 
          status: 500,
          detail: error instanceof Error ? error.message : String(error)
        }
      }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
    )
  }
})