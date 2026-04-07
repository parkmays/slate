import { NextRequest, NextResponse } from 'next/server'
import { createServerSupabaseClient } from '@/lib/supabase'
import { ReviewRouteError, requireClipAccess, requireShareLinkAccess } from '@/lib/review-server'

export async function GET(
  request: NextRequest,
  { params }: { params: { clipId: string } }
) {
  try {
    const shareToken = request.headers.get('X-Share-Token') ?? request.nextUrl.searchParams.get('shareToken')
    if (!shareToken) {
      return NextResponse.json({ error: 'Missing share token' }, { status: 401 })
    }
    const supabase = createServerSupabaseClient()
    const shareLink = await requireShareLinkAccess(supabase, shareToken, request)
    await requireClipAccess(supabase, params.clipId, shareLink)

    const { data, error } = await supabase
      .from('face_clusters')
      .select('*')
      .eq('clip_id', params.clipId)
      .order('created_at', { ascending: true })

    if (error) {
      throw new ReviewRouteError('Failed to load face clusters', 500)
    }
    return NextResponse.json({ clusters: data ?? [] })
  } catch (error) {
    if (error instanceof ReviewRouteError) {
      return NextResponse.json({ error: error.message }, { status: error.status })
    }
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}

export async function POST(
  request: NextRequest,
  { params }: { params: { clipId: string } }
) {
  try {
    const body = await request.json()
    const shareToken = request.headers.get('X-Share-Token') ?? body.shareToken
    const clusterKey = typeof body.clusterKey === 'string' ? body.clusterKey.trim() : ''
    const displayName = typeof body.displayName === 'string' ? body.displayName.trim() : null
    const characterName = typeof body.characterName === 'string' ? body.characterName.trim() : null

    if (!shareToken || !clusterKey) {
      return NextResponse.json({ error: 'Missing share token or cluster key' }, { status: 400 })
    }

    const supabase = createServerSupabaseClient()
    const shareLink = await requireShareLinkAccess(supabase, shareToken, request)
    await requireClipAccess(supabase, params.clipId, shareLink)

    const now = new Date().toISOString()
    const { data, error } = await supabase
      .from('face_clusters')
      .upsert({
        clip_id: params.clipId,
        cluster_key: clusterKey,
        display_name: displayName,
        character_name: characterName,
        updated_at: now,
      }, {
        onConflict: 'clip_id,cluster_key',
      })
      .select('*')
      .single()

    if (error || !data) {
      throw new ReviewRouteError('Failed to save face cluster', 500)
    }
    return NextResponse.json({ cluster: data })
  } catch (error) {
    if (error instanceof ReviewRouteError) {
      return NextResponse.json({ error: error.message }, { status: error.status })
    }
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
