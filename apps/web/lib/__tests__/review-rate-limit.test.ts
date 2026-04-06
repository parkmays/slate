import { describe, expect, it } from 'vitest'
import { checkReviewRateLimit, rateLimitFingerprint } from '@/lib/review-rate-limit'

describe('checkReviewRateLimit', () => {
  it('allows requests under the limit', () => {
    const fp = rateLimitFingerprint('127.0.0.1', 'tokentokentokentoken')
    for (let i = 0; i < 5; i += 1) {
      expect(checkReviewRateLimit('unlock', fp).ok).toBe(true)
    }
  })

  it('returns retry-after when the window is saturated', () => {
    process.env.REVIEW_RL_UNLOCK_PER_MINUTE = '3'
    const fp = `sat-${Math.random()}-127.0.0.1:abc`
    expect(checkReviewRateLimit('unlock', fp).ok).toBe(true)
    expect(checkReviewRateLimit('unlock', fp).ok).toBe(true)
    expect(checkReviewRateLimit('unlock', fp).ok).toBe(true)
    const fourth = checkReviewRateLimit('unlock', fp)
    expect(fourth.ok).toBe(false)
    if (!fourth.ok) {
      expect(fourth.retryAfterSeconds).toBeGreaterThan(0)
    }
    delete process.env.REVIEW_RL_UNLOCK_PER_MINUTE
  })
})
