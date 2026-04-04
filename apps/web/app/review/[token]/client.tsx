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
import { clipLabel } from '@/lib/review-insights'
import {
  type AnnotationType,
  type ReviewAnnotation,
  type ReviewAnnotationReply,
  type ReviewAssemblyData,
  type ReviewAssemblyVersionDiff,
  type ReviewClip,
  type ReviewPresenceUser,
  type ReviewProjectData,
  type ReviewShareLink,
  type ReviewStatus,
} from '@/lib/review-types'
import { secondsToTimecode, timecodeToSeconds } from '@/lib/timecode'
import { cn } from '@/lib/utils'

interface ReviewClientProps {
  shareLink: ReviewShareLink
  projectData: ReviewProjectData
  token: string
}

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

function primaryVideoElement(): HTMLVideoElement | null {
  return document.querySelector('video[data-review-player="primary"]')
}

function VideoPlayer({
  clipId,
  token,
  fps,
  onTimeUpdate,
  seekTo,
  playerId = 'primary',
  muted = false,
}: {
  clipId: string
  token: string
  fps: number
  onTimeUpdate: (time: number) => void
  seekTo?: number | null
  playerId?: 'primary' | 'compare'
  muted?: boolean
}) {
  const videoRef = useRef<HTMLVideoElement>(null)
  const hlsRef = useRef<{ destroy: () => void } | null>(null)
  const [signedUrl, setSignedUrl] = useState<string | null>(null)
  const [thumbnailUrl, setThumbnailUrl] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let isActive = true

    async function loadStream() {
      setLoading(true)
      setError(null)
      setSignedUrl(null)
      setThumbnailUrl(null)

      try {
        const response = await fetch('/api/proxy-url', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Share-Token': token,
          },
          body: JSON.stringify({ clipId }),
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
  }, [clipId, token])

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
        className="aspect-video w-full rounded-2xl"
        controls
        muted={muted}
        playsInline
        preload="metadata"
        poster={thumbnailUrl ?? undefined}
        onTimeUpdate={(event) => onTimeUpdate(event.currentTarget.currentTime)}
      />

      <div className="pointer-events-none absolute bottom-12 right-3 rounded bg-black/70 px-2 py-1 text-xs font-mono text-white">
        {secondsToTimecode(videoRef.current?.currentTime ?? 0, fps)}
      </div>
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

export default function ReviewClient({ shareLink, projectData, token }: ReviewClientProps) {
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
  const [inspectorTab, setInspectorTab] = useState<'notes' | 'transcript' | 'ai' | 'context' | 'ops'>('notes')
  const [realtimeStatus, setRealtimeStatus] = useState<string | null>(null)
  const [activeSidebarTab, setActiveSidebarTab] = useState<'clips' | 'assembly'>('clips')
  const [selectedClipIds, setSelectedClipIds] = useState<Set<string>>(new Set())
  const [presence, setPresence] = useState<Record<string, ReviewPresenceUser>>({})
  const viewerIdRef = useRef(`reviewer-${crypto.randomUUID()}`)
  const viewerNameRef = useRef(`Reviewer ${shareLink.token.slice(0, 4)}`)

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
      .subscribe((status) => {
        setRealtimeStatus(status)
      })

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
      void supabase.removeAllChannels()
    }
  }, [selectedClipId, supabase])

  const selectClip = useCallback((clipId: string) => {
    startTransition(() => {
      setSelectedClipId(clipId)
      setSelectedAnnotationId(null)
      setCurrentTime(0)
      setSeekTo(0)
      setAnnotationError(null)
      setAlternateMessage(null)
    })
  }, [])

  const handleSeek = useCallback((seconds: number) => {
    setCurrentTime(seconds)
    setSeekTo(seconds)
  }, [])

  const handleSelectAnnotation = useCallback((timecodeIn: string) => {
    if (!selectedClip) {
      return
    }

    handleSeek(timecodeToSeconds(timecodeIn, selectedClip.sourceFps))
  }, [handleSeek, selectedClip])

  const handleAddAnnotation = useCallback(async (type: AnnotationType, body: string, voiceUrl?: string | null) => {
    if (!selectedClip) {
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
      timecodeOut: null,
      body,
      type,
      voiceUrl: voiceUrl ?? null,
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
  }, [currentTimecode, selectedClip, token])

  const handleReply = useCallback(async (annotationId: string, body: string) => {
    if (!selectedClip) {
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
  }, [selectedClip, token])

  const handleToggleResolved = useCallback(async (annotationId: string, nextResolved: boolean) => {
    if (!selectedClip) {
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
  }, [selectedClip, token])

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
    <div className="flex h-screen flex-col overflow-hidden bg-zinc-950 text-zinc-100">
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
                  playerId="primary"
                />
              )}

              <div className="mt-4 flex items-center gap-3 rounded-2xl border border-zinc-800 bg-zinc-900/60 px-4 py-3">
                <span className="text-xs font-mono text-zinc-500">{currentTimecode}</span>
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
                    ['context', 'Context'],
                    ['ops', 'Ops'],
                  ] as const).map(([value, label]) => (
                    <button
                      key={value}
                      type="button"
                      onClick={() => setInspectorTab(value)}
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
                      permissions={{ canComment: shareLink.permissions.canComment }}
                      onAddAnnotation={handleAddAnnotation}
                      onReply={handleReply}
                      onToggleResolved={handleToggleResolved}
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

                {inspectorTab === 'ops' ? (
                  <ReviewOpsPanel
                    clips={clips}
                    selectedClipId={selectedClip.id}
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
    </div>
  )
}
