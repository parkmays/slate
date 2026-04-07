'use client'

import React from 'react'
import { useDeferredValue, useEffect, useMemo, useState } from 'react'
import { Badge } from '@/components/ui/badge'
import { ScrollArea } from '@/components/ui/scroll-area'
import { StatusBadge } from '@/components/StatusBadge'
import { buildClipSearchMatch, clipLabel } from '@/lib/review-insights'
import { cn, formatDuration, storage } from '@/lib/utils'
import type { ReviewClip, ReviewStatus } from '@/lib/review-types'

interface ClipListProps {
  clips: ReviewClip[]
  grouped: Record<string, string[]>
  selectedClipId: string | null
  onSelectClip: (clipId: string) => void
  selectedClipIds?: Set<string>
  onSelectClipCheckbox?: (clipId: string, selected: boolean) => void
}

type QuickFilter = 'all' | 'needs-review' | 'flagged' | 'mine' | 'low-ai' | 'has-notes'

const SAVED_FILTER_KEY = 'slate-review-clip-filters'

export function ClipList({
  clips,
  grouped,
  selectedClipId,
  onSelectClip,
  selectedClipIds = new Set(),
  onSelectClipCheckbox,
}: ClipListProps) {
  const [searchQuery, setSearchQuery] = useState('')
  const [statusFilter, setStatusFilter] = useState<'all' | ReviewStatus>('all')
  const [quickFilter, setQuickFilter] = useState<QuickFilter>('all')
  const deferredSearchQuery = useDeferredValue(searchQuery)

  const clipsById = useMemo(
    () => new Map(clips.map((clip) => [clip.id, clip])),
    [clips]
  )

  const searchMatches = useMemo(() => {
    if (!deferredSearchQuery.trim()) {
      return new Map<string, ReturnType<typeof buildClipSearchMatch>>()
    }

    return new Map(
      clips.flatMap((clip) => {
        const match = buildClipSearchMatch(clip, deferredSearchQuery)
        return match ? [[clip.id, match] as const] : []
      })
    )
  }, [clips, deferredSearchQuery])

  useEffect(() => {
    const saved = storage.get(SAVED_FILTER_KEY) as {
      searchQuery?: string
      statusFilter?: 'all' | ReviewStatus
      quickFilter?: QuickFilter
    } | null
    if (!saved) return

    setSearchQuery(saved.searchQuery ?? '')
    setStatusFilter(saved.statusFilter ?? 'all')
    setQuickFilter(saved.quickFilter ?? 'all')
  }, [])

  // Filter clips by search query and status
  const filteredClips = useMemo(() => {
    return clips.filter((clip) => {
      if (quickFilter === 'needs-review' && clip.reviewStatus !== 'unreviewed') {
        return false
      }
      if (quickFilter === 'flagged' && clip.reviewStatus !== 'flagged') {
        return false
      }
      // 'mine' shows clips with any annotations. In the share-link context all annotations share
      // the same anonymous identity ('share-token'), so we can't distinguish between reviewers.
      // If per-reviewer tracking is needed, store a session ID via storage and tag annotations.
      if (quickFilter === 'mine' && clip.annotations.length === 0) {
        return false
      }
      if (quickFilter === 'low-ai' && (clip.aiScores?.composite ?? 101) > 60) {
        return false
      }
      if (quickFilter === 'has-notes' && clip.annotations.length === 0) {
        return false
      }

      // Status filter
      if (statusFilter !== 'all' && clip.reviewStatus !== statusFilter) {
        return false
      }

      // Search query filter
      if (deferredSearchQuery.trim()) {
        return searchMatches.has(clip.id)
      }

      return true
    })
  }, [clips, deferredSearchQuery, quickFilter, searchMatches, statusFilter])

  const sections = useMemo(() => {
    const groupedEntries = Object.entries(grouped).flatMap(([label, ids]) => {
      const groupClips = ids
        .map((id) => clipsById.get(id))
        .filter((clip): clip is ReviewClip => clip !== undefined && filteredClips.includes(clip))

      return groupClips.length > 0 ? [[label, groupClips] as const] : []
    })

    if (groupedEntries.length > 0) {
      return groupedEntries
    }

    return filteredClips.length > 0 ? [['Clips', filteredClips] as const] : []
  }, [filteredClips, clipsById, grouped])

  const totalFilteredCount = filteredClips.length
  const totalCount = clips.length
  const showCount = searchQuery.trim() || statusFilter !== 'all' || quickFilter !== 'all'

  function saveCurrentFilters() {
    storage.set(SAVED_FILTER_KEY, { searchQuery, statusFilter, quickFilter })
  }

  return (
    <div className="flex h-full flex-col">
      <div className="shrink-0 border-b border-zinc-800 space-y-3 p-3">
        <div className="flex flex-wrap gap-2">
          {([
            ['all', 'Inbox'],
            ['needs-review', 'Needs Review'],
            ['flagged', 'Flagged'],
            ['mine', 'My Notes'],
            ['low-ai', 'Low AI'],
            ['has-notes', 'Has Notes'],
          ] as const).map(([value, label]) => (
            <button
              key={value}
              type="button"
              onClick={() => setQuickFilter(value)}
              title={`Filter clips: ${label}`}
              className={cn(
                'rounded-full px-3 py-1.5 text-xs font-medium transition-colors',
                quickFilter === value
                  ? 'bg-zinc-100 text-zinc-950'
                  : 'bg-zinc-900 text-zinc-400 hover:bg-zinc-800 hover:text-zinc-200'
              )}
            >
              {label}
            </button>
          ))}
        </div>

        {/* Search input */}
        <input
          type="text"
          placeholder="Search clips, transcript, notes, metadata..."
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="w-full rounded-lg border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 placeholder:text-zinc-600 focus:border-zinc-700 focus:outline-none"
          data-testid="clip-search-input"
          title="Search clips (/)"
        />

        {/* Status filter dropdown */}
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value as 'all' | ReviewStatus)}
          className="w-full rounded-lg border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 focus:border-zinc-700 focus:outline-none"
          data-testid="clip-status-filter"
          title="Filter by review status"
        >
          <option value="all">All Statuses</option>
          <option value="circled">Circled</option>
          <option value="flagged">Flagged</option>
          <option value="x">Rejected</option>
          <option value="deprioritized">Deprioritized</option>
        </select>

        {/* Filter count */}
        {showCount && (
          <div className="flex items-center justify-between gap-3 text-xs text-zinc-500">
            <span>{totalFilteredCount} of {totalCount} clips shown</span>
            <button
              type="button"
              onClick={saveCurrentFilters}
              title="Save current filter preset locally"
              className="rounded-full border border-zinc-800 px-2.5 py-1 text-zinc-400 transition-colors hover:border-zinc-700 hover:text-zinc-200"
            >
              Save filter
            </button>
          </div>
        )}
      </div>

      <ScrollArea className="flex-1">
        <div className="space-y-4 p-3">
          {sections.length === 0 ? (
            <div className="rounded-xl border border-dashed border-zinc-800 px-4 py-8 text-center text-sm text-zinc-500">
              No clips match your filters.
            </div>
          ) : (
            sections.map(([label, sectionClips]) => (
              <section key={label} className="space-y-2">
                <div className="px-1 text-[10px] font-semibold uppercase tracking-[0.22em] text-zinc-500">
                  {label}
                </div>

                <div className="space-y-2">
                  {sectionClips.map((clip) => {
                    const isSelected = clip.id === selectedClipId
                    const isCheckboxSelected = selectedClipIds.has(clip.id)
                    const searchMatch = searchMatches.get(clip.id)

                    return (
                      <div
                        key={clip.id}
                        className="flex items-start gap-2"
                      >
                        {onSelectClipCheckbox && (
                          <input
                            type="checkbox"
                            checked={isCheckboxSelected}
                            onChange={(e) => onSelectClipCheckbox(clip.id, e.target.checked)}
                            data-testid={`clip-select-${clip.id}`}
                            className="mt-3 rounded border border-zinc-700 bg-zinc-950 text-blue-500 focus:ring-0"
                          />
                        )}
                        <button
                          type="button"
                          onClick={() => onSelectClip(clip.id)}
                          className={cn(
                            'flex-1 rounded-xl border px-3 py-3 text-left transition-colors',
                            isSelected
                              ? 'border-blue-500 bg-zinc-900 shadow-[0_0_0_1px_rgba(59,130,246,0.2)]'
                              : 'border-zinc-800 bg-zinc-950 hover:border-zinc-700 hover:bg-zinc-900/70'
                          )}
                        >
                          <div className="flex items-start justify-between gap-3">
                            <div className="min-w-0 space-y-1">
                              <div className="truncate text-sm font-medium text-zinc-100">
                                {clipLabel(clip)}
                              </div>
                              {deferredSearchQuery.trim() && searchMatch?.reasons.length ? (
                                <div className="mt-2 flex flex-wrap gap-1.5">
                                  {searchMatch.reasons.map((reason) => (
                                    <span
                                      key={`${clip.id}-${reason.kind}-${reason.label}`}
                                      className="rounded-full border border-zinc-800 bg-zinc-900/80 px-2 py-1 text-[11px] text-zinc-400"
                                    >
                                      {reason.label}
                                    </span>
                                  ))}
                                </div>
                              ) : null}
                              <div className="flex flex-wrap items-center gap-2 text-xs text-zinc-500">
                                <span>{formatDuration(clip.duration)}</span>
                                <span>{clip.sourceFps} fps</span>
                                <Badge variant="outline" className="border-zinc-700 text-zinc-400">
                                  {clip.annotations.length} notes
                                </Badge>
                              </div>
                            </div>

                            <StatusBadge status={clip.reviewStatus} />
                          </div>

                          {clip.aiScores && (
                            <div className="mt-3 flex items-center gap-2">
                              <span className="text-[10px] uppercase tracking-wide text-zinc-500">
                                AI
                              </span>
                              <div className="h-1.5 flex-1 rounded-full bg-zinc-800">
                                <div
                                  className={cn(
                                    'h-1.5 rounded-full',
                                    clip.aiScores.composite >= 75
                                      ? 'bg-emerald-500'
                                      : clip.aiScores.composite >= 50
                                        ? 'bg-amber-400'
                                        : 'bg-rose-500'
                                  )}
                                  style={{ width: `${clip.aiScores.composite}%` }}
                                />
                              </div>
                              <span className="text-xs font-medium text-zinc-300">
                                {Math.round(clip.aiScores.composite)}
                              </span>
                            </div>
                          )}
                        </button>
                      </div>
                    )
                  })}
                </div>
              </section>
            ))
          )}
        </div>
      </ScrollArea>
    </div>
  )
}
