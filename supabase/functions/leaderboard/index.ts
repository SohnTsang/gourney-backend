// functions/leaderboard/index.ts
// GET /leaderboard?city=Tokyo&range=week|lifetime&limit=20&cursor=BASE64(points|user_id)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

type RangeType = "week" | "lifetime";
type Cursor = { points: number; user_id: string };

// ---------- small helpers ----------
const enc = new TextEncoder();
const dec = new TextDecoder();

function json(body: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(body), {
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, OPTIONS",
      "Access-Control-Allow-Headers": "Authorization, apikey, X-API-Version, Content-Type",
      ...init.headers,
    },
    ...init,
  });
}

function bad(status: number, error: string, detail?: string) {
  return json({ error, detail }, { status });
}

function clamp(n: number, min: number, max: number) {
  return Math.max(min, Math.min(max, n));
}

function encCursor(c: Cursor): string {
  return btoa(`${c.points}|${c.user_id}`);
}
function tryDecCursor(s: string | null): Cursor | null {
  if (!s) return null;
  try {
    const raw = atob(s);
    const [p, uid] = raw.split("|");
    const points = Number(p);
    if (!Number.isFinite(points) || !uid || uid.length < 36) return null;
    return { points, user_id: uid };
  } catch {
    return null;
  }
}

// ISO-week Monday (UTC) as yyyy-mm-dd
function isoWeekStartUTC(d: Date): string {
  const utc = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dow = (utc.getUTCDay() + 6) % 7; // Mon=0
  utc.setUTCDate(utc.getUTCDate() - dow);
  return utc.toISOString().slice(0, 10);
}

// ---------- main ----------
Deno.serve(async (req: Request) => {
  // CORS preflight
  if (req.method === "OPTIONS") return json({}, { status: 204 });

  try {
    // Secrets (must be set for this function)
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");
    if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
      return bad(500, "server_misconfigured", "Missing SUPABASE_URL or SUPABASE_ANON_KEY");
    }

    // Contract header
    const apiVersion = req.headers.get("X-API-Version");
    if (apiVersion !== "v1") {
      return bad(400, "bad_request", "Missing or invalid X-API-Version");
    }

    // RLS-aware client using caller JWT
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });

    // Query params
    const url = new URL(req.url);
    const city = url.searchParams.get("city")?.trim();
    const range = (url.searchParams.get("range") ?? "week").toLowerCase() as RangeType;
    const limit = clamp(Number(url.searchParams.get("limit") ?? "20"), 1, 50);
    const cursor = tryDecCursor(url.searchParams.get("cursor"));

    if (!city) return bad(400, "bad_request", "city is required");
    if (range !== "week" && range !== "lifetime") {
      return bad(400, "bad_request", "range must be 'week' or 'lifetime'");
    }

    const weekStart = isoWeekStartUTC(new Date());
    const pointsCol = range === "week" ? "weekly_points" : "lifetime_points";

    // Base query
    let q = supabase
      .from("city_scores")
      .select("user_id, city, week_start_date, weekly_points, lifetime_points")
      .eq("city", city);

    if (range === "week") q = q.eq("week_start_date", weekStart);

    // Keyset: (points desc, user_id asc)
    if (cursor) {
      // (points < cursor.points) OR (points = cursor.points AND user_id > cursor.user_id)
      q = q.or(`${pointsCol}.lt.${cursor.points},and(${pointsCol}.eq.${cursor.points},user_id.gt.${cursor.user_id})`);
    }

    q = q.order(pointsCol, { ascending: false }).order("user_id", { ascending: true }).limit(limit + 1);

    const { data: rows, error } = await q;
    if (error) return bad(500, "db_error", error.message);

    // Optional block filtering (viewer may be null)
    const { data: me } = await supabase.auth.getUser();
    const viewerId = me?.user?.id ?? null;

    const blocked = new Set<string>();
    if (viewerId) {
      const { data: outBlocks } = await supabase
        .from("user_blocks")
        .select("blockee_id")
        .eq("blocker_id", viewerId);
      const { data: inBlocks } = await supabase
        .from("user_blocks")
        .select("blocker_id")
        .eq("blockee_id", viewerId);
      for (const r of outBlocks ?? []) blocked.add(r.blockee_id);
      for (const r of inBlocks ?? []) blocked.add(r.blocker_id);
    }

    const filtered = (rows ?? []).filter((r) => !blocked.has(r.user_id));
    const page = filtered.slice(0, limit);
    const hasMore = filtered.length > limit;

    let next_cursor: string | null = null;
    if (hasMore) {
      const last = page[page.length - 1];
      const lastPoints = range === "week" ? last.weekly_points : last.lifetime_points;
      next_cursor = encCursor({ points: lastPoints, user_id: last.user_id });
    }

    // hydrate profiles (best-effort)
    const userIds = [...new Set(page.map((r) => r.user_id))];
    const profiles: Record<string, { handle: string; display_name: string | null; avatar_url: string | null }> = {};
    if (userIds.length) {
      const { data: usersRows } = await supabase
        .from("users")
        .select("id, handle, display_name, avatar_url")
        .in("id", userIds);
      for (const u of usersRows ?? []) {
        profiles[u.id] = {
          handle: u.handle,
          display_name: u.display_name,
          avatar_url: u.avatar_url,
        };
      }
    }

    const items = page.map((r) => ({
      user_id: r.user_id,
      handle: profiles[r.user_id]?.handle ?? null,
      display_name: profiles[r.user_id]?.display_name ?? null,
      avatar_url: profiles[r.user_id]?.avatar_url ?? null,
      city: r.city,
      week_start_date: r.week_start_date, // null for lifetime range
      weekly_points: r.weekly_points,
      lifetime_points: r.lifetime_points,
    }));

    return json(
      {
        city,
        range,
        week_start_date: range === "week" ? weekStart : null,
        limit,
        items,
        next_cursor,
      },
      { status: 200 },
    );
  } catch (e) {
    // never crash; always return JSON
    return bad(500, "server_error", e instanceof Error ? e.message : String(e));
  }
});
