import type { Metadata } from 'next'
import { cookies } from 'next/headers'
import ReviewClient from './client'
import PasswordGate from '@/components/PasswordGate'
import { getMockReviewFixture } from '@/lib/review-mocks'
import { hasValidReviewAccessCookie, isShareLinkExpired, reviewAccessCookieName } from '@/lib/review-auth'
import { loadReviewShareLink } from '@/lib/review-share-links'
import {
  filterClipRowsForShareLink,
  incrementShareLinkView,
  isLinkRevoked,
  normalizeAnnotation as normalizeServerAnnotation,
  normalizeAnnotationReply,
} from '@/lib/review-server'
import type {
  ReviewAIScores,
  ReviewAnnotation,
  ReviewAnnotationReply,
  ReviewClip,
  ReviewProjectData,
  ReviewShareLink,
} from '@/lib/review-types'
import { createServerSupabaseClient } from '@/lib/supabase'
import { secondsToTimecode } from '@/lib/timecode'

interface PageProps {
  params: { token: string }
  searchParams?: { clip?: string; t?: string }
}

function ReviewAccessState({
  title,
  description,
}: {
  title: string
  description: string
}) {
  return (
    <main className="min-h-screen bg-zinc-950 text-zinc-100 flex items-center justify-center p-6">
      <div className="max-w-md rounded-2xl border border-zinc-800 bg-zinc-900/80 p-8 text-center space-y-3">
        <h1 className="text-2xl font-semibold">{title}</h1>
        <p className="text-sm text-zinc-400">{description}</p>
      </div>
    </main>
  )
}

function normalizeReviewStatus(status: string | null | undefined): ReviewClip['reviewStatus'] {
  switch (status) {
    case 'approved':
    case 'circled':
      return 'circled'
    case 'alternate':
    case 'flagged':
      return 'flagged'
    case 'rejected':
    case 'x':
      return 'x'
    case 'deprioritized':
      return 'deprioritized'
    case 'in_review':
      return 'unreviewed'
    case 'new':
      return 'unreviewed'
    default:
      return 'unreviewed'
  }
}

function normalizeProxyStatus(status: string | null | undefined): ReviewClip['proxyStatus'] {
  switch (status) {
    case 'processing':
    case 'ready':
    case 'error':
      return status
    case 'completed':
      return 'ready'
    case 'failed':
      return 'error'
    default:
      return 'pending'
  }
}

function normalizeTranscriptStatus(status: string | null | undefined): ReviewClip['transcriptStatus'] {
  switch (status) {
    case 'completed':
    case 'ready':
      return 'ready'
    case 'failed':
      return 'error'
    case 'processing':
      return 'processing'
    default:
      return 'pending'
  }
}

function normalizeSyncConfidence(value: unknown): ReviewClip['syncResult'] extends { confidence: infer T } | null ? T : never {
  if (value === 'high' || value === 'medium' || value === 'low' || value === 'manual_required' || value === 'unsynced') {
    return value
  }

  if (typeof value === 'number') {
    if (value >= 0.85) return 'high'
    if (value >= 0.6) return 'medium'
    if (value >= 0.35) return 'low'
    return 'manual_required'
  }

  return 'unsynced'
}

function buildTranscriptSegments(record: any, duration: number, fps: number): ReviewClip['transcriptSegments'] {
  const sourceSegments = record.metadata?.transcriptSegments ?? record.metadata?.transcript_segments
  if (Array.isArray(sourceSegments) && sourceSegments.length > 0) {
    return sourceSegments.map((segment: any, index: number) => {
      const startSeconds = Number(segment.startSeconds ?? segment.start_seconds ?? 0)
      const endSeconds = Number(segment.endSeconds ?? segment.end_seconds ?? startSeconds + 3)
      return {
        id: segment.id ?? `segment-${index + 1}`,
        startSeconds,
        endSeconds,
        startTimecode: segment.startTimecode ?? secondsToTimecode(startSeconds, fps),
        endTimecode: segment.endTimecode ?? secondsToTimecode(endSeconds, fps),
        text: segment.text ?? '',
        speaker: segment.speaker ?? null,
      }
    })
  }

  const transcriptText = typeof record.transcription_text === 'string'
    ? record.transcription_text.trim()
    : ''
  if (!transcriptText) {
    return []
  }

  const sentences = transcriptText
    .split(/(?<=[.!?])\s+/)
    .map((sentence: string) => sentence.trim())
    .filter(Boolean)

  if (sentences.length === 0) {
    return []
  }

  const segmentDuration = duration > 0 ? duration / sentences.length : 4
  return sentences.map((sentence: string, index: number) => {
    const startSeconds = index * segmentDuration
    const endSeconds = Math.min(duration || startSeconds + segmentDuration, startSeconds + segmentDuration)
    return {
      id: `generated-segment-${index + 1}`,
      startSeconds,
      endSeconds,
      startTimecode: secondsToTimecode(startSeconds, fps),
      endTimecode: secondsToTimecode(endSeconds, fps),
      text: sentence,
      speaker: null,
    }
  })
}

