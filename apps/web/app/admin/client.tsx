'use client'

import React, { useState, useCallback } from 'react'
import { cn } from '@/lib/utils'

interface ShareLink {
  id: string
  token: string
  scope: 'project' | 'scene' | 'subject' | 'assembly'
  scope_id: string | null
  created_at: string
  expires_at: string | null
  password_hash: string | null
  permissions?: Record<string, unknown> | null
  revoked_at?: string | null
  view_count?: number
}

type StatusFilter = 'all' | 'active' | 'expired' | 'revoked'

function isLinkRevoked(shareLink: ShareLink): boolean {
  return Boolean(shareLink.revoked_at && new Date(shareLink.revoked_at) < new Date())
}

function isLinkExpired(shareLink: ShareLink): boolean {
  if (!shareLink.expires_at) {
    return false
  }
  return !isLinkRevoked(shareLink) && new Date(shareLink.expires_at) < new Date()
}

function isLinkActive(shareLink: ShareLink): boolean {
  if (!shareLink.expires_at) {
    return !isLinkRevoked(shareLink)
  }
  return !isLinkRevoked(shareLink) && new Date(shareLink.expires_at) >= new Date()
}

function getLinkStatus(shareLink: ShareLink): 'Active' | 'Expired' | 'Revoked' {
  if (isLinkRevoked(shareLink)) return 'Revoked'
  if (isLinkExpired(shareLink)) return 'Expired'
  return 'Active'
}

function filterLinks(links: ShareLink[], status: StatusFilter): ShareLink[] {
  if (status === 'all') return links
  if (status === 'active') return links.filter(isLinkActive)
  if (status === 'expired') return links.filter(isLinkExpired)
  if (status === 'revoked') return links.filter(isLinkRevoked)
  return links
}

