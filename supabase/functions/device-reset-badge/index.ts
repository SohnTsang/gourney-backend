// supabase/functions/device-reset-badge/index.ts

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
      return bad(500, 'server_misconfigured', 'Missing environment variables')
    }

    if (req.headers.get('X-API-Version') !== 'v1') {
      return bad(400, 'bad_request', 'Missing or invalid X-API-Version')
    }

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return bad(401, 'unauthorized', 'Missing Authorization header')
    }

    const { user, error: authError } = await getUserFromAuth(SUPABASE_URL, authHeader)
    
    if (authError || !user || !user.id) {
      return bad(401, 'unauthorized', 'Invalid or expired token')
    }

    const url = new URL(req.url)
    const apnsToken = url.searchParams.get('apns_token')

    if (!apnsToken) {
      return bad(400, 'bad_request', 'apns_token query parameter is required')
    }

    const serviceSupabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    
    const { error: updateError } = await serviceSupabase
      .from('devices')
      .update({ badge_count: 0 })
      .eq('user_id', user.id)
      .eq('apns_token', apnsToken)

    if (updateError) {
      console.error('Reset badge error:', updateError)
      return bad(500, 'db_error', updateError.message)
    }

    return json({ success: true, badge_count: 0 })

  } catch (error) {
    console.error('Reset badge error:', error)
    return bad(500, 'server_error', error instanceof Error ? error.message : String(error))
  }
})