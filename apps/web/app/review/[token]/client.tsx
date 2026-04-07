'use client'

import React, {
  startTransition,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react'
import { createBrowserSupabaseClient } from '@/lib/supabase'
import ReviewHeader from '@/components/ReviewHeader'
import { ClipList } from '@/components/ClipList'
import { AnnotationPanel } from '@/components/AnnotationPanel'
import { AIScoresPanel } from '@/components/AIScoresPanel'
import { StatusControls } from '@/components/StatusControls'
import { RequestAlternateButton } from '@/components/RequestAlternateButton'
import { StatusBadge } from '@/components/StatusBadge'
import { BatchStatusBar } from '@/components/BatchStatusBar'
import { TranscriptPanel } from '@/components/TranscriptPanel'
import { ClipContextPanel } from '@/components/ClipContextPanel'
import { ReviewPresenceBar } from '@/components/ReviewPresenceBar'
import { ReviewOpsPanel } from '@/components/ReviewOpsPanel'
import { SpatialAnnotationOverlay } from '@/components/SpatialAnnotationOverlay'
import { CastCharactersPanel } from '@/components/CastCharactersPanel'
import { clipLabel } from '@/lib/review-insights'
import {
  type AnnotationType,
  type ReviewAnnotation,
  type ReviewAnnotationReply,
  type ReviewAssemblyData,
  type ReviewAssemblyVersionDiff,
  type ReviewClip,
  type ReviewFaceCluster,
  type ReviewPresenceUser,
  type ReviewProjectData,
  type ReviewShareLink,
  type ReviewStatus,
  type SpatialAnnotationPayload,
} from '@/lib/review-types'
import { secondsToTimecode, timecodeToSeconds } from '@/lib/timecode'
import { cn, storage } from '@/lib/utils'

interface ReviewClientProps {
  shareLink: ReviewShareLink
  projectData: ReviewProjectData
  token: string
  initialClipId?: string | null
  initialTimeSeconds?: number | null
}

type QuickActionId =
  | 'copy-link'
  | 'notes-tab'
  | 'transcript-tab'
  | 'toggle-shortcuts'
  | 'walkthrough'

const WALKTHROUGH_STORAGE_KEY = 'slate-review-walkthrough-v1'
const QUICK_ACTIONS_STORAGE_KEY = 'slate-review-quick-actions-v1'
const DEFAULT_QUICK_ACTIONS: QuickActionId[] = [
  'copy-link',
  'notes-tab',
  'transcript-tab',
  'toggle-shortcuts',
  'walkthrough',
]

function annotationMatches(left: ReviewAnnotation, right: ReviewAnnotation): boolean {
  return (
    left.id === right.id ||
    (
      left.timecodeIn === right.timecodeIn &&
      left.body === right.body &&
      left.type === right.type &&
      left.userDisplayName === right.userDisplayName
    )
  )
}

function mergeAnnotation(
  annotations: ReviewAnnotation[],
  incoming: ReviewAnnotation
): ReviewAnnotation[] {
  const exactIndex = annotations.findIndex((annotation) => annotation.id === incoming.id)
  if (exactIndex >= 0) {
    return annotations.map((annotation, index) => (
      index === exactIndex ? incoming : annotation
    ))
  }

  const optimisticIndex = annotations.findIndex((annotation) => (
    annotation.id.startsWith('temp-') &&
    annotation.timecodeIn === incoming.timecodeIn &&
    annotation.body === incoming.body &&
    annotation.type === incoming.type
  ))

  if (optimisticIndex >= 0) {
    return annotations.map((annotation, index) => (
      index === optimisticIndex ? incoming : annotation
    ))
  }

  if (annotations.some((annotation) => annotationMatches(annotation, incoming))) {
    return annotations
  }

  return [...annotations, incoming]
}

function mergeReply(
  annotations: ReviewAnnotation[],
  annotationId: string,
  incoming: ReviewAnnotationReply
): ReviewAnnotation[] {
  return annotations.map((annotation) => {
    if (annotation.id !== annotationId) {
      return annotation
    }

    const existingReplies = annotation.replies ?? []
    const optimisticIndex = existingReplies.findIndex((reply) =>
      reply.id === incoming.id ||
      (
        reply.id.startsWith('temp-') &&
        reply.body === incoming.body &&
        reply.userDisplayName === incoming.userDisplayName
      )
    )

    if (optimisticIndex >= 0) {
      return {
        ...annotation,
        replies: existingReplies.map((reply, index) => (
          index === optimisticIndex ? incoming : reply
        )),
      }
    }

    return {
      ...annotation,
      replies: [...existingReplies, incoming],
    }
  })
}

function formatDuration(seconds: number): string {
  const mins = Math.floor(seconds / 60)
  const secs = Math.floor(seconds % 60)
  return `${mins}m ${String(secs).padStart(2, '0')}s`
}

function normalizeClusterToken(value: string): string {
  return value.trim().toLowerCase()
}

function preferredClusterSpeakerName(cluster: ReviewFaceCluster): string | null {
  const actor = cluster.display_name?.trim() ?? ''
  const character = cluster.character_name?.trim() ?? ''
  if (actor && character) {
    return `${actor} (${character})`
  }
  return actor || character || null
}

function buildSpeakerNameMap(clusters: ReviewFaceCluster[]): Record<string, string> {
  const map: Record<string, string> = {}
  for (const cluster of clusters) {
    const preferredName = preferredClusterSpeakerName(cluster)
    if (!preferredName) {
      continue
    }

    const candidateTokens = new Set<string>()
    const clusterKey = cluster.cluster_key?.trim() ?? ''
    if (clusterKey) {
      candidateTokens.add(clusterKey)
    }

    const metadata = cluster.metadata ?? {}
    const possibleArrays = [
      metadata.speakerIds,
      metadata.speaker_ids,
      metadata.aliases,
      metadata.labels,
    ]

    for (const value of possibleArrays) {
      if (!Array.isArray(value)) {
        continue
      }
      for (const token of value) {
        if (typeof token === 'string' && token.trim()) {
          candidateTokens.add(token)
        }
      }
    }

    for (const token of Array.from(candidateTokens)) {
      map[token] = preferredName
      map[normalizeClusterToken(token)] = preferredName
    }
  }
  return map
}

function primaryVideoElement(): HTMLVideoElement | null {
  return document.querySelector('video[data-review-player="primary"]')
}

function VideoPlayer({
  clipId,
  token,
  fps,
  onTimeUpdate,
  seekTo,
  timecodeLabel,
  annotations = [],
  onCreateSpatialAnnotation,
  onPlaybackEvent,
  showShortcutOverlay = false,
  prefetchedStream,
  watermarkSessionId,
  playerId = 'primary',
  muted = false,
}: {
  clipId: string
  token: string
  fps: number
  onTimeUpdate: (time: number) => void
  seekTo?: number | null
  /** When set, drives the burn-in overlay (keeps display in sync with parent playback state). */
  timecodeLabel?: string
  annotations?: ReviewAnnotation[]
  onCreateSpatialAnnotation?: (payload: SpatialAnnotationPayload) => void
  onPlaybackEvent?: (payload: { kind: 'play' | 'pause' | 'seek'; currentTime: number; isPlaying: boolean }) => void
  showShortcutOverlay?: boolean
  prefetchedStream?: {
    signedUrl: string
    thumbnailUrl?: string | null
    watermark?: { token?: string | null; sessionId?: string | null } | null
  } | null
  watermarkSessionId?: string
  playerId?: 'primary' | 'compare'
  muted?: boolean
}) {
  const videoRef = useRef<HTMLVideoElement>(null)
  const hlsRef = useRef<{ destroy: () => void } | null>(null)
  const [signedUrl, setSignedUrl] = useState<string | null>(null)
  const [thumbnailUrl, setThumbnailUrl] = useState<string | null>(null)
  const [watermarkToken, setWatermarkToken] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let isActive = true

    async function loadStream() {
      if (prefetchedStream?.signedUrl) {
        setSignedUrl(prefetchedStream.signedUrl)
        setThumbnailUrl(prefetchedStream.thumbnailUrl ?? null)
        setWatermarkToken(prefetchedStream.watermark?.token ?? null)
        setLoading(false)
        return
      }
      setLoading(true)
      setError(null)
      setSignedUrl(null)
      setThumbnailUrl(null)
      setWatermarkToken(null)

      try {
        const response = await fetch('/api/proxy-url', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Share-Token': token,
          },
          body: JSON.stringify({
            clipId,
            watermarkSessionId,
          }),
        })

        const payload = await response.json()
        if (!response.ok) {
          throw new Error(payload.error ?? 'Failed to load proxy')
        }

        if (!isActive) {
          return
        }

        setSignedUrl(payload.signedUrl)
        setThumbnailUrl(payload.thumbnailUrl ?? null)
        setWatermarkToken(typeof payload?.watermark?.token === 'string' ? payload.watermark.token : null)
      } catch (loadError) {
        if (!isActive) {
          return
        }

        setError(loadError instanceof Error ? loadError.message : 'Failed to load proxy')
      } finally {
        if (isActive) {
          setLoading(false)
        }
      }
    }

    void loadStream()

    return () => {
      isActive = false
    }
  }, [clipId, token, prefetchedStream, watermarkSessionId])

  useEffect(() => {
    let isActive = true

    async function attachStream() {
      if (!signedUrl || !videoRef.current) {
        return
      }

      if (hlsRef.current) {
        hlsRef.current.destroy()
        hlsRef.current = null
      }

      if (videoRef.current.canPlayType('application/vnd.apple.mpegurl')) {
        videoRef.current.src = signedUrl
        return
      }

      const { default: Hls } = await import('hls.js')
      if (!isActive || !videoRef.current) {
        return
      }

      if (Hls.isSupported()) {
        const hls = new Hls({
          enableWorker: true,
          lowLatencyMode: false,
        })
        hls.loadSource(signedUrl)
        hls.attachMedia(videoRef.current)
        hlsRef.current = hls
      } else {
        videoRef.current.src = signedUrl
      }
    }

    void attachStream()

    return () => {
      isActive = false
      if (hlsRef.current) {
        hlsRef.current.destroy()
        hlsRef.current = null
      }
    }
  }, [signedUrl])

  useEffect(() => {
    if (seekTo == null || !videoRef.current) {
      return
    }

    if (Math.abs(videoRef.current.currentTime - seekTo) > 0.25) {
      videoRef.current.currentTime = seekTo
    }
  }, [seekTo])

  if (loading) {
    return (
      <div
        className="flex aspect-video items-center justify-center rounded-2xl bg-zinc-950 text-sm text-zinc-500"
        data-testid="proxy-player-shell"
      >
        Loading proxy…
      </div>
    )
  }

  if (error) {
    return (
      <div
        className="flex aspect-video items-center justify-center rounded-2xl bg-zinc-950 text-sm text-rose-300"
        data-testid="proxy-player-error"
      >
        {error}
      </div>
    )
  }

  return (
    <div className="relative rounded-2xl bg-black" data-testid="proxy-player-shell">
      <video
        ref={videoRef}
        data-review-player={playerId}
        data-watermark-token={watermarkToken ?? undefined}
        className="aspect-video w-full rounded-2xl"
        controls
        muted={muted}
        playsInline
        preload="metadata"
        poster={thumbnailUrl ?? undefined}
        onTimeUpdate={(event) => onTimeUpdate(event.currentTarget.currentTime)}
        onPlay={(event) => onPlaybackEvent?.({
          kind: 'play',
          currentTime: event.currentTarget.currentTime,
          isPlaying: true,
        })}
        onPause={(event) => onPlaybackEvent?.({
          kind: 'pause',
          currentTime: event.currentTarget.currentTime,
          isPlaying: false,
        })}
        onSeeked={(event) => onPlaybackEvent?.({
          kind: 'seek',
          currentTime: event.currentTarget.currentTime,
          isPlaying: !event.currentTarget.paused,
        })}
      />

      {playerId === 'primary' && onCreateSpatialAnnotation ? (
        <SpatialAnnotationOverlay
          videoRef={videoRef}
          annotations={annotations}
          onSave={onCreateSpatialAnnotation}
          disabled={false}
        />
      ) : null}

      <div className="pointer-events-none absolute bottom-12 right-3 rounded bg-black/70 px-2 py-1 text-xs font-mono text-white">
        {timecodeLabel ?? secondsToTimecode(videoRef.current?.currentTime ?? 0, fps)}
      </div>
      {showShortcutOverlay ? (
        <div className="pointer-events-none absolute bottom-3 left-3 rounded bg-black/70 px-2 py-1 text-[11px] text-zinc-200">
          J / K / L: -10s · Play/Pause · +10s
        </div>
      ) : null}
    </div>
  )
}

