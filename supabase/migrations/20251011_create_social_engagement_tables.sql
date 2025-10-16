-- 20251012_create_social_engagement_tables_fixed.sql
-- Week 5 Step 2: Social Engagement (Comments & Likes)
-- FIXED: Uses correct column names (blockee_id not blocked_id)

BEGIN;
SET search_path = public, extensions;

-- ============================================
-- 1. Add deleted_at to visits if missing
-- ============================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='visits' AND column_name='deleted_at'
  ) THEN
    ALTER TABLE visits ADD COLUMN deleted_at TIMESTAMPTZ;
    CREATE INDEX idx_visits_not_deleted ON visits(id) WHERE deleted_at IS NULL;
  END IF;
END $$;

-- ============================================
-- 2. Create visit_comments table
-- ============================================
CREATE TABLE IF NOT EXISTS visit_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_id UUID NOT NULL REFERENCES visits(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  comment_text TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  
  -- Constraints
  CONSTRAINT check_comment_length CHECK (
    char_length(comment_text) >= 1 AND 
    char_length(comment_text) <= 500
  )
);

-- Indexes for visit_comments
CREATE INDEX IF NOT EXISTS idx_visit_comments_visit_created
  ON visit_comments(visit_id, created_at ASC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_visit_comments_user
  ON visit_comments(user_id, created_at DESC)
  WHERE deleted_at IS NULL;

-- ============================================
-- 3. Enable RLS on visit_comments
-- ============================================
ALTER TABLE visit_comments ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS visit_comments_insert ON visit_comments;
DROP POLICY IF EXISTS visit_comments_update ON visit_comments;
DROP POLICY IF EXISTS visit_comments_select ON visit_comments;

-- Insert policy: authenticated users only, visit must exist
CREATE POLICY visit_comments_insert ON visit_comments
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM visits v
      WHERE v.id = visit_id
    )
  );

-- Update policy: owner only (for soft delete)
CREATE POLICY visit_comments_update ON visit_comments
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Select policy: visible if visit is visible to user
-- FIXED: Uses blockee_id instead of blocked_id
CREATE POLICY visit_comments_select ON visit_comments
  FOR SELECT TO authenticated
  USING (
    deleted_at IS NULL AND
    EXISTS (
      SELECT 1 FROM visits v
      WHERE v.id = visit_id
    ) AND
    NOT EXISTS (
      SELECT 1 FROM user_blocks 
      WHERE (blocker_id = auth.uid() AND blockee_id = visit_comments.user_id)
         OR (blocker_id = visit_comments.user_id AND blockee_id = auth.uid())
    )
  );

-- ============================================
-- 4. Create visit_likes table
-- ============================================
CREATE TABLE IF NOT EXISTS visit_likes (
  visit_id UUID NOT NULL REFERENCES visits(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  PRIMARY KEY (visit_id, user_id)
);

-- Indexes for visit_likes
CREATE INDEX IF NOT EXISTS idx_visit_likes_visit
  ON visit_likes(visit_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_visit_likes_user
  ON visit_likes(user_id, created_at DESC);

-- ============================================
-- 5. Enable RLS on visit_likes
-- ============================================
ALTER TABLE visit_likes ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS visit_likes_insert ON visit_likes;
DROP POLICY IF EXISTS visit_likes_delete ON visit_likes;
DROP POLICY IF EXISTS visit_likes_select ON visit_likes;

-- Insert policy: authenticated users only, cannot like own visits
CREATE POLICY visit_likes_insert ON visit_likes
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid() AND
    user_id != (SELECT user_id FROM visits WHERE id = visit_id) AND
    EXISTS (
      SELECT 1 FROM visits v
      WHERE v.id = visit_id
    )
  );

-- Delete policy: owner only
CREATE POLICY visit_likes_delete ON visit_likes
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- Select policy: visible if visit exists and no blocks
-- FIXED: Uses blockee_id instead of blocked_id
CREATE POLICY visit_likes_select ON visit_likes
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM visits v
      WHERE v.id = visit_id
    ) AND
    NOT EXISTS (
      SELECT 1 FROM user_blocks 
      WHERE (blocker_id = auth.uid() AND blockee_id = visit_likes.user_id)
         OR (blocker_id = visit_likes.user_id AND blockee_id = auth.uid())
    )
  );

-- ============================================
-- 6. Add comments for tracking
-- ============================================
COMMENT ON TABLE visit_comments IS 'Week 5 Step 2: Social engagement - comments on visits';
COMMENT ON TABLE visit_likes IS 'Week 5 Step 2: Social engagement - likes on visits';

COMMIT;