-- 20251012_enhance_activity_for_comments_likes.sql
-- Week 5 Step 3: Enhance existing activity table for social engagement

BEGIN;
SET search_path = public, extensions;

-- ============================================
-- 1. Check and add new activity types
-- ============================================

-- Drop the old constraint and add new types
ALTER TABLE activity DROP CONSTRAINT IF EXISTS activity_type_valid;

ALTER TABLE activity
  ADD CONSTRAINT activity_type_valid
  CHECK (type IN ('visit', 'follow', 'list_add', 'visit_comment', 'visit_like'));

-- ============================================
-- 2. Add comment_id column if missing
-- ============================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='activity' AND column_name='comment_id'
  ) THEN
    ALTER TABLE activity ADD COLUMN comment_id UUID REFERENCES visit_comments(id) ON DELETE CASCADE;
    CREATE INDEX idx_activity_comment ON activity(comment_id) WHERE comment_id IS NOT NULL;
  END IF;
END $$;

-- ============================================
-- 3. Add recipient_id column (who receives the notification)
-- ============================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='activity' AND column_name='recipient_id'
  ) THEN
    ALTER TABLE activity ADD COLUMN recipient_id UUID REFERENCES users(id) ON DELETE CASCADE;
    CREATE INDEX idx_activity_recipient_created ON activity(recipient_id, created_at DESC);
  END IF;
END $$;

-- ============================================
-- 4. Add read_at column for marking activities as read
-- ============================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='activity' AND column_name='read_at'
  ) THEN
    ALTER TABLE activity ADD COLUMN read_at TIMESTAMPTZ;
    CREATE INDEX idx_activity_recipient_unread ON activity(recipient_id, created_at DESC) WHERE read_at IS NULL;
  END IF;
END $$;

-- ============================================
-- 5. Update RLS policies for activity
-- ============================================

-- Drop old select policy
DROP POLICY IF EXISTS activity_select_policy ON activity;

-- New select policy: users see activities where they are the recipient
CREATE POLICY activity_select_policy ON activity
  FOR SELECT TO authenticated
  USING (
    (recipient_id = auth.uid() OR actor_id = auth.uid())
    AND app.can_see_user(auth.uid(), actor_id)
  );

-- Update policy: users can only mark their own activities as read
DROP POLICY IF EXISTS activity_update_policy ON activity;
CREATE POLICY activity_update_policy ON activity
  FOR UPDATE TO authenticated
  USING (recipient_id = auth.uid())
  WITH CHECK (recipient_id = auth.uid() AND read_at IS NOT NULL);

-- ============================================
-- 6. Create trigger functions for new activity types
-- ============================================

-- Function: Create activity when someone comments on a visit
CREATE OR REPLACE FUNCTION create_activity_visit_comment()
RETURNS TRIGGER AS $$
DECLARE
  visit_owner_id UUID;
  visit_visibility TEXT;
BEGIN
  -- Get the visit owner and visibility
  SELECT user_id, visibility INTO visit_owner_id, visit_visibility
  FROM visits
  WHERE id = NEW.visit_id;
  
  -- Only create activity if commenter is not the visit owner
  IF visit_owner_id IS NOT NULL AND visit_owner_id != NEW.user_id THEN
    INSERT INTO activity (
      type, 
      actor_id, 
      recipient_id, 
      subject_id, 
      comment_id, 
      visibility
    )
    VALUES (
      'visit_comment',
      NEW.user_id,
      visit_owner_id,
      NEW.visit_id,
      NEW.id,
      visit_visibility
    );
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Create activity when someone likes a visit
CREATE OR REPLACE FUNCTION create_activity_visit_like()
RETURNS TRIGGER AS $$
DECLARE
  visit_owner_id UUID;
  visit_visibility TEXT;
BEGIN
  -- Get the visit owner and visibility
  SELECT user_id, visibility INTO visit_owner_id, visit_visibility
  FROM visits
  WHERE id = NEW.visit_id;
  
  -- Only create activity if liker is not the visit owner
  IF visit_owner_id IS NOT NULL AND visit_owner_id != NEW.user_id THEN
    INSERT INTO activity (
      type,
      actor_id,
      recipient_id,
      subject_id,
      visibility
    )
    VALUES (
      'visit_like',
      NEW.user_id,
      visit_owner_id,
      NEW.visit_id,
      visit_visibility
    );
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Update existing new_visit activity creation to use recipient_id
CREATE OR REPLACE FUNCTION create_activity_new_visit()
RETURNS TRIGGER AS $$
BEGIN
  -- Create activity for all followers of the visit creator
  INSERT INTO activity (type, actor_id, recipient_id, subject_id, visibility)
  SELECT 
    'visit',
    NEW.user_id,
    f.follower_id,
    NEW.id,
    NEW.visibility
  FROM follows f
  WHERE f.followee_id = NEW.user_id
    AND f.follower_id != NEW.user_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Delete activity when like is removed
CREATE OR REPLACE FUNCTION delete_activity_visit_like()
RETURNS TRIGGER AS $$
BEGIN
  DELETE FROM activity
  WHERE type = 'visit_like'
    AND actor_id = OLD.user_id
    AND subject_id = OLD.visit_id;
  
  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 7. Create/update triggers
-- ============================================

DROP TRIGGER IF EXISTS trigger_activity_visit_comment ON visit_comments;
CREATE TRIGGER trigger_activity_visit_comment
  AFTER INSERT ON visit_comments
  FOR EACH ROW
  EXECUTE FUNCTION create_activity_visit_comment();

DROP TRIGGER IF EXISTS trigger_activity_visit_like ON visit_likes;
CREATE TRIGGER trigger_activity_visit_like
  AFTER INSERT ON visit_likes
  FOR EACH ROW
  EXECUTE FUNCTION create_activity_visit_like();

DROP TRIGGER IF EXISTS trigger_delete_activity_visit_like ON visit_likes;
CREATE TRIGGER trigger_delete_activity_visit_like
  AFTER DELETE ON visit_likes
  FOR EACH ROW
  EXECUTE FUNCTION delete_activity_visit_like();

-- Update the new visit trigger if it exists
DROP TRIGGER IF EXISTS trigger_activity_new_visit ON visits;
CREATE TRIGGER trigger_activity_new_visit
  AFTER INSERT ON visits
  FOR EACH ROW
  EXECUTE FUNCTION create_activity_new_visit();

-- ============================================
-- 8. Add comments for tracking
-- ============================================
COMMENT ON COLUMN activity.recipient_id IS 'Week 5 Step 3: User who receives this activity notification';
COMMENT ON COLUMN activity.comment_id IS 'Week 5 Step 3: Reference to comment for visit_comment activities';
COMMENT ON COLUMN activity.read_at IS 'Week 5 Step 3: Timestamp when user marked activity as read';

COMMIT;