function AssemblyPanel({
  token,
  assemblyId,
}: {
  token: string
  assemblyId: string
}) {
  const [assembly, setAssembly] = useState<ReviewAssemblyData | null>(null)
  const [diff, setDiff] = useState<ReviewAssemblyVersionDiff | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [query, setQuery] = useState('')

  useEffect(() => {
    let isActive = true

    async function loadAssembly() {
      setIsLoading(true)
      setError(null)

      try {
        const [assemblyResponse, diffResponse] = await Promise.all([
          fetch(`/api/assembly/${assemblyId}`, {
            headers: {
              'X-Share-Token': token,
            },
          }),
          fetch(`/api/assembly/${assemblyId}/diff`, {
            headers: {
              'X-Share-Token': token,
            },
          }),
        ])

        const assemblyPayload = await assemblyResponse.json()
        const diffPayload = await diffResponse.json()

        if (!assemblyResponse.ok) {
          throw new Error(assemblyPayload.error ?? 'Failed to load assembly')
        }

        if (isActive) {
          setAssembly(assemblyPayload)
          setDiff(diffPayload)
        }
      } catch (loadError) {
        if (isActive) {
          setError(loadError instanceof Error ? loadError.message : 'Failed to load assembly')
        }
      } finally {
        if (isActive) {
          setIsLoading(false)
        }
      }
    }

    void loadAssembly()

    return () => {
      isActive = false
    }
  }, [assemblyId, token])

  if (isLoading) {
    return <div className="p-4 text-sm text-zinc-500">Loading assembly…</div>
  }

  if (error) {
    return <div className="p-4 text-sm text-rose-300">{error}</div>
  }

  if (!assembly) {
    return <div className="p-4 text-sm text-zinc-500">Assembly unavailable.</div>
  }

  const filteredClips = !query.trim()
    ? assembly.clips
    : assembly.clips.filter((clip) => {
        const searchable = [
          clip.label,
          clip.timecodeIn,
          clip.timecodeOut,
          clip.duration ?? '',
        ].join(' ').toLowerCase()
        return searchable.includes(query.toLowerCase())
      })

  return (
    <div className="space-y-4 p-4">
      <div className="space-y-1">
        <h3 className="text-sm font-semibold text-zinc-100">{assembly.title}</h3>
        <p className="text-xs uppercase tracking-[0.22em] text-zinc-500">
          {assembly.versionLabel}
        </p>
      </div>

      <div className="space-y-2">
        <input
          type="text"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Search assembly clips…"
          className="w-full rounded-lg border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 placeholder:text-zinc-600 focus:border-zinc-700 focus:outline-none"
        />

        {filteredClips.map((clip) => (
          <div key={clip.id} className="rounded-xl border border-zinc-800 bg-zinc-950 px-3 py-3">
            <div className="flex items-center justify-between gap-3">
              <div>
                <p className="text-sm font-medium text-zinc-100">{clip.label}</p>
                <p className="text-xs text-zinc-500">
                  {clip.timecodeIn} - {clip.timecodeOut}
                </p>
              </div>
              {clip.duration ? (
                <span className="text-xs text-zinc-400">{clip.duration}</span>
              ) : null}
            </div>
          </div>
        ))}

        {filteredClips.length === 0 ? (
          <div className="rounded-xl border border-dashed border-zinc-800 px-4 py-8 text-center text-sm text-zinc-500">
            No assembly clips match your search.
          </div>
        ) : null}
      </div>

      {diff?.available ? (
        <div className="rounded-2xl border border-zinc-800 bg-zinc-900/40 p-4">
          <div className="flex items-center justify-between gap-3">
            <span className="text-xs font-semibold uppercase tracking-[0.22em] text-zinc-400">
              Version Diff
            </span>
            <span className="text-xs text-zinc-500">
              {diff.fromLabel} → {diff.toLabel}
            </span>
          </div>
          <div className="mt-3 grid gap-3 text-sm md:grid-cols-3">
            <div>
              <div className="text-xs uppercase tracking-wide text-zinc-500">Added</div>
              <div className="mt-2 space-y-1 text-zinc-300">
                {diff.added.length > 0 ? diff.added.map((clip) => (
                  <div key={clip.clipId}>{clip.label}</div>
                )) : <div className="text-zinc-500">No additions</div>}
              </div>
            </div>
            <div>
              <div className="text-xs uppercase tracking-wide text-zinc-500">Removed</div>
              <div className="mt-2 space-y-1 text-zinc-300">
                {diff.removed.length > 0 ? diff.removed.map((clip) => (
                  <div key={clip.clipId}>{clip.label}</div>
                )) : <div className="text-zinc-500">No removals</div>}
              </div>
            </div>
            <div>
              <div className="text-xs uppercase tracking-wide text-zinc-500">Moved</div>
              <div className="mt-2 space-y-1 text-zinc-300">
                {diff.moved.length > 0 ? diff.moved.map((clip) => (
                  <div key={clip.clipId}>
                    {clip.label} ({clip.from} → {clip.to})
                  </div>
                )) : <div className="text-zinc-500">No reordering</div>}
              </div>
            </div>
          </div>
        </div>
      ) : null}

      <div className="space-y-2">
        {assembly.artifactPath ? (
          <a
            href={`/api/assembly/${assembly.id}/download?shareToken=${encodeURIComponent(token)}`}
            className="block rounded-md border border-zinc-700 px-3 py-2 text-center text-sm font-medium text-zinc-100 transition-colors hover:bg-zinc-900"
          >
            Download Export
          </a>
        ) : null}
        <a
          href={`/api/assembly/${assembly.id}/report?format=csv&token=${encodeURIComponent(token)}`}
          className="block rounded-md border border-zinc-700 px-3 py-2 text-center text-sm font-medium text-zinc-100 transition-colors hover:bg-zinc-900"
        >
          Download Report (CSV)
        </a>
      </div>
    </div>
  )
}

