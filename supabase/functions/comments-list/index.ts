// functions/comments-list/index.ts
// GET /comments-list?visit_id=UUID&limit=20&cursor=BASE64

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

type Cursor = { created_at: string; id: string };

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
  return btoa(`${c.created_at}|${c.id}`);
}

function tryDecCursor(s: string | null): Cursor | null {
  if (!s) return null;
  try {
    const [created_at, id] = atob(s).split("|");
    if (!created_at || !id || id.length < 36) return null;
    return { created_at, id };
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

    // Get current user (optional - can view public visits)
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

    // Get comments (RLS enforces visibility)
    let q = supabase
      .from("visit_comments")
      .select("id, user_id, comment_text, created_at")
      .eq("visit_id", visit_id)
      .is("deleted_at", null);

    // Keyset pagination: (created_at ASC, id ASC) - oldest first like Instagram
    if (cursor) {
      q = q.or(`created_at.gt.${cursor.created_at},and(created_at.eq.${cursor.created_at},id.gt.${cursor.id})`);
    }

    q = q.order("created_at", { ascending: true }).order("id", { ascending: true }).limit(limit + 1);

    const { data: rows, error } = await q;
    if (error) return bad(500, "db_error", error.message);

    const page = (rows ?? []).slice(0, limit);
    const hasMore = (rows ?? []).length > limit;

    let next_cursor: string | null = null;
    if (hasMore) {
      const last = page[page.length - 1];
      next_cursor = encCursor({ created_at: last.created_at, id: last.id });
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

    const comments = page.map((r) => ({
      id: r.id,
      user_id: r.user_id,
      user_handle: profiles[r.user_id]?.handle ?? null,
      user_display_name: profiles[r.user_id]?.display_name ?? null,
      user_avatar_url: profiles[r.user_id]?.avatar_url ?? null,
      comment_text: r.comment_text,
      created_at: r.created_at,
      is_mine: viewerId === r.user_id,
    }));

    // Get total comment count
    const { count } = await supabase
      .from("visit_comments")
      .select("id", { count: "exact", head: true })
      .eq("visit_id", visit_id)
      .is("deleted_at", null);

    return json(
      {
        visit_id,
        comments,
        comment_count: count ?? 0,
        next_cursor,
      },
      { status: 200 }
    );
  } catch (e) {
    return bad(500, "server_error", e instanceof Error ? e.message : String(e));
  }
});