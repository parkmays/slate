import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-shotgrid-sync-secret",
}

const VALID_REVIEW = new Set([
  "unreviewed",
  "circled",
  "flagged",
  "x",
  "deprioritized",
])

function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

function errorResponse(status: number, error: string, code: string): Response {
  return jsonResponse({ error, code }, status)
}

/**
 * ShotGrid / RV pipeline hook: POST JSON
 * { "shotgridEntityId": "123", "reviewStatus": "circled" } OR { "clipId": "uuid", "reviewStatus": "..." }
 * Header X-ShotGrid-Sync-Secret must match SHOTGRID_SYNC_SECRET.
 */
serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }
  if (req.method !== "POST") {
    return errorResponse(405, "Method not allowed", "method_not_allowed")
  }

  const secret = Deno.env.get("SHOTGRID_SYNC_SECRET")
  if (!secret || secret.length < 8) {
    return errorResponse(503, "SHOTGRID_SYNC_SECRET not configured", "misconfigured")
  }

  const provided = req.headers.get("x-shotgrid-sync-secret") ?? ""
  if (provided !== secret) {
    return errorResponse(401, "Unauthorized", "unauthorized")
  }

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return errorResponse(400, "Invalid JSON", "invalid_json")
  }

  const reviewStatus = typeof body.reviewStatus === "string" ? body.reviewStatus : ""
  if (!VALID_REVIEW.has(reviewStatus)) {
    return errorResponse(400, "Invalid reviewStatus", "invalid_status")
  }

  const shotgridEntityId = typeof body.shotgridEntityId === "string" ? body.shotgridEntityId : ""
  const clipId = typeof body.clipId === "string" ? body.clipId : ""

  if (!shotgridEntityId && !clipId) {
    return errorResponse(400, "Provide shotgridEntityId or clipId", "missing_target")
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  const supabase = createClient(supabaseUrl, serviceKey)

  let targetClipId: string | null = clipId || null

  if (!targetClipId && shotgridEntityId) {
    const { data: rows, error: qErr } = await supabase
      .from("clips")
      .select("id")
      .eq("shotgrid_entity_id", shotgridEntityId)
      .limit(1)

    if (qErr) {
      console.error("clip lookup", qErr)
      return errorResponse(500, "Database error", "db_error")
    }
    targetClipId = rows?.[0]?.id ?? null
  }

  if (!targetClipId) {
    return errorResponse(404, "Clip not found", "not_found")
  }

  const updatedAt = new Date().toISOString()
  const { error: upErr } = await supabase
    .from("clips")
    .update({
      review_status: reviewStatus,
      updated_at: updatedAt,
      editorial_updated_at: updatedAt,
    })
    .eq("id", targetClipId)

  if (upErr) {
    console.error("clip update", upErr)
    return errorResponse(500, "Update failed", "update_failed")
  }

  await supabase.channel(`clip:${targetClipId}`).send({
    type: "broadcast",
    event: "review_status_changed",
    payload: {
      clipId: targetClipId,
      status: reviewStatus,
      updatedBy: "shotgrid-sync",
      updatedAt,
    },
  })

  return jsonResponse({ ok: true, clipId: targetClipId, reviewStatus, updatedAt })
})
