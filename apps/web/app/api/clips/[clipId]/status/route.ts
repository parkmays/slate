import { NextRequest, NextResponse } from 'next/server'
import { createServerSupabaseClient } from '@/lib/supabase'
import {
  ReviewRouteError,
  broadcastClipEvent,
  isReviewStatus,
  requireClipAccess,
  requireShareLinkAccess,
} from '@/lib/review-server'

async function updateClipStatus(
  request: NextRequest,
  clipId: string
) {
  const body = await request.json()
  const reviewStatus = body.reviewStatus ?? body.status
  const shareToken = request.headers.get('X-Share-Token') ?? body.shareToken

  if (!clipId || !isReviewStatus(reviewStatus)) {
    return NextResponse.json({ error: 'Missing or invalid review status' }, { status: 400 })
  }
  if (!shareToken || typeof shareToken !== 'string') {
    return NextResponse.json({ error: 'Missing share token' }, { status: 401 })
  }

  const supabase = createServerSupabaseClient()
  const shareLink = await requireShareLinkAccess(supabase, shareToken, request)

  if (!shareLink.permissions.canFlag) {
    return NextResponse.json({ error: 'Status updates are not permitted for this share link' }, { status: 403 })
  }

  await requireClipAccess(supabase, clipId, shareLink)

  const updatedAt = new Date().toISOString()
  const { error } = await supabase
    .from('clips')
    .update({
      review_status: reviewStatus,
      updated_at: updatedAt,
    })
    .eq('id', clipId)

  if (error) {
    console.error('Clip status update error:', error)
    return NextResponse.json({ error: 'Failed to update clip status' }, { status: 500 })
  }

  await broadcastClipEvent(supabase, clipId, 'review_status_changed', {
    clipId,
    status: reviewStatus,
    updatedBy: shareToken,
    updatedAt,
  })

  return NextResponse.json({ clipId, status: reviewStatus, updatedAt })
}

export async function POST(
  request: NextRequest,
  { params }: { params: { clipId: string } }
) {
  try {
    return await updateClipStatus(request, params.clipId)
  } catch (error) {
    if (error instanceof ReviewRouteError) {
      return NextResponse.json({ error: error.message }, { status: error.status })
    }

    console.error('Clip status update error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}

export async function PATCH(
  request: NextRequest,
  { params }: { params: { clipId: string } }
) {
  return POST(request, { params })
}
