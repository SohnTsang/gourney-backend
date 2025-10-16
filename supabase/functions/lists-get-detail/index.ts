import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3';
import { corsHeaders } from '../_shared/cors.ts';

interface ListItem {
  id: string;
  place_id: string;
  note: string | null;
  created_at: string;
  place: {
    id: string;
    name_en: string | null;
    name_ja: string | null;
    name_zh: string | null;
    city: string;
    ward: string | null;
    categories: string[];
    price_level: number | null;
    lat: number;
    lng: number;
  };
}

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
        JSON.stringify({ error: 'Invalid or missing API version. Please include X-API-Version: v1 header.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // 2. Extract list ID from URL
    const url = new URL(req.url);
    const pathParts = url.pathname.split('/');
    const listId = pathParts[pathParts.length - 1];

    if (!listId || listId === 'lists-get-detail') {
      return new Response(
        JSON.stringify({ error: 'List ID is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // 3. Get pagination params
    const limit = Math.min(parseInt(url.searchParams.get('limit') || '20'), 50);
    const cursor = url.searchParams.get('cursor');

    // 4. Authenticate user
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Create admin client first to verify the JWT
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // Extract JWT from Bearer token
    const jwt = authHeader.replace('Bearer ', '');
    
    // Verify JWT and get user
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(jwt);
    
    if (authError || !user) {
      console.error('Auth error:', authError);
      return new Response(
        JSON.stringify({ 
          error: 'Unauthorized',
          details: authError?.message || 'Invalid token'
        }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log('User authenticated:', user.id);

    // Create client with user context for RLS
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: {
          headers: { Authorization: authHeader },
        },
      }
    );

    // 5. Fetch list metadata (RLS will check visibility)
    const { data: list, error: listError } = await supabaseClient
      .from('lists')
      .select(`
        id,
        user_id,
        title,
        description,
        visibility,
        created_at
      `)
      .eq('id', listId)
      .single();

    if (listError || !list) {
      console.error('List fetch error:', listError);
      return new Response(
        JSON.stringify({ error: 'List not found or you do not have permission to view it' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // 6. Get owner details
    const { data: owner } = await supabaseClient
      .from('users')
      .select('id, handle, display_name, avatar_url')
      .eq('id', list.user_id)
      .single();

    // 7. Build items query with cursor pagination
    let itemsQuery = supabaseClient
      .from('list_items')
      .select(`
        id,
        place_id,
        note,
        created_at,
        places (
          id,
          name_en,
          name_ja,
          name_zh,
          city,
          ward,
          categories,
          price_level,
          lat,
          lng
        )
      `)
      .eq('list_id', listId)
      .order('created_at', { ascending: false })
      .order('id', { ascending: false })
      .limit(limit + 1);

    // Apply cursor if provided
    if (cursor) {
      try {
        const decodedCursor = JSON.parse(atob(cursor));
        itemsQuery = itemsQuery
          .or(`created_at.lt.${decodedCursor.created_at},and(created_at.eq.${decodedCursor.created_at},id.lt.${decodedCursor.id})`);
      } catch {
        return new Response(
          JSON.stringify({ error: 'Invalid cursor' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
    }

    const { data: rawItems, error: itemsError } = await itemsQuery;

    if (itemsError) {
      console.error('Error fetching list items:', itemsError);
      return new Response(
        JSON.stringify({ error: 'Failed to fetch list items' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // 8. Process pagination
    const hasMore = rawItems.length > limit;
    const items = hasMore ? rawItems.slice(0, limit) : rawItems;

    let nextCursor = null;
    if (hasMore) {
      const lastItem = items[items.length - 1];
      nextCursor = btoa(JSON.stringify({
        created_at: lastItem.created_at,
        id: lastItem.id
      }));
    }

    // 9. Get total item count
    const { count: itemCount } = await supabaseClient
      .from('list_items')
      .select('id', { count: 'exact', head: true })
      .eq('list_id', listId);

    // 10. Format response with place details
    const formattedItems: ListItem[] = items.map((item: any) => {
      const place = item.places;
      return {
        id: item.id,
        place_id: item.place_id,
        note: item.note,
        created_at: item.created_at,
        place: {
          id: place.id,
          name_en: place.name_en,
          name_ja: place.name_ja,
          name_zh: place.name_zh,
          city: place.city,
          ward: place.ward,
          categories: place.categories || [],
          price_level: place.price_level,
          lat: place.lat,
          lng: place.lng
        }
      };
    });

    // 11. Return response
    return new Response(
      JSON.stringify({
        list: {
          id: list.id,
          title: list.title,
          description: list.description,
          visibility: list.visibility,
          owner_id: list.user_id,
          owner_handle: owner?.handle || null,
          owner_display_name: owner?.display_name || null,
          owner_avatar_url: owner?.avatar_url || null,
          created_at: list.created_at,
          item_count: itemCount || 0
        },
        items: formattedItems,
        next_cursor: nextCursor
      }),
      { 
        status: 200, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    );

  } catch (error) {
    console.error('Unexpected error:', error);
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});