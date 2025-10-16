// functions/comments-create/index.ts
// POST /comments-create?visit_id=UUID
// Body: { comment_text: string }

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

    // Parse body
    let body: { comment_text?: string };
    try {
      body = await req.json();
    } catch {
      return bad(400, "bad_request", "Invalid JSON body");
    }

    const comment_text = body.comment_text?.trim();
    if (!comment_text) {
      return bad(400, "bad_request", "comment_text is required");
    }

    // Validate length (1-500 chars)
    if (comment_text.length < 1 || comment_text.length > 500) {
      return bad(400, "bad_request", "comment_text must be 1-500 characters");
    }

    // Check visit exists and is visible (RLS will enforce this on insert)
    const { data: visit, error: visitError } = await supabase
      .from("visits")
      .select("id, user_id")
      .eq("id", visit_id)
      .single();

    if (visitError || !visit) {
      return bad(404, "not_found", "Visit not found or not accessible");
    }

    // Insert comment (RLS enforces user_id = auth.uid())
    const { data: comment, error: insertError } = await supabase
      .from("visit_comments")
      .insert({
        visit_id,
        user_id: user.id,
        comment_text,
      })
      .select("id, visit_id, user_id, comment_text, created_at")
      .single();

    if (insertError) {
      return bad(500, "db_error", insertError.message);
    }

    // Fetch user details for response
    const { data: userData } = await supabase
      .from("users")
      .select("handle, display_name, avatar_url")
      .eq("id", user.id)
      .single();

    return json(
      {
        id: comment.id,
        visit_id: comment.visit_id,
        user_id: comment.user_id,
        user_handle: userData?.handle ?? null,
        user_display_name: userData?.display_name ?? null,
        user_avatar_url: userData?.avatar_url ?? null,
        comment_text: comment.comment_text,
        created_at: comment.created_at,
      },
      { status: 201 }
    );
  } catch (e) {
    return bad(500, "server_error", e instanceof Error ? e.message : String(e));
  }
});