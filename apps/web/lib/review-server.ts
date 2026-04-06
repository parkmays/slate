import type { SupabaseClient } from '@supabase/supabase-js'
import { hasValidReviewAccessCookie, reviewAccessCookieName } from '@/lib/review-auth'
import { timecodeToSeconds } from '@/lib/timecode'
import type {
  AnnotationType,
  ReviewAnnotation,
  ReviewAnnotationReply,
  ReviewAssemblyClipRange,
  ReviewAssemblyData,
  ReviewSharePermissions,
  ReviewShareLink,
  ReviewStatus,
} from '@/lib/review-types'

export class ReviewRouteError extends Error {
  constructor(
    message: string,
    public status: number
  ) {
    super(message)
    this.name = 'ReviewRouteError'
  }
}

const REVIEW_STATUSES = new Set<ReviewStatus>([
  'unreviewed',
  'circled',
  'flagged',
  'x',
  'deprioritized',
])

const ANNOTATION_TYPES = new Set<AnnotationType>([
  'text',
  'voice',
])

interface ShareLinkAccessRecord {
  id: string
  project_id: string
  token: string
  scope: ReviewShareLink['scope']
  scope_id: string | null
  expires_at: string
  password_hash: string | null
  permissions: ReviewSharePermissions | null
  revoked_at?: string | null
}

interface ClipAccessRecord {
  id: string
  project_id: string
  hierarchy?: Record<string, unknown> | null
  duration_seconds?: number | string | null
  frame_rate?: number | string | null
}

interface RequestCookieReader {
  cookies: {
    get(name: string): { value?: string } | undefined
  }
}

function normalizePermissions(
  permissions: Partial<ReviewSharePermissions> | null | undefined
): ReviewSharePermissions {
  return {
    canComment: Boolean(permissions?.canComment),
    canFlag: Boolean(permissions?.canFlag),
    canRequestAlternate: Boolean(permissions?.canRequestAlternate),
  }
}

function normalizeMentionTokens(text: string): string[] {
  return Array.from(
    new Set(
      Array.from(text.matchAll(/@([a-z0-9_.-]+)/gi)).map((match) => match[1].toLowerCase())
    )
  )
}

export function isReviewStatus(value: unknown): value is ReviewStatus {
  return typeof value === 'string' && REVIEW_STATUSES.has(value as ReviewStatus)
}

