import { NextRequest, NextResponse } from 'next/server'
import { createServerSupabaseClient } from '@/lib/supabase'
import { ReviewRouteError, loadAssemblyData, requireShareLinkAccess } from '@/lib/review-server'

export async function GET(
  request: NextRequest,
  { params }: { params: { assemblyId: string } }
) {
  try {
    const shareToken = request.headers.get('X-Share-Token') ?? request.nextUrl.searchParams.get('shareToken')
    if (!params.assemblyId) {
      return NextResponse.json({ error: 'Missing assemblyId' }, { status: 400 })
    }
    if (!shareToken) {
      return NextResponse.json({ error: 'Missing share token' }, { status: 401 })
    }

    const supabase = createServerSupabaseClient()
    const shareLink = await requireShareLinkAccess(supabase, shareToken, request)

    if (shareLink.scope !== 'assembly' || shareLink.scope_id !== params.assemblyId) {
      return NextResponse.json({ error: 'Assembly access is not permitted for this share link' }, { status: 403 })
    }

    const assembly = await loadAssemblyData(supabase, params.assemblyId)
    return NextResponse.json(assembly)
  } catch (error) {
    if (error instanceof ReviewRouteError) {
      return NextResponse.json({ error: error.message }, { status: error.status })
    }

    console.error('Assembly fetch error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
