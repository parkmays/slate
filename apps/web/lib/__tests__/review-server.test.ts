import { describe, expect, it } from 'vitest'
import { reviewAccessCookieValue } from '@/lib/review-auth'
import { clipMatchesShareScope, requireShareLinkAccess } from '@/lib/review-server'

describe('clipMatchesShareScope', () => {
  it('matches scene-scoped links against narrative hierarchy identifiers', () => {
    expect(
      clipMatchesShareScope(
        {
          id: 'clip-1',
          hierarchy: {
            narrative: {
              sceneId: 'scene-1',
              sceneNumber: '12',
            },
          },
        },
        {
          scope: 'scene',
          scope_id: 'scene-1',
        }
      )
    ).toBe(true)
  })

  it('matches subject-scoped links against documentary hierarchy identifiers', () => {
    expect(
      clipMatchesShareScope(
        {
          id: 'clip-1',
          hierarchy: {
            documentary: {
              subjectId: 'subject-1',
              subjectName: 'Jordan',
            },
          },
        },
        {
          scope: 'subject',
          scope_id: 'subject-1',
        }
      )
    ).toBe(true)
  })

  it('restricts assembly-scoped links to the supplied clip ids', () => {
    expect(
      clipMatchesShareScope(
        { id: 'clip-1' },
        {
          scope: 'assembly',
          scope_id: 'assembly-1',
        },
        new Set(['clip-1'])
      )
    ).toBe(true)

    expect(
      clipMatchesShareScope(
        { id: 'clip-2' },
        {
          scope: 'assembly',
          scope_id: 'assembly-1',
        },
        new Set(['clip-1'])
      )
    ).toBe(false)
  })
})

describe('requireShareLinkAccess', () => {
  function createSupabaseShareLinkMock(passwordHash: string | null) {
    return {
      from: () => ({
        select: () => ({
          eq: () => ({
            single: async () => ({
              data: {
                id: 'share-1',
                project_id: 'project-1',
                token: 'valid-share-token',
                scope: 'project',
                scope_id: null,
                expires_at: '2099-01-01T00:00:00.000Z',
                password_hash: passwordHash,
                permissions: {
                  canComment: true,
                  canFlag: true,
                  canRequestAlternate: true,
                },
                revoked_at: null,
              },
              error: null,
            }),
          }),
        }),
      }),
    }
  }

  it('rejects password-protected links when the review access cookie is missing', async () => {
    const supabase = createSupabaseShareLinkMock('hash-value')

    await expect(
      requireShareLinkAccess(supabase as never, 'valid-share-token')
    ).rejects.toMatchObject({
      message: 'Password required for this share link',
      status: 401,
    })
  })

  it('allows password-protected links when the review access cookie matches', async () => {
    const supabase = createSupabaseShareLinkMock('hash-value')

    await expect(
      requireShareLinkAccess(supabase as never, 'valid-share-token', {
        cookies: {
          get: () => ({
            value: reviewAccessCookieValue('valid-share-token', 'hash-value'),
          }),
        },
      })
    ).resolves.toMatchObject({
      token: 'valid-share-token',
    })
  })
})
