'use client'

import React from 'react'
import type { ReviewPresenceUser } from '@/lib/review-types'

interface ReviewPresenceBarProps {
  viewers: ReviewPresenceUser[]
}

function initials(name: string): string {
  return name
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? '')
    .join('')
}

export function ReviewPresenceBar({ viewers }: ReviewPresenceBarProps) {
  if (viewers.length === 0) {
    return null
  }

  return (
    <div className="rounded-2xl border border-zinc-800 bg-zinc-950/70 px-4 py-3">
      <div className="flex items-center justify-between gap-3">
        <span className="text-xs font-semibold uppercase tracking-[0.22em] text-zinc-400">
          Live Reviewers
        </span>
        <span className="text-xs text-zinc-500">{viewers.length} active</span>
      </div>

      <div className="mt-3 flex flex-wrap gap-2">
        {viewers.map((viewer) => (
          <div
            key={viewer.id}
            className="inline-flex items-center gap-2 rounded-full border border-zinc-800 bg-zinc-900/50 px-3 py-1.5"
          >
            <span className="inline-flex h-6 w-6 items-center justify-center rounded-full bg-sky-500/15 text-xs font-semibold text-sky-300">
              {initials(viewer.name)}
            </span>
            <span className="text-sm text-zinc-300">{viewer.name}</span>
          </div>
        ))}
      </div>
    </div>
  )
}
