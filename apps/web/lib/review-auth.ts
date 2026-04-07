import { createHash, timingSafeEqual } from 'crypto'

function sha256(value: string): string {
  return createHash('sha256').update(value).digest('hex')
}

export function reviewAccessCookieName(token: string): string {
  return `slate_review_${sha256(token).slice(0, 20)}`
}

export function reviewAccessCookieValue(token: string, passwordHash: string): string {
  return sha256(`${token}:${passwordHash}`)
}

export function hasValidReviewAccessCookie(
  cookieValue: string | undefined,
  token: string,
  passwordHash: string
): boolean {
  if (!cookieValue) {
    return false
  }

  const expectedValue = reviewAccessCookieValue(token, passwordHash)

  try {
    return timingSafeEqual(Buffer.from(cookieValue), Buffer.from(expectedValue))
  } catch {
    return false
  }
}

export function isShareLinkExpired(expiresAt: string | null | undefined): boolean {
  if (!expiresAt) {
    return false
  }

  return new Date(expiresAt) < new Date()
}
