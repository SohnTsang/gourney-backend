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

    // Get target user from query parameter
    const url = new URL(req.url)
    const targetUserId = url.searchParams.get('user_id')

    if (!targetUserId) {
      return new Response(
        JSON.stringify({ 
          error: { 
            code: 'VALIDATION_ERROR', 
            message: 'user_id query parameter required', 
            status: 400 
          }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    if (targetUserId === user.id) {
      return new Response(
        JSON.stringify({ 
          error: { 
            code: 'VALIDATION_ERROR', 
            message: 'Cannot follow yourself', 
            status: 400 
          }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    const { data: targetUser, error: targetError } = await supabase
      .from('users')
      .select('id, handle, deleted_at')
      .eq('id', targetUserId)
      .single()

    if (targetError || !targetUser || targetUser.deleted_at) {
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

    // ENHANCEMENT 1: Check for blocks (bidirectional)
    const { data: blockCheck } = await supabase
      .from('user_blocks')
      .select('blocker_id')
      .or(`and(blocker_id.eq.${user.id},blockee_id.eq.${targetUserId}),and(blocker_id.eq.${targetUserId},blockee_id.eq.${user.id})`)
      .limit(1)

    if (blockCheck && blockCheck.length > 0) {
      return new Response(
        JSON.stringify({ 
          error: { 
            code: 'FORBIDDEN', 
            message: 'Cannot follow blocked user', 
            status: 403 
          }
        }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    if (req.method === 'POST') {
      // ENHANCEMENT 2: Rate limiting (200 follows per day)
      const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()
      
      const { count: followCount } = await supabase
        .from('follows')
        .select('follower_id', { count: 'exact', head: true })
        .eq('follower_id', user.id)
        .gte('created_at', oneDayAgo)

      if (followCount && followCount >= 200) {
        const retryAfter = 86400 // 24 hours in seconds
        return new Response(
          JSON.stringify({ 
            error: { 
              code: 'RATE_LIMIT_EXCEEDED', 
              message: 'Maximum 200 follows per day', 
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

      const { data: follow, error: followError } = await supabase
        .from('follows')
        .insert({
          follower_id: user.id,
          followee_id: targetUserId
        })
        .select('created_at')
        .single()

      if (followError) {
        if (followError.code === '23505') {
          return new Response(
            JSON.stringify({ 
              error: { 
                code: 'CONFLICT', 
                message: 'Already following this user', 
                status: 409 
              }
            }),
            { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
          )
        }

        console.error('Follow error:', followError)
        return new Response(
          JSON.stringify({ 
            error: { 
              code: 'INTERNAL_ERROR', 
              message: 'Failed to follow user', 
              status: 500 
            }
          }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
        )
      }

      // ENHANCEMENT 3: Get updated follower count
      const { count: followerCount } = await supabase
        .from('follows')
        .select('follower_id', { count: 'exact', head: true })
        .eq('followee_id', targetUserId)

      return new Response(
        JSON.stringify({
          success: true,
          action: 'followed',
          followee_id: targetUserId,
          followee_handle: targetUser.handle,
          follower_count: followerCount || 0,
          created_at: follow?.created_at
        }),
        { status: 201, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    if (req.method === 'DELETE') {
      const { error: unfollowError } = await supabase
        .from('follows')
        .delete()
        .eq('follower_id', user.id)
        .eq('followee_id', targetUserId)

      if (unfollowError) {
        console.error('Unfollow error:', unfollowError)
        return new Response(
          JSON.stringify({ 
            error: { 
              code: 'INTERNAL_ERROR', 
              message: 'Failed to unfollow user', 
              status: 500 
            }
          }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
        )
      }

      // ENHANCEMENT 3: Get updated follower count
      const { count: followerCount } = await supabase
        .from('follows')
        .select('follower_id', { count: 'exact', head: true })
        .eq('followee_id', targetUserId)

      return new Response(
        JSON.stringify({
          success: true,
          action: 'unfollowed',
          followee_id: targetUserId,
          followee_handle: targetUser.handle,
          follower_count: followerCount || 0
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }

    return new Response(
      JSON.stringify({ 
        error: { 
          code: 'METHOD_NOT_ALLOWED', 
          message: 'Only POST and DELETE allowed', 
          status: 405 
        }
      }),
      { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
    )

  } catch (error) {
    console.error('Unexpected error:', error)
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