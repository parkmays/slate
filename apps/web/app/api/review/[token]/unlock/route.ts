import { compare } from 'bcryptjs'
import { NextRequest, NextResponse } from 'next/server'
import { reviewAccessCookieName, reviewAccessCookieValue } from '@/lib/review-auth'
import { getRequestClientIp } from '@/lib/request-ip'
import { checkReviewRateLimit, rateLimitResponse } from '@/lib/review-rate-limit'
import { isLinkRevoked } from '@/lib/review-server'
import { loadReviewShareLink } from '@/lib/review-share-links'

export async function POST(
  request: NextRequest,
  { params }: { params: { token: string } }
) {
  try {
    const body = await request.json()
    const password = typeof body.password === 'string' ? body.password : ''

    if (!params.token || !password) {
      return NextResponse.json({ error: 'Missing password' }, { status: 400 })
    }

    const ip = getRequestClientIp(request)
    const unlockLimit = checkReviewRateLimit('unlock', `${ip}:${params.token}`)
    if (!unlockLimit.ok) {
      return rateLimitResponse(unlockLimit.retryAfterSeconds)
    }

    const shareLink = await loadReviewShareLink(params.token)
    if (!shareLink) {
      return NextResponse.json({ error: 'Review link not found' }, { status: 404 })
    }

    if (isLinkRevoked(shareLink)) {
      return NextResponse.json({ error: 'This review link has been revoked' }, { status: 410 })
    }

    if (new Date(shareLink.expires_at) < new Date()) {
      return NextResponse.json({ error: 'This review link has expired' }, { status: 410 })
    }

    if (!shareLink.password_hash) {
      return NextResponse.json({ error: 'This review link is not password protected' }, { status: 400 })
    }

    const isValid = await compare(password, shareLink.password_hash)
    if (!isValid) {
      return NextResponse.json({ error: 'Invalid password' }, { status: 401 })
    }

    const response = NextResponse.json({ success: true })
    response.cookies.set({
      name: reviewAccessCookieName(params.token),
      value: reviewAccessCookieValue(params.token, shareLink.password_hash),
      httpOnly: true,
      sameSite: 'lax',
      secure: process.env.NODE_ENV === 'production',
      path: '/',
      expires: new Date(shareLink.expires_at),
    })

    return response
  } catch (error) {
    console.error('Review unlock error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
