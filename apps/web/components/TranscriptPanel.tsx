'use client'

import React, { useCallback, useMemo, useState } from 'react'
import { Input } from '@/components/ui/input'
import type { ClipScriptContext, ReviewTranscriptSegment } from '@/lib/review-types'

interface TranscriptPanelProps {
  transcriptText: string | null
  transcriptStatus: 'pending' | 'processing' | 'ready' | 'error'
  segments: ReviewTranscriptSegment[]
  speakerNameMap?: Record<string, string>
  scriptContext?: ClipScriptContext | null
  currentTimeSeconds?: number
  onSeek: (seconds: number) => void
}

export function TranscriptPanel({
  transcriptText,
  transcriptStatus,
  segments,
  speakerNameMap = {},
  scriptContext,
  currentTimeSeconds = 0,
  onSeek,
}: TranscriptPanelProps) {
  const [query, setQuery] = useState('')
  const resolveSpeaker = useCallback((speaker: string | null): string | null => {
    if (!speaker) {
      return null
    }
    return speakerNameMap[speaker] ?? speakerNameMap[speaker.toLowerCase()] ?? speaker
  }, [speakerNameMap])

  const filteredSegments = useMemo(() => {
    if (!query.trim()) {
      return segments
    }

    const normalizedQuery = query.toLowerCase()
    return segments.filter((segment) =>
      segment.text.toLowerCase().includes(normalizedQuery) ||
      (resolveSpeaker(segment.speaker) ?? '').toLowerCase().includes(normalizedQuery)
    )
  }, [query, resolveSpeaker, segments])

  if (transcriptStatus === 'processing') {
    return (
      <div className="rounded-2xl border border-zinc-800 bg-zinc-950/70 p-4 text-sm text-zinc-400">
        Transcript is processing…
      </div>
    )
  }

  if (transcriptStatus === 'error') {
    return (
      <div className="rounded-2xl border border-zinc-800 bg-zinc-950/70 p-4 text-sm text-rose-300">
        Transcript is unavailable for this clip.
      </div>
    )
  }

  if (!transcriptText) {
    return (
      <div className="rounded-2xl border border-zinc-800 bg-zinc-950/70 p-4 text-sm text-zinc-500">
        No transcript yet.
      </div>
    )
  }

  return (
    <div className="rounded-2xl border border-zinc-800 bg-zinc-950/70">
      <div className="border-b border-zinc-800 px-4 py-3">
        <h3 className="text-xs font-semibold uppercase tracking-[0.22em] text-zinc-400">
          Transcript
        </h3>
        <Input
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Search transcript…"
          className="mt-3 border-zinc-800 bg-zinc-950 text-zinc-100 placeholder:text-zinc-600"
          data-testid="transcript-search"
        />
      </div>

      {scriptContext ? (
        <div className="border-b border-zinc-800 px-4 py-3">
          <h4 className="text-xs font-semibold uppercase tracking-[0.22em] text-zinc-400">
            Script-to-Screen
          </h4>
          <p className="mt-1 text-sm text-zinc-200">{scriptContext.sceneSlugline}</p>
          <p className="mt-1 text-xs text-zinc-500">
            Scene {scriptContext.sceneNumber} · confidence {(scriptContext.confidence * 100).toFixed(0)}%
          </p>
          {scriptContext.lineAnchors.length > 0 ? (
            <div className="mt-3 space-y-2">
              {scriptContext.lineAnchors.slice(0, 8).map((anchor) => {
                const isActive = currentTimeSeconds >= anchor.startSeconds && currentTimeSeconds <= anchor.endSeconds
                return (
                  <button
                    key={anchor.id}
                    type="button"
                    onClick={() => onSeek(anchor.startSeconds)}
                    className={`w-full rounded-md border px-3 py-2 text-left text-xs transition-colors ${
                      isActive
                        ? 'border-amber-400/70 bg-amber-400/10 text-amber-100'
                        : 'border-zinc-800 bg-zinc-900/50 text-zinc-300 hover:border-zinc-700'
                    }`}
                  >
                    <div className="flex items-center justify-between gap-3">
                      <span className="font-mono text-zinc-500">
                        {anchor.startSeconds.toFixed(2)}s
                      </span>
                      <span className="text-zinc-500">{anchor.endSeconds.toFixed(2)}s</span>
                    </div>
                    <p className="mt-1 line-clamp-2">{anchor.text}</p>
                  </button>
                )
              })}
            </div>
          ) : null}
        </div>
      ) : null}

      <div className="max-h-[320px] space-y-2 overflow-y-auto p-3">
        {filteredSegments.length > 0 ? (
          filteredSegments.map((segment) => {
            const resolvedSpeaker = resolveSpeaker(segment.speaker)
            return (
              <button
                key={segment.id}
                type="button"
                onClick={() => onSeek(segment.startSeconds)}
                className="w-full rounded-xl border border-zinc-800 bg-zinc-900/50 px-3 py-3 text-left transition-colors hover:border-zinc-700 hover:bg-zinc-900"
              >
                <div className="flex items-center justify-between gap-3">
                  <span className="text-xs font-mono text-zinc-500">{segment.startTimecode}</span>
                  {resolvedSpeaker ? (
                    <span className="text-xs text-zinc-400">{resolvedSpeaker}</span>
                  ) : null}
                </div>
                <p className="mt-2 text-sm text-zinc-300">{segment.text}</p>
              </button>
            )
          })
        ) : (
          <div className="rounded-xl border border-dashed border-zinc-800 px-4 py-8 text-center text-sm text-zinc-500">
            No transcript lines match your search.
          </div>
        )}
      </div>
    </div>
  )
}
