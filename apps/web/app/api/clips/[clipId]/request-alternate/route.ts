import { NextRequest, NextResponse } from 'next/server'
import { createServerSupabaseClient } from '@/lib/supabase'
import {
  ReviewRouteError,
  broadcastClipEvent,
  createAnnotationRecord,
  requireClipAccess,
  requireShareLinkAccess,
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

    if (!params.clipId || !note) {
      return NextResponse.json({ error: 'Missing request note' }, { status: 400 })
    }
    if (!shareToken || typeof shareToken !== 'string') {
      return NextResponse.json({ error: 'Missing share token' }, { status: 401 })
    }

    const supabase = createServerSupabaseClient()
    const shareLink = await requireShareLinkAccess(supabase, shareToken, request)

    if (!shareLink.permissions.canRequestAlternate) {
      return NextResponse.json({ error: 'Alternate requests are not permitted for this share link' }, { status: 403 })
    }

    await requireClipAccess(supabase, params.clipId, shareLink)

    const annotation = await createAnnotationRecord(supabase, {
      clipId: params.clipId,
      authorName: 'Reviewer',
      body: `REQUEST ALTERNATE: ${note}`,
      timecodeIn,
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
