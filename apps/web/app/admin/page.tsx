import { cookies } from 'next/headers'
import { redirect } from 'next/navigation'
import { createServerSupabaseClient, getSupabaseUserForAccessToken } from '@/lib/supabase'
import AdminClient from './client'

export default async function AdminPage() {
  const cookieStore = cookies()
  const jwtCookie = cookieStore.get('slate-jwt')

  const user = await getSupabaseUserForAccessToken(jwtCookie?.value)

  if (!user) {
    redirect('/?message=Please+authenticate+to+access+admin')
  }

  const supabase = createServerSupabaseClient()

  // Fetch share links from Supabase
  const { data: shareLinks, error } = await supabase
    .from('share_links')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(100)

  if (error) {
    console.error('Failed to load share links:', error)
  }

  return (
    <AdminClient
      initialShareLinks={shareLinks ?? []}
    />
  )
}
