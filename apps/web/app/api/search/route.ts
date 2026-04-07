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
    const { data, error } = await supabase
      .from('review_search_documents')
      .select('id, clip_id, source_type, source_id, time_offset_seconds, body, metadata')
      .eq('project_id', shareLink.project_id)
      .textSearch('body_tsv', search, { type: 'websearch', config: 'english' })
      .limit(20)

    if (error) {
      throw new ReviewRouteError('Failed to run search', 500)
    }

    const results = (data ?? []).map((row) => ({
      id: row.id,
      clipId: row.clip_id,
      sourceType: row.source_type,
      sourceId: row.source_id,
      timeOffsetSeconds: row.time_offset_seconds,
      body: row.body,
      metadata: row.metadata ?? {},
    }))

    return NextResponse.json({ results })
  } catch (error) {
    if (error instanceof ReviewRouteError) {
      return NextResponse.json({ error: error.message }, { status: error.status })
    }
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
