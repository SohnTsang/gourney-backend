// supabase/functions/visits-list/index.ts
// GET /visits-list?user_handle={handle}&limit=20&cursor={cursor}
// Alias for visits-history - lists user's visits

import { corsHeaders } from '../_shared/cors.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Parse URL and extract query parameters
    const url = new URL(req.url)
    const userHandle = url.searchParams.get('user_handle')
    const limit = url.searchParams.get('limit') || '10'
    const cursor = url.searchParams.get('cursor')
    
    if (!userHandle) {
      return new Response(
        JSON.stringify({ 
          error: { 
            code: 'VALIDATION_ERROR', 
            message: 'user_handle parameter required', 
            status: 400 
          }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }
    
    // Build the visits-history URL with query params
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const historyUrl = `${supabaseUrl}/functions/v1/visits-history?user_handle=${userHandle}&limit=${limit}${cursor ? `&cursor=${cursor}` : ''}`
    
    // Forward to visits-history with all headers
    const response = await fetch(historyUrl, {
      method: 'GET',
      headers: {
        'Authorization': req.headers.get('Authorization') || '',
        'apikey': req.headers.get('apikey') || '',
        'X-API-Version': req.headers.get('X-API-Version') || 'v1',
        'Content-Type': 'application/json'
      }
    })
    
    const responseBody = await response.text()
    
    return new Response(responseBody, {
      status: response.status,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    })
  } catch (error) {
    console.error('visits-list error:', error)
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