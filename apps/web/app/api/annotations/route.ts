import { NextRequest, NextResponse } from 'next/server'
import { createServerSupabaseClient } from '@/lib/supabase'
import {
  ReviewRouteError,
  broadcastClipEvent,
  createAnnotationRecord,
  isAnnotationType,
  requireClipAccess,
  requireShareLinkAccess,
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

    const supabase = createServerSupabaseClient()
    const shareLink = await requireShareLinkAccess(supabase, shareToken, request)
    if (!shareLink.permissions.canComment) {
      return NextResponse.json({ error: 'Commenting is not permitted for this share link' }, { status: 403 })
    }

    await requireClipAccess(supabase, clipId, shareLink)

    const annotation = await createAnnotationRecord(supabase, {
      clipId,
      authorName: 'Reviewer',
      body: annotationBody,
      timecodeIn,
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
