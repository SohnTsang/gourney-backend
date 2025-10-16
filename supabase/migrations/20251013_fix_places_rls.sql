-- Allow everyone to read places
ALTER TABLE places ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "places_select_all" ON places;

CREATE POLICY "places_select_all" ON places
  FOR SELECT
  USING (true);