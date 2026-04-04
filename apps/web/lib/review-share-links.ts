import { getMockReviewFixture } from '@/lib/review-mocks'
import { createServerSupabaseClient } from '@/lib/supabase'
import type { ReviewShareLink } from '@/lib/review-types'

export async function loadReviewShareLink(token: string): Promise<ReviewShareLink | null> {
  if (process.env.NEXT_PUBLIC_REVIEW_E2E_MODE === 'mock') {
    return getMockReviewFixture(token)?.shareLink ?? null
  }

  const supabase = createServerSupabaseClient()
  const { data, error } = await supabase
    .from('share_links')
    .select(`
      *,
      project:projects(id, name, mode)
    `)
    .eq('token', token)
    .single()

  if (error || !data) {
    return null
  }

  return data as ReviewShareLink
}
