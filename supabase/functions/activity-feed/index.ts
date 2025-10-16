// supabase/functions/activity-feed/index.ts
// Week 5 Step 3: Get personalized activity feed

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3'
import { corsHeaders } from '../_shared/cors.ts'

interface ActivityItem {
  id: string
  type: string
  actor_id: string
  actor_handle: string
  actor_display_name: string
  actor_avatar_url: string | null
  subject_id: string | null
  comment_id: string | null
  comment_text: string | null
  visit_rating: number | null
  visit_photo_urls: string[] | null
  place_id: string | null
  place_name_en: string | null
  place_name_ja: string | null
  created_at: string
  read_at: string | null
  is_following: boolean
}

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

    // Verify auth
    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    const url = new URL(req.url)
    const limit = Math.min(parseInt(url.searchParams.get('limit') || '20'), 50)
    const cursor = url.searchParams.get('cursor') // ISO timestamp
    const unreadOnly = url.searchParams.get('unread_only') === 'true'

    // Build the query
    let query = supabase
      .from('activity')
      .select(`
        id,
        type,
        subject_id,
        comment_id,
        created_at,
        read_at,
        actor:actor_id (
          id,
          handle,
          display_name,
          avatar_url
        ),
        comment:comment_id (
          comment_text
        ),
        visit:subject_id (
          rating,
          photo_urls,
          place:place_id (
            id,
            name_en,
            name_ja
          )
        )
      `)
      .eq('recipient_id', user.id)
      .order('created_at', { ascending: false })
      .limit(limit)

    // Apply cursor pagination
    if (cursor) {
      query = query.lt('created_at', cursor)
    }

    // Apply unread filter
    if (unreadOnly) {
      query = query.is('read_at', null)
    }

    const { data: activities, error: activityError } = await query

    if (activityError) {
      console.error('Activity fetch error:', activityError)
      return new Response(JSON.stringify({ error: 'Failed to fetch activities' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Get user's following list to mark who they follow
    const { data: followingData } = await supabase
      .from('follows')
      .select('followee_id')
      .eq('follower_id', user.id)

    const followingSet = new Set(followingData?.map(f => f.followee_id) || [])

    // Format the response
    const formattedActivities: ActivityItem[] = (activities || []).map((activity: any) => {
      const actor = activity.actor
      const comment = activity.comment
      const visit = activity.visit

      return {
        id: activity.id,
        type: activity.type,
        actor_id: actor?.id || null,
        actor_handle: actor?.handle || null,
        actor_display_name: actor?.display_name || actor?.handle || null,
        actor_avatar_url: actor?.avatar_url || null,
        subject_id: activity.subject_id,
        comment_id: activity.comment_id,
        comment_text: comment?.comment_text || null,
        visit_rating: visit?.rating || null,
        visit_photo_urls: visit?.photo_urls || null,
        place_id: visit?.place?.id || null,
        place_name_en: visit?.place?.name_en || null,
        place_name_ja: visit?.place?.name_ja || null,
        created_at: activity.created_at,
        read_at: activity.read_at,
        is_following: actor?.id ? followingSet.has(actor.id) : false
      }
    })

    // Get unread count
    const { count: unreadCount } = await supabase
      .from('activity')
      .select('id', { count: 'exact', head: true })
      .eq('recipient_id', user.id)
      .is('read_at', null)

    const nextCursor = formattedActivities.length === limit
      ? formattedActivities[formattedActivities.length - 1].created_at
      : null

    return new Response(JSON.stringify({
      activities: formattedActivities,
      unread_count: unreadCount || 0,
      next_cursor: nextCursor
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })

  } catch (error) {
    console.error('Activity feed error:', error)
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})