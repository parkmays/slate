import { ReviewRouteError } from '@/lib/review-server'

export const MAX_REVIEW_TEXT_CHARS = 8_000
export const MAX_VOICE_DATA_URL_CHARS = 600_000
export const MAX_VOICE_HTTPS_URL_CHARS = 2_048
export const MAX_TIMECODE_IN_CHARS = 48

function stripNullBytes(s: string): string {
  return s.replace(/\u0000/g, '')
}

export function sanitizeReviewTextBody(body: string): string {
  return stripNullBytes(body).trim()
}

const SMPTE_TIMECODE_RE = /^\d+:\d{2}:\d{2}[:;]\d{2}$/

export function assertValidTimecodeIn(timecodeIn: string): void {
  if (timecodeIn.length > MAX_TIMECODE_IN_CHARS) {
    throw new ReviewRouteError('Timecode is too long', 400)
  }
  const t = timecodeIn.trim()
  if (!SMPTE_TIMECODE_RE.test(t)) {
    throw new ReviewRouteError('Invalid timecode format', 400)
  }
}

export function assertValidAnnotationTextBody(body: string): void {
  const t = stripNullBytes(body)
  if (t.length > MAX_REVIEW_TEXT_CHARS) {
    throw new ReviewRouteError(`Comment must be at most ${MAX_REVIEW_TEXT_CHARS} characters`, 400)
  }
}

export function assertValidVoicePayload(voiceUrl: string): void {
  const v = stripNullBytes(voiceUrl)
  if (v.startsWith('data:audio')) {
    if (v.length > MAX_VOICE_DATA_URL_CHARS) {
      throw new ReviewRouteError('Voice attachment is too large', 413)
    }
    return
  }
  if (v.startsWith('https://') || v.startsWith('http://')) {
    if (v.length > MAX_VOICE_HTTPS_URL_CHARS) {
      throw new ReviewRouteError('Voice URL is too long', 400)
    }
    return
  }
  throw new ReviewRouteError('Invalid voice attachment', 400)
}

const ALTERNATE_PREFIX = 'REQUEST ALTERNATE: '

export function assertValidAlternateRequestNote(note: string): void {
  const t = stripNullBytes(note).trim()
  if (t.length === 0) {
    throw new ReviewRouteError('Missing request note', 400)
  }
  if (ALTERNATE_PREFIX.length + t.length > MAX_REVIEW_TEXT_CHARS) {
    throw new ReviewRouteError(
      `Note must be at most ${MAX_REVIEW_TEXT_CHARS - ALTERNATE_PREFIX.length} characters`,
      400
    )
  }
}
