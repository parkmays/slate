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

interface StatusControlsProps {
  currentStatus: ReviewStatus
  disabled?: boolean
  onChange: (status: ReviewStatus) => Promise<void> | void
}

export function StatusControls({
  currentStatus,
  disabled = false,
  onChange,
}: StatusControlsProps) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      {STATUS_ACTIONS.map((action) => {
        const selected = currentStatus === action.status

        return (
          <Button
            key={action.status}
            type="button"
            variant={selected ? 'default' : 'outline'}
            size="sm"
            data-testid={`review-status-${action.status}`}
            aria-pressed={selected}
            data-active={selected ? 'true' : 'false'}
            disabled={disabled}
            className={cn(
              'gap-2',
              !selected && 'border-zinc-700 bg-zinc-950 text-zinc-300 hover:bg-zinc-900'
            )}
            onClick={() => void onChange(action.status)}
          >
            <span>{action.icon}</span>
            <span>{action.label}</span>
          </Button>
        )
      })}
    </div>
  )
}
