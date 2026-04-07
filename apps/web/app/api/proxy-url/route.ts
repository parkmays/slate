import { NextRequest, NextResponse } from 'next/server'
import { reviewAccessCookieName } from '@/lib/review-auth'
import { getRequestClientIp } from '@/lib/request-ip'
import {
  checkReviewRateLimit,
  rateLimitFingerprint,
  rateLimitResponse,
} from '@/lib/review-rate-limit'
import { createServerSupabaseClient } from '@/lib/supabase'
import {
  ReviewRouteError,
  requireClipAccess,
  requireShareLinkAccess,
} from '@/lib/review-server'

function edgeBaseUrl(): string | null {
  return process.env.NEXT_PUBLIC_SUPABASE_URL ?? process.env.SUPABASE_URL ?? null
}

function anonKey(): string | null {
  return process.env.SUPABASE_ANON_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? null
}

export async function POST(request: NextRequest) {
  try {
    const { clipId, watermarkSessionId } = await request.json()
    const shareToken = request.headers.get('X-Share-Token')
    const baseUrl = edgeBaseUrl()
    const bearer = anonKey()

    if (!clipId) {
      return NextResponse.json({ error: 'Missing clipId' }, { status: 400 })
    }
    if (!shareToken) {
      return NextResponse.json({ error: 'Missing share token' }, { status: 401 })
    }
    if (!baseUrl || !bearer) {
      return NextResponse.json(
        {
          error: 'Supabase environment is not configured. Use desktop local demo mode for prototype playback.',
          code: 'local_demo_only',
        },
        { status: 500 }
      )
    }

    const ip = getRequestClientIp(request)
    const proxyLimit = checkReviewRateLimit('proxy', rateLimitFingerprint(ip, shareToken))
    if (!proxyLimit.ok) {
      return rateLimitResponse(proxyLimit.retryAfterSeconds)
    }

    const supabase = createServerSupabaseClient()
    const shareLink = await requireShareLinkAccess(supabase, shareToken, request)
    await requireClipAccess(supabase, clipId, shareLink)
    const reviewAccess = request.cookies.get(reviewAccessCookieName(shareToken))?.value

    const response = await fetch(`${baseUrl}/functions/v1/sign-proxy-url`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Share-Token': shareToken,
        ...(reviewAccess ? { 'X-Review-Access': reviewAccess } : {}),
        Authorization: `Bearer ${bearer}`,
      },
      body: JSON.stringify({
        clipId,
        watermarkSessionId: typeof watermarkSessionId === 'string' && watermarkSessionId.trim().length > 0
          ? watermarkSessionId
          : crypto.randomUUID(),
      }),
      cache: 'no-store',
    })

    const raw = await response.text()
    let payload: Record<string, unknown> = {}
    if (raw) {
      try {
        payload = JSON.parse(raw) as Record<string, unknown>
      } catch {
        return NextResponse.json({ error: 'Invalid upstream response' }, { status: 502 })
      }
    }

    if (!response.ok) {
      return NextResponse.json(
        { error: typeof payload.error === 'string' ? payload.error : 'Failed to get proxy URL' },
        { status: response.status }
      )
    }

    return NextResponse.json(payload)
  } catch (error) {
    if (error instanceof ReviewRouteError) {
      return NextResponse.json({ error: error.message }, { status: error.status })
    }

    console.error('Proxy URL error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
