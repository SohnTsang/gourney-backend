// functions/likes-list/index.ts
// GET /likes-list?visit_id=UUID&limit=20&cursor=BASE64

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

type Cursor = { created_at: string; user_id: string };

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
  return btoa(`${c.created_at}|${c.user_id}`);
}

function tryDecCursor(s: string | null): Cursor | null {
  if (!s) return null;
  try {
    const [created_at, user_id] = atob(s).split("|");
    if (!created_at || !user_id || user_id.length < 36) return null;
    return { created_at, user_id };
  } catch {
    return null;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return json({}, { status: 204 });

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");
    if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
      return bad(500, "server_misconfigured", "Missing SUPABASE_URL or SUPABASE_ANON_KEY");
    }

    if (req.headers.get("X-API-Version") !== "v1") {
      return bad(400, "bad_request", "Missing or invalid X-API-Version");
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });

    // Get current user (optional)
    const { data: { user } } = await supabase.auth.getUser();
    const viewerId = user?.id ?? null;

    const url = new URL(req.url);
    const visit_id = url.searchParams.get("visit_id");
    const limit = clamp(Number(url.searchParams.get("limit") ?? "20"), 1, 50);
    const cursor = tryDecCursor(url.searchParams.get("cursor"));

    if (!visit_id) {
      return bad(400, "bad_request", "visit_id is required");
    }

    // Check visit exists (RLS will filter if not visible)
    const { data: visit, error: visitError } = await supabase
      .from("visits")
      .select("id")
      .eq("id", visit_id)
      .single();

    if (visitError || !visit) {
      return bad(404, "not_found", "Visit not found or not accessible");
    }

    // Get likes (RLS enforces visibility)
    let q = supabase
      .from("visit_likes")
      .select("user_id, created_at")
      .eq("visit_id", visit_id);

    // Keyset pagination: (created_at DESC, user_id ASC) - most recent first
    if (cursor) {
      q = q.or(`created_at.lt.${cursor.created_at},and(created_at.eq.${cursor.created_at},user_id.gt.${cursor.user_id})`);
    }

    q = q.order("created_at", { ascending: false }).order("user_id", { ascending: true }).limit(limit + 1);

    const { data: rows, error } = await q;
    if (error) return bad(500, "db_error", error.message);

    const page = (rows ?? []).slice(0, limit);
    const hasMore = (rows ?? []).length > limit;

    let next_cursor: string | null = null;
    if (hasMore) {
      const last = page[page.length - 1];
      next_cursor = encCursor({ created_at: last.created_at, user_id: last.user_id });
    }

    // Hydrate user details
    const userIds = [...new Set(page.map((r) => r.user_id))];
    const profiles: Record<string, { handle: string; display_name: string | null; avatar_url: string | null }> = {};
    if (userIds.length) {
      const { data: usersRows } = await supabase
        .from("users")
        .select("id, handle, display_name, avatar_url")
        .in("id", userIds);
      for (const u of usersRows ?? []) {
        profiles[u.id] = { handle: u.handle, display_name: u.display_name, avatar_url: u.avatar_url };
      }
    }

    // Check if current user follows each liker
    const followingSet = new Set<string>();
    if (viewerId && userIds.length) {
      const { data: followsData } = await supabase
        .from("follows")
        .select("followee_id")
        .eq("follower_id", viewerId)
        .in("followee_id", userIds);
      for (const f of followsData ?? []) {
        followingSet.add(f.followee_id);
      }
    }

    const likes = page.map((r) => ({
      user_id: r.user_id,
      user_handle: profiles[r.user_id]?.handle ?? null,
      user_display_name: profiles[r.user_id]?.display_name ?? null,
      user_avatar_url: profiles[r.user_id]?.avatar_url ?? null,
      created_at: r.created_at,
      is_following: followingSet.has(r.user_id),
    }));

    // Get total like count
    const { count } = await supabase
      .from("visit_likes")
      .select("visit_id", { count: "exact", head: true })
      .eq("visit_id", visit_id);

    // Check if current user has liked this visit
    let has_liked = false;
    if (viewerId) {
      const { data: myLike } = await supabase
        .from("visit_likes")
        .select("visit_id")
        .eq("visit_id", visit_id)
        .eq("user_id", viewerId)
        .single();
      has_liked = !!myLike;
    }

    return json(
      {
        visit_id,
        likes,
        like_count: count ?? 0,
        has_liked,
        next_cursor,
      },
      { status: 200 }
    );
  } catch (e) {
    return bad(500, "server_error", e instanceof Error ? e.message : String(e));
  }
});