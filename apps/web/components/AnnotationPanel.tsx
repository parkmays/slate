'use client'

import React, { Fragment, useEffect, useMemo, useRef, useState } from 'react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { ScrollArea } from '@/components/ui/scroll-area'
import { Textarea } from '@/components/ui/textarea'
import { timecodeToSeconds } from '@/lib/timecode'
import { cn, getAnnotationColor, getAnnotationIcon } from '@/lib/utils'
import type { Annotation, AnnotationType, SpatialAnnotationPayload } from '@/types'

interface AnnotationPanelProps {
  annotations: Annotation[]
  currentTimecode: string
  /** Used to sort notes by timeline position when `timeOffsetSeconds` is absent (legacy rows). */
  annotationSortFps?: number
  permissions: {
    canComment: boolean
  }
  role: 'viewer' | 'commenter' | 'editor'
  onAddAnnotation: (
    type: AnnotationType,
    body: string,
    voiceUrl?: string | null,
    spatialData?: SpatialAnnotationPayload | null
  ) => Promise<void> | void
  onReply?: (annotationId: string, body: string) => Promise<void> | void
  onToggleResolved?: (annotationId: string, nextResolved: boolean) => Promise<void> | void
  onSelectAnnotation: (timecodeIn: string) => void
  onSelectAnnotationId?: (annotationId: string) => void
  selectedAnnotationId?: string | null
  isSubmitting?: boolean
  errorMessage?: string | null
}

const annotationTypes: Array<AnnotationType | 'all'> = [
  'all',
  'text',
  'voice',
]

function renderMentionText(body: string): React.ReactNode {
  const segments = body.split(/(@[a-z0-9_.-]+)/gi)
  return segments.map((segment, index) => {
    if (/^@[a-z0-9_.-]+$/i.test(segment)) {
      return (
        <span
          key={`${segment}-${index}`}
          className="rounded bg-sky-500/10 px-1 py-0.5 text-sky-300"
        >
          {segment}
        </span>
      )
    }

    return <Fragment key={`text-${index}`}>{segment}</Fragment>
  })
}

