import { NextRequest, NextResponse } from 'next/server'
import { getRequestClientIp } from '@/lib/request-ip'
import {
  checkReviewRateLimit,
  rateLimitFingerprint,
  rateLimitResponse,
} from '@/lib/review-rate-limit'
import { createServerSupabaseClient } from '@/lib/supabase'
import {
  ReviewRouteError,
  broadcastClipEvent,
  requireClipAccess,
  requireShareLinkAccess,
  setAnnotationResolved,
} from '@/lib/review-server'

export async function POST(
  request: NextRequest,
  { params }: { params: { annotationId: string } }
) {
  try {
    const body = await request.json()
    const isResolved = body.isResolved !== false
    const shareToken = request.headers.get('X-Share-Token') ?? body.shareToken

    if (!params.annotationId) {
      return NextResponse.json({ error: 'Missing annotationId' }, { status: 400 })
    }
    if (!shareToken || typeof shareToken !== 'string') {
      return NextResponse.json({ error: 'Missing share token' }, { status: 401 })
    }

    const ip = getRequestClientIp(request)
    const resolveLimit = checkReviewRateLimit('resolve', rateLimitFingerprint(ip, shareToken))
    if (!resolveLimit.ok) {
      return rateLimitResponse(resolveLimit.retryAfterSeconds)
    }

    const supabase = createServerSupabaseClient()
    const shareLink = await requireShareLinkAccess(supabase, shareToken, request)
    if (shareLink.role !== 'editor') {
      return NextResponse.json({ error: 'Only editor links can resolve annotations' }, { status: 403 })
    }

    const { data: annotationRow, error: annotationError } = await supabase
      .from('annotations')
      .select('id, clip_id')
      .eq('id', params.annotationId)
      .single()

    if (annotationError || !annotationRow) {
      return NextResponse.json({ error: 'Annotation not found' }, { status: 404 })
    }

    await requireClipAccess(supabase, annotationRow.clip_id, shareLink)

    const annotation = await setAnnotationResolved(supabase, params.annotationId, isResolved)

    await broadcastClipEvent(supabase, annotationRow.clip_id, 'annotation_resolved', {
      annotationId: params.annotationId,
      resolvedAt: annotation.resolvedAt,
      resolvedBy: 'share-token',
      isResolved,
    })
    await broadcastClipEvent(supabase, annotationRow.clip_id, 'nle_marker_event', {
      eventId: crypto.randomUUID(),
      origin: 'web',
      action: 'resolve',
      clipId: annotationRow.clip_id,
      annotationId: params.annotationId,
      timecodeIn: null,
      timeOffsetSeconds: null,
      body: null,
      sentAt: new Date().toISOString(),
    })

    return NextResponse.json({ annotation })
  } catch (error) {
    if (error instanceof ReviewRouteError) {
      return NextResponse.json({ error: error.message }, { status: error.status })
    }

    console.error('Annotation resolve error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
