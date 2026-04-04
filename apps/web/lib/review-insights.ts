import type { ReviewAnnotation, ReviewClip, ReviewStatus } from '@/lib/review-types'

export type ReviewSearchReasonKind =
  | 'label'
  | 'transcript'
  | 'annotation'
  | 'reply'
  | 'metadata'
  | 'ai'
  | 'status'
  | 'sync'

export interface ReviewSearchReason {
  kind: ReviewSearchReasonKind
  label: string
}

export interface ReviewClipSearchMatch {
  searchableText: string
  reasons: ReviewSearchReason[]
}

export interface ReviewPipelineCounts {
  pending: number
  processing: number
  ready: number
  error: number
}

export interface ReviewSyncCounts {
  high: number
  medium: number
  low: number
  manualRequired: number
  unsynced: number
}

export interface ReviewSmartSelect {
  clipId: string
  label: string
  score: number
  reviewStatus: ReviewStatus
  summary: string
  transcriptSnippet: string | null
  unresolvedNotes: number
}

export interface ReviewWatchlistItem {
  clipId: string
  label: string
  severity: 'high' | 'medium' | 'low'
  issues: string[]
}

export interface ReviewActivityItem {
  id: string
  clipId: string
  clipLabel: string
  kind: 'annotation' | 'reply' | 'resolved'
  actor: string
  occurredAt: string
  summary: string
}

export interface ReviewOpsSummary {
  totalClips: number
  circledCount: number
  flaggedCount: number
  unreviewedCount: number
  readyToAssembleCount: number
  followUpCount: number
  unresolvedNotesCount: number
  proxy: ReviewPipelineCounts
  transcript: ReviewPipelineCounts
  ai: ReviewPipelineCounts
  sync: ReviewSyncCounts
  smartSelects: ReviewSmartSelect[]
  watchlist: ReviewWatchlistItem[]
  recentActivity: ReviewActivityItem[]
}

interface SearchCandidate {
  kind: ReviewSearchReasonKind
  label: string
  text: string
}

function tokenize(query: string): string[] {
  return query
    .toLowerCase()
    .trim()
    .split(/\s+/)
    .filter(Boolean)
}

function normalizeText(value: string): string {
  return value
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim()
}

function includesAllTokens(searchableText: string, tokens: string[]): boolean {
  if (tokens.length === 0) {
    return true
  }

  return tokens.every((token) => searchableText.includes(token))
}

function includesAnyToken(searchableText: string, tokens: string[]): boolean {
  return tokens.some((token) => searchableText.includes(token))
}

function flattenMetadata(
  value: unknown,
  path: string[] = [],
  depth = 0
): string[] {
  if (value == null || depth > 3) {
    return []
  }

  if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
    const label = path.length > 0 ? `${path.join(' ')} ${String(value)}` : String(value)
    return [label]
  }

  if (Array.isArray(value)) {
    return value.flatMap((entry) => flattenMetadata(entry, path, depth + 1))
  }

  if (typeof value === 'object') {
    return Object.entries(value as Record<string, unknown>).flatMap(([key, entry]) =>
      flattenMetadata(entry, [...path, key], depth + 1)
    )
  }

  return []
}

function firstSentence(text: string): string {
  const normalized = text.replace(/\s+/g, ' ').trim()
  if (normalized.length <= 88) {
    return normalized
  }

  return `${normalized.slice(0, 85).trimEnd()}...`
}

function uniqueReasons(reasons: ReviewSearchReason[]): ReviewSearchReason[] {
  const seen = new Set<string>()
  return reasons.filter((reason) => {
    const key = `${reason.kind}:${reason.label}`
    if (seen.has(key)) {
      return false
    }
    seen.add(key)
    return true
  })
}

function normalizePipelineStatus(status: ReviewClip['proxyStatus'] | ReviewClip['transcriptStatus'] | ReviewClip['aiProcessingStatus']): keyof ReviewPipelineCounts {
  switch (status) {
    case 'processing':
      return 'processing'
    case 'ready':
      return 'ready'
    case 'error':
      return 'error'
    default:
      return 'pending'
  }
}

function unresolvedNotesCount(clip: ReviewClip): number {
  return clip.annotations.filter((annotation) => !annotation.isResolved).length
}

