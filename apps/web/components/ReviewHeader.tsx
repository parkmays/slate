'use client'

import React, { useState } from 'react'
import { Button } from '@/components/ui/button'
import { 
  DropdownMenu, 
  DropdownMenuContent, 
  DropdownMenuItem, 
  DropdownMenuTrigger 
} from '@/components/ui/dropdown-menu'
import { Badge } from '@/components/ui/badge'
import { 
  MoreVertical, 
  Share2, 
  Download, 
  Info, 
  Lock,
  Unlock,
  Calendar,
  Eye
} from 'lucide-react'
import { format } from 'date-fns'

interface ReviewHeaderShareLink {
  scope: 'project' | 'scene' | 'subject' | 'assembly'
  password_hash: string | null
  expires_at: string
  view_count?: number
}

interface ReviewHeaderProps {
  projectName: string
  projectMode: 'narrative' | 'documentary'
  token: string
  shareLink: ReviewHeaderShareLink
}

export function ReviewHeader({ projectName, projectMode, token, shareLink }: ReviewHeaderProps) {
  const [copied, setCopied] = useState(false)
  const [infoOpen, setInfoOpen] = useState(false)
  
  const handleCopyLink = async () => {
    const url = window.location.href
    await navigator.clipboard.writeText(url)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  const handleExport = (format: 'csv' | 'json' | 'html') => {
    window.open(`/api/review/${token}/annotations/export?format=${format}`, '_blank')
  }
  
  const expiresAt = new Date(shareLink.expires_at)
  const isExpired = expiresAt < new Date()
  
  return (
    <header className="review-header relative">
      <div className="flex items-center gap-4">
        <div className="flex items-center gap-2">
          <h1 className="text-xl font-semibold">{projectName}</h1>
          <Badge variant="secondary" className="capitalize">
            {projectMode}
          </Badge>
          {shareLink.scope !== 'project' && (
            <Badge variant="outline" className="capitalize">
              {shareLink.scope}
            </Badge>
          )}
        </div>
        
        <div className="flex items-center gap-4 text-sm text-muted-foreground">
          <div className="flex items-center gap-1">
            {shareLink.password_hash ? (
              <Lock className="w-4 h-4" />
            ) : (
              <Unlock className="w-4 h-4" />
            )}
            <span>{shareLink.password_hash ? 'Protected' : 'Public'}</span>
          </div>
          
          <div className="flex items-center gap-1">
            <Calendar className="w-4 h-4" />
            <span>
              {isExpired ? 'Expired' : `Expires ${format(expiresAt, 'MMM d, yyyy')}`}
            </span>
          </div>
          
          <div className="flex items-center gap-1">
            <Eye className="w-4 h-4" />
            <span>{shareLink.view_count ?? 0} views</span>
          </div>
        </div>
      </div>
      
      <div className="flex items-center gap-2">
        <Button
          variant="outline"
          size="sm"
          onClick={handleCopyLink}
          className="gap-2"
        >
          <Share2 className="w-4 h-4" />
          {copied ? 'Copied!' : 'Copy Link'}
        </Button>
        
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="sm">
              <MoreVertical className="w-4 h-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onSelect={() => setInfoOpen((open) => !open)}>
              <Info className="w-4 h-4 mr-2" />
              Project Info
            </DropdownMenuItem>
            <DropdownMenuItem onSelect={() => handleExport('csv')}>
              <Download className="w-4 h-4 mr-2" />
              Export Annotations CSV
            </DropdownMenuItem>
            <DropdownMenuItem onSelect={() => handleExport('json')}>
              <Download className="w-4 h-4 mr-2" />
              Download JSON Package
            </DropdownMenuItem>
            <DropdownMenuItem onSelect={() => handleExport('html')}>
              <Download className="w-4 h-4 mr-2" />
              Print Review Summary
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>

      {infoOpen ? (
        <div className="absolute right-4 top-20 z-30 w-[320px] rounded-2xl border border-zinc-800 bg-zinc-950/95 p-4 shadow-xl">
          <div className="flex items-center justify-between gap-3">
            <div>
              <h2 className="text-sm font-semibold text-zinc-100">Project Info</h2>
              <p className="text-xs text-zinc-500">{projectName}</p>
            </div>
            <Button variant="ghost" size="sm" onClick={() => setInfoOpen(false)}>
              Close
            </Button>
          </div>
          <div className="mt-4 grid gap-3 text-sm">
            <div className="rounded-xl border border-zinc-800 bg-zinc-900/50 px-3 py-2">
              <div className="text-xs uppercase tracking-wide text-zinc-500">Scope</div>
              <div className="mt-1 text-zinc-200">{shareLink.scope}</div>
            </div>
            <div className="rounded-xl border border-zinc-800 bg-zinc-900/50 px-3 py-2">
              <div className="text-xs uppercase tracking-wide text-zinc-500">Protection</div>
              <div className="mt-1 text-zinc-200">{shareLink.password_hash ? 'Password protected' : 'Open link'}</div>
            </div>
            <div className="rounded-xl border border-zinc-800 bg-zinc-900/50 px-3 py-2">
              <div className="text-xs uppercase tracking-wide text-zinc-500">Expires</div>
              <div className="mt-1 text-zinc-200">{expiresAt.toLocaleString()}</div>
            </div>
            <div className="rounded-xl border border-zinc-800 bg-zinc-900/50 px-3 py-2">
              <div className="text-xs uppercase tracking-wide text-zinc-500">Link Analytics</div>
              <div className="mt-1 text-zinc-200">{shareLink.view_count ?? 0} tracked views</div>
            </div>
          </div>
        </div>
      ) : null}
    </header>
  )
}

export default ReviewHeader
