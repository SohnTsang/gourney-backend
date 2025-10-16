import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3';
import { corsHeaders } from '../_shared/cors.ts';

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // 1. Check API version
    const apiVersion = req.headers.get('X-API-Version');
    if (apiVersion !== 'v1') {
      return new Response(
        JSON.stringify({
          error: {
            code: 'INVALID_API_VERSION',
            message: 'Invalid or missing API version. Required: X-API-Version: v1',
            status: 400
          }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // 2. Only allow DELETE method
    if (req.method !== 'DELETE') {
      return new Response(
        JSON.stringify({
          error: {
            code: 'METHOD_NOT_ALLOWED',
            message: 'Method not allowed. Use DELETE.',
            status: 405
          }
        }),
        { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // 3. Extract parameters from query string
    const url = new URL(req.url);
    const listId = url.searchParams.get('list_id');
    const placeId = url.searchParams.get('place_id');

    if (!listId) {
      return new Response(
        JSON.stringify({
          error: {
            code: 'MISSING_PARAMETER',
            message: 'list_id is required',
            field: 'list_id',
            status: 400
          }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!placeId) {
      return new Response(
        JSON.stringify({
          error: {
            code: 'MISSING_PARAMETER',
            message: 'place_id is required',
            field: 'place_id',
            status: 400
          }
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // 4. Authenticate user (use service role pattern)
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(
        JSON.stringify({
          error: {
            code: 'MISSING_AUTH',
            message: 'Missing authorization header',
            status: 401
          }
        }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const jwt = authHeader.replace('Bearer ', '');
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(jwt);

    if (authError || !user) {
      return new Response(
        JSON.stringify({
          error: {
            code: 'UNAUTHORIZED',
            message: 'Invalid or expired token',
            status: 401
          }
        }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // 5. Rate limit check: 30 deletes per hour
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: {
          headers: { Authorization: authHeader },
        },
      }
    );

    const { count: deleteCount } = await supabaseClient
      .from('list_items')
      .select('*', { count: 'exact', head: true })
      .eq('added_by', user.id)
      .gte('created_at', oneHourAgo);

    if ((deleteCount ?? 0) >= 30) {
      const resetTime = new Date(Date.now() + 60 * 60 * 1000);
      return new Response(
        JSON.stringify({
          error: {
            code: 'RATE_LIMIT_EXCEEDED',
            message: 'Rate limit exceeded: 30 deletions per hour',
            status: 429
          }
        }),
        {
          status: 429,
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json',
            'Retry-After': Math.ceil((resetTime.getTime() - Date.now()) / 1000).toString(),
            'X-RateLimit-Limit': '30',
            'X-RateLimit-Remaining': '0',
            'X-RateLimit-Reset': Math.floor(resetTime.getTime() / 1000).toString()
          }
        }
      );
    }

    // 6. Verify list exists and user owns it (RLS enforces)
    const { data: list, error: listError } = await supabaseClient
      .from('lists')
      .select('id, user_id')
      .eq('id', listId)
      .single();

    if (listError || !list) {
      return new Response(
        JSON.stringify({
          error: {
            code: 'NOT_FOUND',
            message: 'List not found or access denied',
            status: 404
          }
        }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // 7. Verify item exists in list
    const { data: item, error: itemError } = await supabaseClient
      .from('list_items')
      .select('id')
      .eq('list_id', listId)
      .eq('place_id', placeId)
      .single();

    if (itemError || !item) {
      return new Response(
        JSON.stringify({
          error: {
            code: 'NOT_FOUND',
            message: 'Item not found in list',
            status: 404
          }
        }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // 8. Delete the list item (cascade will handle activity entries)
    const { error: deleteError } = await supabaseClient
      .from('list_items')
      .delete()
      .eq('list_id', listId)
      .eq('place_id', placeId);

    if (deleteError) {
      console.error('Delete error:', deleteError);
      return new Response(
        JSON.stringify({
          error: {
            code: 'DELETE_FAILED',
            message: 'Failed to remove item',
            status: 500
          }
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // 9. Return success (204 No Content)
    return new Response(null, {
      status: 204,
      headers: corsHeaders
    });

  } catch (error) {
    console.error('Unexpected error:', error);
    return new Response(
      JSON.stringify({
        error: {
          code: 'INTERNAL_ERROR',
          message: 'Internal server error',
          status: 500
        }
      }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});