function clipIssueList(clip: ReviewClip): string[] {
  const issues: string[] = []

  if (clip.reviewStatus === 'flagged') {
    issues.push('Marked as alternate')
  }
  if (clip.reviewStatus === 'x') {
    issues.push('Rejected in review')
  }
  if (clip.reviewStatus === 'unreviewed') {
    issues.push('Still waiting on review')
  }
  if (clip.proxyStatus === 'error') {
    issues.push('Proxy generation failed')
  }
  if (clip.transcriptStatus === 'error') {
    issues.push('Transcript failed')
  }
  if (clip.aiProcessingStatus === 'error') {
    issues.push('AI scoring failed')
  }
  if (clip.syncResult?.confidence === 'manual_required') {
    issues.push('Sync needs manual alignment')
  }
  if (clip.syncResult?.confidence === 'unsynced') {
    issues.push('Sync not verified')
  }
  if ((clip.aiScores?.composite ?? 101) < 55) {
    issues.push('Low composite AI score')
  }

  const unresolved = unresolvedNotesCount(clip)
  if (unresolved > 0) {
    issues.push(`${unresolved} open note${unresolved === 1 ? '' : 's'}`)
  }

  return issues
}

function issueSeverity(clip: ReviewClip, issues: string[]): ReviewWatchlistItem['severity'] {
  if (
    clip.reviewStatus === 'flagged' ||
    clip.reviewStatus === 'x' ||
    clip.proxyStatus === 'error' ||
    clip.transcriptStatus === 'error' ||
    clip.aiProcessingStatus === 'error' ||
    clip.syncResult?.confidence === 'manual_required' ||
    clip.syncResult?.confidence === 'unsynced'
  ) {
    return 'high'
  }

  if (issues.length > 0) {
    return 'medium'
  }

  return 'low'
}

function clipReadyToAssemble(clip: ReviewClip): boolean {
  return (
    clip.reviewStatus === 'circled' &&
    clip.proxyStatus === 'ready' &&
    clip.aiProcessingStatus === 'ready' &&
    clip.syncResult?.confidence !== 'manual_required' &&
    clip.syncResult?.confidence !== 'unsynced' &&
    unresolvedNotesCount(clip) === 0
  )
}

function smartSelectScore(clip: ReviewClip): number {
  const unresolved = unresolvedNotesCount(clip)
  const aiBase = clip.aiScores?.composite ?? 45
  const performanceBoost = clip.aiScores?.performance ?? 0
  const densityBoost = clip.aiScores?.contentDensity ?? 0

  let score = aiBase + (performanceBoost * 0.25) + (densityBoost * 0.15)

  if (clip.reviewStatus === 'circled') {
    score += 18
  }
  if (clip.reviewStatus === 'flagged') {
    score -= 22
  }
  if (clip.reviewStatus === 'x') {
    score -= 30
  }
  if (clip.proxyStatus !== 'ready') {
    score -= 12
  }
  if (clip.aiProcessingStatus !== 'ready') {
    score -= 8
  }
  if (clip.syncResult?.confidence === 'high') {
    score += 6
  }
  if (clip.syncResult?.confidence === 'manual_required' || clip.syncResult?.confidence === 'unsynced') {
    score -= 10
  }

  return score - (unresolved * 6)
}

function smartSelectSummary(clip: ReviewClip): string {
  const summary: string[] = []
  const unresolved = unresolvedNotesCount(clip)

  if (clip.reviewStatus === 'circled') {
    summary.push('circled for review')
  }
  if ((clip.aiScores?.performance ?? 0) >= 75) {
    summary.push('strong performance')
  }
  if ((clip.aiScores?.contentDensity ?? 0) >= 65) {
    summary.push('dialogue-dense')
  }
  if (clip.syncResult?.confidence === 'high') {
    summary.push('sync verified')
  }
  if (unresolved === 0) {
    summary.push('no open notes')
  }

  return summary.length > 0 ? summary.join(' · ') : 'worth a closer look'
}

function transcriptSnippet(clip: ReviewClip): string | null {
  if (clip.transcriptSegments.length > 0) {
    return firstSentence(clip.transcriptSegments[0]!.text)
  }

  if (clip.transcriptText) {
    return firstSentence(clip.transcriptText)
  }

  return null
}

function annotationSummary(annotation: ReviewAnnotation): string {
  if (annotation.type === 'voice') {
    return annotation.body.trim() || 'Voice note added'
  }

  return firstSentence(annotation.body)
}

