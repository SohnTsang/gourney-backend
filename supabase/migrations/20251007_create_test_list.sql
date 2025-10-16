-- Migration: 20251007_create_test_list.sql
-- Purpose: Create temporary test list for testing lists-delete function
-- Week: 4 Step 3
-- Date: 2025-10-07

-- Create a temporary test list for testuser
INSERT INTO lists (id, user_id, title, visibility, is_system, created_at)
VALUES (
  'bbbbbbbb-1111-1111-1111-111111111111',
  '1d6d3310-2c47-48a0-802b-bbc72599bc7d', -- testuser's ID
  'Temporary Test List',
  'public',
  false,
  NOW()
);

-- Verify it was created
SELECT id, title, user_id, is_system, visibility 
FROM lists 
WHERE id = 'bbbbbbbb-1111-1111-1111-111111111111';