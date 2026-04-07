import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { nanoid } from "https://deno.land/x/nanoid@v3.0.0/nanoid.ts"
import { bcrypt } from "https://deno.land/x/bcrypt@v0.4.1/mod.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const RATE_LIMIT_WINDOW_MS = 60_000
const RATE_LIMIT_MAX_REQUESTS = 10
// NOTE: This in-memory rate limit resets on every cold start and is not shared
// across multiple Edge Function instances. It provides best-effort protection only.
// Also note: the map is keyed on the full Authorization header string rather than
// the resolved user ID, so a token rotation bypasses the limit.
// For production-grade rate limiting, resolve the user ID first and key on that,
// using a shared store such as Upstash Redis.
const authRateLimit = new Map<string, number[]>()

interface GenerateShareLinkRequest {
  projectId: string
  projectName?: string
  scope: 'project' | 'scene' | 'subject' | 'assembly'
  scopeId?: string
  expiryHours?: number
  expiresAt?: string | null
  role?: 'viewer' | 'commenter' | 'editor'
  password?: string
  permissions: {
    canComment: boolean
    canFlag: boolean
    canRequestAlternate: boolean
  }
  notifyEmail?: string
}

function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function errorResponse(status: number, error: string, code: string): Response {
  return jsonResponse({ error, code }, status)
}

function enforceRateLimit(authorization: string): boolean {
  const now = Date.now()

  for (const [key, timestamps] of authRateLimit.entries()) {
    const fresh = timestamps.filter((timestamp) => now - timestamp < RATE_LIMIT_WINDOW_MS)
    if (fresh.length === 0) {
      authRateLimit.delete(key)
    } else {
      authRateLimit.set(key, fresh)
    }
  }

  const attempts = authRateLimit.get(authorization) ?? []
  const freshAttempts = attempts.filter((timestamp) => now - timestamp < RATE_LIMIT_WINDOW_MS)
  if (freshAttempts.length >= RATE_LIMIT_MAX_REQUESTS) {
    authRateLimit.set(authorization, freshAttempts)
    return false
  }

  authRateLimit.set(authorization, [...freshAttempts, now])
  return true
}

function permissionsForRole(role: 'viewer' | 'commenter' | 'editor'): GenerateShareLinkRequest['permissions'] {
  switch (role) {
    case 'viewer':
      return { canComment: false, canFlag: false, canRequestAlternate: false }
    case 'commenter':
      return { canComment: true, canFlag: false, canRequestAlternate: false }
    case 'editor':
      return { canComment: true, canFlag: true, canRequestAlternate: true }
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return errorResponse(401, 'Missing authorization header', 'missing_authorization')
    }

    if (!enforceRateLimit(authHeader)) {
      return errorResponse(429, 'Rate limit exceeded', 'rate_limited')
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!supabaseUrl || !supabaseServiceKey) {
      return errorResponse(500, 'Supabase environment is not configured', 'supabase_env_missing')
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      global: {
        headers: { Authorization: authHeader },
      },
    })

    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) {
      return errorResponse(401, 'Invalid authentication token', 'invalid_authentication')
    }

    const body: GenerateShareLinkRequest = await req.json()
    const {
      projectId,
      scope,
      scopeId,
      expiryHours = 168,
      expiresAt: rawExpiresAt,
      role: rawRole = 'viewer',
      password,
      permissions,
      notifyEmail,
    } = body

    if (!projectId || !scope || !permissions) {
      return errorResponse(400, 'Missing required fields', 'missing_fields')
    }

    if (rawRole !== 'viewer' && rawRole !== 'commenter' && rawRole !== 'editor') {
      return errorResponse(400, 'role must be viewer, commenter, or editor', 'invalid_role')
    }

    if (rawExpiresAt != null && Number.isNaN(new Date(rawExpiresAt).getTime())) {
      return errorResponse(400, 'expiresAt must be a valid ISO 8601 timestamp', 'invalid_expires_at')
    }

    if (rawExpiresAt == null && (expiryHours < 1 || expiryHours > 720)) {
      return errorResponse(400, 'expiryHours must be between 1 and 720', 'invalid_expiry_hours')
    }

    if ((scope === 'scene' || scope === 'subject' || scope === 'assembly') && !scopeId) {
      return errorResponse(400, 'scopeId is required for this scope type', 'missing_scope_id')
    }

    const { data: crewMember, error: crewError } = await supabase
      .from('project_crew')
      .select('id')
      .eq('project_id', projectId)
      .eq('user_id', user.id)
      .single()

    if (crewError || !crewMember) {
      return errorResponse(403, 'Access denied to project', 'project_access_denied')
    }

    const token = nanoid(32)
    const passwordHash = password ? await bcrypt.hash(password) : null
    const expiresAt = rawExpiresAt ?? new Date(Date.now() + expiryHours * 60 * 60 * 1000).toISOString()
    const role = rawRole
    const normalizedPermissions = permissionsForRole(role)

    const { data: shareLink, error: insertError } = await supabase
      .from('share_links')
      .insert({
        project_id: projectId,
        token,
        scope,
        scope_id: scopeId || null,
        password_hash: passwordHash,
        expires_at: expiresAt,
        role,
        permissions: normalizedPermissions,
        created_by: user.id,
        notify_email: notifyEmail ?? null,
      })
      .select('token, expires_at, role')
      .single()

    if (insertError || !shareLink) {
      console.error('Error creating share link:', insertError)
      return errorResponse(500, 'Failed to create share link', 'share_link_insert_failed')
    }

    const reviewBaseUrl = Deno.env.get('SLATE_REVIEW_APP_URL')
      ?? req.headers.get('origin')
      ?? 'https://slate.app'
    const reviewUrl = `${reviewBaseUrl.replace(/\/+$/, '')}/review/${token}`

    // Fire-and-forget notification if notifyEmail is provided
    if (notifyEmail) {
      const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
      const internalSecret = Deno.env.get('SLATE_INTERNAL_SECRET') ?? ''
      fetch(`${supabaseUrl}/functions/v1/send-notification`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Internal-Secret': internalSecret,
        },
        body: JSON.stringify({
          event: 'share_link_created',
          recipientEmail: notifyEmail,
          reviewUrl,
          projectName: body.projectName,
        }),
      }).catch(() => {}) // fire and forget
    }

    return jsonResponse({
      token: shareLink.token,
      url: reviewUrl,
      expiresAt: shareLink.expires_at,
      role: shareLink.role,
    })
  } catch (error) {
    console.error('Error in generate-share-link:', error)
    return errorResponse(500, 'Internal server error', 'internal_error')
  }
})