function buildSearchCandidates(clip: ReviewClip): SearchCandidate[] {
  const metadataCandidates = flattenMetadata(clip.metadata).map((entry) => ({
    kind: 'metadata' as const,
    label: firstSentence(entry),
    text: entry,
  }))

  const annotationCandidates = clip.annotations.flatMap((annotation) => {
    const baseCandidates: SearchCandidate[] = [
      {
        kind: 'annotation',
        label: annotationSummary(annotation),
        text: [annotation.body, annotation.mentions.join(' ')].join(' '),
      },
    ]

    for (const reply of annotation.replies) {
      baseCandidates.push({
        kind: 'reply',
        label: firstSentence(reply.body),
        text: [reply.body, reply.mentions.join(' ')].join(' '),
      })
    }

    return baseCandidates
  })

  const transcriptCandidates = clip.transcriptSegments.map((segment) => ({
    kind: 'transcript' as const,
    label: firstSentence(segment.text),
    text: [segment.text, segment.speaker ?? '', segment.startTimecode].join(' '),
  }))

  const aiCandidates = (clip.aiScores?.reasoning ?? []).map((reason) => ({
    kind: 'ai' as const,
    label: firstSentence(reason.message),
    text: [reason.dimension, reason.message, reason.flag, reason.timecode ?? ''].join(' '),
  }))

  const label = clipLabel(clip)
  const statusLabel = [
    clip.reviewStatus,
    clip.proxyStatus,
    clip.transcriptStatus,
    clip.aiProcessingStatus,
  ].join(' ')
  const syncLabel = clip.syncResult
    ? [clip.syncResult.confidence, clip.syncResult.method].join(' ')
    : 'unsynced'

  return [
    {
      kind: 'label',
      label,
      text: [
        label,
        clip.narrativeMeta?.sceneNumber ?? '',
        clip.narrativeMeta?.shotCode ?? '',
        String(clip.narrativeMeta?.takeNumber ?? ''),
        clip.narrativeMeta?.cameraId ?? '',
        clip.documentaryMeta?.subjectName ?? '',
        clip.documentaryMeta?.sessionLabel ?? '',
        String(clip.documentaryMeta?.shootingDay ?? ''),
      ].join(' '),
    },
    {
      kind: 'status',
      label: `Status: ${clip.reviewStatus}`,
      text: statusLabel,
    },
    {
      kind: 'sync',
      label: `Sync: ${clip.syncResult?.confidence ?? 'unsynced'}`,
      text: syncLabel,
    },
    ...transcriptCandidates,
    ...annotationCandidates,
    ...metadataCandidates,
    ...aiCandidates,
  ]
}

export function clipLabel(clip: ReviewClip): string {
  if (clip.narrativeMeta) {
    const { sceneNumber, shotCode, takeNumber, cameraId } = clip.narrativeMeta
    return `Sc${sceneNumber} Sh${shotCode} T${takeNumber} ${cameraId}`
  }

  if (clip.documentaryMeta) {
    const { subjectName, sessionLabel, shootingDay } = clip.documentaryMeta
    return `${subjectName} · Day ${shootingDay} · ${sessionLabel}`
  }

  return clip.id.slice(0, 8)
}

export function buildClipSearchMatch(
  clip: ReviewClip,
  query: string
): ReviewClipSearchMatch | null {
  const tokens = tokenize(query)
  const candidates = buildSearchCandidates(clip)
  const searchableText = normalizeText(candidates.map((candidate) => candidate.text).join(' '))

  if (!includesAllTokens(searchableText, tokens)) {
    return null
  }

  const reasons = uniqueReasons(
    candidates
      .filter((candidate) => includesAnyToken(normalizeText(candidate.text), tokens))
      .map((candidate) => ({
        kind: candidate.kind,
        label: candidate.label,
      }))
  ).slice(0, 4)

  return {
    searchableText,
    reasons,
  }
}

