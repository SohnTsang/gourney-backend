-- Add role column to users table for admin access control
BEGIN;

ALTER TABLE users 
  ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'user';

-- Add constraint for valid roles
ALTER TABLE users
  DROP CONSTRAINT IF EXISTS check_user_role;

ALTER TABLE users
  ADD CONSTRAINT check_user_role 
  CHECK (role IN ('user', 'admin', 'moderator'));

-- Create index for admin queries
CREATE INDEX IF NOT EXISTS idx_users_role 
  ON users(role) 
  WHERE role != 'user';

COMMENT ON COLUMN users.role IS 'user | admin | moderator - for access control';
COMMIT;