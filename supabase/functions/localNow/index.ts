// supabase/functions/localNow/index.ts
// Returns current time in specified timezone (city-based or IANA tz)
// Used for open_now filtering and weekly leaderboard calculations

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-api-version',
};

interface LocalNowRequest {
  city?: string;           // e.g. "Tokyo", "Singapore"
  timezone?: string;       // e.g. "Asia/Tokyo" (fallback if city not found)
}

interface LocalNowResponse {
  now: string;             // ISO 8601 timestamp in local timezone
  timezone: string;        // IANA timezone used
  weekday: number;         // 0=Sunday, 6=Saturday
  time: string;            // HH:MM format (24-hour)
  week_start_date: string; // Monday of current week (YYYY-MM-DD)
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Parse request
    const { city, timezone: fallbackTz }: LocalNowRequest = await req.json();

    let timezone = fallbackTz || 'Asia/Tokyo'; // default

    // If city provided, look up timezone from city_timezones table
    if (city) {
      const { data, error } = await supabase
        .from('city_timezones')
        .select('tz')
        .eq('city', city)
        .single();

      if (!error && data) {
        timezone = data.tz;
      }
    }

    // Get current time in the specified timezone
    const now = new Date();
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: timezone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false,
    });

    const parts = formatter.formatToParts(now);
    const getPart = (type: string) => parts.find(p => p.type === type)?.value || '';

    const year = getPart('year');
    const month = getPart('month');
    const day = getPart('day');
    const hour = getPart('hour');
    const minute = getPart('minute');
    const second = getPart('second');

    // Construct ISO-like timestamp (not true ISO due to local tz, but useful for display)
    const localTimestamp = `${year}-${month}-${day}T${hour}:${minute}:${second}`;
    const time = `${hour}:${minute}`;

    // Calculate weekday (0=Sunday, 6=Saturday)
    const localDate = new Date(`${year}-${month}-${day}`);
    const weekday = localDate.getDay();

    // Calculate Monday of current week (for leaderboard week_start_date)
    const mondayOffset = (weekday === 0 ? -6 : 1 - weekday); // If Sunday, go back 6 days
    const monday = new Date(localDate);
    monday.setDate(localDate.getDate() + mondayOffset);
    const weekStartDate = monday.toISOString().split('T')[0]; // YYYY-MM-DD

    const response: LocalNowResponse = {
      now: localTimestamp,
      timezone,
      weekday,
      time,
      week_start_date: weekStartDate,
    };

    return new Response(
      JSON.stringify(response),
      { 
        headers: { 
          ...corsHeaders, 
          'Content-Type': 'application/json' 
        } 
      }
    );

  } catch (error) {
    console.error('Error in localNow:', error);
    return new Response(
      JSON.stringify({ 
        error: error instanceof Error ? error.message : 'Unknown error' 
      }),
      { 
        status: 500, 
        headers: { 
          ...corsHeaders, 
          'Content-Type': 'application/json' 
        } 
      }
    );
  }
});

/**
 * USAGE EXAMPLES:
 * 
 * 1. Get current time in Tokyo:
 * POST /functions/v1/localNow
 * { "city": "Tokyo" }
 * 
 * Response:
 * {
 *   "now": "2025-10-02T15:30:00",
 *   "timezone": "Asia/Tokyo",
 *   "weekday": 4,
 *   "time": "15:30",
 *   "week_start_date": "2025-09-29"
 * }
 * 
 * 2. Fallback to explicit timezone:
 * POST /functions/v1/localNow
 * { "timezone": "America/New_York" }
 * 
 * 3. Use in open_now filter:
 * const { time, weekday } = response;
 * SELECT * FROM places p
 * JOIN place_hours ph ON ph.place_id = p.id
 * WHERE ph.weekday = weekday
 * AND (
 *   (ph.open_time <= time AND ph.close_time >= time) -- normal hours
 *   OR (ph.open_time > ph.close_time AND (ph.open_time <= time OR ph.close_time >= time)) -- overnight
 * );
 * 
 * 4. Use in leaderboard trigger:
 * const { week_start_date } = response;
 * INSERT INTO city_scores (user_id, city, week_start_date, weekly_points)
 * VALUES ($1, $2, week_start_date, $3)
 * ON CONFLICT (user_id, city, week_start_date) DO UPDATE ...
 */