BEGIN;

-- Simply allow users to DELETE their own comments (hard delete)
DROP POLICY IF EXISTS visit_comments_delete ON visit_comments;

CREATE POLICY visit_comments_delete ON visit_comments
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

COMMIT;