-- 20251012_push_notifications_setup.sql
-- Week 5 Step 4: Push Notifications Infrastructure

BEGIN;
SET search_path = public, extensions;

-- ============================================
-- 1. Update devices table for better token management
-- ============================================

-- Check if we need to update the devices table
DO $$
BEGIN
  -- Add notification preferences column if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='devices' AND column_name='notification_preferences'
  ) THEN
    ALTER TABLE devices ADD COLUMN notification_preferences JSONB NOT NULL DEFAULT jsonb_build_object(
      'new_follower', true,
      'visit_comment', true,
      'visit_like', true,
      'friend_visit', true
    );
  END IF;

  -- Add badge_count column for iOS badge management
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='devices' AND column_name='badge_count'
  ) THEN
    ALTER TABLE devices ADD COLUMN badge_count INTEGER NOT NULL DEFAULT 0;
  END IF;
END $$;

-- ============================================
-- 2. Create notification_log table for tracking
-- ============================================
CREATE TABLE IF NOT EXISTS notification_log (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  activity_id BIGINT REFERENCES activity(id) ON DELETE CASCADE,
  notification_type TEXT NOT NULL,
  apns_token TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued',
  apns_response JSONB,
  error_message TEXT,
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  CONSTRAINT check_notification_type CHECK (
    notification_type IN ('new_follower', 'visit_comment', 'visit_like', 'friend_visit')
  ),
  CONSTRAINT check_status CHECK (
    status IN ('queued', 'sent', 'failed', 'skipped')
  )
);

-- Indexes for notification_log
CREATE INDEX IF NOT EXISTS idx_notification_log_user_created
  ON notification_log(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notification_log_status
  ON notification_log(status, created_at ASC)
  WHERE status = 'queued';

CREATE INDEX IF NOT EXISTS idx_notification_log_activity
  ON notification_log(activity_id)
  WHERE activity_id IS NOT NULL;

-- ============================================
-- 3. Enable RLS on notification_log
-- ============================================
ALTER TABLE notification_log ENABLE ROW LEVEL SECURITY;

-- Users can only see their own notification logs
DROP POLICY IF EXISTS notification_log_select ON notification_log;
CREATE POLICY notification_log_select ON notification_log
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- ============================================
-- 4. Create function to queue notifications
-- ============================================

CREATE OR REPLACE FUNCTION queue_push_notification(
  p_activity_id BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_activity RECORD;
  v_device RECORD;
  v_notification_type TEXT;
BEGIN
  -- Get activity details
  SELECT 
    a.id,
    a.type,
    a.recipient_id,
    a.actor_id
  INTO v_activity
  FROM activity a
  WHERE a.id = p_activity_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- Map activity type to notification type
  v_notification_type := CASE v_activity.type
    WHEN 'visit_comment' THEN 'visit_comment'
    WHEN 'visit_like' THEN 'visit_like'
    WHEN 'follow' THEN 'new_follower'
    WHEN 'visit' THEN 'friend_visit'
    ELSE NULL
  END;

  IF v_notification_type IS NULL THEN
    RETURN;
  END IF;

  -- Queue notification for each active device
  FOR v_device IN
    SELECT 
      d.user_id,
      d.apns_token,
      d.notification_preferences
    FROM devices d
    WHERE d.user_id = v_activity.recipient_id
      AND d.last_active > NOW() - INTERVAL '30 days'
      -- Check if user wants this notification type
      AND (d.notification_preferences->v_notification_type)::boolean = true
  LOOP
    -- Insert into notification log (prevents duplicates via unique constraint we'll add)
    INSERT INTO notification_log (
      user_id,
      activity_id,
      notification_type,
      apns_token,
      status
    )
    VALUES (
      v_device.user_id,
      p_activity_id,
      v_notification_type,
      v_device.apns_token,
      'queued'
    )
    ON CONFLICT DO NOTHING;
  END LOOP;
END;
$$;

-- ============================================
-- 5. Create trigger to auto-queue notifications
-- ============================================

CREATE OR REPLACE FUNCTION trigger_queue_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Queue notification for new activity
  PERFORM queue_push_notification(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_auto_queue_notification ON activity;
CREATE TRIGGER trigger_auto_queue_notification
  AFTER INSERT ON activity
  FOR EACH ROW
  EXECUTE FUNCTION trigger_queue_notification();

-- ============================================
-- 6. Add unique constraint to prevent duplicate notifications
-- ============================================
CREATE UNIQUE INDEX IF NOT EXISTS idx_notification_log_unique
  ON notification_log(user_id, activity_id, apns_token)
  WHERE status IN ('queued', 'sent');

-- ============================================
-- 7. Add comments
-- ============================================
COMMENT ON TABLE notification_log IS 'Week 5 Step 4: Log of push notifications sent to users';
COMMENT ON FUNCTION queue_push_notification IS 'Week 5 Step 4: Queue push notification for an activity';
COMMENT ON FUNCTION trigger_queue_notification IS 'Week 5 Step 4: Auto-queue notifications when activity is created';

COMMIT;