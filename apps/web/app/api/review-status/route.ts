import { NextRequest, NextResponse } from 'next/server'

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    const clipId = body.clipId

    if (!clipId || typeof clipId !== 'string') {
      return NextResponse.json({ error: 'Missing clipId' }, { status: 400 })
    }

    // Validate clipId is a UUID to prevent path traversal in the proxied URL
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    if (!uuidRegex.test(clipId)) {
      return NextResponse.json({ error: 'Invalid clipId format' }, { status: 400 })
    }

    const url = new URL(`/api/clips/${clipId}/status`, request.url)
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Share-Token': request.headers.get('X-Share-Token') ?? '',
      },
      body: JSON.stringify(body),
      cache: 'no-store',
    })

    const payload = await response.json()
    return NextResponse.json(payload, { status: response.status })
  } catch (error) {
    console.error('Review status proxy error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
