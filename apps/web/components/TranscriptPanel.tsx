'use client'

import React, { useMemo, useState } from 'react'
import { Input } from '@/components/ui/input'
import type { ReviewTranscriptSegment } from '@/lib/review-types'

interface TranscriptPanelProps {
  transcriptText: string | null
  transcriptStatus: 'pending' | 'processing' | 'ready' | 'error'
  segments: ReviewTranscriptSegment[]
  onSeek: (seconds: number) => void
}

export function TranscriptPanel({
  transcriptText,
  transcriptStatus,
  segments,
  onSeek,
}: TranscriptPanelProps) {
  const [query, setQuery] = useState('')

  const filteredSegments = useMemo(() => {
    if (!query.trim()) {
      return segments
    }

    const normalizedQuery = query.toLowerCase()
    return segments.filter((segment) =>
      segment.text.toLowerCase().includes(normalizedQuery)
    )
  }, [query, segments])

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

      <div className="max-h-[320px] space-y-2 overflow-y-auto p-3">
        {filteredSegments.length > 0 ? (
          filteredSegments.map((segment) => (
            <button
              key={segment.id}
              type="button"
              onClick={() => onSeek(segment.startSeconds)}
              className="w-full rounded-xl border border-zinc-800 bg-zinc-900/50 px-3 py-3 text-left transition-colors hover:border-zinc-700 hover:bg-zinc-900"
            >
              <div className="flex items-center justify-between gap-3">
                <span className="text-xs font-mono text-zinc-500">{segment.startTimecode}</span>
                {segment.speaker ? (
                  <span className="text-xs text-zinc-400">{segment.speaker}</span>
                ) : null}
              </div>
              <p className="mt-2 text-sm text-zinc-300">{segment.text}</p>
            </button>
          ))
        ) : (
          <div className="rounded-xl border border-dashed border-zinc-800 px-4 py-8 text-center text-sm text-zinc-500">
            No transcript lines match your search.
          </div>
        )}
      </div>
    </div>
  )
}
