// supabase/functions/process-notifications/index.ts
// Production-ready push notification processor with APNs JWT signing

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3'
import { create, getNumericDate } from 'https://deno.land/x/djwt@v3.0.1/mod.ts'

interface QueuedNotification {
  id: number
  user_id: string
  activity_id: number
  notification_type: string
  apns_token: string
}

interface ActivityData {
  activity_id: number
  activity_type: string
  actor_id: string
  actor_handle: string
  actor_display_name: string
  visit_id?: string
  place_name_en?: string
  place_name_ja?: string
  comment_text?: string
}

const APNS_ENDPOINT = Deno.env.get('APNS_ENVIRONMENT') === 'production'
  ? 'https://api.push.apple.com'
  : 'https://api.sandbox.push.apple.com'

async function createAPNsJWT(teamId: string, keyId: string, privateKeyPem: string): Promise<string> {
  // Parse PEM private key for ES256 signing
  const pemHeader = '-----BEGIN PRIVATE KEY-----'
  const pemFooter = '-----END PRIVATE KEY-----'
  const pemContents = privateKeyPem
    .replace(pemHeader, '')
    .replace(pemFooter, '')
    .replace(/\s/g, '')

  // Decode base64 to get the raw key bytes
  const binaryDer = Uint8Array.from(atob(pemContents), c => c.charCodeAt(0))

  // Import the key for signing
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryDer,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign']
  )

  // Create JWT
  const jwt = await create(
    { alg: 'ES256', kid: keyId },
    {
      iss: teamId,
      iat: getNumericDate(0),
    },
    cryptoKey
  )

  return jwt
}

async function sendAPNs(
  token: string,
  payload: any,
  teamId: string,
  keyId: string,
  privateKey: string,
  bundleId: string
): Promise<{ success: boolean; response?: any; error?: string; statusCode?: number }> {
  try {
    const jwt = await createAPNsJWT(teamId, keyId, privateKey)
    
    const response = await fetch(`${APNS_ENDPOINT}/3/device/${token}`, {
      method: 'POST',
      headers: {
        'authorization': `bearer ${jwt}`,
        'apns-topic': bundleId,
        'apns-push-type': 'alert',
        'apns-priority': '10',
        'apns-expiration': '0',
      },
      body: JSON.stringify(payload),
    })

    const statusCode = response.status

    if (statusCode === 200) {
      return { success: true, statusCode }
    }

    const errorBody = await response.text()
    let errorDetail = errorBody

    try {
      const errorJson = JSON.parse(errorBody)
      errorDetail = errorJson.reason || errorBody
    } catch {
      // Keep raw error body if not JSON
    }

    return {
      success: false,
      statusCode,
      error: `APNs error ${statusCode}: ${errorDetail}`,
      response: { status: statusCode, body: errorBody }
    }
  } catch (error) {
    return {
      success: false,
      error: error instanceof Error ? error.message : String(error),
    }
  }
}

