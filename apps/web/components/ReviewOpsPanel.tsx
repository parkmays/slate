'use client'

import React, { useMemo } from 'react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import {
  buildReviewOpsSummary,
  type ReviewPipelineCounts,
  type ReviewSyncCounts,
} from '@/lib/review-insights'
import type { ReviewClip } from '@/lib/review-types'

interface ReviewOpsPanelProps {
  clips: ReviewClip[]
  selectedClipId: string | null
  onSelectClip: (clipId: string) => void
  onCompareClip: (clipId: string) => void
}

function ProgressRow({
  label,
  counts,
}: {
  label: string
  counts: ReviewPipelineCounts
}) {
  const total = Math.max(1, counts.pending + counts.processing + counts.ready + counts.error)
  const segments = [
    { label: 'Ready', value: counts.ready, className: 'bg-emerald-400' },
    { label: 'Processing', value: counts.processing, className: 'bg-sky-400' },
    { label: 'Pending', value: counts.pending, className: 'bg-zinc-600' },
    { label: 'Error', value: counts.error, className: 'bg-rose-400' },
  ]

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between gap-3">
        <span className="text-sm font-medium text-zinc-200">{label}</span>
        <span className="text-xs text-zinc-500">
          {counts.ready}/{total} ready
        </span>
      </div>
      <div className="flex h-2 overflow-hidden rounded-full bg-zinc-900">
        {segments.map((segment) => (
          <div
            key={segment.label}
            className={cn('h-full transition-[width]', segment.className)}
            style={{ width: `${(segment.value / total) * 100}%` }}
            title={`${segment.label}: ${segment.value}`}
          />
        ))}
      </div>
      <div className="flex flex-wrap gap-2 text-[11px] text-zinc-500">
        <span>Ready {counts.ready}</span>
        <span>Processing {counts.processing}</span>
        <span>Pending {counts.pending}</span>
        <span>Error {counts.error}</span>
      </div>
    </div>
  )
}

function SyncRow({ counts }: { counts: ReviewSyncCounts }) {
  const total = Math.max(
    1,
    counts.high + counts.medium + counts.low + counts.manualRequired + counts.unsynced
  )

  const segments = [
    { label: 'High', value: counts.high, className: 'bg-emerald-400' },
    { label: 'Medium', value: counts.medium, className: 'bg-amber-300' },
    { label: 'Low', value: counts.low, className: 'bg-orange-400' },
    { label: 'Manual', value: counts.manualRequired, className: 'bg-rose-400' },
    { label: 'Unsynced', value: counts.unsynced, className: 'bg-zinc-600' },
  ]

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between gap-3">
        <span className="text-sm font-medium text-zinc-200">Sync Verification</span>
        <span className="text-xs text-zinc-500">
          {counts.high + counts.medium}/{total} verified
        </span>
      </div>
      <div className="flex h-2 overflow-hidden rounded-full bg-zinc-900">
        {segments.map((segment) => (
          <div
            key={segment.label}
            className={cn('h-full transition-[width]', segment.className)}
            style={{ width: `${(segment.value / total) * 100}%` }}
            title={`${segment.label}: ${segment.value}`}
          />
        ))}
      </div>
      <div className="flex flex-wrap gap-2 text-[11px] text-zinc-500">
        <span>High {counts.high}</span>
        <span>Medium {counts.medium}</span>
        <span>Low {counts.low}</span>
        <span>Manual {counts.manualRequired}</span>
        <span>Unsynced {counts.unsynced}</span>
      </div>
    </div>
  )
}

