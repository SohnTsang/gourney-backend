// functions/comments-delete/index.ts
// DELETE /comments-delete?comment_id=UUID
// Soft deletes comment (sets deleted_at)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

function json(body: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(body), {
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "DELETE, OPTIONS",
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
    const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    
    if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_KEY) {
      return bad(500, "server_misconfigured", "Missing Supabase credentials");
    }

    if (req.headers.get("X-API-Version") !== "v1") {
      return bad(400, "bad_request", "Missing or invalid X-API-Version");
    }

    // Client for auth and permission checks (respects RLS)
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });

    // Service client for the actual update (bypasses RLS)
    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    // Get current user
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
      return bad(401, "unauthorized", "Authentication required");
    }

    const url = new URL(req.url);
    const comment_id = url.searchParams.get("comment_id");
    if (!comment_id) {
      return bad(400, "bad_request", "comment_id is required");
    }

    // Check comment exists and user owns it (using regular client with RLS)
    const { data: comment, error: fetchError } = await supabase
      .from("visit_comments")
      .select("id, user_id, deleted_at")
      .eq("id", comment_id)
      .single();

    if (fetchError || !comment) {
      return bad(404, "not_found", "Comment not found");
    }

    if (comment.deleted_at) {
      return bad(410, "gone", "Comment already deleted");
    }

    if (comment.user_id !== user.id) {
      return bad(403, "forbidden", "You can only delete your own comments");
    }

    // Perform soft delete using service role (bypasses RLS)
    const now = new Date().toISOString();
    const { error: updateError } = await supabaseAdmin
      .from("visit_comments")
      .update({ deleted_at: now })
      .eq("id", comment_id);

    if (updateError) {
      console.error("Delete comment error:", updateError);
      return bad(500, "db_error", `Update failed: ${updateError.message}`);
    }

    return new Response(null, { status: 204 });
  } catch (e) {
    console.error("Unexpected error:", e);
    return bad(500, "server_error", e instanceof Error ? e.message : String(e));
  }
});