function normalizeAIScores(raw: any): ReviewAIScores | null {
  if (!raw) return null

  const technical = raw.technical ?? raw
  return {
    composite: Number(raw.composite ?? technical.overall ?? 0),
    focus: Number(raw.focus ?? technical.focus ?? 0),
    exposure: Number(raw.exposure ?? technical.exposure ?? 0),
    stability: Number(raw.stability ?? technical.stability ?? 0),
    audio: Number(raw.audio ?? technical.audio ?? technical.audioLevel ?? 0),
    performance: raw.performance ?? null,
    contentDensity: raw.contentDensity ?? raw.content_density ?? raw.content?.contentDensity ?? null,
    scoredAt: raw.scoredAt ?? raw.scored_at ?? new Date().toISOString(),
    modelVersion: raw.modelVersion ?? raw.model_version ?? 'unknown',
    reasoning: Array.isArray(raw.reasoning)
      ? raw.reasoning.map((reason: any) => ({
          dimension: reason.dimension ?? 'unknown',
          score: Number(reason.score ?? 0),
          flag: reason.flag ?? 'info',
          message: reason.message ?? '',
          timecode: reason.timecode ?? null,
        }))
      : [],
  }
}

function normalizeClip(record: any, projectMode: 'narrative' | 'documentary', annotations: ReviewAnnotation[]): ReviewClip {
  const hierarchy = record.hierarchy ?? {}
  const narrative = hierarchy.narrative
  const documentary = hierarchy.documentary
  const duration = Number(record.duration_seconds ?? record.duration ?? 0)
  const sourceFps = Number(record.frame_rate ?? record.source_fps ?? 24)
  const aiProcessingStatus = (() => {
    switch (record.ai_processing_status) {
      case 'processing':
      case 'ready':
      case 'error':
      case 'pending':
        return record.ai_processing_status
      default:
        return record.ai_scores || record.aiScores ? 'ready' : 'pending'
    }
  })()

  return {
    id: record.id,
    projectId: record.project_id,
    reviewStatus: normalizeReviewStatus(record.review_status),
    proxyStatus: normalizeProxyStatus(record.proxy_status),
    duration,
    sourceFps,
    sourceTimecodeStart: record.timecode_start ?? record.source_timecode_start ?? '00:00:00:00',
    narrativeMeta: (hierarchy.mode ?? projectMode) === 'narrative'
      ? {
          sceneNumber: narrative?.sceneNumber ?? 'UNK',
          shotCode: narrative?.setupLetter ?? narrative?.shotCode ?? 'A',
          takeNumber: Number(narrative?.takeNumber ?? 1),
          cameraId: record.metadata?.camera?.model ?? 'A Cam',
        }
      : null,
    documentaryMeta: (hierarchy.mode ?? projectMode) === 'documentary'
      ? {
          subjectName: documentary?.subjectName || 'Uncategorized',
          shootingDay: Number(documentary?.dayNumber ?? 1),
          sessionLabel: documentary?.interviewNumber ? `Interview ${documentary.interviewNumber}` : (documentary?.bRollCategory || 'Session'),
        }
      : null,
    aiScores: normalizeAIScores(record.ai_scores ?? record.aiScores),
    annotations,
    projectMode,
    transcriptText: record.transcription_text ?? null,
    transcriptStatus: normalizeTranscriptStatus(record.transcription_status),
    transcriptSegments: buildTranscriptSegments(record, duration, sourceFps),
    syncResult: record.sync_confidence != null || record.sync_status
      ? {
          confidence: normalizeSyncConfidence(
            record.sync_confidence ?? (record.sync_status === 'completed' ? 'medium' : 'unsynced')
          ),
          method: record.sync_method ?? (record.sync_status === 'completed' ? 'waveform_correlation' : 'none'),
          offsetFrames: Number(record.sync_offset_frames ?? 0),
          driftPPM: Number(record.sync_drift_ppm ?? 0),
          verifiedAt: record.sync_processed_at ?? null,
        }
      : null,
    metadata: record.metadata ?? {},
    aiProcessingStatus,
  }
}

function buildGroupedClipIds(clips: ReviewClip[]): Record<string, string[]> {
  return clips.reduce<Record<string, string[]>>((acc, clip) => {
    const key = clip.narrativeMeta
      ? `Scene ${clip.narrativeMeta.sceneNumber}`
      : clip.documentaryMeta?.subjectName || 'Uncategorized'

    if (!acc[key]) {
      acc[key] = []
    }
    acc[key].push(clip.id)
    return acc
  }, {})
}

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const shareLink = await loadReviewShareLink(params.token)
  const unavailable = {
    title: 'Review Link Unavailable - SLATE',
    description: 'This review link is no longer available.',
  } as const

  if (!shareLink || isLinkRevoked(shareLink) || isShareLinkExpired(shareLink.expires_at)) {
    return unavailable
  }

  return {
    title: `${shareLink.project.name} - SLATE Review`,
    description: `Review and collaborate on ${shareLink.project.name}`,
  }
}