export function ReviewOpsPanel({
  clips,
  selectedClipId,
  onSelectClip,
  onCompareClip,
}: ReviewOpsPanelProps) {
  const summary = useMemo(() => buildReviewOpsSummary(clips), [clips])

  return (
    <div className="space-y-4 rounded-2xl border border-zinc-800 bg-zinc-950/70 p-4" data-testid="review-ops-panel">
      <div className="space-y-1">
        <h3 className="text-xs font-semibold uppercase tracking-[0.22em] text-zinc-400">
          Review Ops
        </h3>
        <p className="text-sm text-zinc-500">
          Smart selects, workflow pressure, and background pipeline health for the current review set.
        </p>
      </div>

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {[
          ['Ready To Assemble', summary.readyToAssembleCount, 'text-emerald-300'],
          ['Needs Follow-Up', summary.followUpCount, 'text-amber-300'],
          ['Circled', summary.circledCount, 'text-sky-300'],
          ['Open Notes', summary.unresolvedNotesCount, 'text-zinc-200'],
        ].map(([label, value, valueClass]) => (
          <div
            key={label}
            className="rounded-xl border border-zinc-800 bg-zinc-900/40 px-4 py-4"
          >
            <div className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">{label}</div>
            <div className={cn('mt-2 text-2xl font-semibold', valueClass)}>{value}</div>
          </div>
        ))}
      </div>

      <div className="grid gap-4 xl:grid-cols-[1.15fr_0.85fr]">
        <section className="space-y-4 rounded-2xl border border-zinc-800 bg-zinc-900/30 p-4">
          <div className="flex items-center justify-between gap-3">
            <div>
              <h4 className="text-sm font-semibold text-zinc-100">Smart Selects</h4>
              <p className="text-xs text-zinc-500">
                Ranked from current review status, AI signal, sync confidence, and open-note pressure.
              </p>
            </div>
            <Badge variant="outline" className="border-zinc-700 text-zinc-400">
              {summary.smartSelects.length}
            </Badge>
          </div>

          <div className="space-y-3">
            {summary.smartSelects.length > 0 ? (
              summary.smartSelects.map((clip) => (
                <div
                  key={clip.clipId}
                  className="rounded-xl border border-zinc-800 bg-zinc-950/70 px-3 py-3"
                >
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <p className="truncate text-sm font-medium text-zinc-100">{clip.label}</p>
                        <Badge variant="outline" className="border-zinc-700 text-zinc-400">
                          {clip.reviewStatus}
                        </Badge>
                      </div>
                      <p className="mt-1 text-xs text-zinc-500">{clip.summary}</p>
                      {clip.transcriptSnippet ? (
                        <p className="mt-2 text-sm text-zinc-300">
                          {clip.transcriptSnippet}
                        </p>
                      ) : null}
                    </div>
                    <div className="text-right">
                      <div className="text-xl font-semibold text-zinc-100">{clip.score}</div>
                      <div className="text-[11px] uppercase tracking-wide text-zinc-500">
                        select score
                      </div>
                    </div>
                  </div>

                  <div className="mt-3 flex flex-wrap items-center justify-between gap-2">
                    <span className="text-xs text-zinc-500">
                      {clip.unresolvedNotes === 0
                        ? 'No open notes'
                        : `${clip.unresolvedNotes} open note${clip.unresolvedNotes === 1 ? '' : 's'}`}
                    </span>
                    <div className="flex gap-2">
                      <Button
                        type="button"
                        size="sm"
                        variant="outline"
                        className="border-zinc-700 bg-zinc-950 text-zinc-200 hover:bg-zinc-900"
                        onClick={() => onSelectClip(clip.clipId)}
                      >
                        Open
                      </Button>
                      <Button
                        type="button"
                        size="sm"
                        variant="outline"
                        className="border-zinc-700 bg-zinc-950 text-zinc-200 hover:bg-zinc-900"
                        onClick={() => onCompareClip(clip.clipId)}
                        disabled={selectedClipId === clip.clipId}
                      >
                        Compare
                      </Button>
                    </div>
                  </div>
                </div>
              ))
            ) : (
              <div className="rounded-xl border border-dashed border-zinc-800 px-4 py-8 text-center text-sm text-zinc-500">
                Smart selects will appear once clips have enough review signal.
              </div>
            )}
          </div>
        </section>

        <section className="space-y-4 rounded-2xl border border-zinc-800 bg-zinc-900/30 p-4">
          <div>
            <h4 className="text-sm font-semibold text-zinc-100">Pipeline Health</h4>
            <p className="text-xs text-zinc-500">
              Track proxy, transcript, AI, and sync progress without leaving review.
            </p>
          </div>

          <ProgressRow label="Proxy" counts={summary.proxy} />
          <ProgressRow label="Transcript" counts={summary.transcript} />
          <ProgressRow label="AI" counts={summary.ai} />
          <SyncRow counts={summary.sync} />
        </section>
      </div>

      <div className="grid gap-4 xl:grid-cols-[0.95fr_1.05fr]">
        <section className="space-y-3 rounded-2xl border border-zinc-800 bg-zinc-900/30 p-4">
          <div className="flex items-center justify-between gap-3">
            <div>
              <h4 className="text-sm font-semibold text-zinc-100">Watchlist</h4>
              <p className="text-xs text-zinc-500">
                Clips that still need intervention before handoff.
              </p>
            </div>
            <Badge variant="outline" className="border-zinc-700 text-zinc-400">
              {summary.watchlist.length}
            </Badge>
          </div>

          <div className="space-y-3">
            {summary.watchlist.length > 0 ? (
              summary.watchlist.map((item) => (
                <button
                  key={item.clipId}
                  type="button"
                  onClick={() => onSelectClip(item.clipId)}
                  className="w-full rounded-xl border border-zinc-800 bg-zinc-950/70 px-3 py-3 text-left transition-colors hover:border-zinc-700 hover:bg-zinc-950"
                >
                  <div className="flex items-center justify-between gap-3">
                    <p className="text-sm font-medium text-zinc-100">{item.label}</p>
                    <Badge
                      variant="outline"
                      className={cn(
                        'capitalize',
                        item.severity === 'high'
                          ? 'border-rose-500/40 text-rose-300'
                          : item.severity === 'medium'
                            ? 'border-amber-500/40 text-amber-300'
                            : 'border-zinc-700 text-zinc-400'
                      )}
                    >
                      {item.severity}
                    </Badge>
                  </div>
                  <div className="mt-2 flex flex-wrap gap-2">
                    {item.issues.map((issue) => (
                      <span
                        key={issue}
                        className="rounded-full border border-zinc-800 px-2 py-1 text-[11px] text-zinc-400"
                      >
                        {issue}
                      </span>
                    ))}
                  </div>
                </button>
              ))
            ) : (
              <div className="rounded-xl border border-dashed border-zinc-800 px-4 py-8 text-center text-sm text-zinc-500">
                No active blockers in this review set.
              </div>
            )}
          </div>
        </section>

        <section className="space-y-3 rounded-2xl border border-zinc-800 bg-zinc-900/30 p-4">
          <div className="flex items-center justify-between gap-3">
            <div>
              <h4 className="text-sm font-semibold text-zinc-100">Recent Activity</h4>
              <p className="text-xs text-zinc-500">
                Notes, replies, and resolution events across the review room.
              </p>
            </div>
            <Badge variant="outline" className="border-zinc-700 text-zinc-400">
              {summary.recentActivity.length}
            </Badge>
          </div>

          <div className="space-y-3">
            {summary.recentActivity.length > 0 ? (
              summary.recentActivity.map((item) => (
                <button
                  key={item.id}
                  type="button"
                  onClick={() => onSelectClip(item.clipId)}
                  className="w-full rounded-xl border border-zinc-800 bg-zinc-950/70 px-3 py-3 text-left transition-colors hover:border-zinc-700 hover:bg-zinc-950"
                >
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <div className="flex flex-wrap items-center gap-2 text-xs">
                        <span className="font-medium text-zinc-200">{item.actor}</span>
                        <span className="text-zinc-500">on {item.clipLabel}</span>
                      </div>
                      <p className="mt-2 text-sm text-zinc-300">{item.summary}</p>
                    </div>
                    <div className="text-right text-[11px] text-zinc-500">
                      <div className="uppercase tracking-wide">{item.kind}</div>
                      <div className="mt-1">{new Date(item.occurredAt).toLocaleString()}</div>
                    </div>
                  </div>
                </button>
              ))
            ) : (
              <div className="rounded-xl border border-dashed border-zinc-800 px-4 py-8 text-center text-sm text-zinc-500">
                Activity will populate as reviewers leave notes.
              </div>
            )}
          </div>
        </section>
      </div>

      <div className="rounded-2xl border border-zinc-800 bg-zinc-900/30 p-4">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h4 className="text-sm font-semibold text-zinc-100">Keyboard Flow</h4>
            <p className="text-xs text-zinc-500">
              The review player now pairs with search and ops so you can stay in the keyboard loop.
            </p>
          </div>
          <Badge variant="outline" className="border-zinc-700 text-zinc-400">
            {summary.totalClips} clips
          </Badge>
        </div>
        <div className="mt-3 grid gap-2 text-sm text-zinc-300 sm:grid-cols-2">
          {[
            ['`/`', 'Focus clip search'],
            ['`J` `K` `L`', 'Scrub and play the primary viewer'],
            ['`Arrow Up/Down`', 'Move clip focus'],
            ['`N` `T` `I` `M` `O`', 'Switch notes, transcript, AI, context, and ops tabs'],
            ['`C` `F` `X` `D`', 'Set status when the link can flag'],
            ['`Batch select` + `Compare`', 'Open side-by-side playback'],
          ].map(([shortcut, description]) => (
            <div key={shortcut} className="rounded-xl border border-zinc-800 bg-zinc-950/50 px-3 py-2">
              <div className="font-medium text-zinc-100">{shortcut}</div>
              <div className="mt-1 text-xs text-zinc-500">{description}</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
