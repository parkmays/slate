import { NextRequest, NextResponse } from 'next/server'
import { assertValidAnnotationTextBody, sanitizeReviewTextBody } from '@/lib/review-input-validation'
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
  createAnnotationReplyRecord,
  requireClipAccess,
  requireShareLinkAccess,
} from '@/lib/review-server'

export async function POST(
  request: NextRequest,
  { params }: { params: { annotationId: string } }
) {
  try {
    const body = await request.json()
    const replyBody = typeof body.body === 'string' ? body.body.trim() : ''
    const shareToken = request.headers.get('X-Share-Token') ?? body.shareToken

    if (!params.annotationId || !replyBody) {
      return NextResponse.json({ error: 'Missing reply payload' }, { status: 400 })
    }
    if (!shareToken || typeof shareToken !== 'string') {
      return NextResponse.json({ error: 'Missing share token' }, { status: 401 })
    }

    const ip = getRequestClientIp(request)
    const replyLimit = checkReviewRateLimit('reply', rateLimitFingerprint(ip, shareToken))
    if (!replyLimit.ok) {
      return rateLimitResponse(replyLimit.retryAfterSeconds)
    }

    assertValidAnnotationTextBody(sanitizeReviewTextBody(replyBody))

    const supabase = createServerSupabaseClient()
    const shareLink = await requireShareLinkAccess(supabase, shareToken, request)
    if (!shareLink.permissions.canComment) {
      return NextResponse.json({ error: 'Commenting is not permitted for this share link' }, { status: 403 })
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

    const reply = await createAnnotationReplyRecord(supabase, {
      annotationId: params.annotationId,
      authorName: 'Reviewer',
      body: sanitizeReviewTextBody(replyBody),
    })

    await broadcastClipEvent(supabase, annotationRow.clip_id, 'annotation_reply_added', {
      annotationId: params.annotationId,
      reply,
    })

    return NextResponse.json({ reply }, { status: 201 })
  } catch (error) {
    if (error instanceof ReviewRouteError) {
      return NextResponse.json({ error: error.message }, { status: error.status })
    }

    console.error('Annotation reply error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
