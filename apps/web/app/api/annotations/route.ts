import { NextRequest, NextResponse } from 'next/server'
import {
  assertValidAnnotationTextBody,
  assertValidTimecodeIn,
  assertValidVoicePayload,
  sanitizeReviewTextBody,
} from '@/lib/review-input-validation'
import { getRequestClientIp } from '@/lib/request-ip'
import {
  checkReviewRateLimit,
  rateLimitFingerprint,
  rateLimitResponse,
} from '@/lib/review-rate-limit'
import { createServerSupabaseClient } from '@/lib/supabase'
import {
  ReviewRouteError,
  assertAnnotationTimeOffsetAllowed,
  broadcastClipEvent,
  clipPlaybackBounds,
  createAnnotationRecord,
  isAnnotationType,
  requireClipAccess,
  requireShareLinkAccess,
  resolveAnnotationTimeOffsetSeconds,
} from '@/lib/review-server'

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    const clipId = typeof body.clipId === 'string' ? body.clipId : null
    const timecodeIn = typeof body.timecodeIn === 'string' ? body.timecodeIn : null
    const annotationType = body.type
    const annotationBody = typeof body.body === 'string' ? body.body.trim() : ''
    const voiceUrl = typeof body.voiceUrl === 'string' ? body.voiceUrl : null
    const shareToken = request.headers.get('X-Share-Token') ?? body.shareToken

    const isValidPayload = (
      Boolean(clipId) &&
      Boolean(timecodeIn) &&
      isAnnotationType(annotationType) &&
      (
        annotationType === 'voice'
          ? Boolean(voiceUrl)
          : Boolean(annotationBody)
      )
    )

    if (!isValidPayload) {
      return NextResponse.json({ error: 'Missing or invalid annotation payload' }, { status: 400 })
    }
    if (!shareToken || typeof shareToken !== 'string') {
      return NextResponse.json({ error: 'Missing share token' }, { status: 401 })
    }

    const ip = getRequestClientIp(request)
    const annotateLimit = checkReviewRateLimit('annotate', rateLimitFingerprint(ip, shareToken))
    if (!annotateLimit.ok) {
      return rateLimitResponse(annotateLimit.retryAfterSeconds)
    }

    assertValidTimecodeIn(timecodeIn!)

    const supabase = createServerSupabaseClient()
    const shareLink = await requireShareLinkAccess(supabase, shareToken, request)
    if (!shareLink.permissions.canComment) {
      return NextResponse.json({ error: 'Commenting is not permitted for this share link' }, { status: 403 })
    }

    const clip = await requireClipAccess(supabase, clipId, shareLink)
    const { durationSeconds } = clipPlaybackBounds(clip)
    const timeOffsetSeconds = resolveAnnotationTimeOffsetSeconds(timecodeIn, clip)
    assertAnnotationTimeOffsetAllowed(timeOffsetSeconds, durationSeconds)

    if (annotationType === 'voice') {
      assertValidVoicePayload(voiceUrl!)
    } else {
      assertValidAnnotationTextBody(sanitizeReviewTextBody(annotationBody))
    }

    const annotation = await createAnnotationRecord(supabase, {
      clipId,
      authorName: 'Reviewer',
      body: annotationType === 'voice' ? '' : sanitizeReviewTextBody(annotationBody),
      timecodeIn,
      timeOffsetSeconds,
      type: annotationType,
      voiceUrl,
    })

    await broadcastClipEvent(supabase, clipId, 'annotation_added', { annotation })

    return NextResponse.json({ annotation }, { status: 201 })
  } catch (error) {
    if (error instanceof ReviewRouteError) {
      return NextResponse.json({ error: error.message }, { status: error.status })
    }

    console.error('Annotation creation error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
