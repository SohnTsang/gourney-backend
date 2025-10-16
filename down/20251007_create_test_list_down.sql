-- Down Migration: 20251007_create_test_list_down.sql
-- Purpose: Rollback test list creation
-- Week: 4 Step 3
-- Date: 2025-10-07

-- Delete the test list if it exists
DELETE FROM lists 
WHERE id = 'bbbbbbbb-1111-1111-1111-111111111111';

-- Verify deletion
SELECT COUNT(*) as remaining_test_lists 
FROM lists 
WHERE id = 'bbbbbbbb-1111-1111-1111-111111111111';