function buildNotificationPayload(
  type: string,
  data: ActivityData,
  badgeCount: number
): any {
  let title = ''
  let body = ''
  let categoryId = ''
  
  switch (type) {
    case 'new_follower':
      title = 'New Follower'
      body = `${data.actor_display_name} started following you`
      categoryId = 'FOLLOWER'
      break
    
    case 'visit_comment':
      title = 'New Comment'
      if (data.comment_text) {
        const truncated = data.comment_text.length > 100 
          ? data.comment_text.substring(0, 97) + '...'
          : data.comment_text
        body = `${data.actor_display_name}: ${truncated}`
      } else {
        body = `${data.actor_display_name} commented on your visit`
      }
      categoryId = 'COMMENT'
      break
    
    case 'visit_like':
      title = 'New Like'
      body = data.place_name_en
        ? `${data.actor_display_name} liked your visit to ${data.place_name_en}`
        : `${data.actor_display_name} liked your visit`
      categoryId = 'LIKE'
      break
    
    case 'friend_visit':
      title = 'New Visit'
      body = data.place_name_en
        ? `${data.actor_display_name} visited ${data.place_name_en}`
        : `${data.actor_display_name} posted a new visit`
      categoryId = 'VISIT'
      break
  }
  
  return {
    aps: {
      alert: {
        title,
        body,
      },
      badge: badgeCount,
      sound: 'default',
      category: categoryId,
      'thread-id': `${type}_${data.actor_id}`,
      'mutable-content': 1,
    },
    notification_type: type,
    activity_id: data.activity_id.toString(),
    actor_id: data.actor_id,
    actor_handle: data.actor_handle,
    visit_id: data.visit_id || null,
  }
}

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders() })
  }

  try {
    // Verify authorization (cron secret or service role)
    const authHeader = req.headers.get('Authorization')
    const cronSecret = Deno.env.get('CRON_SECRET')
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    
    if (!authHeader || 
        (authHeader !== `Bearer ${cronSecret}` && 
         authHeader !== `Bearer ${serviceRoleKey}`)) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders(), 'Content-Type': 'application/json' },
      })
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Get APNs credentials
    const apnsTeamId = Deno.env.get('APNS_TEAM_ID')
    const apnsKeyId = Deno.env.get('APNS_KEY_ID')
    const apnsPrivateKey = Deno.env.get('APNS_PRIVATE_KEY')
    const apnsBundleId = Deno.env.get('APNS_BUNDLE_ID')

    if (!apnsTeamId || !apnsKeyId || !apnsPrivateKey || !apnsBundleId) {
      console.error('Missing APNs credentials')
      return new Response(JSON.stringify({ 
        error: 'APNs not configured',
        message: 'Set APNS_TEAM_ID, APNS_KEY_ID, APNS_PRIVATE_KEY, APNS_BUNDLE_ID',
        processed: 0 
      }), {
        status: 200,
        headers: { ...corsHeaders(), 'Content-Type': 'application/json' },
      })
    }

    // Fetch queued notifications (limit to 100 per run)
    const { data: notifications, error: fetchError } = await supabase
      .from('notification_log')
      .select('*')
      .eq('status', 'queued')
      .order('created_at', { ascending: true })
      .limit(100)

    if (fetchError) {
      console.error('Fetch error:', fetchError)
      return new Response(JSON.stringify({ 
        error: 'Failed to fetch notifications',
        detail: fetchError.message,
        processed: 0 
      }), {
        status: 500,
        headers: { ...corsHeaders(), 'Content-Type': 'application/json' },
      })
    }

    if (!notifications || notifications.length === 0) {
      return new Response(JSON.stringify({ 
        message: 'No notifications to process',
        processed: 0 
      }), {
        status: 200,
        headers: { ...corsHeaders(), 'Content-Type': 'application/json' },
      })
    }

    console.log(`Processing ${notifications.length} notifications`)

    let processed = 0
    let sent = 0
    let failed = 0
    const errors: string[] = []

    for (const notification of notifications as QueuedNotification[]) {
      try {
        // Get activity details using the activity_id directly
        const { data: activityData, error: activityError } = await supabase
          .from('activity')
          .select(`
            id,
            type,
            actor_id,
            subject_id,
            comment_id,
            actor:actor_id (
              id,
              handle,
              display_name
            ),
            comment:comment_id (
              comment_text
            ),
            visit:subject_id (
              id,
              place:place_id (
                name_en,
                name_ja
              )
            )
          `)
          .eq('id', notification.activity_id)
          .single()

        if (activityError || !activityData) {
          await supabase
            .from('notification_log')
            .update({ 
              status: 'skipped',
              error_message: 'Activity not found or deleted'
            })
            .eq('id', notification.id)
          
          failed++
          errors.push(`Activity ${notification.activity_id} not found`)
          continue
        }

        // Format activity data
        const activity: ActivityData = {
          activity_id: activityData.id,
          activity_type: activityData.type,
          actor_id: activityData.actor?.id || '',
          actor_handle: activityData.actor?.handle || '',
          actor_display_name: activityData.actor?.display_name || activityData.actor?.handle || '',
          visit_id: activityData.visit?.id || null,
          place_name_en: activityData.visit?.place?.name_en || null,
          place_name_ja: activityData.visit?.place?.name_ja || null,
          comment_text: activityData.comment?.comment_text || null,
        }

        // Get current badge count
        const { data: device } = await supabase
          .from('devices')
          .select('badge_count')
          .eq('user_id', notification.user_id)
          .eq('apns_token', notification.apns_token)
          .single()

        const badgeCount = (device?.badge_count || 0) + 1

        // Build notification payload
        const payload = buildNotificationPayload(
          notification.notification_type,
          activity,
          badgeCount
        )

        console.log(`Sending notification ${notification.id} to token ${notification.apns_token.substring(0, 10)}...`)

        // Send to APNs
        const result = await sendAPNs(
          notification.apns_token,
          payload,
          apnsTeamId,
          apnsKeyId,
          apnsPrivateKey,
          apnsBundleId
        )

        if (result.success) {
          await supabase
            .from('notification_log')
            .update({
              status: 'sent',
              sent_at: new Date().toISOString(),
              apns_response: result.response || { status: result.statusCode }
            })
            .eq('id', notification.id)

          await supabase
            .from('devices')
            .update({ badge_count: badgeCount })
            .eq('user_id', notification.user_id)
            .eq('apns_token', notification.apns_token)

          sent++
          console.log(`✓ Notification ${notification.id} sent successfully`)
        } else {
          await supabase
            .from('notification_log')
            .update({
              status: 'failed',
              error_message: result.error,
              apns_response: result.response || {}
            })
            .eq('id', notification.id)

          failed++
          errors.push(result.error || 'Unknown error')
          console.error(`✗ Notification ${notification.id} failed: ${result.error}`)
        }

        processed++
      } catch (error) {
        console.error(`Error processing notification ${notification.id}:`, error)
        
        await supabase
          .from('notification_log')
          .update({
            status: 'failed',
            error_message: error instanceof Error ? error.message : String(error)
          })
          .eq('id', notification.id)
        
        failed++
        errors.push(error instanceof Error ? error.message : String(error))
      }
    }

    return new Response(JSON.stringify({
      message: 'Notifications processed',
      processed,
      sent,
      failed,
      errors: errors.length > 0 ? errors.slice(0, 10) : undefined
    }), {
      status: 200,
      headers: { ...corsHeaders(), 'Content-Type': 'application/json' },
    })

  } catch (error) {
    console.error('Process notifications error:', error)
    return new Response(JSON.stringify({ 
      error: 'Internal server error',
      message: error instanceof Error ? error.message : String(error)
    }), {
      status: 500,
      headers: { ...corsHeaders(), 'Content-Type': 'application/json' },
    })
  }
})