-- Update notification preferences default
ALTER TABLE devices 
  ALTER COLUMN notification_preferences 
  SET DEFAULT jsonb_build_object(
    'new_follower', true,
    'visit_comment', true,
    'visit_like', true,
    'friend_visit', false
  );

-- Also update existing devices to turn off friend_visit by default
UPDATE devices 
SET notification_preferences = notification_preferences || jsonb_build_object('friend_visit', false)
WHERE (notification_preferences->>'friend_visit') IS NULL
   OR (notification_preferences->>'friend_visit')::boolean = true;
