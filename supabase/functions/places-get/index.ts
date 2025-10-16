// supabase/functions/places-get/index.ts
// GET /places-get?id={placeId}
// Alias for places-detail - gets single place details

import { corsHeaders } from '../_shared/cors.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Extract place ID from query parameter
    const url = new URL(req.url)
    const placeId = url.searchParams.get('id')
    
    if (!placeId) {
      return new Response(
        JSON.stringify({ 
          error: { 
            code: 'VALIDATION_ERROR', 
            message: 'id query parameter required', 
            status: 400 
          }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }}
      )
    }
    
    // Build places-detail URL with place ID in path
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const detailUrl = `${supabaseUrl}/functions/v1/places-detail/${placeId}`
    
    // Forward to places-detail with all headers
    const response = await fetch(detailUrl, {
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
    console.error('places-get error:', error)
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