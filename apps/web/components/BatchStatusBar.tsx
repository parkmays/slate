'use client'

import React from 'react'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import type { ReviewStatus } from '@/lib/review-types'

const STATUS_ACTIONS: Array<{
  status: ReviewStatus
  label: string
  icon: string
}> = [
  { status: 'circled', label: 'Circle', icon: '✓' },
  { status: 'flagged', label: 'Flag', icon: '⚑' },
  { status: 'x', label: 'Reject', icon: '✕' },
  { status: 'deprioritized', label: 'Deprioritize', icon: '↓' },
]

interface BatchStatusBarProps {
  selectedCount: number
  onStatusChange: (status: ReviewStatus) => Promise<void> | void
  onClear: () => void
  isLoading?: boolean
}

export function BatchStatusBar({
  selectedCount,
  onStatusChange,
  onClear,
  isLoading = false,
}: BatchStatusBarProps) {
  if (selectedCount === 0) {
    return null
  }

  return (
    <div className="sticky bottom-0 left-0 right-0 border-t border-zinc-800 bg-zinc-900/95 backdrop-blur px-4 py-3">
      <div className="flex items-center justify-between gap-4 flex-wrap">
        <span className="text-sm text-zinc-300">
          {selectedCount} selected
        </span>

        <div className="flex items-center gap-2 flex-wrap">
          {STATUS_ACTIONS.map((action) => (
            <Button
              key={action.status}
              type="button"
              variant="outline"
              size="sm"
              disabled={isLoading}
              className="gap-2 border-zinc-700 bg-zinc-950 text-zinc-300 hover:bg-zinc-900"
              onClick={() => void onStatusChange(action.status)}
              data-testid={`batch-status-${action.status}`}
            >
              <span>{action.icon}</span>
              <span>{action.label}</span>
            </Button>
          ))}

          <Button
            type="button"
            variant="outline"
            size="sm"
            disabled={isLoading}
            className="gap-2 border-zinc-700 bg-zinc-950 text-zinc-300 hover:bg-zinc-900"
            onClick={onClear}
            data-testid="batch-clear-selection"
          >
            Clear
          </Button>
        </div>
      </div>
    </div>
  )
}
