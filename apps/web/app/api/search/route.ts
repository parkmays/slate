import { NextRequest, NextResponse } from 'next/server'
import { createServerSupabaseClient } from '@/lib/supabase'
import { ReviewRouteError, requireShareLinkAccess } from '@/lib/review-server'

export async function GET(request: NextRequest) {
  try {
    const q = request.nextUrl.searchParams.get('q')?.trim() ?? ''
    const shareToken = request.headers.get('X-Share-Token') ?? request.nextUrl.searchParams.get('shareToken')
    if (!shareToken) {
      return NextResponse.json({ error: 'Missing share token' }, { status: 401 })
    }
    if (q.length < 2) {
      return NextResponse.json({ results: [] })
    }

    const supabase = createServerSupabaseClient()
    const shareLink = await requireShareLinkAccess(supabase, shareToken, request)

    const search = q.replace(/\s+/g, ' ').trim()
    const { data, error } = await supabase.rpc('search_review_documents_hybrid', {
      p_project_id: shareLink.project_id,
      p_query: search,
      p_limit: 20,
    })

    if (error) {
      throw new ReviewRouteError('Failed to run search', 500)
    }

    const results = (data ?? []).map((row: {
      id: string
      clip_id: string | null
      source_type: string
      source_id: string
      time_offset_seconds: number | null
      body: string
      metadata?: Record<string, unknown> | null
      score?: number | null
    }) => ({
      id: row.id,
      clipId: row.clip_id,
      sourceType: row.source_type,
      sourceId: row.source_id,
      timeOffsetSeconds: row.time_offset_seconds,
      body: row.body,
      metadata: row.metadata ?? {},
      score: row.score ?? null,
    }))

    return NextResponse.json({ results })
  } catch (error) {
    if (error instanceof ReviewRouteError) {
      return NextResponse.json({ error: error.message }, { status: error.status })
    }
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