export function buildReviewOpsSummary(clips: ReviewClip[]): ReviewOpsSummary {
  const proxy: ReviewPipelineCounts = { pending: 0, processing: 0, ready: 0, error: 0 }
  const transcript: ReviewPipelineCounts = { pending: 0, processing: 0, ready: 0, error: 0 }
  const ai: ReviewPipelineCounts = { pending: 0, processing: 0, ready: 0, error: 0 }
  const sync: ReviewSyncCounts = {
    high: 0,
    medium: 0,
    low: 0,
    manualRequired: 0,
    unsynced: 0,
  }

  let circledCount = 0
  let flaggedCount = 0
  let unreviewedCount = 0
  let readyToAssembleCount = 0
  let followUpCount = 0
  let unresolvedNotesCountTotal = 0

  for (const clip of clips) {
    proxy[normalizePipelineStatus(clip.proxyStatus)] += 1
    transcript[normalizePipelineStatus(clip.transcriptStatus)] += 1
    ai[normalizePipelineStatus(clip.aiProcessingStatus)] += 1

    switch (clip.syncResult?.confidence ?? 'unsynced') {
      case 'high':
        sync.high += 1
        break
      case 'medium':
        sync.medium += 1
        break
      case 'low':
        sync.low += 1
        break
      case 'manual_required':
        sync.manualRequired += 1
        break
      default:
        sync.unsynced += 1
        break
    }

    if (clip.reviewStatus === 'circled') {
      circledCount += 1
    }
    if (clip.reviewStatus === 'flagged') {
      flaggedCount += 1
    }
    if (clip.reviewStatus === 'unreviewed') {
      unreviewedCount += 1
    }

    const issues = clipIssueList(clip)
    const unresolved = unresolvedNotesCount(clip)
    unresolvedNotesCountTotal += unresolved

    if (clipReadyToAssemble(clip)) {
      readyToAssembleCount += 1
    }

    if (issues.length > 0) {
      followUpCount += 1
    }
  }

  const smartSelects = [...clips]
    .filter((clip) => clip.reviewStatus !== 'x' && clip.reviewStatus !== 'deprioritized')
    .sort((left, right) => smartSelectScore(right) - smartSelectScore(left))
    .slice(0, 5)
    .map((clip) => ({
      clipId: clip.id,
      label: clipLabel(clip),
      score: Math.round(smartSelectScore(clip)),
      reviewStatus: clip.reviewStatus,
      summary: smartSelectSummary(clip),
      transcriptSnippet: transcriptSnippet(clip),
      unresolvedNotes: unresolvedNotesCount(clip),
    }))

  const watchlist = clips
    .map((clip) => {
      const issues = clipIssueList(clip)
      if (issues.length === 0) {
        return null
      }

      return {
        clipId: clip.id,
        label: clipLabel(clip),
        severity: issueSeverity(clip, issues),
        issues: issues.slice(0, 3),
      } satisfies ReviewWatchlistItem
    })
    .filter((item): item is ReviewWatchlistItem => item !== null)
    .sort((left, right) => {
      const severityRank = { high: 0, medium: 1, low: 2 }
      return severityRank[left.severity] - severityRank[right.severity]
    })
    .slice(0, 6)

  const recentActivity = clips
    .flatMap((clip) => {
      const label = clipLabel(clip)
      const items: ReviewActivityItem[] = []

      for (const annotation of clip.annotations) {
        items.push({
          id: `annotation:${annotation.id}`,
          clipId: clip.id,
          clipLabel: label,
          kind: 'annotation',
          actor: annotation.userDisplayName,
          occurredAt: annotation.createdAt,
          summary: annotationSummary(annotation),
        })

        for (const reply of annotation.replies) {
          items.push({
            id: `reply:${reply.id}`,
            clipId: clip.id,
            clipLabel: label,
            kind: 'reply',
            actor: reply.userDisplayName,
            occurredAt: reply.createdAt,
            summary: firstSentence(reply.body),
          })
        }

        if (annotation.resolvedAt) {
          items.push({
            id: `resolved:${annotation.id}`,
            clipId: clip.id,
            clipLabel: label,
            kind: 'resolved',
            actor: annotation.userDisplayName,
            occurredAt: annotation.resolvedAt,
            summary: 'Annotation resolved',
          })
        }
      }

      return items
    })
    .sort((left, right) =>
      new Date(right.occurredAt).getTime() - new Date(left.occurredAt).getTime()
    )
    .slice(0, 8)

  return {
    totalClips: clips.length,
    circledCount,
    flaggedCount,
    unreviewedCount,
    readyToAssembleCount,
    followUpCount,
    unresolvedNotesCount: unresolvedNotesCountTotal,
    proxy,
    transcript,
    ai,
    sync,
    smartSelects,
    watchlist,
    recentActivity,
  }
}
