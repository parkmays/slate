'use client'

import React from 'react'
import { cn } from '@/lib/utils'
import type { ReviewStatus } from '@/lib/review-types'

const STATUS_STYLES: Record<ReviewStatus, { label: string; className: string }> = {
  unreviewed: {
    label: 'Unreviewed',
    className: 'border-zinc-700 bg-zinc-900 text-zinc-400',
  },
  circled: {
    label: 'Circle',
    className: 'border-emerald-500/40 bg-emerald-500/10 text-emerald-300',
  },
  flagged: {
    label: 'Flag',
    className: 'border-amber-400/40 bg-amber-400/10 text-amber-300',
  },
  x: {
    label: 'Reject',
    className: 'border-rose-500/40 bg-rose-500/10 text-rose-300',
  },
  deprioritized: {
    label: 'Deprioritize',
    className: 'border-zinc-700 bg-zinc-900/80 text-zinc-500',
  },
}

export function StatusBadge({ status }: { status: ReviewStatus }) {
  const config = STATUS_STYLES[status]

  return (
    <span
      className={cn(
        'inline-flex rounded-full border px-2 py-1 text-[10px] font-medium uppercase tracking-wide',
        config.className
      )}
    >
      {config.label}
    </span>
  )
}
