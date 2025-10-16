// supabase/functions/places-moderate/index.ts
// Week 6: Admin moderation for user-submitted places
// Approve/reject pending places and award bonus points

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-api-version',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
};

interface ModerateRequest {
  place_id: string;
  action: 'approve' | 'reject';
  admin_notes?: string;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  try {
    // Auth check
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Authentication required' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const token = authHeader.replace('Bearer ', '');
    
    // Verify token
    const verifyResponse = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: {
        'Authorization': `Bearer ${token}`,
        'apikey': supabaseAnonKey,
      },
    });

    if (!verifyResponse.ok) {
      return new Response(
        JSON.stringify({ error: 'Invalid or expired token' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const user = await verifyResponse.json();
    if (!user || !user.id) {
      return new Response(
        JSON.stringify({ error: 'Authentication required' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const serviceClient = createClient(supabaseUrl, supabaseServiceKey);

    // Check if user is admin (role = 'admin' in users table)
    const { data: userRecord } = await serviceClient
      .from('users')
      .select('role')
      .eq('id', user.id)
      .single();

    if (!userRecord || userRecord.role !== 'admin') {
      return new Response(
        JSON.stringify({ error: 'Admin access required' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // GET: List pending places for moderation
    if (req.method === 'GET') {
      const url = new URL(req.url);
      const status = url.searchParams.get('status') || 'pending';
      const limit = parseInt(url.searchParams.get('limit') || '20');

      const { data: places, error } = await serviceClient
        .from('places')
        .select(`
          id,
          provider,
          provider_place_id,
          name_en,
          name_ja,
          name_zh,
          city,
          ward,
          lat,
          lng,
          categories,
          moderation_status,
          submission_notes,
          created_by,
          created_at
        `)
        .eq('moderation_status', status)
        .not('created_by', 'is', null)
        .order('created_at', { ascending: false })
        .limit(limit);

      if (error) {
        console.error('Failed to fetch places:', error);
        return new Response(
          JSON.stringify({ error: 'Failed to fetch places' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      return new Response(
        JSON.stringify({
          places: places || [],
          count: places?.length || 0,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      );
    }

    // POST: Approve or reject a place
    if (req.method === 'POST') {
      const { place_id, action, admin_notes }: ModerateRequest = await req.json();

      // Validation
      if (!place_id || !action) {
        return new Response(
          JSON.stringify({ error: 'place_id and action are required' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      if (!['approve', 'reject'].includes(action)) {
        return new Response(
          JSON.stringify({ error: 'action must be "approve" or "reject"' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      // Get the place
      const { data: place, error: fetchError } = await serviceClient
        .from('places')
        .select('id, moderation_status, created_by')
        .eq('id', place_id)
        .single();

      if (fetchError || !place) {
        return new Response(
          JSON.stringify({ error: 'Place not found' }),
          { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      if (place.moderation_status !== 'pending') {
        return new Response(
          JSON.stringify({ 
            error: 'Place already moderated',
            current_status: place.moderation_status 
          }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      const newStatus = action === 'approve' ? 'approved' : 'rejected';

      // Update place moderation status
      const { error: updateError } = await serviceClient
        .from('places')
        .update({
          moderation_status: newStatus,
          reviewed_by: user.id,
          reviewed_at: new Date().toISOString(),
          submission_notes: admin_notes 
            ? `${place.submission_notes || ''}\n\nAdmin: ${admin_notes}`.trim()
            : place.submission_notes,
        })
        .eq('id', place_id);

      if (updateError) {
        console.error('Failed to update place:', updateError);
        return new Response(
          JSON.stringify({ error: 'Failed to update place' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      console.log(`Place ${place_id} ${action}d by admin ${user.id}`);

      // If approved, the existing trigger (award_ugc_place_points) will automatically award +3 bonus points
      // No need to manually update points here

      return new Response(
        JSON.stringify({
          message: `Place ${action}d successfully`,
          place_id: place_id,
          new_status: newStatus,
          points_awarded: action === 'approve' ? 3 : 0,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      );
    }

    return new Response(
      JSON.stringify({ error: 'Method not allowed' }),
      { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Moderation error:', error);
    return new Response(
      JSON.stringify({ 
        error: 'Moderation failed',
        message: error.message,
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    );
  }
});