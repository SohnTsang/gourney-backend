// supabase/functions/moderate-image/index.ts

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

Deno.serve(async (req) => {
  try {
    // Service role access (cron job)
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    console.log('Starting photo moderation sweep...')

    // Fetch recent visits with photos (last 30 minutes)
    const thirtyMinsAgo = new Date(Date.now() - 30 * 60 * 1000).toISOString()
    
    const { data: recentVisits, error: fetchError } = await supabase
      .from('visits')
      .select('id, user_id, photo_urls, visibility')
      .not('photo_urls', 'is', null)
      .gte('created_at', thirtyMinsAgo)
      .neq('visibility', 'private') // Skip already private

    if (fetchError) {
      console.error('Fetch error:', fetchError)
      throw fetchError
    }

    console.log(`Found ${recentVisits?.length || 0} visits to check`)

    let flaggedCount = 0

    for (const visit of recentVisits || []) {
      if (!visit.photo_urls || visit.photo_urls.length === 0) continue

      let shouldFlag = false
      const reasons: string[] = []

      // Check each photo URL
      for (const photoUrl of visit.photo_urls) {
        try {
          // Validate URL pattern (should be from user-photos bucket)
          if (!photoUrl.includes('user-photos/')) {
            shouldFlag = true
            reasons.push('Invalid photo URL pattern')
            break
          }

          // HEAD request to check MIME type and size
          const headResponse = await fetch(photoUrl, { method: 'HEAD' })
          
          if (!headResponse.ok) {
            shouldFlag = true
            reasons.push('Photo not accessible')
            break
          }

          const contentType = headResponse.headers.get('content-type')
          const contentLength = headResponse.headers.get('content-length')

          // Validate MIME type
          if (!contentType || !['image/jpeg', 'image/jpg', 'image/png'].includes(contentType)) {
            shouldFlag = true
            reasons.push(`Invalid MIME type: ${contentType}`)
            break
          }

          // Validate size (4MB max)
          if (contentLength) {
            const sizeInMB = parseInt(contentLength) / (1024 * 1024)
            if (sizeInMB > 4) {
              shouldFlag = true
              reasons.push(`File too large: ${sizeInMB.toFixed(2)}MB`)
              break
            }
          }

          // Future: Add NSFW detection API call here
          // const nsfwCheck = await checkNSFW(photoUrl)
          // if (nsfwCheck.isNSFW) {
          //   shouldFlag = true
          //   reasons.push('NSFW content detected')
          //   break
          // }

        } catch (error) {
          console.error(`Error checking photo ${photoUrl}:`, error)
          shouldFlag = true
          reasons.push('Error validating photo')
          break
        }
      }

      // If flagged, auto-privatize and create report
      if (shouldFlag) {
        console.log(`Flagging visit ${visit.id}: ${reasons.join(', ')}`)
        flaggedCount++

        // Update visit and activity to private
        await supabase
          .from('visits')
          .update({ visibility: 'private' })
          .eq('id', visit.id)

        await supabase
          .from('activity')
          .update({ visibility: 'private' })
          .eq('type', 'visit')
          .eq('subject_id', visit.id)

        // Create report entry
        await supabase
          .from('reports')
          .insert({
            reporter_id: visit.user_id, // System-flagged, but need user_id
            target_type: 'visit',
            target_id: visit.id,
            reporter_comment: `Auto-flagged: ${reasons.join(', ')}`,
            status: 'open'
          })
      }
    }

    console.log(`Moderation complete. Flagged ${flaggedCount} visits.`)

    return new Response(
      JSON.stringify({
        success: true,
        checked: recentVisits?.length || 0,
        flagged: flaggedCount
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' }}
    )

  } catch (error) {
    console.error('Moderation error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' }}
    )
  }
})