export function AnnotationPanel({
  annotations,
  currentTimecode,
  annotationSortFps = 24,
  permissions,
  role,
  onAddAnnotation,
  onReply,
  onToggleResolved,
  onSelectAnnotation,
  onSelectAnnotationId,
  selectedAnnotationId = null,
  isSubmitting = false,
  errorMessage = null,
}: AnnotationPanelProps) {
  const [draft, setDraft] = useState('')
  const [filter, setFilter] = useState<AnnotationType | 'all'>('all')
  const [showMarkupOnly, setShowMarkupOnly] = useState(false)
  const [replyDrafts, setReplyDrafts] = useState<Record<string, string>>({})
  const [isRecording, setIsRecording] = useState(false)
  const [recordingTime, setRecordingTime] = useState(0)
  const [hasMediaRecorder, setHasMediaRecorder] = useState(true)
  const mediaRecorderRef = useRef<MediaRecorder | null>(null)
  const audioChunksRef = useRef<Blob[]>([])
  const recordingIntervalRef = useRef<number | null>(null)

  useEffect(() => {
    const isHttps = typeof window !== 'undefined' && window.location.protocol === 'https:'
    const supportsMediaRecorder = typeof window !== 'undefined' && 'MediaRecorder' in window
    setHasMediaRecorder(isHttps && supportsMediaRecorder)
  }, [])

  const filteredAnnotations = useMemo(() => {
    const byType = filter === 'all'
      ? annotations
      : annotations.filter((annotation) => annotation.type === filter)
    const visible = showMarkupOnly
      ? byType.filter((annotation) => annotation.spatialData != null)
      : byType

    const sortKey = (annotation: Annotation) => {
      if (typeof annotation.timeOffsetSeconds === 'number' && Number.isFinite(annotation.timeOffsetSeconds)) {
        return annotation.timeOffsetSeconds
      }
      return timecodeToSeconds(annotation.timecodeIn, annotationSortFps)
    }

    return [...visible].sort((left, right) => {
      const delta = sortKey(left) - sortKey(right)
      if (delta !== 0) {
        return delta
      }
      return left.timecodeIn.localeCompare(right.timecodeIn)
    })
  }, [annotations, annotationSortFps, filter, showMarkupOnly])

  async function handleSubmit() {
    const trimmed = draft.trim()
    if (!trimmed || !permissions.canComment || isSubmitting) {
      return
    }

    await onAddAnnotation('text', trimmed, null, null)
    setDraft('')
  }

  async function handleReply(annotationId: string) {
    const trimmed = replyDrafts[annotationId]?.trim() ?? ''
    if (!trimmed || !permissions.canComment || !onReply) {
      return
    }

    await onReply(annotationId, trimmed)
    setReplyDrafts((previous) => ({ ...previous, [annotationId]: '' }))
  }

  async function startRecording() {
    if (!hasMediaRecorder || isRecording) {
      return
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      const mediaRecorder = new MediaRecorder(stream)
      mediaRecorderRef.current = mediaRecorder
      audioChunksRef.current = []

      mediaRecorder.ondataavailable = (event) => {
        audioChunksRef.current.push(event.data)
      }

      mediaRecorder.start()
      setIsRecording(true)
      setRecordingTime(0)

      recordingIntervalRef.current = window.setInterval(() => {
        setRecordingTime((previous) => previous + 1)
      }, 1000)
    } catch (error) {
      console.error('Failed to start recording:', error)
    }
  }

  async function stopRecording() {
    if (!mediaRecorderRef.current || !isRecording) {
      return
    }

    return new Promise<void>((resolve) => {
      const mediaRecorder = mediaRecorderRef.current
      if (!mediaRecorder) {
        resolve()
        return
      }
      mediaRecorder.onstop = async () => {
        if (recordingIntervalRef.current) {
          clearInterval(recordingIntervalRef.current)
        }

        const audioBlob = new Blob(audioChunksRef.current, { type: 'audio/webm' })
        const reader = new FileReader()
        reader.onloadend = async () => {
          const voiceUrl = typeof reader.result === 'string' ? reader.result : null
          mediaRecorder.stream.getTracks().forEach((track) => track.stop())
          await onAddAnnotation('voice', 'Voice note', voiceUrl, null)
          setIsRecording(false)
          setRecordingTime(0)
          mediaRecorderRef.current = null
          resolve()
        }
        reader.readAsDataURL(audioBlob)
      }

      mediaRecorder.stop()
    })
  }

  function formatRecordingTime(seconds: number): string {
    const mins = Math.floor(seconds / 60)
    const secs = seconds % 60
    return `${mins}:${String(secs).padStart(2, '0')}`
  }

  return (
    <div className="flex h-full flex-col rounded-2xl border border-zinc-800 bg-zinc-950/70">
      <div className="border-b border-zinc-800 px-4 py-3">
        <div className="flex items-center justify-between">
          <h3 className="text-xs font-semibold uppercase tracking-[0.22em] text-zinc-400">
            Annotations
          </h3>
          <Badge variant="outline" className="border-zinc-700 text-zinc-400">
            {annotations.length}
          </Badge>
        </div>

        <div className="mt-3 flex flex-wrap gap-2">
          {annotationTypes.map((type) => (
            <Button
              key={type}
              type="button"
              variant={filter === type ? 'default' : 'outline'}
              size="sm"
              className="gap-1 capitalize"
              onClick={() => setFilter(type)}
            >
              {type === 'all' ? (
                <span>All</span>
              ) : (
                <>
                  <span>{getAnnotationIcon(type)}</span>
                  <span>{type}</span>
                </>
              )}
            </Button>
          ))}
          <Button
            type="button"
            variant={showMarkupOnly ? 'default' : 'outline'}
            size="sm"
            className="gap-1"
            onClick={() => setShowMarkupOnly((v) => !v)}
          >
            <span>✏️</span>
            <span>Markup</span>
          </Button>
        </div>

        {!permissions.canComment ? (
          <div className="mt-3 rounded-lg border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-xs text-amber-100">
            You are in View-Only mode. Access level: {role}.
          </div>
        ) : null}
      </div>

      <ScrollArea className="flex-1">
        <div className="space-y-2 p-3">
          {filteredAnnotations.length === 0 ? (
            <div className="rounded-xl border border-dashed border-zinc-800 px-4 py-8 text-center text-sm text-zinc-500">
              No annotations yet.
            </div>
          ) : (
            filteredAnnotations.map((annotation) => {
              const isSelected = selectedAnnotationId === annotation.id
              const replies = annotation.replies ?? []
              const isResolved = annotation.isResolved ?? Boolean(annotation.resolvedAt)

              return (
                <div
                  key={annotation.id}
                  className={cn(
                    'rounded-xl border bg-zinc-900/50 p-3 transition-colors',
                    isSelected
                      ? 'border-sky-500/60 bg-zinc-900'
                      : 'border-zinc-800 hover:border-zinc-700'
                  )}
                >
                  <button
                    type="button"
                    onClick={() => {
                      onSelectAnnotation(annotation.timecodeIn)
                      onSelectAnnotationId?.(annotation.id)
                    }}
                    className="w-full text-left"
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <div className="flex flex-wrap items-center gap-2 text-xs">
                          <span style={{ color: getAnnotationColor(annotation.type) }}>
                            {getAnnotationIcon(annotation.type)}
                          </span>
                          <span className="font-medium text-zinc-200">
                            {annotation.userDisplayName}
                          </span>
                          <Badge variant="outline" className="border-zinc-700 text-zinc-400">
                            {annotation.timecodeIn}
                          </Badge>
                          {isResolved ? (
                            <Badge variant="outline" className="border-emerald-500/40 text-emerald-300">
                              Resolved
                            </Badge>
                          ) : null}
                          {annotation.spatialData ? (
                            <Badge variant="outline" className="border-amber-500/40 text-amber-300">
                              Markup
                            </Badge>
                          ) : null}
                          {replies.length > 0 ? (
                            <Badge variant="outline" className="border-zinc-700 text-zinc-400">
                              {replies.length} repl{replies.length === 1 ? 'y' : 'ies'}
                            </Badge>
                          ) : null}
                        </div>
                        {annotation.type === 'voice' && annotation.voiceUrl ? (
                          <div className="mt-2">
                            <audio
                              controls
                              src={annotation.voiceUrl}
                              className="h-8 w-full"
                            />
                          </div>
                        ) : (
                          <p className="mt-2 text-sm leading-relaxed text-zinc-300">
                            {annotation.body.trim().length > 0
                              ? renderMentionText(annotation.body)
                              : (annotation.spatialData ? <span className="text-zinc-500">(drawing annotation)</span> : null)}
                          </p>
                        )}
                      </div>
                    </div>
                  </button>

                  {(replies.length > 0 || isSelected) && (
                    <div className="mt-3 space-y-2 border-t border-zinc-800/80 pt-3">
                      {replies.map((reply) => (
                        <div
                          key={reply.id}
                          className="rounded-lg border border-zinc-800 bg-zinc-950/60 px-3 py-2"
                        >
                          <div className="flex items-center justify-between gap-3 text-xs">
                            <span className="font-medium text-zinc-200">{reply.userDisplayName}</span>
                            <span className="text-zinc-500">
                              {new Date(reply.createdAt).toLocaleTimeString([], {
                                hour: '2-digit',
                                minute: '2-digit',
                              })}
                            </span>
                          </div>
                          <p className="mt-1 text-sm text-zinc-300">
                            {renderMentionText(reply.body)}
                          </p>
                        </div>
                      ))}

                      {permissions.canComment && isSelected ? (
                        <div className="space-y-2">
                          <Textarea
                            value={replyDrafts[annotation.id] ?? ''}
                            onChange={(event) => setReplyDrafts((previous) => ({
                              ...previous,
                              [annotation.id]: event.target.value,
                            }))}
                            placeholder="Reply or mention someone with @name"
                            rows={2}
                            className="resize-none border-zinc-800 bg-zinc-950 text-zinc-100 placeholder:text-zinc-600"
                          />
                          <div className="flex items-center justify-between gap-2">
                            {onToggleResolved ? (
                              <Button
                                type="button"
                                size="sm"
                                variant="outline"
                                onClick={() => void onToggleResolved(annotation.id, !isResolved)}
                              >
                                {isResolved ? 'Reopen' : 'Resolve'}
                              </Button>
                            ) : (
                              <span />
                            )}
                            {onReply ? (
                              <Button
                                type="button"
                                size="sm"
                                onClick={() => void handleReply(annotation.id)}
                                disabled={!(replyDrafts[annotation.id] ?? '').trim() || isSubmitting}
                              >
                                Reply
                              </Button>
                            ) : null}
                          </div>
                        </div>
                      ) : null}
                    </div>
                  )}
                </div>
              )
            })
          )}
        </div>
      </ScrollArea>

      {permissions.canComment && (
        <div className="border-t border-zinc-800 px-4 py-3">
          <Textarea
            value={draft}
            onChange={(event) => setDraft(event.target.value)}
            placeholder={`Add a text annotation at ${currentTimecode}...`}
            rows={4}
            data-testid="annotation-textarea"
            className={cn(
              'resize-none border-zinc-800 bg-zinc-950 text-zinc-100 placeholder:text-zinc-600',
              errorMessage && 'border-rose-500/50'
            )}
            title="Write a note and press Cmd/Ctrl+Enter to post"
            onKeyDown={(event) => {
              if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) {
                event.preventDefault()
                void handleSubmit()
              }
            }}
            disabled={isRecording}
          />

          {errorMessage && (
            <p className="mt-2 text-xs text-rose-400">{errorMessage}</p>
          )}

          <div className="mt-3 flex flex-wrap items-center justify-between gap-2">
            <span className="text-xs text-zinc-500">
              {currentTimecode} · Text annotation
              {isRecording ? (
                <span className="ml-2 inline-flex items-center gap-1">
                  <span className="inline-block h-2 w-2 animate-pulse rounded-full bg-rose-500" />
                  Recording… {formatRecordingTime(recordingTime)}
                </span>
              ) : null}
            </span>
            <div className="flex items-center gap-2">
              {hasMediaRecorder ? (
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => {
                    if (isRecording) {
                      void stopRecording()
                      return
                    }
                    void startRecording()
                  }}
                  disabled={isSubmitting}
                  className={cn(
                    'gap-2',
                    isRecording && 'border-rose-500 bg-rose-500/10 text-rose-300 hover:bg-rose-500/20'
                  )}
                  data-testid="voice-record-button"
                  title={isRecording ? 'Stop voice recording' : 'Start voice recording'}
                >
                  <span>{isRecording ? '⏹' : '🎤'}</span>
                  <span>{isRecording ? 'Stop' : 'Record'}</span>
                </Button>
              ) : (
                <Button
                  type="button"
                  variant="outline"
                  disabled
                  title="Voice notes require HTTPS"
                  className="gap-2 opacity-50"
                >
                  <span>🎤</span>
                  <span>Record</span>
                </Button>
              )}
              <Button
                type="button"
                onClick={() => void handleSubmit()}
                disabled={!draft.trim() || isSubmitting || isRecording}
                data-testid="post-annotation"
                title="Post annotation (Cmd/Ctrl+Enter)"
              >
                {isSubmitting ? 'Posting…' : 'Post annotation'}
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