export default function ReviewClient({
  shareLink,
  projectData,
  token,
  initialClipId = null,
  initialTimeSeconds = null,
}: ReviewClientProps) {
  const [supabase] = useState(() => createBrowserSupabaseClient())
  const [clips, setClips] = useState<ReviewClip[]>(projectData.clips)
  const [selectedClipId, setSelectedClipId] = useState<string | null>(projectData.clips[0]?.id ?? null)
  const [selectedAnnotationId, setSelectedAnnotationId] = useState<string | null>(null)
  const [currentTime, setCurrentTime] = useState(0)
  const [seekTo, setSeekTo] = useState<number | null>(null)
  const [isPostingAnnotation, setIsPostingAnnotation] = useState(false)
  const [annotationError, setAnnotationError] = useState<string | null>(null)
  const [isUpdatingStatus, setIsUpdatingStatus] = useState(false)
  const [alternateMessage, setAlternateMessage] = useState<string | null>(null)
  const [inspectorTab, setInspectorTab] = useState<'notes' | 'transcript' | 'ai' | 'cast' | 'context' | 'ops'>('notes')
  const [realtimeStatus, setRealtimeStatus] = useState<string | null>(null)
  const [activeSidebarTab, setActiveSidebarTab] = useState<'clips' | 'assembly'>('clips')
  const [selectedClipIds, setSelectedClipIds] = useState<Set<string>>(new Set())
  const [presence, setPresence] = useState<Record<string, ReviewPresenceUser>>({})
  const [showSearchPalette, setShowSearchPalette] = useState(false)
  const [showWalkthrough, setShowWalkthrough] = useState(false)
  const [walkthroughStep, setWalkthroughStep] = useState(0)
  const [showQuickActionsEditor, setShowQuickActionsEditor] = useState(false)
  const [quickActions, setQuickActions] = useState<QuickActionId[]>(DEFAULT_QUICK_ACTIONS)
  const [showShortcutOverlay, setShowShortcutOverlay] = useState(true)
  const [searchQuery, setSearchQuery] = useState('')
  const [searchResults, setSearchResults] = useState<Array<{
    id: string
    clipId: string | null
    sourceType: string
    sourceId: string
    timeOffsetSeconds: number | null
    body: string
    score?: number | null
  }>>([])
  const [isSearching, setIsSearching] = useState(false)
  const [prefetchedStreams, setPrefetchedStreams] = useState<Record<string, {
    signedUrl: string
    thumbnailUrl?: string | null
    watermark?: { token?: string | null; sessionId?: string | null } | null
  }>>({})
  const [faceClustersByClipId, setFaceClustersByClipId] = useState<Record<string, ReviewFaceCluster[]>>({})
  const [faceClustersLoadingByClipId, setFaceClustersLoadingByClipId] = useState<Record<string, boolean>>({})
  const [faceClusterErrorByClipId, setFaceClusterErrorByClipId] = useState<Record<string, string | null>>({})
  const [watchPartyHostId, setWatchPartyHostId] = useState<string | null>(null)
  const [watchPartyEnabled, setWatchPartyEnabled] = useState(true)
  const viewerIdRef = useRef(`reviewer-${crypto.randomUUID()}`)
  const viewerNameRef = useRef(`Reviewer ${shareLink.token.slice(0, 4)}`)
  const deepLinkAppliedRef = useRef(false)
  const activeChannelRef = useRef<ReturnType<typeof supabase.channel> | null>(null)
  const suppressPlaybackBroadcastRef = useRef(false)

  useEffect(() => {
    const walkthroughState = storage.get(WALKTHROUGH_STORAGE_KEY) as { completed?: boolean } | null
    if (!walkthroughState?.completed) {
      setShowWalkthrough(true)
      setWalkthroughStep(0)
    }

    const savedActions = storage.get(QUICK_ACTIONS_STORAGE_KEY) as QuickActionId[] | null
    if (Array.isArray(savedActions) && savedActions.length > 0) {
      const filtered = savedActions.filter((value) => DEFAULT_QUICK_ACTIONS.includes(value))
      setQuickActions(filtered.length > 0 ? filtered : DEFAULT_QUICK_ACTIONS)
    }
  }, [])

  const selectedClip = clips.find((clip) => clip.id === selectedClipId) ?? null
  const compareClip = useMemo(() => {
    if (!selectedClip) {
      return null
    }

    return Array.from(selectedClipIds)
      .map((clipId) => clips.find((clip) => clip.id === clipId) ?? null)
      .find((clip): clip is ReviewClip => clip !== null && clip.id !== selectedClip.id) ?? null
  }, [clips, selectedClip, selectedClipIds])
  const currentTimecode = secondsToTimecode(currentTime, selectedClip?.sourceFps ?? 24)
  const activePresence = useMemo(
    () => Object.values(presence)
      .filter((viewer) => Date.now() - new Date(viewer.activeAt).getTime() < 35_000)
      .sort((left, right) => left.name.localeCompare(right.name)),
    [presence]
  )
  const selectedClipFaceClusters = useMemo(
    () => (selectedClip ? faceClustersByClipId[selectedClip.id] ?? [] : []),
    [faceClustersByClipId, selectedClip]
  )
  const selectedClipSpeakerNameMap = useMemo(
    () => buildSpeakerNameMap(selectedClipFaceClusters),
    [selectedClipFaceClusters]
  )

  useEffect(() => {
    if (!selectedClip) {
      return
    }
    const clipId = selectedClip.id
    let cancelled = false

    setFaceClustersLoadingByClipId((previous) => ({ ...previous, [clipId]: true }))
    setFaceClusterErrorByClipId((previous) => ({ ...previous, [clipId]: null }))

    void (async () => {
      try {
        const response = await fetch(`/api/face-clusters/${clipId}`, {
          headers: {
            'X-Share-Token': token,
          },
        })
        const payload = await response.json()
        if (!response.ok) {
          throw new Error(payload.error ?? 'Failed to load cast clusters')
        }
        if (cancelled) {
          return
        }
        const clusters = Array.isArray(payload.clusters)
          ? payload.clusters as ReviewFaceCluster[]
          : []
        setFaceClustersByClipId((previous) => ({ ...previous, [clipId]: clusters }))
      } catch (loadError) {
        if (cancelled) {
          return
        }
        setFaceClusterErrorByClipId((previous) => ({
          ...previous,
          [clipId]: loadError instanceof Error ? loadError.message : 'Failed to load cast clusters',
        }))
      } finally {
        if (!cancelled) {
          setFaceClustersLoadingByClipId((previous) => ({ ...previous, [clipId]: false }))
        }
      }
    })()

    return () => {
      cancelled = true
    }
  }, [selectedClip, token])

  const handleSaveFaceCluster = useCallback(async (
    cluster: ReviewFaceCluster,
    displayName: string,
    characterName: string
  ) => {
    if (!selectedClip) {
      return
    }

    const response = await fetch(`/api/face-clusters/${selectedClip.id}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Share-Token': token,
      },
      body: JSON.stringify({
        shareToken: token,
        clusterKey: cluster.cluster_key,
        displayName,
        characterName,
      }),
    })
    const payload = await response.json()
    if (!response.ok || !payload.cluster) {
      throw new Error(payload.error ?? 'Failed to save cast label')
    }

    const updated = payload.cluster as ReviewFaceCluster
    setFaceClustersByClipId((previous) => {
      const prior = previous[selectedClip.id] ?? []
      const next = prior.some((item) => item.id === updated.id || item.cluster_key === updated.cluster_key)
        ? prior.map((item) => (
            item.id === updated.id || item.cluster_key === updated.cluster_key
              ? updated
              : item
          ))
        : [...prior, updated]
      return { ...previous, [selectedClip.id]: next }
    })
  }, [selectedClip, token])

  useEffect(() => {
    if (!selectedClip) {
      return
    }
    const selectedIndex = clips.findIndex((clip) => clip.id === selectedClip.id)
    if (selectedIndex < 0 || selectedIndex >= clips.length - 1) {
      return
    }
    const nextClip = clips[selectedIndex + 1]
    if (!nextClip || prefetchedStreams[nextClip.id]) {
      return
    }
    let cancelled = false
    void (async () => {
      try {
        const response = await fetch('/api/proxy-url', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Share-Token': token,
          },
          body: JSON.stringify({
            clipId: nextClip.id,
            watermarkSessionId: viewerIdRef.current,
          }),
        })
        const payload = await response.json()
        if (!response.ok || !payload?.signedUrl || cancelled) {
          return
        }
        setPrefetchedStreams((previous) => ({
          ...previous,
          [nextClip.id]: {
            signedUrl: payload.signedUrl as string,
            thumbnailUrl: (payload.thumbnailUrl as string | null) ?? null,
            watermark: (
              typeof payload?.watermark === 'object' && payload?.watermark != null
                ? payload.watermark as { token?: string | null; sessionId?: string | null }
                : null
            ),
          },
        }))
      } catch {
        // Best effort prefetch.
      }
    })()
    return () => {
      cancelled = true
    }
  }, [clips, prefetchedStreams, selectedClip, token])

  useEffect(() => {
    if (!showSearchPalette) {
      return
    }
    const query = searchQuery.trim()
    if (query.length < 2) {
      setSearchResults([])
      return
    }
    let cancelled = false
    const timeout = window.setTimeout(async () => {
      setIsSearching(true)
      try {
        const response = await fetch(`/api/search?q=${encodeURIComponent(query)}&shareToken=${encodeURIComponent(token)}`, {
          headers: {
            'X-Share-Token': token,
          },
        })
        const payload = await response.json()
        if (!cancelled) {
          setSearchResults(payload.results ?? [])
        }
      } catch {
        if (!cancelled) {
          setSearchResults([])
        }
      } finally {
        if (!cancelled) {
          setIsSearching(false)
        }
      }
    }, 180)
    return () => {
      cancelled = true
      clearTimeout(timeout)
    }
  }, [searchQuery, showSearchPalette, token])

  useEffect(() => {
    if (!selectedClipId) {
      return
    }

    const channel = supabase
      .channel(`clip:${selectedClipId}`)
      .on('broadcast', { event: 'annotation_added' }, ({ payload }) => {
        if (!payload?.annotation) {
          return
        }

        setClips((previous) => previous.map((clip) => (
          clip.id === selectedClipId
            ? { ...clip, annotations: mergeAnnotation(clip.annotations, payload.annotation as ReviewAnnotation) }
            : clip
        )))
      })
      .on('broadcast', { event: 'annotation_reply_added' }, ({ payload }) => {
        if (!payload?.annotationId || !payload?.reply) {
          return
        }

        setClips((previous) => previous.map((clip) => (
          clip.id === selectedClipId
            ? {
                ...clip,
                annotations: mergeReply(
                  clip.annotations,
                  payload.annotationId as string,
                  payload.reply as ReviewAnnotationReply
                ),
              }
            : clip
        )))
      })
      .on('broadcast', { event: 'annotation_resolved' }, ({ payload }) => {
        if (!payload?.annotationId) {
          return
        }

        setClips((previous) => previous.map((clip) => (
          clip.id === selectedClipId
            ? {
                ...clip,
                annotations: clip.annotations.map((annotation) => (
                  annotation.id === payload.annotationId
                    ? {
                        ...annotation,
                        isResolved: Boolean(payload.isResolved),
                        resolvedAt: payload.isResolved ? (payload.resolvedAt as string | null) ?? new Date().toISOString() : null,
                      }
                    : annotation
                )),
              }
            : clip
        )))
      })
      .on('broadcast', { event: 'review_status_changed' }, ({ payload }) => {
        if (!payload?.clipId || !payload?.status) {
          return
        }

        setClips((previous) => previous.map((clip) => (
          clip.id === payload.clipId
            ? { ...clip, reviewStatus: payload.status as ReviewStatus }
            : clip
        )))
      })
      .on('broadcast', { event: 'proxy_status_changed' }, ({ payload }) => {
        if (!payload?.clipId || !payload?.proxyStatus) {
          return
        }

        setClips((previous) => previous.map((clip) => (
          clip.id === payload.clipId
            ? { ...clip, proxyStatus: payload.proxyStatus as ReviewClip['proxyStatus'] }
            : clip
        )))
      })
      .on('broadcast', { event: 'ai_scores_ready' }, ({ payload }) => {
        if (!payload?.clipId || !payload?.aiScores) {
          return
        }

        setClips((previous) => previous.map((clip) => (
          clip.id === payload.clipId
            ? {
                ...clip,
                aiScores: payload.aiScores as ReviewClip['aiScores'],
                aiProcessingStatus: payload.aiProcessingStatus === 'error' ? 'error' : 'ready',
              }
            : clip
        )))
      })
      .on('broadcast', { event: 'presence_ping' }, ({ payload }) => {
        if (!payload?.viewer?.id || !payload?.viewer?.name) {
          return
        }

        setPresence((previous) => ({
          ...previous,
          [payload.viewer.id as string]: {
            id: payload.viewer.id as string,
            name: payload.viewer.name as string,
            activeAt: payload.viewer.activeAt as string,
          },
        }))
      })
      .on('broadcast', { event: 'watch_party_state' }, ({ payload }) => {
        if (!payload || typeof payload !== 'object') {
          return
        }
        const hostId = typeof payload.hostId === 'string' ? payload.hostId : null
        const viewerId = typeof payload.viewerId === 'string' ? payload.viewerId : null
        const currentTime = typeof payload.currentTime === 'number' ? payload.currentTime : null
        const shouldPlay = Boolean(payload.isPlaying)
        if (hostId) {
          setWatchPartyHostId(hostId)
        }
        if (!watchPartyEnabled || !hostId || (watchPartyHostId != null && hostId !== watchPartyHostId)) {
          return
        }
        if (viewerId === viewerIdRef.current || currentTime == null) {
          return
        }
        const video = primaryVideoElement()
        if (!video) {
          return
        }
        suppressPlaybackBroadcastRef.current = true
        if (Math.abs(video.currentTime - currentTime) > 0.3) {
          video.currentTime = currentTime
        }
        if (shouldPlay && video.paused) {
          void video.play().catch(() => {})
        } else if (!shouldPlay && !video.paused) {
          video.pause()
        }
        window.setTimeout(() => {
          suppressPlaybackBroadcastRef.current = false
        }, 100)
      })
      .subscribe((status) => {
        setRealtimeStatus(status)
      })

    activeChannelRef.current = channel

    const sendPresence = () => channel.send({
      type: 'broadcast',
      event: 'presence_ping',
      payload: {
        viewer: {
          id: viewerIdRef.current,
          name: viewerNameRef.current,
          activeAt: new Date().toISOString(),
        },
      },
    })

    const presenceInterval = window.setInterval(() => {
      void sendPresence()
    }, 15_000)

    void sendPresence()
 
    return () => {
      clearInterval(presenceInterval)
      activeChannelRef.current = null
      void supabase.removeAllChannels()
    }
  }, [selectedClipId, supabase, watchPartyEnabled, watchPartyHostId])

  const selectClip = useCallback((clipId: string, options?: { seekSeconds?: number | null }) => {
    startTransition(() => {
      setSelectedClipId(clipId)
      setSelectedAnnotationId(null)
      const seek = options?.seekSeconds
      if (seek != null && Number.isFinite(seek)) {
        const t = Math.max(0, seek)
        setCurrentTime(t)
        setSeekTo(t)
      } else {
        setCurrentTime(0)
        setSeekTo(0)
      }
      setAnnotationError(null)
      setAlternateMessage(null)
    })
  }, [])

  useEffect(() => {
    if (deepLinkAppliedRef.current) {
      return
    }
    if (!initialClipId) {
      return
    }
    const clip = projectData.clips.find((c) => c.id === initialClipId)
    if (!clip) {
      return
    }
    deepLinkAppliedRef.current = true
    selectClip(initialClipId, {
      seekSeconds: initialTimeSeconds != null && Number.isFinite(initialTimeSeconds) ? initialTimeSeconds : null,
    })
  }, [initialClipId, initialTimeSeconds, projectData.clips, selectClip])

  const walkthroughSteps = useMemo(() => ([
    {
      title: 'Clip Browser',
      body: 'Use left panel search and filters to pick a hero clip fast.',
    },
    {
      title: 'Playback',
      body: 'Use J/K/L to shuttle and Arrow Up/Down to move between clips.',
    },
    {
      title: 'Notes & Status',
      body: 'Add an annotation, then mark status (C/F/X/D) to demonstrate review flow.',
    },
    {
      title: 'Quick Actions',
      body: 'Pin your preferred controls in Quick Actions. Press ? any time to replay this tour.',
    },
  ]), [])

  const completeWalkthrough = useCallback(() => {
    storage.set(WALKTHROUGH_STORAGE_KEY, { completed: true })
    setShowWalkthrough(false)
    setWalkthroughStep(0)
  }, [])

  const nextWalkthroughStep = useCallback(() => {
    setWalkthroughStep((previous) => {
      const next = previous + 1
      if (next >= walkthroughSteps.length) {
        completeWalkthrough()
        return previous
      }
      return next
    })
  }, [completeWalkthrough, walkthroughSteps.length])

  const handleCopyLinkAtTime = useCallback(async () => {
    if (!selectedClip || typeof window === 'undefined') {
      return
    }
    const url = new URL(`/review/${token}`, window.location.origin)
    url.searchParams.set('clip', selectedClip.id)
    url.searchParams.set('t', String(Math.max(0, currentTime)))
    try {
      await navigator.clipboard.writeText(url.toString())
    } catch {
      // Clipboard may be unavailable (permissions / non-secure context).
    }
  }, [selectedClip, token, currentTime])

  const moveQuickAction = useCallback((index: number, delta: number) => {
    setQuickActions((previous) => {
      const nextIndex = index + delta
      if (nextIndex < 0 || nextIndex >= previous.length) {
        return previous
      }
      const clone = [...previous]
      const [moved] = clone.splice(index, 1)
      clone.splice(nextIndex, 0, moved)
      storage.set(QUICK_ACTIONS_STORAGE_KEY, clone)
      return clone
    })
  }, [])

  const runQuickAction = useCallback((action: QuickActionId) => {
    switch (action) {
      case 'copy-link':
        void handleCopyLinkAtTime()
        break
      case 'notes-tab':
        setInspectorTab('notes')
        break
      case 'transcript-tab':
        setInspectorTab('transcript')
        break
      case 'toggle-shortcuts':
        setShowShortcutOverlay((value) => !value)
        break
      case 'walkthrough':
        setShowWalkthrough(true)
        setWalkthroughStep(0)
        break
    }
  }, [handleCopyLinkAtTime])

  const handleSeek = useCallback((seconds: number) => {
    setCurrentTime(seconds)
    setSeekTo(seconds)
  }, [])

  const handlePlaybackEvent = useCallback((payload: { kind: 'play' | 'pause' | 'seek'; currentTime: number; isPlaying: boolean }) => {
    if (!watchPartyEnabled || suppressPlaybackBroadcastRef.current) {
      return
    }
    const hostId = watchPartyHostId ?? viewerIdRef.current
    if (hostId !== viewerIdRef.current) {
      return
    }
    setWatchPartyHostId(hostId)
    const channel = activeChannelRef.current
    if (!channel) {
      return
    }
    void channel.send({
      type: 'broadcast',
      event: 'watch_party_state',
      payload: {
        hostId,
        viewerId: viewerIdRef.current,
        kind: payload.kind,
        currentTime: payload.currentTime,
        isPlaying: payload.isPlaying,
        sentAt: new Date().toISOString(),
      },
    })
  }, [watchPartyEnabled, watchPartyHostId])

  const handleSelectAnnotation = useCallback((timecodeIn: string) => {
    if (!selectedClip) {
      return
    }

    handleSeek(timecodeToSeconds(timecodeIn, selectedClip.sourceFps))
  }, [handleSeek, selectedClip])

  const handleAddAnnotation = useCallback(async (
    type: AnnotationType,
    body: string,
    voiceUrl?: string | null,
    spatialData?: SpatialAnnotationPayload | null
  ) => {
    if (!selectedClip || !shareLink.permissions.canComment) {
      return
    }

    setAnnotationError(null)
    setAlternateMessage(null)
    setIsPostingAnnotation(true)

    const optimisticAnnotation: ReviewAnnotation = {
      id: `temp-${crypto.randomUUID()}`,
      userId: 'share-token',
      userDisplayName: 'Reviewer',
      timecodeIn: currentTimecode,
      timeOffsetSeconds: currentTime,
      timecodeOut: null,
      body,
      type,
      voiceUrl: voiceUrl ?? null,
      spatialData: spatialData ?? null,
      createdAt: new Date().toISOString(),
      resolvedAt: null,
      isResolved: false,
      mentions: Array.from(new Set(Array.from((body || '').matchAll(/@([a-z0-9_.-]+)/gi)).map((match) => match[1].toLowerCase()))),
      replies: [],
    }

    setClips((previous) => previous.map((clip) => (
      clip.id === selectedClip.id
        ? { ...clip, annotations: mergeAnnotation(clip.annotations, optimisticAnnotation) }
        : clip
    )))

    try {
      const response = await fetch('/api/annotations', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Share-Token': token,
        },
        body: JSON.stringify({
          clipId: selectedClip.id,
          timecodeIn: currentTimecode,
          body,
          type,
          voiceUrl: voiceUrl ?? null,
          spatialData: spatialData ?? null,
          shareToken: token,
        }),
      })

      const payload = await response.json()
      if (!response.ok) {
        throw new Error(payload.error ?? 'Failed to post annotation')
      }

      if (!payload.annotation) {
        throw new Error('Annotation response was empty')
      }

      setClips((previous) => previous.map((clip) => (
        clip.id === selectedClip.id
          ? { ...clip, annotations: mergeAnnotation(clip.annotations, payload.annotation as ReviewAnnotation) }
          : clip
      )))
    } catch (postError) {
      setClips((previous) => previous.map((clip) => (
        clip.id === selectedClip.id
          ? {
              ...clip,
              annotations: clip.annotations.filter((annotation) => annotation.id !== optimisticAnnotation.id),
            }
          : clip
      )))
      setAnnotationError(postError instanceof Error ? postError.message : 'Failed to post annotation')
    } finally {
      setIsPostingAnnotation(false)
    }
  }, [currentTime, currentTimecode, selectedClip, shareLink.permissions.canComment, token])

  const handleReply = useCallback(async (annotationId: string, body: string) => {
    if (!selectedClip || !shareLink.permissions.canComment) {
      return
    }

    const optimisticReply: ReviewAnnotationReply = {
      id: `temp-${crypto.randomUUID()}`,
      annotationId,
      userId: 'share-token',
      userDisplayName: 'Reviewer',
      body,
      createdAt: new Date().toISOString(),
      mentions: Array.from(new Set(Array.from(body.matchAll(/@([a-z0-9_.-]+)/gi)).map((match) => match[1].toLowerCase()))),
    }

    setClips((previous) => previous.map((clip) => (
      clip.id === selectedClip.id
        ? { ...clip, annotations: mergeReply(clip.annotations, annotationId, optimisticReply) }
        : clip
    )))

    try {
      const response = await fetch(`/api/annotation-actions/${annotationId}/replies`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Share-Token': token,
        },
        body: JSON.stringify({ body, shareToken: token }),
      })
      const payload = await response.json()

      if (!response.ok) {
        throw new Error(payload.error ?? 'Failed to add reply')
      }

      setClips((previous) => previous.map((clip) => (
        clip.id === selectedClip.id
          ? { ...clip, annotations: mergeReply(clip.annotations, annotationId, payload.reply as ReviewAnnotationReply) }
          : clip
      )))
    } catch (error) {
      setClips((previous) => previous.map((clip) => (
        clip.id === selectedClip.id
          ? {
                  ...clip,
                  annotations: clip.annotations.map((annotation) => (
                    annotation.id === annotationId
                      ? {
                          ...annotation,
                          replies: (annotation.replies ?? []).filter((reply) => reply.id !== optimisticReply.id),
                        }
                      : annotation
                  )),
                }
          : clip
      )))
      setAnnotationError(error instanceof Error ? error.message : 'Failed to add reply')
    }
  }, [selectedClip, shareLink.permissions.canComment, token])

  const handleToggleResolved = useCallback(async (annotationId: string, nextResolved: boolean) => {
    if (!selectedClip || shareLink.role !== 'editor') {
      return
    }

    const previousAnnotation = selectedClip.annotations.find((annotation) => annotation.id === annotationId) ?? null
    setClips((previous) => previous.map((clip) => (
      clip.id === selectedClip.id
        ? {
            ...clip,
            annotations: clip.annotations.map((annotation) => (
              annotation.id === annotationId
                ? {
                    ...annotation,
                    isResolved: nextResolved,
                    resolvedAt: nextResolved ? new Date().toISOString() : null,
                  }
                : annotation
            )),
          }
        : clip
    )))

    try {
      const response = await fetch(`/api/annotation-actions/${annotationId}/resolve`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Share-Token': token,
        },
        body: JSON.stringify({ isResolved: nextResolved, shareToken: token }),
      })
      const payload = await response.json()
      if (!response.ok) {
        throw new Error(payload.error ?? 'Failed to update annotation')
      }

      if (payload.annotation) {
        setClips((previous) => previous.map((clip) => (
          clip.id === selectedClip.id
            ? { ...clip, annotations: mergeAnnotation(clip.annotations, payload.annotation as ReviewAnnotation) }
            : clip
        )))
      }
    } catch (error) {
      setClips((previous) => previous.map((clip) => (
        clip.id === selectedClip.id
          ? {
              ...clip,
              annotations: clip.annotations.map((annotation) => (
                annotation.id === annotationId && previousAnnotation
                  ? previousAnnotation
                  : annotation
              )),
            }
          : clip
      )))
      setAnnotationError(error instanceof Error ? error.message : 'Failed to update annotation')
    }
  }, [selectedClip, shareLink.role, token])

  const handleBatchStatusChange = useCallback(async (reviewStatus: ReviewStatus) => {
    const clipsToUpdate = Array.from(selectedClipIds)
    if (clipsToUpdate.length === 0) {
      return
    }

    const previousStatuses = new Map(
      clipsToUpdate.map((clipId) => [
        clipId,
        clips.find((clip) => clip.id === clipId)?.reviewStatus ?? 'unreviewed',
      ])
    )
    setIsUpdatingStatus(true)
    setClips((current) => current.map((clip) => (
      clipsToUpdate.includes(clip.id) ? { ...clip, reviewStatus } : clip
    )))

    try {
      for (const clipId of clipsToUpdate) {
        const response = await fetch(`/api/clips/${clipId}/status`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Share-Token': token,
          },
          body: JSON.stringify({
            reviewStatus,
            shareToken: token,
          }),
        })

        if (!response.ok) {
          const payload = await response.json()
          throw new Error(payload.error ?? 'Failed to update clip status')
        }
      }
    } catch (error) {
      setClips((current) => current.map((clip) => (
        previousStatuses.has(clip.id)
          ? { ...clip, reviewStatus: previousStatuses.get(clip.id) ?? 'unreviewed' }
          : clip
      )))
      setAlternateMessage(error instanceof Error ? error.message : 'Failed to update statuses')
    } finally {
      setIsUpdatingStatus(false)
      setSelectedClipIds(new Set())
    }
  }, [clips, selectedClipIds, token])

  const handleSelectClipCheckbox = useCallback((clipId: string, selected: boolean) => {
    setSelectedClipIds((previous) => {
      const updated = new Set(previous)
      if (selected) {
        updated.add(clipId)
      } else {
        updated.delete(clipId)
      }
      return updated
    })
  }, [])

  const handleClearSelection = useCallback(() => {
    setSelectedClipIds(new Set())
  }, [])

  const handleCompareClip = useCallback((clipId: string) => {
    if (selectedClipId == null) {
      selectClip(clipId)
      return
    }

    if (selectedClipId === clipId) {
      return
    }

    setSelectedClipIds(new Set([selectedClipId, clipId]))
  }, [selectClip, selectedClipId])

  const handleStatusChange = useCallback(async (reviewStatus: ReviewStatus) => {
    if (!selectedClip) {
      return
    }

    const previousStatus = selectedClip.reviewStatus
    setIsUpdatingStatus(true)
    setClips((previous) => previous.map((clip) => (
      clip.id === selectedClip.id ? { ...clip, reviewStatus } : clip
    )))

    try {
      const response = await fetch(`/api/clips/${selectedClip.id}/status`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Share-Token': token,
        },
        body: JSON.stringify({
          reviewStatus,
          shareToken: token,
        }),
      })
      const payload = await response.json()

      if (!response.ok) {
        throw new Error(payload.error ?? 'Failed to update clip status')
      }
    } catch (updateError) {
      setClips((previous) => previous.map((clip) => (
        clip.id === selectedClip.id ? { ...clip, reviewStatus: previousStatus } : clip
      )))
      setAlternateMessage(updateError instanceof Error ? updateError.message : 'Failed to update status')
    } finally {
      setIsUpdatingStatus(false)
    }
  }, [selectedClip, token])

  useEffect(() => {
    if (!selectedClip) {
      return
    }

    const orderedClipIds = clips.map((clip) => clip.id)
    const selectedIndex = orderedClipIds.findIndex((clipId) => clipId === selectedClip.id)

    function handleKeyDown(event: KeyboardEvent) {
      const target = event.target as HTMLElement | null
      if (target && ['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName)) {
        return
      }

      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault()
        setShowSearchPalette((value) => !value)
        return
      }

      if (event.key === '?') {
        event.preventDefault()
        setShowWalkthrough(true)
        setWalkthroughStep(0)
        return
      }

      if (event.key === 'j') {
        event.preventDefault()
        const video = primaryVideoElement()
        if (video) {
          video.currentTime = Math.max(0, video.currentTime - 10)
        }
      }

      if (event.key === 'l') {
        event.preventDefault()
        const video = primaryVideoElement()
        if (video) {
          video.currentTime = video.currentTime + 10
        }
      }

      if (event.key === 'k') {
        event.preventDefault()
        const video = primaryVideoElement()
        if (video) {
          if (video.paused) {
            void video.play()
          } else {
            video.pause()
          }
        }
      }

      if (event.key === 'ArrowDown' && selectedIndex < orderedClipIds.length - 1) {
        event.preventDefault()
        selectClip(orderedClipIds[selectedIndex + 1]!)
      }

      if (event.key === 'ArrowUp' && selectedIndex > 0) {
        event.preventDefault()
        selectClip(orderedClipIds[selectedIndex - 1]!)
      }

      if (event.key === '/') {
        event.preventDefault()
        const searchInput = document.querySelector<HTMLInputElement>('[data-testid="clip-search-input"]')
        searchInput?.focus()
        searchInput?.select()
      }

      if (shareLink.permissions.canFlag) {
        if (event.key.toLowerCase() === 'c') {
          event.preventDefault()
          void handleStatusChange('circled')
        }
        if (event.key.toLowerCase() === 'f') {
          event.preventDefault()
          void handleStatusChange('flagged')
        }
        if (event.key.toLowerCase() === 'x') {
          event.preventDefault()
          void handleStatusChange('x')
        }
        if (event.key.toLowerCase() === 'd') {
          event.preventDefault()
          void handleStatusChange('deprioritized')
        }
      }

      if (event.key.toLowerCase() === 'n') {
        setInspectorTab('notes')
      }
      if (event.key.toLowerCase() === 't') {
        setInspectorTab('transcript')
      }
      if (event.key.toLowerCase() === 'i') {
        setInspectorTab('ai')
      }
      if (event.key.toLowerCase() === 'g') {
        setInspectorTab('cast')
      }
      if (event.key.toLowerCase() === 'm') {
        setInspectorTab('context')
      }
      if (event.key.toLowerCase() === 'o') {
        setInspectorTab('ops')
      }
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => {
      window.removeEventListener('keydown', handleKeyDown)
    }
  }, [clips, handleStatusChange, selectedClip, selectClip, shareLink.permissions.canFlag])

  const handleRequestAlternate = useCallback(async (note: string) => {
    if (!selectedClip) {
      return
    }

    setAlternateMessage(null)

    const response = await fetch(`/api/clips/${selectedClip.id}/request-alternate`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Share-Token': token,
      },
      body: JSON.stringify({
        note,
        timecodeIn: currentTimecode,
        shareToken: token,
      }),
    })
    const payload = await response.json()

    if (!response.ok) {
      setAlternateMessage(payload.error ?? 'Failed to request alternate')
      return
    }

    if (payload.annotation) {
      setClips((previous) => previous.map((clip) => (
        clip.id === selectedClip.id
          ? { ...clip, annotations: mergeAnnotation(clip.annotations, payload.annotation as ReviewAnnotation) }
          : clip
      )))
    }

    setAlternateMessage('Alternate request sent.')
  }, [currentTimecode, selectedClip, token])

  const showRealtimeBanner = realtimeStatus != null && realtimeStatus !== 'SUBSCRIBED'

  return (
    <div className="relative flex h-screen flex-col overflow-hidden bg-zinc-950 text-zinc-100">
      <ReviewHeader
        projectName={shareLink.project.name}
        projectMode={shareLink.project.mode}
        token={token}
        shareLink={{
          scope: shareLink.scope,
          password_hash: shareLink.password_hash,
          expires_at: shareLink.expires_at,
          view_count: shareLink.view_count,
        }}
      />

      <div className="flex flex-1 flex-col overflow-hidden lg:flex-row">
        <aside className="w-full border-b border-zinc-800 bg-zinc-950 lg:w-80 lg:shrink-0 lg:border-b-0 lg:border-r">
          {shareLink.scope === 'assembly' && shareLink.scope_id ? (
            <div className="flex gap-2 border-b border-zinc-800 px-3 py-3">
              <button
                type="button"
                onClick={() => setActiveSidebarTab('clips')}
                className={cn(
                  'rounded-full px-3 py-1.5 text-sm transition-colors',
                  activeSidebarTab === 'clips'
                    ? 'bg-zinc-100 text-zinc-950'
                    : 'bg-zinc-900 text-zinc-400 hover:text-zinc-200'
                )}
              >
                Clips
              </button>
              <button
                type="button"
                onClick={() => setActiveSidebarTab('assembly')}
                className={cn(
                  'rounded-full px-3 py-1.5 text-sm transition-colors',
                  activeSidebarTab === 'assembly'
                    ? 'bg-zinc-100 text-zinc-950'
                    : 'bg-zinc-900 text-zinc-400 hover:text-zinc-200'
                )}
              >
                Assembly
              </button>
            </div>
          ) : null}

          <div className="max-h-[34vh] lg:max-h-none">
            {activeSidebarTab === 'assembly' && shareLink.scope === 'assembly' && shareLink.scope_id ? (
              <AssemblyPanel token={token} assemblyId={shareLink.scope_id} />
            ) : (
              <ClipList
                clips={clips}
                grouped={projectData.grouped}
                selectedClipId={selectedClipId}
                onSelectClip={selectClip}
                selectedClipIds={selectedClipIds}
                onSelectClipCheckbox={shareLink.permissions.canFlag ? handleSelectClipCheckbox : undefined}
              />
            )}
          </div>
          {shareLink.permissions.canFlag ? (
            <BatchStatusBar
              selectedCount={selectedClipIds.size}
              onStatusChange={handleBatchStatusChange}
              onClear={handleClearSelection}
              isLoading={isUpdatingStatus}
            />
          ) : null}
        </aside>

        {selectedClip ? (
          <div className="flex flex-1 flex-col overflow-hidden xl:flex-row">
            <main className="flex min-w-0 flex-1 flex-col overflow-y-auto p-4">
              {compareClip ? (
                <div className="grid gap-4 xl:grid-cols-2">
                  <div className="space-y-3">
                    <div className="flex items-center justify-between gap-3">
                      <div>
                        <p className="text-sm font-semibold text-zinc-100">{clipLabel(selectedClip)}</p>
                        <p className="text-xs text-zinc-500">Primary</p>
                      </div>
                      <StatusBadge status={selectedClip.reviewStatus} />
                    </div>
                    <VideoPlayer
                      clipId={selectedClip.id}
                      token={token}
                      fps={selectedClip.sourceFps}
                      onTimeUpdate={setCurrentTime}
                      seekTo={seekTo}
                      timecodeLabel={currentTimecode}
                      annotations={selectedClip.annotations}
                      onCreateSpatialAnnotation={shareLink.permissions.canComment
                        ? ((spatialData) => {
                            void handleAddAnnotation('text', '', null, spatialData)
                          })
                        : undefined}
                      onPlaybackEvent={handlePlaybackEvent}
                      showShortcutOverlay={showShortcutOverlay}
                      prefetchedStream={prefetchedStreams[selectedClip.id] ?? null}
                      watermarkSessionId={viewerIdRef.current}
                      playerId="primary"
                    />
                  </div>

                  <div className="space-y-3">
                    <div className="flex items-center justify-between gap-3">
                      <div>
                        <p className="text-sm font-semibold text-zinc-100">{clipLabel(compareClip)}</p>
                        <p className="text-xs text-zinc-500">Compare</p>
                      </div>
                      <StatusBadge status={compareClip.reviewStatus} />
                    </div>
                    <VideoPlayer
                      clipId={compareClip.id}
                      token={token}
                      fps={compareClip.sourceFps}
                      onTimeUpdate={() => {}}
                      seekTo={seekTo}
                      timecodeLabel={currentTimecode}
                      onPlaybackEvent={() => {}}
                      prefetchedStream={prefetchedStreams[compareClip.id] ?? null}
                      watermarkSessionId={viewerIdRef.current}
                      playerId="compare"
                      muted
                    />
                  </div>
                </div>
              ) : (
                <VideoPlayer
                  clipId={selectedClip.id}
                  token={token}
                  fps={selectedClip.sourceFps}
                  onTimeUpdate={setCurrentTime}
                  seekTo={seekTo}
                  timecodeLabel={currentTimecode}
                  annotations={selectedClip.annotations}
                  onCreateSpatialAnnotation={shareLink.permissions.canComment
                    ? ((spatialData) => {
                        void handleAddAnnotation('text', '', null, spatialData)
                      })
                    : undefined}
                  onPlaybackEvent={handlePlaybackEvent}
                  showShortcutOverlay={showShortcutOverlay}
                  prefetchedStream={prefetchedStreams[selectedClip.id] ?? null}
                  watermarkSessionId={viewerIdRef.current}
                  playerId="primary"
                />
              )}

              <div className="mt-4 flex items-center gap-3 rounded-2xl border border-zinc-800 bg-zinc-900/60 px-4 py-3">
                <span className="text-xs font-mono text-zinc-500">{currentTimecode}</span>
                <div className="flex flex-wrap items-center gap-2">
                  {quickActions.map((action) => (
                    <button
                      key={action}
                      type="button"
                      onClick={() => runQuickAction(action)}
                      title={
                        action === 'copy-link' ? 'Copy link at current time' :
                        action === 'notes-tab' ? 'Open Notes tab (N)' :
                        action === 'transcript-tab' ? 'Open Transcript tab (T)' :
                        action === 'toggle-shortcuts' ? 'Toggle shortcut legend' :
                        'Replay walkthrough (?)'
                      }
                      className="rounded-md border border-zinc-700 px-2 py-1 text-xs text-zinc-300 transition-colors hover:bg-zinc-800"
                    >
                      {action === 'copy-link' ? 'Copy link' :
                        action === 'notes-tab' ? 'Notes' :
                        action === 'transcript-tab' ? 'Transcript' :
                        action === 'toggle-shortcuts' ? (showShortcutOverlay ? 'Hide shortcuts' : 'Show shortcuts') :
                        'Walkthrough'}
                    </button>
                  ))}
                  <button
                    type="button"
                    onClick={() => setShowQuickActionsEditor(true)}
                    title="Customize quick actions"
                    className="rounded-md border border-zinc-700 px-2 py-1 text-xs text-zinc-300 transition-colors hover:bg-zinc-800"
                  >
                    Customize
                  </button>
                </div>
                <div className="flex-1" />
                <StatusBadge status={selectedClip.reviewStatus} />
              </div>
            </main>

            <aside className="w-full shrink-0 overflow-y-auto border-t border-zinc-800 bg-zinc-950/80 p-4 xl:w-[460px] xl:border-l xl:border-t-0">
              <div className="space-y-4">
                {showRealtimeBanner ? (
                  <div
                    className="rounded-xl border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-sm text-amber-100"
                    data-testid="realtime-banner"
                  >
                    Realtime connection is {realtimeStatus?.toLowerCase()}.
                  </div>
                ) : null}

                <ReviewPresenceBar viewers={activePresence} />

                <section className="rounded-xl border border-zinc-800 bg-zinc-950/70 px-3 py-2">
                  <div className="flex items-center justify-between gap-2">
                    <div className="text-xs text-zinc-400">
                      Watch party host:{' '}
                      <span className="font-medium text-zinc-200">
                        {watchPartyHostId === viewerIdRef.current
                          ? 'You'
                          : (watchPartyHostId ? 'Remote reviewer' : 'None')}
                      </span>
                    </div>
                    <div className="flex items-center gap-2">
                      <button
                        type="button"
                        onClick={() => setWatchPartyEnabled((v) => !v)}
                        title={watchPartyEnabled ? 'Disable host-follow mode' : 'Enable host-follow mode'}
                        className="rounded border border-zinc-700 px-2 py-1 text-xs text-zinc-200 hover:bg-zinc-900"
                      >
                        {watchPartyEnabled ? 'Following host' : 'Local playback'}
                      </button>
                      <button
                        type="button"
                        title="Broadcast your current playback as host"
                        onClick={() => {
                          const hostId = viewerIdRef.current
                          setWatchPartyHostId(hostId)
                          const video = primaryVideoElement()
                          const channel = activeChannelRef.current
                          if (video && channel) {
                            void channel.send({
                              type: 'broadcast',
                              event: 'watch_party_state',
                              payload: {
                                hostId,
                                viewerId: viewerIdRef.current,
                                kind: 'seek',
                                currentTime: video.currentTime,
                                isPlaying: !video.paused,
                                sentAt: new Date().toISOString(),
                              },
                            })
                          }
                        }}
                        className="rounded border border-zinc-700 px-2 py-1 text-xs text-zinc-200 hover:bg-zinc-900"
                      >
                        Take host
                      </button>
                    </div>
                  </div>
                </section>

                <section className="space-y-3 rounded-2xl border border-zinc-800 bg-zinc-950/70 p-4">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <p className="text-sm font-semibold text-zinc-100">{clipLabel(selectedClip)}</p>
                      <p className="text-xs text-zinc-500">
                        {formatDuration(selectedClip.duration)} · {selectedClip.sourceFps} fps
                      </p>
                    </div>
                    <StatusBadge status={selectedClip.reviewStatus} />
                  </div>

                  {shareLink.permissions.canFlag ? (
                    <StatusControls
                      currentStatus={selectedClip.reviewStatus}
                      disabled={isUpdatingStatus}
                      onChange={handleStatusChange}
                    />
                  ) : null}

                  {shareLink.permissions.canRequestAlternate ? (
                    <RequestAlternateButton
                      disabled={isPostingAnnotation}
                      onSubmit={handleRequestAlternate}
                    />
                  ) : null}

                  {compareClip ? (
                    <p className="text-xs text-zinc-500">
                      Compare mode is active with {clipLabel(compareClip)}. Use `J`, `K`, and `L` to drive the primary player.
                    </p>
                  ) : null}

                  {alternateMessage ? (
                    <p className="text-sm text-zinc-400">{alternateMessage}</p>
                  ) : null}
                </section>

                <div className="flex flex-wrap gap-2">
                  {([
                    ['notes', 'Notes'],
                    ['transcript', 'Transcript'],
                    ['ai', 'AI Scores'],
                    ['cast', 'Cast'],
                    ['context', 'Context'],
                    ['ops', 'Ops'],
                  ] as const).map(([value, label]) => (
                    <button
                      key={value}
                      type="button"
                      onClick={() => setInspectorTab(value)}
                      title={
                        value === 'notes' ? 'Notes (N)' :
                        value === 'transcript' ? 'Transcript (T)' :
                        value === 'ai' ? 'AI Scores (I)' :
                        value === 'cast' ? 'Cast (G)' :
                        value === 'context' ? 'Context (M)' :
                        'Ops (O)'
                      }
                      className={cn(
                        'rounded-full px-3 py-1.5 text-sm transition-colors',
                        inspectorTab === value
                          ? 'bg-zinc-100 text-zinc-950'
                          : 'bg-zinc-900 text-zinc-400 hover:text-zinc-200'
                      )}
                    >
                      {label}
                    </button>
                  ))}
                </div>

                {inspectorTab === 'notes' ? (
                  <div className="h-[480px]">
                    <AnnotationPanel
                      annotations={selectedClip.annotations}
                      currentTimecode={currentTimecode}
                      annotationSortFps={selectedClip.sourceFps}
                      permissions={{ canComment: shareLink.permissions.canComment }}
                      role={shareLink.role}
                      onAddAnnotation={handleAddAnnotation}
                      onReply={handleReply}
                      onToggleResolved={shareLink.role === 'editor' ? handleToggleResolved : undefined}
                      onSelectAnnotation={handleSelectAnnotation}
                      onSelectAnnotationId={setSelectedAnnotationId}
                      selectedAnnotationId={selectedAnnotationId}
                      isSubmitting={isPostingAnnotation}
                      errorMessage={annotationError}
                    />
                  </div>
                ) : null}

                {inspectorTab === 'transcript' ? (
                  <TranscriptPanel
                    transcriptText={selectedClip.transcriptText}
                    transcriptStatus={selectedClip.transcriptStatus}
                    segments={selectedClip.transcriptSegments}
                    speakerNameMap={selectedClipSpeakerNameMap}
                    scriptContext={selectedClip.scriptContext ?? null}
                    currentTimeSeconds={currentTime}
                    onSeek={handleSeek}
                  />
                ) : null}

                {inspectorTab === 'ai' ? (
                  <AIScoresPanel
                    scores={selectedClip.aiScores}
                    isLoading={selectedClip.proxyStatus === 'processing' || selectedClip.aiProcessingStatus === 'processing'}
                  />
                ) : null}

                {inspectorTab === 'context' ? (
                  <ClipContextPanel clip={selectedClip} />
                ) : null}

                {inspectorTab === 'cast' ? (
                  <CastCharactersPanel
                    clusters={selectedClipFaceClusters}
                    loading={Boolean(faceClustersLoadingByClipId[selectedClip.id])}
                    error={faceClusterErrorByClipId[selectedClip.id] ?? null}
                    onSave={handleSaveFaceCluster}
                  />
                ) : null}

                {inspectorTab === 'ops' ? (
                  <ReviewOpsPanel
                    clips={clips}
                    selectedClipId={selectedClip.id}
                    accessRole={shareLink.role}
                    expiresAt={shareLink.expires_at}
                    onSelectClip={selectClip}
                    onCompareClip={handleCompareClip}
                  />
                ) : null}
              </div>
            </aside>
          </div>
        ) : (
          <div className="flex flex-1 items-center justify-center text-sm text-zinc-500">
            Select a clip to begin review.
          </div>
        )}
      </div>
      {showWalkthrough ? (
        <div className="absolute inset-0 z-40 flex items-start justify-end bg-black/40 p-6">
          <div className="w-full max-w-sm rounded-2xl border border-zinc-700 bg-zinc-950 p-4 shadow-xl">
            <p className="text-xs uppercase tracking-[0.2em] text-zinc-500">Prototype walkthrough</p>
            <h3 className="mt-2 text-base font-semibold text-zinc-100">{walkthroughSteps[walkthroughStep]?.title}</h3>
            <p className="mt-2 text-sm text-zinc-300">{walkthroughSteps[walkthroughStep]?.body}</p>
            <p className="mt-2 text-xs text-zinc-500">Shortcut recap: J/K/L shuttle, Arrow keys clip nav, / focus search, ? replay tour.</p>
            <div className="mt-4 flex items-center justify-between gap-3">
              <button
                type="button"
                onClick={completeWalkthrough}
                className="rounded border border-zinc-700 px-3 py-1.5 text-xs text-zinc-300 hover:bg-zinc-900"
              >
                Skip
              </button>
              <div className="text-xs text-zinc-500">
                Step {walkthroughStep + 1} of {walkthroughSteps.length}
              </div>
              <button
                type="button"
                onClick={nextWalkthroughStep}
                className="rounded border border-zinc-700 bg-zinc-100 px-3 py-1.5 text-xs text-zinc-900 hover:bg-zinc-200"
              >
                {walkthroughStep + 1 >= walkthroughSteps.length ? 'Done' : 'Next'}
              </button>
            </div>
          </div>
        </div>
      ) : null}
      {showQuickActionsEditor ? (
        <div className="absolute inset-0 z-40 flex items-center justify-center bg-black/40 p-6">
          <div className="w-full max-w-lg rounded-xl border border-zinc-700 bg-zinc-950 p-4">
            <div className="flex items-center justify-between gap-3">
              <h3 className="text-sm font-semibold text-zinc-100">Customize Quick Actions</h3>
              <button
                type="button"
                onClick={() => setShowQuickActionsEditor(false)}
                className="rounded border border-zinc-700 px-2 py-1 text-xs text-zinc-300 hover:bg-zinc-900"
              >
                Close
              </button>
            </div>
            <div className="mt-3 space-y-2">
              {quickActions.map((action, index) => (
                <div key={`${action}-${index}`} className="flex items-center justify-between rounded border border-zinc-800 px-3 py-2">
                  <span className="text-sm text-zinc-200">
                    {action === 'copy-link' ? 'Copy link at time' :
                      action === 'notes-tab' ? 'Open Notes tab' :
                      action === 'transcript-tab' ? 'Open Transcript tab' :
                      action === 'toggle-shortcuts' ? 'Toggle shortcuts legend' :
                      'Replay walkthrough'}
                  </span>
                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      onClick={() => moveQuickAction(index, -1)}
                      className="rounded border border-zinc-700 px-2 py-1 text-xs text-zinc-300 hover:bg-zinc-900"
                      disabled={index === 0}
                    >
                      Up
                    </button>
                    <button
                      type="button"
                      onClick={() => moveQuickAction(index, 1)}
                      className="rounded border border-zinc-700 px-2 py-1 text-xs text-zinc-300 hover:bg-zinc-900"
                      disabled={index === quickActions.length - 1}
                    >
                      Down
                    </button>
                  </div>
                </div>
              ))}
            </div>
            <div className="mt-3">
              <button
                type="button"
                onClick={() => {
                  setQuickActions(DEFAULT_QUICK_ACTIONS)
                  storage.set(QUICK_ACTIONS_STORAGE_KEY, DEFAULT_QUICK_ACTIONS)
                }}
                className="rounded border border-zinc-700 px-3 py-1.5 text-xs text-zinc-300 hover:bg-zinc-900"
              >
                Reset Defaults
              </button>
            </div>
          </div>
        </div>
      ) : null}
      {showSearchPalette ? (
        <div className="absolute inset-0 z-50 flex items-start justify-center bg-black/50 p-6">
          <div className="w-full max-w-2xl rounded-xl border border-zinc-700 bg-zinc-950 p-3 shadow-xl">
            <div className="flex items-center gap-2">
              <input
                autoFocus
                type="text"
                value={searchQuery}
                onChange={(event) => setSearchQuery(event.target.value)}
                placeholder="Search dialogue, annotations, and tags…"
                className="w-full rounded border border-zinc-700 bg-zinc-900 px-3 py-2 text-sm text-zinc-100"
              />
              <button
                type="button"
                className="rounded border border-zinc-700 px-2 py-2 text-xs text-zinc-200 hover:bg-zinc-900"
                onClick={() => setShowSearchPalette(false)}
              >
                Close
              </button>
            </div>
            <div className="mt-3 max-h-[50vh] overflow-auto">
              {isSearching ? (
                <div className="px-2 py-4 text-sm text-zinc-500">Searching…</div>
              ) : searchResults.length === 0 ? (
                <div className="px-2 py-4 text-sm text-zinc-500">No results yet.</div>
              ) : (
                <div className="space-y-2">
                  {searchResults.map((result) => (
                    <button
                      key={result.id}
                      type="button"
                      className="w-full rounded border border-zinc-800 bg-zinc-900/60 px-3 py-2 text-left hover:border-zinc-700"
                      onClick={() => {
                        if (result.clipId) {
                          selectClip(result.clipId, {
                            seekSeconds: result.timeOffsetSeconds ?? 0,
                          })
                        }
                        setShowSearchPalette(false)
                      }}
                    >
                      <div className="flex items-center justify-between gap-3 text-xs text-zinc-500">
                        <span>{result.sourceType}</span>
                        <span>{typeof result.timeOffsetSeconds === 'number' ? `${result.timeOffsetSeconds.toFixed(2)}s` : ''}</span>
                      </div>
                      <p className="mt-1 line-clamp-2 text-sm text-zinc-100">{result.body}</p>
                    </button>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      ) : null}
    </div>
  )
}
