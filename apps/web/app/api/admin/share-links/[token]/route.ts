import { NextRequest, NextResponse } from 'next/server'
import { cookies } from 'next/headers'
import { createServerSupabaseClient, getSupabaseUserForAccessToken } from '@/lib/supabase'

export async function DELETE(
  request: NextRequest,
  { params }: { params: { token: string } }
) {
  try {
    const cookieStore = cookies()
    const jwtCookie = cookieStore.get('slate-jwt')
    const bearerToken = request.headers.get('Authorization')?.replace(/^Bearer\s+/i, '') ?? null
    const user = await getSupabaseUserForAccessToken(jwtCookie?.value ?? bearerToken)

    if (!user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const token = decodeURIComponent(params.token)
    const supabase = createServerSupabaseClient()

    // Verify the authenticated user owns this share link before revoking it.
    const { data: shareLink, error: fetchError } = await supabase
      .from('share_links')
      .select('id, created_by')
      .eq('token', token)
      .single()

    if (fetchError || !shareLink) {
      return NextResponse.json({ error: 'Share link not found' }, { status: 404 })
    }

    if (shareLink.created_by !== user.id) {
      return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    }

    // Update the share_links table to set revoked_at
    // Note: The share_links table may not have a revoked_at column in the schema.
    // Migration needed: ALTER TABLE share_links ADD COLUMN revoked_at timestamptz;
    const { error } = await supabase
      .from('share_links')
      .update({ revoked_at: new Date().toISOString() })
      .eq('token', token)

    if (error) {
      console.error('Failed to revoke share link:', error)
      return NextResponse.json(
        { error: 'Failed to revoke share link' },
        { status: 500 }
      )
    }

    return NextResponse.json({ success: true })
  } catch (error) {
    console.error('Admin share link revoke error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