function formatDate(dateString: string | null): string {
  if (!dateString) {
    return 'Does not expire'
  }

  return new Date(dateString).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

export default function AdminClient({
  initialShareLinks,
}: {
  initialShareLinks: ShareLink[]
}) {
  const [shareLinks, setShareLinks] = useState<ShareLink[]>(initialShareLinks)
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all')
  const [revoking, setRevoking] = useState<Set<string>>(new Set())
  const [error, setError] = useState<string | null>(null)

  const filteredLinks = filterLinks(shareLinks, statusFilter)
  const totalViews = shareLinks.reduce((sum, link) => sum + (link.view_count ?? 0), 0)
  const activeCount = shareLinks.filter(isLinkActive).length
  const expiredCount = shareLinks.filter(isLinkExpired).length
  const revokedCount = shareLinks.filter(isLinkRevoked).length

  const handleRevoke = useCallback(async (token: string) => {
    if (!confirm('Are you sure you want to revoke this share link?')) {
      return
    }

    setRevoking((prev) => new Set(prev).add(token))
    setError(null)

    try {
      const response = await fetch(`/api/admin/share-links/${encodeURIComponent(token)}`, {
        method: 'DELETE',
        headers: {
          'Content-Type': 'application/json',
        },
      })

      if (!response.ok) {
        const data = await response.json()
        throw new Error(data.error ?? 'Failed to revoke share link')
      }

      setShareLinks((prev) =>
        prev.map((link) =>
          link.token === token
            ? { ...link, revoked_at: new Date().toISOString() }
            : link
        )
      )
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to revoke share link')
    } finally {
      setRevoking((prev) => {
        const next = new Set(prev)
        next.delete(token)
        return next
      })
    }
  }, [])

  const handleCopyLink = useCallback((token: string) => {
    const linkUrl = `${window.location.origin}/review/${token}`
    navigator.clipboard.writeText(linkUrl)
  }, [])

  const handleViewLink = useCallback((token: string) => {
    const linkUrl = `${window.location.origin}/review/${token}`
    window.open(linkUrl, '_blank')
  }, [])

  return (
    <div className="min-h-screen bg-zinc-950 text-zinc-100">
      <div className="border-b border-zinc-800">
        <div className="mx-auto max-w-7xl px-6 py-8">
          <h1 className="text-3xl font-semibold text-zinc-100">Share Link Management</h1>
          <p className="mt-2 text-sm text-zinc-400">
            View, manage, and revoke share links across your project.
          </p>
        </div>
      </div>

      <div className="mx-auto max-w-7xl px-6 py-8">
        {error && (
          <div className="mb-6 rounded-lg border border-rose-500/30 bg-rose-500/10 px-4 py-3 text-sm text-rose-200">
            {error}
          </div>
        )}

        <div className="mb-6 flex gap-2">
          {(['all', 'active', 'expired', 'revoked'] as const).map((status) => (
            <button
              key={status}
              onClick={() => setStatusFilter(status)}
              className={cn(
                'rounded-full px-4 py-2 text-sm font-medium transition-colors',
                statusFilter === status
                  ? 'bg-zinc-100 text-zinc-950'
                  : 'bg-zinc-900 text-zinc-400 hover:bg-zinc-800 hover:text-zinc-200'
              )}
            >
              {status.charAt(0).toUpperCase() + status.slice(1)}
            </button>
          ))}
        </div>

        <div className="mb-6 grid gap-3 md:grid-cols-4">
          {[
            ['Total Views', totalViews],
            ['Active Links', activeCount],
            ['Expired Links', expiredCount],
            ['Revoked Links', revokedCount],
          ].map(([label, value]) => (
            <div
              key={label}
              className="rounded-2xl border border-zinc-800 bg-zinc-900/40 px-4 py-4"
            >
              <div className="text-xs uppercase tracking-wide text-zinc-500">{label}</div>
              <div className="mt-2 text-2xl font-semibold text-zinc-100">{value}</div>
            </div>
          ))}
        </div>

        <div className="overflow-x-auto rounded-lg border border-zinc-800 bg-zinc-900/40">
          <table className="w-full">
            <thead>
              <tr className="border-b border-zinc-800 bg-zinc-900/80">
                <th className="px-6 py-3 text-left text-xs font-semibold uppercase tracking-wider text-zinc-400">
                  Token
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold uppercase tracking-wider text-zinc-400">
                  Scope
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold uppercase tracking-wider text-zinc-400">
                  Created
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold uppercase tracking-wider text-zinc-400">
                  Expires
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold uppercase tracking-wider text-zinc-400">
                  Password
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold uppercase tracking-wider text-zinc-400">
                  Uses
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold uppercase tracking-wider text-zinc-400">
                  Status
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold uppercase tracking-wider text-zinc-400">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {filteredLinks.length === 0 ? (
                <tr>
                  <td colSpan={8} className="px-6 py-8 text-center text-sm text-zinc-500">
                    No share links found.
                  </td>
                </tr>
              ) : (
                filteredLinks.map((link) => {
                  const status = getLinkStatus(link)
                  const statusColor =
                    status === 'Active'
                      ? 'text-green-400 bg-green-500/10'
                      : status === 'Expired'
                        ? 'text-amber-400 bg-amber-500/10'
                        : 'text-red-400 bg-red-500/10'

                  return (
                    <tr key={link.id} className="hover:bg-zinc-800/30">
                      <td className="px-6 py-4 font-mono text-sm text-zinc-300">
                        {link.token.slice(0, 8)}...
                      </td>
                      <td className="px-6 py-4 text-sm text-zinc-300">
                        {link.scope}
                      </td>
                      <td className="px-6 py-4 text-sm text-zinc-400">
                        {formatDate(link.created_at)}
                      </td>
                      <td className="px-6 py-4 text-sm text-zinc-400">
                        {formatDate(link.expires_at)}
                      </td>
                      <td className="px-6 py-4 text-center text-sm text-zinc-400">
                        {link.password_hash ? 'Yes' : 'No'}
                      </td>
                      <td className="px-6 py-4 text-sm text-zinc-300">
                        {link.view_count ?? 0}
                      </td>
                      <td className="px-6 py-4">
                        <span
                          className={cn(
                            'inline-flex items-center rounded-full px-3 py-1 text-xs font-medium',
                            statusColor
                          )}
                        >
                          {status}
                        </span>
                      </td>
                      <td className="px-6 py-4">
                        <div className="flex gap-2">
                          <button
                            onClick={() => handleCopyLink(link.token)}
                            className="rounded px-2.5 py-1.5 text-xs font-medium text-zinc-300 hover:bg-zinc-700 transition-colors"
                            title="Copy link"
                          >
                            Copy
                          </button>
                          <button
                            onClick={() => handleViewLink(link.token)}
                            className="rounded px-2.5 py-1.5 text-xs font-medium text-zinc-300 hover:bg-zinc-700 transition-colors"
                            title="View in new tab"
                          >
                            View
                          </button>
                          <button
                            onClick={() => handleRevoke(link.token)}
                            disabled={revoking.has(link.token) || status === 'Revoked'}
                            className={cn(
                              'rounded px-2.5 py-1.5 text-xs font-medium transition-colors',
                              revoking.has(link.token)
                                ? 'bg-zinc-700 text-zinc-500 cursor-not-allowed'
                                : status === 'Revoked'
                                  ? 'text-zinc-600 cursor-not-allowed'
                                  : 'text-rose-300 hover:bg-rose-500/20'
                            )}
                            title={status === 'Revoked' ? 'Already revoked' : 'Revoke link'}
                          >
                            {revoking.has(link.token) ? 'Revoking...' : 'Revoke'}
                          </button>
                        </div>
                      </td>
                    </tr>
                  )
                })
              )}
            </tbody>
          </table>
        </div>

        {filteredLinks.length > 0 && (
          <p className="mt-4 text-sm text-zinc-500">
            Showing {filteredLinks.length} of {shareLinks.length} share links
          </p>
        )}
      </div>
    </div>
  )
}
