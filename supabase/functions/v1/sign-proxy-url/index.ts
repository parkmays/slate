import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { S3Client, GetObjectCommand } from "npm:@aws-sdk/client-s3"
import { getSignedUrl } from "npm:@aws-sdk/s3-request-presigner"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-share-token, x-review-access',
}

interface SignProxyUrlRequest {
  clipId: string
}

interface ShareLinkRecord {
  id: string
  project_id: string
  expires_at: string
  view_count: number | null
  scope: 'project' | 'scene' | 'subject' | 'assembly'
  scope_id: string | null
  password_hash: string | null
}

interface ClipRecord {
  id: string
  project_id: string
  proxy_r2_key: string | null
  proxy_status: string | null
  proxy_lut: string | null
  proxy_color_space: string | null
  hierarchy?: Record<string, unknown> | null
}

const R2_ACCOUNT_ID = Deno.env.get('R2_ACCOUNT_ID')!
const R2_BUCKET_NAME = Deno.env.get('R2_BUCKET_NAME')!
const R2_ACCESS_KEY_ID = Deno.env.get('R2_ACCESS_KEY_ID')!
const R2_SECRET_ACCESS_KEY = Deno.env.get('R2_SECRET_ACCESS_KEY')!

function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function errorResponse(status: number, error: string, code: string): Response {
  return jsonResponse({ error, code }, status)
}

