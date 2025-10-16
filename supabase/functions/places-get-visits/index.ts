// functions/places-get-visits/index.ts
// Supabase Edge Function (Deno). Requires: @supabase/supabase-js v2
// Behavior:
// - GET /places-get-visits/:placeId?limit=..&cursor=..&friends_only=true|false
// - Requires headers: Authorization: Bearer <user access token>, apikey: <anon>, X-API-Version: v1
// - 200 + JSON for empty results, 404 only if place not found.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

// Simple CORS helper
function corsHeaders(origin?: string) {
  return {
    "Access-Control-Allow-Origin": origin ?? "*",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers":
      "authorization, x-api-version, apikey, content-type",
    "Vary": "Origin",
  };
}

function json(body: unknown, init: ResponseInit = {}) {
  const base = { "content-type": "application/json; charset=utf-8" };
  return new Response(JSON.stringify(body), {
    headers: { ...base, ...(init.headers ?? {}) },
    status: init.status ?? 200,
  });
}

serve(async (req) => {
  const url = new URL(req.url);
  const origin = req.headers.get("Origin") ?? "*";

  // Preflight
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: corsHeaders(origin),
      status: 204,
    });
  }

  // API version guard
  const apiVersion = req.headers.get("X-API-Version");
  if (!apiVersion || apiVersion.toLowerCase() !== "v1") {
    return json(
      { error: "API version required. Use X-API-Version: v1 or /v1 path." },
      { status: 400, headers: corsHeaders(origin) },
    );
  }

  if (req.method !== "GET") {
    return json({ error: "Method not allowed" }, {
      status: 405,
      headers: corsHeaders(origin),
    });
  }

  // Extract :placeId from pathname (…/places-get-visits/<uuid>)
  const segments = url.pathname.split("/").filter(Boolean);
  const placeId = segments[segments.length - 1]; // last segment

  // Basic placeId sanity
  if (!placeId || placeId.length < 36) {
    return json({ error: "Invalid place id" }, {
      status: 400,
      headers: corsHeaders(origin),
    });
  }

  // Prepare Supabase client using the caller's JWT (RLS)
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: {
      headers: {
        Authorization: req.headers.get("Authorization") ?? "",
      },
    },
  });

  // Read query params
  const limitRaw = url.searchParams.get("limit") ?? "20";
  const friendsOnlyRaw = url.searchParams.get("friends_only") ?? "false";
  const cursor = url.searchParams.get("cursor");

  // Clamp limit 1..50
  let limit = Number.parseInt(limitRaw, 10);
  if (!Number.isFinite(limit)) limit = 20;
  limit = Math.max(1, Math.min(limit, 50));

  const friends_only = String(friendsOnlyRaw).toLowerCase() === "true";

  // Call RPC
  const { data, error } = await supabase.rpc("fn_places_get_visits_v1", {
    p_place_id: placeId,
    p_limit: limit,
    p_cursor: cursor,
    p_friends_only: friends_only,
  });

  if (error) {
    // Typical causes: missing/invalid JWT, RLS block, or function error
    // Map auth errors to 401; others to 400
    const msg = (error as any)?.message ?? String(error);
    const status =
      /jwt|auth|authorization/i.test(msg) ? 401
      : /permission|rls/i.test(msg) ? 403
      : 400;
    return json({ error: "rpc_error", detail: msg }, {
      status,
      headers: corsHeaders(origin),
    });
  }

  // The RPC returns: { status, place?, visits, visit_count, next_cursor }
  const status = (data?.status ?? 200) as number;

  if (status === 404) {
    // Only for place_not_found
    return json({ error: "place_not_found" }, {
      status: 404,
      headers: corsHeaders(origin),
    });
  }

  // Normalize final payload (hide internal 'status')
  const { status: _drop, ...payload } = data ?? {};
  return json(payload, { status: 200, headers: corsHeaders(origin) });
});
