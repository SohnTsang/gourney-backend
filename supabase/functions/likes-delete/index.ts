// functions/likes-delete/index.ts
// DELETE /likes-delete?visit_id=UUID
// Removes like (unlike)

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

    // Delete like (RLS policy allows DELETE for owner)
    const { error: deleteError } = await supabase
      .from("visit_likes")
      .delete()
      .eq("visit_id", visit_id)
      .eq("user_id", user.id);

    if (deleteError) {
      return bad(500, "db_error", deleteError.message);
    }

    // Return 204 No Content (success even if like didn't exist)
    return new Response(null, { status: 204 });
  } catch (e) {
    return bad(500, "server_error", e instanceof Error ? e.message : String(e));
  }
});