// supabase/functions/user-profile/index.ts
// GET /user-profile?handle=USERNAME
// Returns comprehensive user profile with relationship context
// SUPPORTS BOTH AUTHENTICATED AND ANONYMOUS ACCESS

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3'
import { corsHeaders } from '../_shared/cors.ts'

function json(body: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(body), {
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
      ...init.headers,
    },
    ...init,
  })
}

function bad(status: number, error: string, detail?: string) {
  return json({ error, detail }, { status })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return json({}, { status: 204 })
  }

  try {
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')
    const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')

    if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
      return bad(500, 'server_misconfigured')
    }

    if (req.headers.get('X-API-Version') !== 'v1') {
      return bad(400, 'bad_request', 'Missing or invalid X-API-Version')
    }

    const authHeader = req.headers.get('Authorization')
    
    // CRITICAL: Always create client with anon key for RPC calls
    // The RPC function handles authentication internally
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)

    // Get viewer ID (optional - can view public profiles without auth)
    let viewerId: string | null = null
    if (authHeader) {
      try {
        // Verify the JWT token by checking with Supabase auth
        const authResponse = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
          headers: {
            'Authorization': authHeader,
            'apikey': SUPABASE_ANON_KEY
          }
        })
        
        if (authResponse.ok) {
          const userData = await authResponse.json()
          viewerId = userData.id
          console.log(`Authenticated viewer: ${viewerId}`)
        } else {
          console.log('Invalid auth token, proceeding as anonymous')
        }
      } catch (error) {
        console.warn('Auth check failed, proceeding as anonymous:', error)
      }
    } else {
      console.log('No auth header, proceeding as anonymous')
    }

    const url = new URL(req.url)
    const handle = url.searchParams.get('handle')

    if (!handle) {
      return bad(400, 'bad_request', 'handle query parameter is required')
    }

    console.log(`Fetching profile for handle: ${handle}, viewer: ${viewerId || 'anonymous'}`)

    // Call RPC function
    const { data, error } = await supabase.rpc('get_user_profile', {
      p_handle: handle,
      p_viewer_id: viewerId,
    })

    if (error) {
      console.error('Profile fetch error:', error)
      return bad(500, 'db_error', error.message)
    }

    // RPC returns a jsonb object with status
    if (data && typeof data === 'object' && 'status' in data) {
      if (data.status === 404) {
        return json({ error: 'user_not_found' }, { status: 404 })
      }

      if (data.status === 403) {
        return json({ error: 'user_blocked' }, { status: 403 })
      }

      if (data.status !== 200) {
        console.error('RPC returned error status:', data)
        return json({ error: data.error || 'unknown_error' }, { status: data.status })
      }
    }

    // Success case
    if (data && data.user) {
      console.log(`Profile found: ${data.user.handle}, relationship: ${data.user.relationship}`)
      return json(data.user, { status: 200 })
    }

    // Unexpected response format
    console.error('Unexpected RPC response format:', data)
    return bad(500, 'unexpected_response', 'Invalid response from database')

  } catch (error) {
    console.error('User profile error:', error)
    return bad(500, 'server_error', error instanceof Error ? error.message : String(error))
  }
})