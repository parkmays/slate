import { NextRequest, NextResponse } from 'next/server'
import { createServerSupabaseClient } from '@/lib/supabase'
import { ReviewRouteError, requireShareLinkAccess } from '@/lib/review-server'

function normalizeVersionClips(clips: unknown): Array<{ clipId: string; label: string; order: number }> {
  if (!Array.isArray(clips)) {
    return []
  }

  return clips
    .map((clip: any, index) => {
      const clipId = clip?.clipId ?? clip?.clip_id ?? (typeof clip === 'string' ? clip : null)
      if (!clipId) {
        return null
      }

      return {
        clipId,
        label: clip?.label ?? clip?.clipLabel ?? clip?.title ?? `Clip ${index + 1}`,
        order: Number(clip?.order ?? index + 1),
      }
    })
    .filter((clip): clip is { clipId: string; label: string; order: number } => clip !== null)
}

export async function GET(
  request: NextRequest,
  { params }: { params: { assemblyId: string } }
) {
  try {
    const shareToken = request.headers.get('X-Share-Token') ?? request.nextUrl.searchParams.get('shareToken')
    if (!shareToken) {
      return NextResponse.json({ error: 'Missing share token' }, { status: 401 })
    }

    const supabase = createServerSupabaseClient()
    const shareLink = await requireShareLinkAccess(supabase, shareToken, request)
    if (shareLink.scope !== 'assembly' || shareLink.scope_id !== params.assemblyId) {
      return NextResponse.json({ error: 'Assembly access is not permitted for this share link' }, { status: 403 })
    }

    const { data: versionRows, error } = await supabase
      .from('assembly_versions')
      .select('*')
      .eq('assembly_id', params.assemblyId)
      .order('created_at', { ascending: false })
      .limit(2)

    if (error || !versionRows || versionRows.length < 2) {
      return NextResponse.json({
        available: false,
        fromLabel: null,
        toLabel: null,
        added: [],
        removed: [],
        moved: [],
      })
    }

    const [latest, previous] = versionRows
    const latestClips = normalizeVersionClips(latest.clips)
    const previousClips = normalizeVersionClips(previous.clips)
    const previousMap = new Map(previousClips.map((clip) => [clip.clipId, clip]))
    const latestMap = new Map(latestClips.map((clip) => [clip.clipId, clip]))

    const added = latestClips
      .filter((clip) => !previousMap.has(clip.clipId))
      .map(({ clipId, label }) => ({ clipId, label }))
    const removed = previousClips
      .filter((clip) => !latestMap.has(clip.clipId))
      .map(({ clipId, label }) => ({ clipId, label }))
    const moved = latestClips
      .filter((clip) => previousMap.has(clip.clipId) && previousMap.get(clip.clipId)?.order !== clip.order)
      .map((clip) => ({
        clipId: clip.clipId,
        label: clip.label,
        from: previousMap.get(clip.clipId)?.order ?? clip.order,
        to: clip.order,
      }))

    return NextResponse.json({
      available: true,
      fromLabel: previous.version_label ?? previous.version ?? 'Previous',
      toLabel: latest.version_label ?? latest.version ?? 'Latest',
      added,
      removed,
      moved,
    })
  } catch (error) {
    if (error instanceof ReviewRouteError) {
      return NextResponse.json({ error: error.message }, { status: error.status })
    }

    console.error('Assembly diff error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
