import { NextRequest, NextResponse } from 'next/server'
import { assertValidAlternateRequestNote, assertValidTimecodeIn } from '@/lib/review-input-validation'
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
  requireClipAccess,
  requireShareLinkAccess,
  resolveAnnotationTimeOffsetSeconds,
} from '@/lib/review-server'

export async function POST(
  request: NextRequest,
  { params }: { params: { clipId: string } }
) {
  try {
    const body = await request.json()
    const note = typeof body.note === 'string' ? body.note.trim() : ''
    const timecodeIn = typeof body.timecodeIn === 'string' ? body.timecodeIn : '00:00:00:00'
    const shareToken = request.headers.get('X-Share-Token') ?? body.shareToken

    if (!params.clipId) {
      return NextResponse.json({ error: 'Missing clip' }, { status: 400 })
    }
    if (!shareToken || typeof shareToken !== 'string') {
      return NextResponse.json({ error: 'Missing share token' }, { status: 401 })
    }

    const ip = getRequestClientIp(request)
    const alternateLimit = checkReviewRateLimit('alternate', rateLimitFingerprint(ip, shareToken))
    if (!alternateLimit.ok) {
      return rateLimitResponse(alternateLimit.retryAfterSeconds)
    }

    assertValidAlternateRequestNote(note)
    assertValidTimecodeIn(timecodeIn)

    const supabase = createServerSupabaseClient()
    const shareLink = await requireShareLinkAccess(supabase, shareToken, request)

    if (!shareLink.permissions.canRequestAlternate) {
      return NextResponse.json({ error: 'Alternate requests are not permitted for this share link' }, { status: 403 })
    }

    const clip = await requireClipAccess(supabase, params.clipId, shareLink)
    const { durationSeconds } = clipPlaybackBounds(clip)
    const timeOffsetSeconds = resolveAnnotationTimeOffsetSeconds(timecodeIn, clip)
    assertAnnotationTimeOffsetAllowed(timeOffsetSeconds, durationSeconds)

    const annotation = await createAnnotationRecord(supabase, {
      clipId: params.clipId,
      authorName: 'Reviewer',
      body: `REQUEST ALTERNATE: ${note}`,
      timecodeIn,
      timeOffsetSeconds,
      type: 'text',
    })

    await broadcastClipEvent(supabase, params.clipId, 'annotation_added', { annotation })

    return NextResponse.json({ annotation }, { status: 201 })
  } catch (error) {
    if (error instanceof ReviewRouteError) {
      return NextResponse.json({ error: error.message }, { status: error.status })
    }

    console.error('Alternate request error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
