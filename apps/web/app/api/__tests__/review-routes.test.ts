/** @vitest-environment node */

import { beforeEach, describe, expect, it, vi } from 'vitest'
import { NextRequest } from 'next/server'
import { POST as annotationsPost } from '@/app/api/annotations/route'
import { POST as proxyUrlPost } from '@/app/api/proxy-url/route'
import { POST as clipStatusPost } from '@/app/api/clips/[clipId]/status/route'
import { POST as requestAlternatePost } from '@/app/api/clips/[clipId]/request-alternate/route'
import { GET as annotationsExportGet } from '@/app/api/review/[token]/annotations/export/route'
import { POST as unlockPost } from '@/app/api/review/[token]/unlock/route'
import { createServerSupabaseClient } from '@/lib/supabase'
import { reviewAccessCookieName, reviewAccessCookieValue } from '@/lib/review-auth'

vi.mock('@/lib/supabase', () => ({
  createServerSupabaseClient: vi.fn(),
}))

function makeRequest(
  pathname: string,
  method: 'POST' | 'PATCH',
  body: Record<string, unknown>,
  headers: Record<string, string> = {}
): NextRequest {
  return new NextRequest(`http://localhost${pathname}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...headers,
    },
    body: JSON.stringify(body),
  })
}

function createSupabaseMock(options?: {
  shareLink?: Record<string, unknown>
  clip?: Record<string, unknown>
}) {
  const clipUpdateEq = vi.fn().mockResolvedValue({ error: null })
  const clipUpdate = vi.fn(() => ({ eq: clipUpdateEq }))

  const annotationInsertSingle = vi.fn().mockResolvedValue({
    data: {
      id: 'annotation-1',
      author_id: 'share-token',
      author_name: 'Reviewer',
      timecode: '01:00:00:00',
      time_offset_seconds: 3600,
      content: 'Needs alt take.',
      type: 'text',
      timestamp: '2026-03-31T12:00:00.000Z',
    },
    error: null,
  })

  const channelSend = vi.fn().mockResolvedValue({ error: null })

  return {
    clipUpdate,
    clipUpdateEq,
    channelSend,
    channel: vi.fn(() => ({
      send: channelSend,
    })),
    storage: {
      from: vi.fn(() => ({
        createSignedUrl: vi.fn().mockResolvedValue({
          data: { signedUrl: 'https://cdn.example.com/export.fcpxml' },
          error: null,
        }),
      })),
    },
    from: vi.fn((table: string) => {
      if (table === 'share_links') {
        return {
          select: vi.fn(() => ({
            eq: vi.fn(() => ({
              single: vi.fn().mockResolvedValue({
                data: {
                  id: 'share-1',
                  project_id: 'project-1',
                  token: 'valid-share-token',
                  scope: 'project',
                  scope_id: null,
                  expires_at: '2099-01-01T00:00:00.000Z',
                  role: 'editor',
                  password_hash: null,
                  permissions: {
                    canComment: true,
                    canFlag: true,
                    canRequestAlternate: true,
                  },
                  ...(options?.shareLink ?? {}),
                },
                error: null,
              }),
            })),
          })),
        }
      }

      if (table === 'clips') {
        return {
          select: vi.fn(() => ({
            eq: vi.fn(() => ({
              eq: vi.fn(() => ({
                single: vi.fn().mockResolvedValue({
                  data: {
                    id: 'clip-1',
                    project_id: 'project-1',
                    duration_seconds: 100000,
                    frame_rate: 24,
                    hierarchy: {
                      narrative: {
                        sceneId: 'scene-1',
                      },
                    },
                    ...(options?.clip ?? {}),
                  },
                  error: null,
                }),
              })),
              single: vi.fn().mockResolvedValue({
                data: {
                  id: 'clip-1',
                  project_id: 'project-1',
                  duration_seconds: 100000,
                  frame_rate: 24,
                  hierarchy: {
                    narrative: {
                      sceneId: 'scene-1',
                    },
                  },
                  ...(options?.clip ?? {}),
                },
                error: null,
              }),
            })),
          })),
          update: clipUpdate,
        }
      }

      if (table === 'annotations') {
        return {
          insert: vi.fn(() => ({
            select: vi.fn(() => ({
              single: annotationInsertSingle,
            })),
          })),
        }
      }

      throw new Error(`Unexpected table: ${table}`)
    }),
  }
}

function createExportSupabaseMock() {
  return {
    from: vi.fn((table: string) => {
      if (table === 'share_links') {
        return {
          select: vi.fn(() => ({
            eq: vi.fn(() => ({
              single: vi.fn().mockResolvedValue({
                data: {
                  id: 'share-1',
                  project_id: 'project-1',
                  token: 'valid-share-token',
                  scope: 'scene',
                  scope_id: 'scene-1',
                  expires_at: '2099-01-01T00:00:00.000Z',
                  role: 'editor',
                  password_hash: 'unused-hash',
                  permissions: {
                    canComment: true,
                    canFlag: true,
                    canRequestAlternate: true,
                  },
                },
                error: null,
              }),
            })),
          })),
        }
      }

      if (table === 'clips') {
        return {
          select: vi.fn(() => ({
            eq: vi.fn().mockResolvedValue({
              data: [
                {
                  id: 'clip-1',
                  hierarchy: {
                    narrative: {
                      sceneId: 'scene-1',
                    },
                  },
                  review_status: 'unreviewed',
                },
                {
                  id: 'clip-2',
                  hierarchy: {
                    narrative: {
                      sceneId: 'scene-2',
                    },
                  },
                  review_status: 'unreviewed',
                },
              ],
              error: null,
            }),
          })),
        }
      }

      if (table === 'annotations') {
        return {
          select: vi.fn(() => ({
            in: vi.fn(() => ({
              order: vi.fn().mockResolvedValue({
                data: [
                  {
                    id: 'annotation-1',
                    clip_id: 'clip-1',
                    author_id: 'share-token',
                    author_name: 'Reviewer',
                    timecode: '01:00:00:00',
                    content: '<script>alert(1)</script>',
                    type: 'text',
                    timestamp: '2026-03-31T12:00:00.000Z',
                    created_at: '2026-03-31T12:00:00.000Z',
                    is_resolved: false,
                  },
                ],
                error: null,
              }),
            })),
          })),
        }
      }

      throw new Error(`Unexpected table: ${table}`)
    }),
  }
}

describe('review routes', () => {
  beforeEach(() => {
    vi.restoreAllMocks()
    process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://example.supabase.co'
    process.env.SUPABASE_URL = 'https://example.supabase.co'
    process.env.SUPABASE_ANON_KEY = 'anon-key'
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'anon-key'
    process.env.SUPABASE_SERVICE_ROLE_KEY = 'service-role-key'
  })

  it('rejects proxy URL requests without a share token', async () => {
    const response = await proxyUrlPost(makeRequest('/api/proxy-url', 'POST', { clipId: 'clip-1' }))

    expect(response.status).toBe(401)
    await expect(response.json()).resolves.toEqual({ error: 'Missing share token' })
  })

  it('forwards successful proxy signing payloads', async () => {
    const supabaseMock = createSupabaseMock()
    vi.mocked(createServerSupabaseClient).mockReturnValue(supabaseMock as never)

    const fetchSpy = vi
      .spyOn(global, 'fetch')
      .mockResolvedValue(
        new Response(JSON.stringify({
          signedUrl: 'https://cdn.example.com/proxy.m3u8',
          thumbnailUrl: 'https://cdn.example.com/proxy-thumb.jpg',
          expiresAt: '2099-01-01T00:00:00.000Z',
        }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      )

    const response = await proxyUrlPost(
      makeRequest(
        '/api/proxy-url',
        'POST',
        { clipId: 'clip-1' },
        { 'X-Share-Token': 'valid-share-token' }
      )
    )

    expect(fetchSpy).toHaveBeenCalledWith(
      'https://example.supabase.co/functions/v1/sign-proxy-url',
      expect.objectContaining({
        method: 'POST',
        headers: expect.objectContaining({
          'X-Share-Token': 'valid-share-token',
          Authorization: 'Bearer anon-key',
        }),
      })
    )
    expect(response.status).toBe(200)
  })

  it('rejects proxy signing for password-protected links without an access cookie', async () => {
    const supabaseMock = createSupabaseMock({
      shareLink: {
        password_hash: 'password-hash',
      },
    })
    vi.mocked(createServerSupabaseClient).mockReturnValue(supabaseMock as never)

    const response = await proxyUrlPost(
      makeRequest(
        '/api/proxy-url',
        'POST',
        { clipId: 'clip-1' },
        { 'X-Share-Token': 'valid-share-token' }
      )
    )

    expect(response.status).toBe(401)
    await expect(response.json()).resolves.toEqual({ error: 'Password required for this share link' })
  })

  it('creates annotations through the app route', async () => {
    const supabaseMock = createSupabaseMock()
    vi.mocked(createServerSupabaseClient).mockReturnValue(supabaseMock as never)

    const response = await annotationsPost(
      makeRequest(
        '/api/annotations',
        'POST',
        {
          clipId: 'clip-1',
          timecodeIn: '01:00:00:00',
          type: 'text',
          body: 'Needs alt take.',
          shareToken: 'valid-share-token',
        },
        { 'X-Share-Token': 'valid-share-token' }
      )
    )

    expect(response.status).toBe(201)
    await expect(response.json()).resolves.toEqual({
      annotation: {
        id: 'annotation-1',
        userId: 'share-token',
        userDisplayName: 'Reviewer',
        timecodeIn: '01:00:00:00',
        timeOffsetSeconds: 3600,
        timecodeOut: null,
        body: 'Needs alt take.',
        type: 'text',
        voiceUrl: null,
        spatialData: null,
        createdAt: '2026-03-31T12:00:00.000Z',
        resolvedAt: null,
        isResolved: false,
        mentions: [],
        replies: [],
      },
    })
  })

  it('rejects annotations when timecode is outside clip duration', async () => {
    const supabaseMock = createSupabaseMock({
      clip: {
        duration_seconds: 10,
        frame_rate: 24,
      },
    })
    vi.mocked(createServerSupabaseClient).mockReturnValue(supabaseMock as never)

    const response = await annotationsPost(
      makeRequest(
        '/api/annotations',
        'POST',
        {
          clipId: 'clip-1',
          timecodeIn: '00:01:00:00',
          type: 'text',
          body: 'Too late in the clip.',
          shareToken: 'valid-share-token',
        },
        { 'X-Share-Token': 'valid-share-token' }
      )
    )

    expect(response.status).toBe(400)
    await expect(response.json()).resolves.toMatchObject({
      error: 'Timecode is outside clip duration',
    })
  })

  it('rejects invalid review statuses before updating clips', async () => {
    const response = await clipStatusPost(
      makeRequest(
        '/api/clips/clip-1/status',
        'POST',
        { reviewStatus: 'approved', shareToken: 'valid-share-token' },
        { 'X-Share-Token': 'valid-share-token' }
      ),
      { params: { clipId: 'clip-1' } }
    )

    expect(response.status).toBe(400)
  })

  it('updates clip review status for a valid share link', async () => {
    const supabaseMock = createSupabaseMock()
    vi.mocked(createServerSupabaseClient).mockReturnValue(supabaseMock as never)

    const response = await clipStatusPost(
      makeRequest(
        '/api/clips/clip-1/status',
        'POST',
        { reviewStatus: 'circled', shareToken: 'valid-share-token' },
        { 'X-Share-Token': 'valid-share-token' }
      ),
      { params: { clipId: 'clip-1' } }
    )

    expect(supabaseMock.clipUpdate).toHaveBeenCalledWith(
      expect.objectContaining({
        review_status: 'circled',
      })
    )
    expect(response.status).toBe(200)
  })

  it('rejects status updates when the share link cannot flag clips', async () => {
    const supabaseMock = createSupabaseMock({
      shareLink: {
        role: 'commenter',
        permissions: {
          canComment: true,
          canFlag: false,
          canRequestAlternate: false,
        },
      },
    })
    vi.mocked(createServerSupabaseClient).mockReturnValue(supabaseMock as never)

    const response = await clipStatusPost(
      makeRequest(
        '/api/clips/clip-1/status',
        'POST',
        { reviewStatus: 'circled', shareToken: 'valid-share-token' },
        { 'X-Share-Token': 'valid-share-token' }
      ),
      { params: { clipId: 'clip-1' } }
    )

    expect(response.status).toBe(403)
  })

  it('creates alternate requests as text annotations', async () => {
    const supabaseMock = createSupabaseMock()
    vi.mocked(createServerSupabaseClient).mockReturnValue(supabaseMock as never)

    const response = await requestAlternatePost(
      makeRequest(
        '/api/clips/clip-1/request-alternate',
        'POST',
        {
          note: 'Need a cleaner alt.',
          timecodeIn: '01:00:10:00',
          shareToken: 'valid-share-token',
        },
        { 'X-Share-Token': 'valid-share-token' }
      ),
      { params: { clipId: 'clip-1' } }
    )

    expect(response.status).toBe(201)
    await expect(response.json()).resolves.toMatchObject({
      annotation: expect.objectContaining({
        type: 'text',
      }),
    })
  })

  it('rejects annotation writes for clips outside the scoped share link', async () => {
    const supabaseMock = createSupabaseMock({
      shareLink: {
        scope: 'scene',
        scope_id: 'scene-2',
      },
    })
    vi.mocked(createServerSupabaseClient).mockReturnValue(supabaseMock as never)

    const response = await annotationsPost(
      makeRequest(
        '/api/annotations',
        'POST',
        {
          clipId: 'clip-1',
          timecodeIn: '01:00:00:00',
          type: 'text',
          body: 'Out of scope',
          shareToken: 'valid-share-token',
        },
        { 'X-Share-Token': 'valid-share-token' }
      )
    )

    expect(response.status).toBe(404)
  })

  it('unlocks password-protected review links with an httpOnly cookie', async () => {
    const supabaseMock = createSupabaseMock({
      shareLink: {
        password_hash: '$2a$10$0IYdUkuvr/M0blEViWklLOaK3XMUajQiiGcqbp9fxvetkrGA6VUxW',
      },
    })
    vi.mocked(createServerSupabaseClient).mockReturnValue(supabaseMock as never)

    const response = await unlockPost(
      makeRequest(
        '/api/review/valid-share-token/unlock',
        'POST',
        { password: 'review123' }
      ),
      { params: { token: 'valid-share-token' } }
    )

    expect(response.status).toBe(200)
    expect(response.headers.get('set-cookie')).toContain('HttpOnly')
  })

  it('exports only scoped annotations and escapes html bodies', async () => {
    const supabaseMock = createExportSupabaseMock()
    vi.mocked(createServerSupabaseClient).mockReturnValue(supabaseMock as never)

    const response = await annotationsExportGet(
      new NextRequest('http://localhost/api/review/valid-share-token/annotations/export?format=html', {
        headers: {
          cookie: `${reviewAccessCookieName('valid-share-token')}=${reviewAccessCookieValue('valid-share-token', 'unused-hash')}`,
        },
      }),
      { params: { token: 'valid-share-token' } }
    )

    expect(response.status).toBe(200)
    const html = await response.text()
    expect(html).toContain('clip-1')
    expect(html).not.toContain('clip-2')
    expect(html).toContain('&lt;script&gt;alert(1)&lt;/script&gt;')
    expect(html).not.toContain('<script>alert(1)</script>')
  })
})