function createR2Client(): S3Client {
  return new S3Client({
    region: 'auto',
    endpoint: `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: R2_ACCESS_KEY_ID,
      secretAccessKey: R2_SECRET_ACCESS_KEY,
    },
  })
}

// Canonical R2 key — must match storage.md locked convention: {projectId}/{clipId}/proxy.mp4
// Server derives this from DB fields; never trusts a client-supplied key.
function canonicalProxyKey(projectId: string, clipId: string): string {
  return `${projectId}/${clipId}/proxy.mp4`
}

function thumbnailKeyFor(proxyKey: string): string {
  if (proxyKey.endsWith('.m3u8')) {
    return proxyKey.replace(/\.m3u8$/, '_thumb.jpg')
  }
  if (proxyKey.endsWith('.mp4')) {
    // For canonical key {projectId}/{clipId}/proxy.mp4 → {projectId}/{clipId}/proxy_thumb.jpg
    return proxyKey.replace(/\/proxy\.mp4$/, '/proxy_thumb.jpg').replace(/\.mp4$/, '_thumb.jpg')
  }
  return `${proxyKey}_thumb.jpg`
}

function normalizeScopeValue(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null
  }

  const trimmed = value.trim()
  return trimmed.length > 0 ? trimmed.toLowerCase() : null
}

function readValueAtPath(source: unknown, path: string): unknown {
  return path.split('.').reduce<unknown>((current, segment) => {
    if (current == null || typeof current !== 'object') {
      return undefined
    }

    return (current as Record<string, unknown>)[segment]
  }, source)
}

function scopeCandidateValues(clip: ClipRecord, scope: ShareLinkRecord['scope']): unknown[] {
  if (scope === 'scene') {
    return [
      readValueAtPath(clip, 'hierarchy.narrative.sceneId'),
      readValueAtPath(clip, 'hierarchy.narrative.scene_id'),
      readValueAtPath(clip, 'hierarchy.narrative.sceneNumber'),
    ]
  }

  if (scope === 'subject') {
    return [
      readValueAtPath(clip, 'hierarchy.documentary.subjectId'),
      readValueAtPath(clip, 'hierarchy.documentary.subject_id'),
      readValueAtPath(clip, 'hierarchy.documentary.subjectName'),
    ]
  }

  return []
}

async function loadAssemblyClipIds(
  supabase: ReturnType<typeof createClient>,
  assemblyId: string
): Promise<Set<string>> {
  const { data: versionRow } = await supabase
    .from('assembly_versions')
    .select('clips')
    .eq('assembly_id', assemblyId)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle<{ clips: Array<{ clipId?: string; clip_id?: string } | string> | null }>()

  if (versionRow?.clips?.length) {
    return new Set(
      versionRow.clips
        .map((clip) => typeof clip === 'string' ? clip : (clip.clipId ?? clip.clip_id ?? null))
        .filter((clipId): clipId is string => Boolean(clipId))
    )
  }

  const { data: clipRows } = await supabase
    .from('assembly_clips')
    .select('clip_id')
    .eq('assembly_id', assemblyId)

  return new Set(
    (clipRows ?? [])
      .map((clip) => clip.clip_id)
      .filter((clipId): clipId is string => Boolean(clipId))
  )
}

async function clipMatchesShareScope(
  supabase: ReturnType<typeof createClient>,
  clip: ClipRecord,
  shareLink: ShareLinkRecord
): Promise<boolean> {
  if (shareLink.scope === 'project') {
    return true
  }

  if (shareLink.scope === 'assembly') {
    if (!shareLink.scope_id) {
      return false
    }

    const assemblyClipIds = await loadAssemblyClipIds(supabase, shareLink.scope_id)
    return assemblyClipIds.has(clip.id)
  }

  const normalizedScopeId = normalizeScopeValue(shareLink.scope_id)
  if (!normalizedScopeId) {
    return false
  }

  return scopeCandidateValues(clip, shareLink.scope)
    .map((candidate) => normalizeScopeValue(candidate))
    .some((candidate) => candidate === normalizedScopeId)
}

async function sha256Hex(value: string): Promise<string> {
  const encoded = new TextEncoder().encode(value)
  const digest = await crypto.subtle.digest('SHA-256', encoded)
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('')
}

async function signObjectUrl(s3: S3Client, key: string, expiresIn = 86400): Promise<string> {
  return await getSignedUrl(
    s3,
    new GetObjectCommand({
      Bucket: R2_BUCKET_NAME,
      Key: key,
    }),
    { expiresIn }
  )
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    const shareToken = req.headers.get('X-Share-Token')
    const reviewAccess = req.headers.get('X-Review-Access')

    if (!authHeader && !shareToken) {
      return errorResponse(401, 'Missing authentication', 'missing_authentication')
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    const body = await req.json() as SignProxyUrlRequest
    const { clipId } = body

    if (!clipId) {
      return errorResponse(400, 'Missing clipId', 'missing_clip_id')
    }

    let projectId: string
    let shareLinkRecord: ShareLinkRecord | null = null

    if (shareToken) {
      const { data: shareLink, error: shareError } = await supabase
        .from('share_links')
        .select('id, project_id, expires_at, view_count, scope, scope_id, password_hash')
        .eq('token', shareToken)
        .single<ShareLinkRecord>()

      if (shareError || !shareLink) {
        return errorResponse(404, 'Invalid or expired share link', 'invalid_share_token')
      }

      if (new Date(shareLink.expires_at) < new Date()) {
        return errorResponse(403, 'TOKEN_EXPIRED', 'token_expired')
      }

      if (shareLink.password_hash) {
        const expectedAccess = await sha256Hex(`${shareToken}:${shareLink.password_hash}`)
        if (!reviewAccess || reviewAccess !== expectedAccess) {
          return errorResponse(401, 'Password required for this share link', 'password_required')
        }
      }

      projectId = shareLink.project_id
      shareLinkRecord = shareLink
    } else {
      const token = authHeader!.replace('Bearer ', '')
      const { data: authData, error: authError } = await supabase.auth.getUser(token)

      if (authError || !authData.user) {
        return errorResponse(401, 'Invalid authentication token', 'invalid_authentication')
      }

      const { data: clip, error: clipError } = await supabase
        .from('clips')
        .select('project_id')
        .eq('id', clipId)
        .single<{ project_id: string }>()

      if (clipError || !clip) {
        return errorResponse(404, 'Clip not found', 'clip_not_found')
      }

      projectId = clip.project_id

      const { data: crewMember, error: crewError } = await supabase
        .from('project_crew')
        .select('id')
        .eq('project_id', projectId)
        .eq('user_id', authData.user.id)
        .single<{ id: string }>()

      if (crewError || !crewMember) {
        return errorResponse(403, 'Access denied to project', 'project_access_denied')
      }
    }

    const { data: clip, error: clipError } = await supabase
      .from('clips')
      .select('id, project_id, proxy_r2_key, proxy_status, proxy_lut, proxy_color_space, hierarchy')
      .eq('id', clipId)
      .single<ClipRecord>()

    if (clipError || !clip) {
      return errorResponse(404, 'Clip not found', 'clip_not_found')
    }

    if (clip.project_id !== projectId) {
      return errorResponse(404, 'Clip not found for this project', 'clip_project_mismatch')
    }

    if (shareLinkRecord && !(await clipMatchesShareScope(supabase, clip, shareLinkRecord))) {
      return errorResponse(404, 'Clip not found for this share link', 'clip_scope_mismatch')
    }

    if (shareLinkRecord) {
      await supabase
        .from('share_links')
        .update({
          view_count: (shareLinkRecord.view_count ?? 0) + 1,
          last_viewed_at: new Date().toISOString(),
        })
        .eq('id', shareLinkRecord.id)
    }

    // Proxy must be in a ready/completed state
    if (!['ready', 'completed'].includes(clip.proxy_status ?? '')) {
      return errorResponse(404, 'Proxy not available for this clip', 'proxy_not_available')
    }

    // Always derive the R2 key server-side using the locked canonical convention.
    // This ensures correctness even if the stored proxy_r2_key uses an old format.
    // storage.md: {projectId}/{clipId}/proxy.mp4
    const r2Key = canonicalProxyKey(clip.project_id, clip.id)

    const s3 = createR2Client()
    const expiresIn = 86400
    const signedUrl = await signObjectUrl(s3, r2Key, expiresIn)
    const thumbnailKey = thumbnailKeyFor(r2Key)
    // Thumbnail may not exist for every clip — sign optimistically, let the browser 404 gracefully
    const thumbnailUrl = await signObjectUrl(s3, thumbnailKey, expiresIn)

    return jsonResponse({
      signedUrl,
      thumbnailUrl,
      expiresAt: new Date(Date.now() + expiresIn * 1000).toISOString(),
      proxyLUT: clip.proxy_lut ?? null,
      proxyColorSpace: clip.proxy_color_space ?? null,
    })
  } catch (error) {
    console.error('Error in sign-proxy-url:', error)
    return errorResponse(500, 'Internal server error', 'internal_error')
  }
})
