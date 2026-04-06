import { NextRequest, NextResponse } from 'next/server'
import { createServerSupabaseClient } from '@/lib/supabase'
import {
  ReviewRouteError,
  normalizeAnnotation,
  normalizeAnnotationReply,
  requireClipAccess,
  requireShareLinkAccess,
} from '@/lib/review-server'

export async function GET(
  request: NextRequest,
  { params }: { params: { clipId: string } }
) {
  try {
    const shareToken = request.headers.get('X-Share-Token') ?? request.nextUrl.searchParams.get('shareToken')

    if (!params.clipId) {
      return NextResponse.json({ error: 'Missing clipId' }, { status: 400 })
    }
    if (!shareToken) {
      return NextResponse.json({ error: 'Missing share token' }, { status: 401 })
    }

    const supabase = createServerSupabaseClient()
    const shareLink = await requireShareLinkAccess(supabase, shareToken, request)
    await requireClipAccess(supabase, params.clipId, shareLink)

    const { data: annotationRows, error: annotationError } = await supabase
      .from('annotations')
      .select('*')
      .eq('clip_id', params.clipId)
      .order('time_offset_seconds', { ascending: true, nullsFirst: false })
      .order('created_at', { ascending: true })

    if (annotationError) {
      return NextResponse.json({ error: 'Failed to fetch annotations' }, { status: 500 })
    }

    const annotationIds = (annotationRows ?? []).map((annotation) => annotation.id)
    const { data: replyRows } = annotationIds.length === 0
      ? { data: [] as any[] }
      : await supabase
          .from('annotation_replies')
          .select('*')
          .in('annotation_id', annotationIds)
          .order('created_at', { ascending: true })

    const repliesByAnnotation = (replyRows ?? []).reduce<Record<string, ReturnType<typeof normalizeAnnotationReply>[]>>((acc, row) => {
      const annotationId = row.annotation_id
      if (!acc[annotationId]) {
        acc[annotationId] = []
      }
      acc[annotationId].push(normalizeAnnotationReply(row))
      return acc
    }, {})

    return NextResponse.json(
      (annotationRows ?? []).map((row) => normalizeAnnotation({
        ...row,
        replies: repliesByAnnotation[row.id] ?? [],
      }))
    )
  } catch (error) {
    if (error instanceof ReviewRouteError) {
      return NextResponse.json({ error: error.message }, { status: error.status })
    }

    console.error('Annotations fetch error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
