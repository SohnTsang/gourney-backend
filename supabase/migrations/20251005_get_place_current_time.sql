CREATE OR REPLACE FUNCTION get_place_current_time(p_city text)
RETURNS TABLE(current_day int, current_time_value time)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  tz text;
BEGIN
  SELECT city_timezones.tz INTO tz 
  FROM city_timezones 
  WHERE city = p_city;
  
  IF tz IS NULL THEN
    tz := 'Asia/Tokyo';
  END IF;
  
  RETURN QUERY
  SELECT 
    EXTRACT(DOW FROM (now() AT TIME ZONE tz))::int as current_day,
    (now() AT TIME ZONE tz)::time as current_time_value;
END;
$$;