export function isAnnotationType(value: unknown): value is AnnotationType {
  return typeof value === 'string' && ANNOTATION_TYPES.has(value as AnnotationType)
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

function scopeCandidateValues(clip: unknown, scope: ReviewShareLink['scope']): Array<unknown> {
  if (scope === 'scene') {
    return [
      readValueAtPath(clip, 'hierarchy.narrative.sceneId'),
      readValueAtPath(clip, 'hierarchy.narrative.scene_id'),
      readValueAtPath(clip, 'hierarchy.narrative.sceneUuid'),
      readValueAtPath(clip, 'hierarchy.narrative.sceneUUID'),
      readValueAtPath(clip, 'hierarchy.narrative.sceneNumber'),
      readValueAtPath(clip, 'narrative_meta.sceneId'),
      readValueAtPath(clip, 'narrative_meta.scene_id'),
      readValueAtPath(clip, 'narrative_meta.sceneNumber'),
      readValueAtPath(clip, 'metadata.sceneId'),
      readValueAtPath(clip, 'metadata.scene_id'),
    ]
  }

  if (scope === 'subject') {
    return [
      readValueAtPath(clip, 'hierarchy.documentary.subjectId'),
      readValueAtPath(clip, 'hierarchy.documentary.subject_id'),
      readValueAtPath(clip, 'hierarchy.documentary.subjectUuid'),
      readValueAtPath(clip, 'hierarchy.documentary.subjectUUID'),
      readValueAtPath(clip, 'hierarchy.documentary.subjectName'),
      readValueAtPath(clip, 'documentary_meta.subjectId'),
      readValueAtPath(clip, 'documentary_meta.subject_id'),
      readValueAtPath(clip, 'documentary_meta.subjectName'),
      readValueAtPath(clip, 'metadata.subjectId'),
      readValueAtPath(clip, 'metadata.subject_id'),
    ]
  }

  return []
}

export function clipMatchesShareScope(
  clip: { id: string; hierarchy?: Record<string, unknown> | null } & Record<string, unknown>,
  shareLink: Pick<ReviewShareLink, 'scope' | 'scope_id'>,
  assemblyClipIds?: Set<string> | null
): boolean {
  if (shareLink.scope === 'project') {
    return true
  }

  if (shareLink.scope === 'assembly') {
    return assemblyClipIds?.has(clip.id) ?? false
  }

  const normalizedScopeId = normalizeScopeValue(shareLink.scope_id)
  if (!normalizedScopeId) {
    return false
  }

  return scopeCandidateValues(clip, shareLink.scope)
    .map((candidate) => normalizeScopeValue(candidate))
    .some((candidate) => candidate === normalizedScopeId)
}

function normalizeAnnotationType(value: unknown): AnnotationType {
  return value === 'voice' ? 'voice' : 'text'
}

function annotationVoiceUrl(record: Record<string, unknown>, type: AnnotationType): string | null {
  if (type !== 'voice') {
    return null
  }

  const explicitVoiceUrl = stringValue(record.voice_url, record.voiceUrl)
  if (explicitVoiceUrl) {
    return explicitVoiceUrl
  }

  const content = stringValue(record.content, record.body)
  return content?.startsWith('data:audio') ? content : null
}

export function normalizeAnnotationReply(record: Record<string, unknown>): ReviewAnnotationReply {
  const body = stringValue(record.content, record.body) ?? ''
  return {
    id: stringValue(record.id) ?? '',
    annotationId: stringValue(record.annotation_id, record.annotationId) ?? '',
    userId: stringValue(record.author_id, record.user_id) ?? 'share-token',
    userDisplayName: stringValue(record.author_name, record.user_display_name) ?? 'Reviewer',
    body,
    createdAt: stringValue(record.created_at, record.createdAt) ?? new Date().toISOString(),
    mentions: normalizeMentionTokens(body),
  }
}

function parseTimeOffsetSeconds(record: Record<string, unknown>): number | null {
  const raw = record.time_offset_seconds ?? record.timeOffsetSeconds
  if (typeof raw === 'number' && Number.isFinite(raw)) {
    return raw
  }
  if (typeof raw === 'string' && raw.trim().length > 0) {
    const n = Number.parseFloat(raw)
    return Number.isFinite(n) ? n : null
  }
  return null
}

export function clipPlaybackBounds(
  clip: Pick<ClipAccessRecord, 'duration_seconds' | 'frame_rate'>
): { durationSeconds: number; fps: number } {
  const durationSeconds = Math.max(0, Number(clip.duration_seconds ?? 0))
  const fpsRaw = Number(clip.frame_rate ?? 24)
  const fps = Number.isFinite(fpsRaw) && fpsRaw > 0 ? fpsRaw : 24
  return { durationSeconds, fps }
}

export function assertAnnotationTimeOffsetAllowed(
  timeOffsetSeconds: number,
  durationSeconds: number
): void {
  if (!Number.isFinite(timeOffsetSeconds)) {
    throw new ReviewRouteError('Invalid timecode', 400)
  }
  if (timeOffsetSeconds < -0.02) {
    throw new ReviewRouteError('Timecode is before clip start', 400)
  }
  const upper = (durationSeconds > 0 ? durationSeconds : 0) + 0.5
  if (timeOffsetSeconds > upper) {
    throw new ReviewRouteError('Timecode is outside clip duration', 400)
  }
}

export function resolveAnnotationTimeOffsetSeconds(
  timecodeIn: string,
  clip: Pick<ClipAccessRecord, 'duration_seconds' | 'frame_rate'>
): number {
  const { fps } = clipPlaybackBounds(clip)
  return timecodeToSeconds(timecodeIn, fps)
}

export function normalizeAnnotation(record: Record<string, unknown>): ReviewAnnotation {
  const type = normalizeAnnotationType(record.type)
  const voiceUrl = annotationVoiceUrl(record, type)
  const rawBody = stringValue(record.content, record.body) ?? ''
  const resolvedAt = stringValue(
    record.resolved_at,
    record.resolvedAt,
    Boolean(record.is_resolved) ? record.updated_at : null,
    Boolean(record.is_resolved) ? record.timestamp : null
  )

  return {
    id: stringValue(record.id) ?? '',
    userId: stringValue(record.author_id, record.user_id, record.userId) ?? 'share-token',
    userDisplayName: stringValue(record.author_name, record.user_display_name, record.userDisplayName) ?? 'Reviewer',
    timecodeIn: stringValue(record.timecode, record.timecode_in, record.timecodeIn) ?? '00:00:00:00',
    timeOffsetSeconds: parseTimeOffsetSeconds(record),
    timecodeOut: stringValue(record.timecode_out, record.timecodeOut) ?? null,
    body: type === 'voice' ? (stringValue(record.voice_transcript) ?? '') : rawBody,
    type,
    voiceUrl,
    createdAt: stringValue(record.timestamp, record.created_at, record.createdAt) ?? new Date().toISOString(),
    resolvedAt,
    isResolved: Boolean(record.is_resolved ?? Boolean(resolvedAt)),
    mentions: normalizeMentionTokens(rawBody),
    replies: Array.isArray(record.replies)
      ? (record.replies as Record<string, unknown>[]).map(normalizeAnnotationReply)
      : [],
  }
}

async function loadAssemblyVersionRow(
  supabase: SupabaseClient,
  assemblyId: string
): Promise<Record<string, unknown> | null> {
  const { data, error } = await supabase
    .from('assembly_versions')
    .select('*')
    .eq('assembly_id', assemblyId)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  if (error || !data) {
    return null
  }

  return data
}

async function loadAssemblyClipRows(
  supabase: SupabaseClient,
  assemblyId: string
): Promise<Array<Record<string, unknown>> | null> {
  const { data, error } = await supabase
    .from('assembly_clips')
    .select('id, clip_id, order, in_point, out_point, duration, notes')
    .eq('assembly_id', assemblyId)
    .order('order', { ascending: true })

  if (error || !data) {
    return null
  }

  return data
}

async function loadAssemblyRecord(
  supabase: SupabaseClient,
  assemblyId: string
): Promise<Record<string, unknown> | null> {
  const { data, error } = await supabase
    .from('assemblies')
    .select('id, name, version, metadata')
    .eq('id', assemblyId)
    .maybeSingle()

  if (error || !data) {
    return null
  }

  return data
}

async function loadAssemblyClipIds(
  supabase: SupabaseClient,
  assemblyId: string
): Promise<Set<string>> {
  const versionRow = await loadAssemblyVersionRow(supabase, assemblyId)
  if (versionRow && Array.isArray(versionRow.clips)) {
    const ids = (versionRow.clips as unknown[])
      .map((clip) => {
        const r = typeof clip === 'object' && clip !== null ? (clip as Record<string, unknown>) : null
        return stringValue(r?.clipId, r?.clip_id, typeof clip === 'string' ? clip : null)
      })
      .filter((clipId): clipId is string => Boolean(clipId))

    return new Set(ids)
  }

  const clipRows = await loadAssemblyClipRows(supabase, assemblyId)
  if (!clipRows) {
    return new Set()
  }

  return new Set(
    clipRows
      .map((clip) => stringValue(clip?.clip_id))
      .filter((clipId): clipId is string => Boolean(clipId))
  )
}

export async function filterClipRowsForShareLink(
  supabase: SupabaseClient,
  shareLink: Pick<ReviewShareLink, 'scope' | 'scope_id'>,
  clipRows: Array<Record<string, unknown>>
): Promise<Array<Record<string, unknown>>> {
  if (shareLink.scope === 'project') {
    return clipRows
  }

  const assemblyClipIds = shareLink.scope === 'assembly' && shareLink.scope_id
    ? await loadAssemblyClipIds(supabase, shareLink.scope_id)
    : null

  return clipRows.filter((clip) =>
    clipMatchesShareScope(
      clip as { id: string; hierarchy?: Record<string, unknown> | null } & Record<string, unknown>,
      shareLink,
      assemblyClipIds
    )
  )
}

export async function requireShareLinkAccess(
  supabase: SupabaseClient,
  shareToken: string,
  request?: RequestCookieReader
): Promise<ShareLinkAccessRecord & { permissions: ReviewSharePermissions }> {
  const { data, error } = await supabase
    .from('share_links')
    .select('id, project_id, token, scope, scope_id, expires_at, password_hash, permissions, revoked_at')
    .eq('token', shareToken)
    .single<ShareLinkAccessRecord>()

  if (error || !data) {
    throw new ReviewRouteError('Invalid or expired share link', 404)
  }

  if (isLinkRevoked(data)) {
    throw new ReviewRouteError('Share link has been revoked', 410)
  }

  if (new Date(data.expires_at) < new Date()) {
    throw new ReviewRouteError('Share link has expired', 410)
  }

  if (data.password_hash) {
    const accessCookie = request?.cookies.get(reviewAccessCookieName(shareToken))?.value
    if (!hasValidReviewAccessCookie(accessCookie, shareToken, data.password_hash)) {
      throw new ReviewRouteError('Password required for this share link', 401)
    }
  }

  return {
    ...data,
    permissions: normalizePermissions(data.permissions),
  }
}

export async function requireClipAccess(
  supabase: SupabaseClient,
  clipId: string,
  shareLink: Pick<ReviewShareLink, 'project_id' | 'scope' | 'scope_id'>
): Promise<ClipAccessRecord> {
  const { data, error } = await supabase
    .from('clips')
    .select('id, project_id, hierarchy, duration_seconds, frame_rate')
    .eq('id', clipId)
    .eq('project_id', shareLink.project_id)
    .single<ClipAccessRecord>()

  if (error || !data) {
    throw new ReviewRouteError('Clip not found for this share link', 404)
  }

  const assemblyClipIds = shareLink.scope === 'assembly' && shareLink.scope_id
    ? await loadAssemblyClipIds(supabase, shareLink.scope_id)
    : null

  if (!clipMatchesShareScope(data as ClipAccessRecord & Record<string, unknown>, shareLink, assemblyClipIds)) {
    throw new ReviewRouteError('Clip not found for this share link', 404)
  }

  return data
}

export async function createAnnotationRecord(
  supabase: SupabaseClient,
  params: {
    clipId: string
    authorName: string
    body: string
    timecodeIn: string
    timeOffsetSeconds: number
    type: AnnotationType
    voiceUrl?: string | null
    userId?: string | null
  }
): Promise<ReviewAnnotation> {
  const now = new Date().toISOString()
  const content = params.type === 'voice'
    ? (params.voiceUrl ?? params.body)
    : params.body
  const { data, error } = await supabase
    .from('annotations')
    .insert({
      id: crypto.randomUUID(),
      clip_id: params.clipId,
      author_id: params.userId ?? '00000000-0000-0000-0000-000000000000',
      author_name: params.authorName,
      timecode: params.timecodeIn,
      time_offset_seconds: params.timeOffsetSeconds,
      type: params.type,
      content,
      voice_url: params.voiceUrl ?? null,
      is_private: false,
      is_resolved: false,
      resolved_at: null,
      timestamp: now,
      created_at: now,
      updated_at: now,
    })
    .select()
    .single()

  if (error || !data) {
    throw new ReviewRouteError('Failed to create annotation', 500)
  }

  return normalizeAnnotation(data)
}

export async function createAnnotationReplyRecord(
  supabase: SupabaseClient,
  params: {
    annotationId: string
    authorName: string
    body: string
    userId?: string | null
  }
): Promise<ReviewAnnotationReply> {
  const { data, error } = await supabase
    .from('annotation_replies')
    .insert({
      id: crypto.randomUUID(),
      annotation_id: params.annotationId,
      author_id: params.userId ?? '00000000-0000-0000-0000-000000000000',
      author_name: params.authorName,
      content: params.body,
      created_at: new Date().toISOString(),
    })
    .select()
    .single()

  if (error || !data) {
    throw new ReviewRouteError('Failed to create annotation reply', 500)
  }

  return normalizeAnnotationReply(data)
}

export async function setAnnotationResolved(
  supabase: SupabaseClient,
  annotationId: string,
  isResolved: boolean
): Promise<ReviewAnnotation> {
  const now = new Date().toISOString()
  const { data, error } = await supabase
    .from('annotations')
    .update({
      is_resolved: isResolved,
      resolved_at: isResolved ? now : null,
      updated_at: now,
    })
    .eq('id', annotationId)
    .select()
    .single()

  if (error || !data) {
    throw new ReviewRouteError('Failed to update annotation state', 500)
  }

  return normalizeAnnotation(data)
}

export async function incrementShareLinkView(
  supabase: SupabaseClient,
  shareLinkId: string,
  currentCount: number
): Promise<number> {
  const nextCount = currentCount + 1
  const { error } = await supabase
    .from('share_links')
    .update({
      view_count: nextCount,
      last_viewed_at: new Date().toISOString(),
    })
    .eq('id', shareLinkId)

  if (error) {
    console.error('Failed to update share link analytics:', error)
    return currentCount
  }

  return nextCount
}

export async function broadcastClipEvent(
  supabase: SupabaseClient,
  clipId: string,
  event: string,
  payload: Record<string, unknown>
): Promise<void> {
  await supabase.channel(`clip:${clipId}`).send({
    type: 'broadcast',
    event,
    payload,
  })
}

function stringValue(...values: Array<unknown>): string | null {
  for (const value of values) {
    if (typeof value === 'string' && value.trim().length > 0) {
      return value
    }
  }
  return null
}

function objectValue(value: unknown): Record<string, unknown> | null {
  return typeof value === 'object' && value !== null ? (value as Record<string, unknown>) : null
}

function normalizeAssemblyClip(raw: Record<string, unknown> | null | undefined, index: number): ReviewAssemblyClipRange | null {
  const clipId = stringValue(raw?.clipId, raw?.clip_id, raw?.id)
  if (!clipId) {
    return null
  }

  return {
    id: stringValue(raw?.id, `${clipId}-${index}`) ?? `${clipId}-${index}`,
    clipId,
    label: stringValue(raw?.label, raw?.clipLabel, raw?.sceneLabel, raw?.title) ?? `Clip ${index + 1}`,
    order: Number(raw?.order ?? index + 1),
    timecodeIn: stringValue(raw?.timecodeIn, raw?.in_point, raw?.inPoint) ?? '00:00:00:00',
    timecodeOut: stringValue(raw?.timecodeOut, raw?.out_point, raw?.outPoint) ?? '00:00:00:00',
    duration: stringValue(raw?.duration, raw?.duration_label) ?? null,
  }
}

export async function loadAssemblyData(
  supabase: SupabaseClient,
  assemblyId: string
): Promise<ReviewAssemblyData> {
  const versionRow = await loadAssemblyVersionRow(supabase, assemblyId)

  if (versionRow) {
    const rawClips = Array.isArray(versionRow.clips) ? versionRow.clips : []
    const clips = (rawClips as Array<Record<string, unknown>>)
      .map((clip, index) => normalizeAssemblyClip(clip, index))
      .filter((clip): clip is ReviewAssemblyClipRange => clip !== null)
      .sort((left, right) => left.order - right.order)

    return {
      id: assemblyId,
      title: stringValue(versionRow.title, versionRow.assembly_title, versionRow.name) ?? 'Assembly',
      versionLabel: stringValue(
        versionRow.version_label,
        typeof versionRow.version === 'number' ? `v${versionRow.version}` : null,
        typeof versionRow.version === 'string' ? versionRow.version : null
      ) ?? 'Latest',
      artifactPath: stringValue(versionRow.artifact_path, versionRow.artifactPath),
      clips,
    }
  }

  const assemblyRow = await loadAssemblyRecord(supabase, assemblyId)
  const clipRows = await loadAssemblyClipRows(supabase, assemblyId)

  if (!assemblyRow) {
    throw new ReviewRouteError('Assembly not found', 404)
  }

  const clips = (clipRows ?? [])
    .map((clip, index) => normalizeAssemblyClip({
      id: clip.id,
      clip_id: clip.clip_id,
      order: clip.order,
      in_point: clip.in_point,
      out_point: clip.out_point,
      duration: clip.duration,
      label: clip.notes,
    }, index))
    .filter((clip): clip is ReviewAssemblyClipRange => clip !== null)
    .sort((left, right) => left.order - right.order)

  const assemblyMetadata = objectValue(assemblyRow.metadata)

  return {
    id: assemblyId,
    title: stringValue(assemblyRow.name, assemblyMetadata?.title) ?? 'Assembly',
    versionLabel: stringValue(
      assemblyRow.version,
      assemblyMetadata?.versionLabel,
      assemblyMetadata?.version_label
    ) ?? 'Latest',
    artifactPath: stringValue(
      assemblyMetadata?.artifactPath,
      assemblyMetadata?.artifact_path
    ),
    clips,
  }
}

export function isLinkRevoked(shareLink: { revoked_at?: string | null }): boolean {
  return Boolean(shareLink.revoked_at)
}
