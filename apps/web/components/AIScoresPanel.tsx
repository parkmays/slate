'use client'

import React from 'react'
import { cn } from '@/lib/utils'
import type { ReviewAIScores } from '@/lib/review-types'

interface AIScoresPanelProps {
  scores: ReviewAIScores | null
  isLoading: boolean
}

function scoreBand(score: number): string {
  if (score >= 75) return 'bg-emerald-500'
  if (score >= 50) return 'bg-amber-400'
  return 'bg-rose-500'
}

function GaugeRow({
  label,
  value,
  prominent = false,
}: {
  label: string
  value: number
  prominent?: boolean
}) {
  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between gap-3">
        <span
          className={cn(
            'text-zinc-400',
            prominent ? 'text-sm font-semibold uppercase tracking-[0.2em]' : 'text-xs'
          )}
        >
          {label}
        </span>
        <span className={cn(prominent ? 'text-2xl font-semibold text-zinc-100' : 'text-sm text-zinc-200')}>
          {Math.round(value)}
        </span>
      </div>

      <div className={cn('overflow-hidden rounded-full bg-zinc-800', prominent ? 'h-3' : 'h-2')}>
        <div
          className={cn('h-full rounded-full transition-[width]', scoreBand(value))}
          style={{ width: `${value}%` }}
        />
      </div>
    </div>
  )
}

function SkeletonRow({ prominent = false }: { prominent?: boolean }) {
  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between gap-3">
        <div className={cn('animate-pulse rounded bg-zinc-800', prominent ? 'h-4 w-28' : 'h-3 w-20')} />
        <div className={cn('animate-pulse rounded bg-zinc-800', prominent ? 'h-8 w-12' : 'h-4 w-8')} />
      </div>
      <div className={cn('animate-pulse overflow-hidden rounded-full bg-zinc-800', prominent ? 'h-3' : 'h-2')}>
        <div className="h-full w-2/3 rounded-full bg-zinc-700" />
      </div>
    </div>
  )
}

export function AIScoresPanel({ scores, isLoading }: AIScoresPanelProps) {
  if (isLoading) {
    return (
      <div className="rounded-2xl border border-zinc-800 bg-zinc-950/70 p-4">
        <div className="space-y-4">
          <SkeletonRow prominent />
          <SkeletonRow />
          <SkeletonRow />
          <SkeletonRow />
          <SkeletonRow />
        </div>
      </div>
    )
  }

  if (!scores) {
    return (
      <div className="rounded-2xl border border-dashed border-zinc-800 bg-zinc-950/70 p-4">
        <p className="text-sm text-zinc-500">AI scores pending</p>
      </div>
    )
  }

  const dimensions = [
    { label: 'Focus', value: scores.focus },
    { label: 'Exposure', value: scores.exposure },
    { label: 'Stability', value: scores.stability },
    { label: 'Audio', value: scores.audio },
    ...(scores.performance != null ? [{ label: 'Performance', value: scores.performance }] : []),
    ...(scores.contentDensity != null ? [{ label: 'Content Density', value: scores.contentDensity }] : []),
  ]

  return (
    <div className="rounded-2xl border border-zinc-800 bg-zinc-950/70 p-4">
      <div className="space-y-4">
        <GaugeRow label="Composite" value={scores.composite} prominent />

        <div className="space-y-3" data-testid="ai-scores-panel">
          {dimensions.map((dimension) => (
            <GaugeRow
              key={dimension.label}
              label={dimension.label}
              value={dimension.value}
            />
          ))}
        </div>

        <p className="text-[11px] text-zinc-500">
          {scores.modelVersion} · {new Date(scores.scoredAt).toLocaleString()}
        </p>
      </div>
    </div>
  )
}
