import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-share-token, x-review-access',
}

type AnnotationInputType = 'text' | 'voice'

interface SyncAnnotationRequest {
  clipId: string
  timecode: string
  type?: AnnotationInputType
  content: string
  isPrivate?: boolean
  authorName?: string
  notifyEmail?: string
}

interface ShareLinkRecord {
  id: string
  project_id: string
  expires_at: string
  scope: 'project' | 'scene' | 'subject' | 'assembly'
  scope_id: string | null
  password_hash: string | null
  permissions: {
    canComment?: boolean
  }
}

const VALID_ANNOTATION_TYPES = new Set<AnnotationInputType>(['text', 'voice'])

function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function errorResponse(status: number, error: string, code: string): Response {
  return jsonResponse({ error, code }, status)
}

function normalizeAnnotation(annotation: any) {
  return {
    annotation: {
      id: annotation.id,
      userId: annotation.author_id,
      userDisplayName: annotation.author_name,
      timecodeIn: annotation.timecode,
      timecodeOut: null,
      body: annotation.content,
      type: annotation.type === 'voice' ? 'voice' : 'text',
      voiceUrl: null,
      createdAt: annotation.timestamp ?? annotation.created_at,
      resolvedAt: null,
    },
  }
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

function scopeCandidateValues(clip: { hierarchy?: Record<string, unknown> | null }, scope: ShareLinkRecord['scope']): unknown[] {
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
  clip: { id: string; hierarchy?: Record<string, unknown> | null },
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

    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!supabaseUrl || !supabaseServiceKey) {
      return errorResponse(500, 'Supabase environment is not configured', 'supabase_env_missing')
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey)
    const body: SyncAnnotationRequest = await req.json()
    const {
      clipId,
      timecode,
      type = 'text',
      content,
      isPrivate = false,
      authorName: providedAuthorName,
      notifyEmail,
    } = body

    if (!clipId || !timecode || !content?.trim()) {
      return errorResponse(400, 'Missing required fields: clipId, timecode, content', 'missing_fields')
    }

    const timecodeRegex = /^\d{2}:\d{2}:\d{2}[:;]\d{2}$/
    if (!timecodeRegex.test(timecode)) {
      return errorResponse(400, 'Invalid timecode format — expected HH:MM:SS:FF', 'invalid_timecode')
    }
    if (!VALID_ANNOTATION_TYPES.has(type)) {
      return errorResponse(400, 'Invalid annotation type', 'invalid_annotation_type')
    }

    let projectId: string
    let userId: string | null = null
    let authorName: string
    let canComment = false
    let scopedShareLink: ShareLinkRecord | null = null
    let validatedClip: { id: string; project_id: string; hierarchy?: Record<string, unknown> | null } | null = null

    if (shareToken) {
      const { data: shareLink, error: shareError } = await supabase
        .from('share_links')
        .select('id, project_id, expires_at, scope, scope_id, password_hash, permissions')
        .eq('token', shareToken)
        .single<ShareLinkRecord>()

      if (shareError || !shareLink) {
        return errorResponse(404, 'Invalid or expired share link', 'invalid_share_token')
      }
      if (new Date(shareLink.expires_at) < new Date()) {
        return errorResponse(410, 'Share link has expired', 'share_link_expired')
      }

      if (shareLink.password_hash) {
        const expectedAccess = await sha256Hex(`${shareToken}:${shareLink.password_hash}`)
        if (!reviewAccess || reviewAccess !== expectedAccess) {
          return errorResponse(401, 'Password required for this share link', 'password_required')
        }
      }

      projectId = shareLink.project_id
      canComment = Boolean(shareLink.permissions?.canComment)
      authorName = providedAuthorName || 'Anonymous Reviewer'
      scopedShareLink = shareLink
    } else {
      const token = authHeader!.replace('Bearer ', '')
      const { data: authData, error: authError } = await supabase.auth.getUser(token)
      if (authError || !authData.user) {
        return errorResponse(401, 'Invalid authentication token', 'invalid_authentication')
      }

      userId = authData.user.id

      const { data: clipRow, error: clipLookupError } = await supabase
        .from('clips')
        .select('id, project_id')
        .eq('id', clipId)
        .single<{ id: string; project_id: string }>()

      if (clipLookupError || !clipRow) {
        return errorResponse(404, 'Clip not found', 'clip_not_found')
      }

      projectId = clipRow.project_id

      const { data: crewMember, error: crewError } = await supabase
        .from('project_crew')
        .select('name')
        .eq('project_id', projectId)
        .eq('user_id', userId)
        .single<{ name: string }>()

      if (crewError || !crewMember) {
        return errorResponse(403, 'Access denied to project', 'project_access_denied')
      }

      canComment = true
      authorName = crewMember.name
    }

    if (!canComment) {
      return errorResponse(403, 'Commenting not permitted for this share link', 'comment_not_permitted')
    }

    const { data: clip, error: clipError } = await supabase
      .from('clips')
      .select('id, project_id, hierarchy')
      .eq('id', clipId)
      .eq('project_id', projectId)
      .single<{ id: string; project_id: string; hierarchy?: Record<string, unknown> | null }>()

    if (clipError || !clip) {
      return errorResponse(404, 'Clip not found for this project', 'clip_project_mismatch')
    }

    if (scopedShareLink && !(await clipMatchesShareScope(supabase, clip, scopedShareLink))) {
      return errorResponse(404, 'Clip not found for this share link', 'clip_scope_mismatch')
    }

    validatedClip = clip

    const windowStart = new Date(Date.now() - 5_000).toISOString()
    const { data: existingAnnotation } = await supabase
      .from('annotations')
      .select('*')
      .eq('clip_id', validatedClip.id)
      .eq('timecode', timecode)
      .eq('content', content)
      .gte('created_at', windowStart)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle()

    if (existingAnnotation) {
      return jsonResponse(normalizeAnnotation(existingAnnotation))
    }

    const annotationId = crypto.randomUUID()
    const now = new Date().toISOString()
    const anonymousUUID = '00000000-0000-0000-0000-000000000000'

    const { data: annotation, error: insertError } = await supabase
      .from('annotations')
      .insert({
        id: annotationId,
        clip_id: validatedClip.id,
        author_id: userId ?? anonymousUUID,
        author_name: authorName,
        timecode,
        type,
        content,
        is_private: isPrivate,
        is_resolved: false,
        timestamp: now,
        created_at: now,
        updated_at: now,
      })
      .select()
      .single()

    if (insertError || !annotation) {
      console.error('Error creating annotation:', insertError)
      return errorResponse(500, 'Failed to create annotation', 'annotation_insert_failed')
    }

    const payload = normalizeAnnotation(annotation)
    await supabase
      .channel(`clip:${validatedClip.id}`)
      .send({
        type: 'broadcast',
        event: 'annotation_added',
        payload,
      })

    // Fire-and-forget notification if notifyEmail is provided
    if (notifyEmail) {
      const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
      const internalSecret = Deno.env.get('SLATE_INTERNAL_SECRET') ?? ''
      const appUrl = Deno.env.get('NEXT_PUBLIC_APP_URL') ?? 'https://slate.app'
      fetch(`${supabaseUrl}/functions/v1/send-notification`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Internal-Secret': internalSecret,
        },
        body: JSON.stringify({
          event: 'annotation_added',
          recipientEmail: notifyEmail,
          reviewUrl: `${appUrl}/review/annotation/${annotation.id}`,
          clipName: clipId,
          annotationBody: content,
          senderName: authorName,
        }),
      }).catch(() => {}) // fire and forget
    }

    return jsonResponse(payload, 201)
  } catch (error) {
    console.error('Error in sync-annotation:', error)
    return errorResponse(500, 'Internal server error', 'internal_error')
  }
})
