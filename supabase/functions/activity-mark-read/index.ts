// supabase/functions/activity-mark-read/index.ts
// Week 5 Step 3: Mark activities as read

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3'
import { corsHeaders } from '../_shared/cors.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing authorization' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    )

    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    const url = new URL(req.url)
    const activityId = url.searchParams.get('activity_id')
    const markAll = url.searchParams.get('mark_all') === 'true'

    if (!activityId && !markAll) {
      return new Response(JSON.stringify({ error: 'Missing activity_id or mark_all parameter' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    if (markAll) {
      // Mark all unread activities as read
      const { error: updateError } = await supabase
        .from('activity')
        .update({ read_at: new Date().toISOString() })
        .eq('recipient_id', user.id)
        .is('read_at', null)

      if (updateError) {
        console.error('Mark all read error:', updateError)
        return new Response(JSON.stringify({ error: 'Failed to mark activities as read' }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      }

      return new Response(JSON.stringify({ success: true, marked_all: true }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Mark single activity as read
    const { error: updateError } = await supabase
      .from('activity')
      .update({ read_at: new Date().toISOString() })
      .eq('id', activityId)
      .eq('recipient_id', user.id)
      .is('read_at', null)

    if (updateError) {
      console.error('Mark read error:', updateError)
      return new Response(JSON.stringify({ error: 'Failed to mark activity as read' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })

  } catch (error) {
    console.error('Mark read error:', error)
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})