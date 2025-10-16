// supabase/functions/device-register/index.ts
// FINAL WORKING VERSION - Uses auth endpoint directly

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3'

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Authorization, apikey, X-API-Version, Content-Type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  }
}

function json(body: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(body), {
    headers: {
      ...corsHeaders(),
      'Content-Type': 'application/json',
      ...init.headers,
    },
    ...init,
  })
}

function bad(status: number, error: string, detail?: string) {
  return json({ error, detail }, { status })
}

// Get user from JWT using Supabase auth endpoint
async function getUserFromAuth(supabaseUrl: string, authHeader: string): Promise<{ user: any, error: any }> {
  try {
    const response = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: {
        'Authorization': authHeader,
        'apikey': Deno.env.get('SUPABASE_ANON_KEY') || ''
      }
    })

    if (!response.ok) {
      const error = await response.text()
      return { user: null, error: { message: error } }
    }

    const user = await response.json()
    return { user, error: null }
  } catch (err) {
    return { user: null, error: err }
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return json({}, { status: 204 })
  }

  try {
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')
    const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    
    if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
      console.error('Missing environment variables')
      return bad(500, 'server_misconfigured', 'Missing environment variables')
    }

    if (req.headers.get('X-API-Version') !== 'v1') {
      return bad(400, 'bad_request', 'Missing or invalid X-API-Version')
    }

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return bad(401, 'unauthorized', 'Missing Authorization header')
    }

    // Verify user by calling auth endpoint directly
    const { user, error: authError } = await getUserFromAuth(SUPABASE_URL, authHeader)
    
    if (authError || !user || !user.id) {
      console.error('Auth verification failed:', authError?.message || 'No user')
      return bad(401, 'unauthorized', 'Invalid or expired token')
    }

    console.log('Authenticated user:', user.id, user.email)

    // Parse request body
    const body = await req.json()

    if (!body.apns_token || typeof body.apns_token !== 'string') {
      return bad(400, 'bad_request', 'apns_token is required')
    }

    // Validate token format (should be 64 hex characters)
    if (!/^[a-fA-F0-9]{64}$/.test(body.apns_token)) {
      return bad(400, 'bad_request', 'Invalid apns_token format (expected 64 hex characters)')
    }

    const deviceData = {
      user_id: user.id,
      apns_token: body.apns_token,
      locale: body.locale || 'ja-JP',
      tz: body.timezone || 'Asia/Tokyo',
      env: body.environment || 'prod',
      last_active: new Date().toISOString(),
      notification_preferences: body.notification_preferences || {
        new_follower: true,
        visit_comment: true,
        visit_like: true,
        friend_visit: false,
      },
    }

    console.log('Upserting device for user:', user.id)

    // Use service role key to upsert (bypasses RLS)
    const serviceSupabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    
    const { data: device, error: upsertError } = await serviceSupabase
      .from('devices')
      .upsert(deviceData, {
        onConflict: 'user_id,apns_token',
      })
      .select()
      .single()

    if (upsertError) {
      console.error('Device upsert error:', upsertError)
      return bad(500, 'db_error', upsertError.message)
    }

    console.log('Device registered successfully')

    return json({
      success: true,
      device: {
        apns_token: device.apns_token,
        notification_preferences: device.notification_preferences,
        badge_count: device.badge_count,
      }
    }, { status: 200 })

  } catch (error) {
    console.error('Device register error:', error)
    return bad(500, 'server_error', error instanceof Error ? error.message : String(error))
  }
})