async function getProjectData(shareLink: ReviewShareLink): Promise<ReviewProjectData> {
  if (process.env.NEXT_PUBLIC_REVIEW_E2E_MODE === 'mock') {
    return getMockReviewFixture(shareLink.token)?.projectData ?? { grouped: {}, clips: [] }
  }

  const supabase = createServerSupabaseClient()

  const clipsQuery = supabase
    .from('clips')
    .select('*')
    .eq('project_id', shareLink.project_id)
    .order('created_at', { ascending: true })

  const { data: clipRows } = await clipsQuery
  const scopedClipRows = await filterClipRowsForShareLink(supabase, shareLink, clipRows ?? [])
  const clipIds = scopedClipRows.map((clip) => clip.id)
  const { data: annotationRows } = clipIds.length === 0
    ? { data: [] as any[] }
    : await supabase
        .from('annotations')
        .select('*')
        .in('clip_id', clipIds)
        .order('time_offset_seconds', { ascending: true, nullsFirst: false })
        .order('created_at', { ascending: true })

  const annotationIds = (annotationRows ?? []).map((row) => row.id)
  const { data: replyRows } = annotationIds.length === 0
    ? { data: [] as any[] }
    : await supabase
        .from('annotation_replies')
        .select('*')
        .in('annotation_id', annotationIds)
        .order('created_at', { ascending: true })

  const repliesByAnnotation = (replyRows ?? []).reduce<Record<string, ReviewAnnotationReply[]>>((acc, row) => {
    const annotationId = row.annotation_id
    if (!acc[annotationId]) {
      acc[annotationId] = []
    }
    acc[annotationId].push(normalizeAnnotationReply(row))
    return acc
  }, {})

  const annotationsByClip = (annotationRows ?? []).reduce<Record<string, ReviewAnnotation[]>>((acc, row) => {
    const clipId = row.clip_id
    if (!acc[clipId]) {
      acc[clipId] = []
    }
    acc[clipId].push(normalizeServerAnnotation({
      ...row,
      replies: repliesByAnnotation[row.id] ?? [],
    }))
    return acc
  }, {})

  const normalizedClips = (clipRows ?? []).map((row) =>
    normalizeClip(row, shareLink.project.mode, annotationsByClip[row.id] ?? [])
  )

  const visibleClips = normalizedClips.filter((clip) =>
    scopedClipRows.some((row) => row.id === clip.id)
  )

  return {
    grouped: buildGroupedClipIds(visibleClips),
    clips: visibleClips,
  }
}

export default async function ReviewPage({ params, searchParams }: PageProps) {
  const shareLinkData = await loadReviewShareLink(params.token)

  if (!shareLinkData) {
    return (
      <ReviewAccessState
        title="Review Link Not Found"
        description="This share link could not be found. Check the link and try again."
      />
    )
  }

  if (isLinkRevoked(shareLinkData)) {
    return (
      <ReviewAccessState
        title="Review Link Revoked"
        description="This share link has been revoked. Ask the production team for a fresh link."
      />
    )
  }

  if (isShareLinkExpired(shareLinkData.expires_at)) {
    return (
      <ReviewAccessState
        title="Review Link Expired"
        description="This share link has expired. Ask the production team for a fresh link."
      />
    )
  }

  if (shareLinkData.password_hash) {
    const cookieStore = cookies()
    const accessCookie = cookieStore.get(reviewAccessCookieName(params.token))?.value
    const hasPasswordAccess = hasValidReviewAccessCookie(
      accessCookie,
      params.token,
      shareLinkData.password_hash
    )

    if (!hasPasswordAccess) {
      return <PasswordGate token={params.token} />
    }
  }

  let hydratedShareLink = shareLinkData
  if (process.env.NEXT_PUBLIC_REVIEW_E2E_MODE !== 'mock') {
    const supabase = createServerSupabaseClient()
    const nextViewCount = await incrementShareLinkView(
      supabase,
      shareLinkData.id,
      shareLinkData.view_count ?? 0
    )
    hydratedShareLink = {
      ...shareLinkData,
      view_count: nextViewCount,
      last_viewed_at: new Date().toISOString(),
    }
  }

  const projectData = await getProjectData(hydratedShareLink)

  const initialClipId = typeof searchParams?.clip === 'string' && searchParams.clip.trim().length > 0
    ? searchParams.clip.trim()
    : null
  const initialTimeParam = searchParams?.t
  const initialTimeSeconds = typeof initialTimeParam === 'string' && initialTimeParam.trim().length > 0
    ? Number.parseFloat(initialTimeParam)
    : null

  return (
    <ReviewClient
      shareLink={hydratedShareLink}
      projectData={projectData}
      token={params.token}
      initialClipId={initialClipId}
      initialTimeSeconds={initialTimeSeconds != null && Number.isFinite(initialTimeSeconds) ? initialTimeSeconds : null}
    />
  )
}
