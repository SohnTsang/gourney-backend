// functions/likes-create/index.ts
// POST /likes-create?visit_id=UUID
// Creates a like (PRIMARY KEY prevents duplicates)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

function json(body: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(body), {
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Authorization, apikey, X-API-Version, Content-Type",
      ...init.headers,
    },
    ...init,
  });
}

function bad(status: number, error: string, detail?: string) {
  return json({ error, detail }, { status });
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

    // Get current user
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
      return bad(401, "unauthorized", "Authentication required");
    }

    const url = new URL(req.url);
    const visit_id = url.searchParams.get("visit_id");
    if (!visit_id) {
      return bad(400, "bad_request", "visit_id is required");
    }

    // Check visit exists (RLS will enforce visibility on insert)
    const { data: visit, error: visitError } = await supabase
      .from("visits")
      .select("id, user_id")
      .eq("id", visit_id)
      .single();

    if (visitError || !visit) {
      return bad(404, "not_found", "Visit not found or not accessible");
    }

    // RLS policy prevents liking own visits
    if (visit.user_id === user.id) {
      return bad(403, "forbidden", "Cannot like your own visit");
    }

    // Insert like (RLS enforces rules, PRIMARY KEY prevents duplicates)
    const { data: like, error: insertError } = await supabase
      .from("visit_likes")
      .insert({
        visit_id,
        user_id: user.id,
      })
      .select("visit_id, user_id, created_at")
      .single();

    if (insertError) {
      // Check for duplicate (PRIMARY KEY violation)
      if (insertError.code === "23505") {
        return bad(409, "conflict", "Already liked this visit");
      }
      return bad(500, "db_error", insertError.message);
    }

    // Get total like count for this visit
    const { count } = await supabase
      .from("visit_likes")
      .select("visit_id", { count: "exact", head: true })
      .eq("visit_id", visit_id);

    return json(
      {
        visit_id: like.visit_id,
        user_id: like.user_id,
        created_at: like.created_at,
        like_count: count ?? 1,
      },
      { status: 201 }
    );
  } catch (e) {
    return bad(500, "server_error", e instanceof Error ? e.message : String(e));
  }
});