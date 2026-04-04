'use client'

import React from 'react'
import type { ReviewClip } from '@/lib/review-types'

interface ClipContextPanelProps {
  clip: ReviewClip
}

export function ClipContextPanel({ clip }: ClipContextPanelProps) {
  const metadataEntries = Object.entries(clip.metadata ?? {}).slice(0, 6)

  return (
    <div className="rounded-2xl border border-zinc-800 bg-zinc-950/70 p-4">
      <div className="space-y-1">
        <h3 className="text-xs font-semibold uppercase tracking-[0.22em] text-zinc-400">
          Clip Context
        </h3>
        <p className="text-sm text-zinc-500">
          Technical metadata, sync health, and AI reasoning for the active clip.
        </p>
      </div>

      <div className="mt-4 grid gap-3 text-sm sm:grid-cols-2">
        <div className="rounded-xl border border-zinc-800 bg-zinc-900/40 p-3">
          <div className="text-xs uppercase tracking-wide text-zinc-500">Source</div>
          <div className="mt-2 text-zinc-200">{clip.sourceTimecodeStart}</div>
          <div className="text-zinc-400">{clip.sourceFps} fps</div>
        </div>
        <div className="rounded-xl border border-zinc-800 bg-zinc-900/40 p-3">
          <div className="text-xs uppercase tracking-wide text-zinc-500">Sync</div>
          <div className="mt-2 text-zinc-200">
            {clip.syncResult?.confidence ?? 'unsynced'}
          </div>
          <div className="text-zinc-400">
            {clip.syncResult ? `${clip.syncResult.method} · ${clip.syncResult.offsetFrames}f offset` : 'No sync result'}
          </div>
        </div>
        <div className="rounded-xl border border-zinc-800 bg-zinc-900/40 p-3">
          <div className="text-xs uppercase tracking-wide text-zinc-500">Transcript</div>
          <div className="mt-2 text-zinc-200">{clip.transcriptStatus}</div>
          <div className="text-zinc-400">
            {clip.transcriptSegments.length} indexed segment{clip.transcriptSegments.length === 1 ? '' : 's'}
          </div>
        </div>
        <div className="rounded-xl border border-zinc-800 bg-zinc-900/40 p-3">
          <div className="text-xs uppercase tracking-wide text-zinc-500">AI Pipeline</div>
          <div className="mt-2 text-zinc-200">{clip.aiProcessingStatus}</div>
          <div className="text-zinc-400">
            {clip.aiScores?.modelVersion ?? 'Awaiting score'}
          </div>
        </div>
      </div>

      {clip.aiScores?.reasoning?.length ? (
        <div className="mt-4 space-y-2">
          <div className="text-xs uppercase tracking-wide text-zinc-500">AI Notes</div>
          {clip.aiScores.reasoning.map((reason, index) => (
            <div
              key={`${reason.dimension}-${index}`}
              className="rounded-xl border border-zinc-800 bg-zinc-900/30 px-3 py-2"
            >
              <div className="flex items-center justify-between gap-3 text-xs">
                <span className="font-medium uppercase tracking-wide text-zinc-300">{reason.dimension}</span>
                <span className="text-zinc-500">{reason.timecode ?? 'full clip'}</span>
              </div>
              <p className="mt-1 text-sm text-zinc-300">{reason.message}</p>
            </div>
          ))}
        </div>
      ) : null}

      {metadataEntries.length > 0 ? (
        <div className="mt-4 space-y-2">
          <div className="text-xs uppercase tracking-wide text-zinc-500">Metadata</div>
          <div className="grid gap-2 sm:grid-cols-2">
            {metadataEntries.map(([key, value]) => (
              <div
                key={key}
                className="rounded-xl border border-zinc-800 bg-zinc-900/30 px-3 py-2"
              >
                <div className="text-xs uppercase tracking-wide text-zinc-500">{key}</div>
                <div className="mt-1 text-sm text-zinc-300">
                  {typeof value === 'object' ? JSON.stringify(value) : String(value)}
                </div>
              </div>
            ))}
          </div>
        </div>
      ) : null}
    </div>
  )
}
