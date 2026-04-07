import { ReviewRouteError } from '@/lib/review-server'

export const MAX_REVIEW_TEXT_CHARS = 8_000
export const MAX_VOICE_DATA_URL_CHARS = 600_000
export const MAX_VOICE_HTTPS_URL_CHARS = 2_048
export const MAX_TIMECODE_IN_CHARS = 48
export const MAX_SPATIAL_DATA_BYTES = 64_000

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

type SpatialPoint = { x: number; y: number }
type SpatialShape =
  | { kind: 'arrow'; from: SpatialPoint; to: SpatialPoint; stroke?: string; strokeWidthNorm?: number }
  | { kind: 'ellipse'; cx: number; cy: number; rx: number; ry: number; stroke?: string; strokeWidthNorm?: number }
  | { kind: 'freehand'; points: SpatialPoint[]; stroke?: string; strokeWidthNorm?: number }

export interface SpatialAnnotationInput {
  version: 1
  shapes: SpatialShape[]
}

function isFinite01(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 1
}

function validPoint(point: unknown): point is SpatialPoint {
  if (!point || typeof point !== 'object' || Array.isArray(point)) {
    return false
  }
  const p = point as Record<string, unknown>
  return isFinite01(p.x) && isFinite01(p.y)
}

export function assertValidSpatialData(payload: unknown): payload is SpatialAnnotationInput {
  if (payload == null) {
    return true
  }
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    throw new ReviewRouteError('Invalid spatial annotation payload', 400)
  }
  const bytes = new TextEncoder().encode(JSON.stringify(payload)).length
  if (bytes > MAX_SPATIAL_DATA_BYTES) {
    throw new ReviewRouteError('Spatial annotation payload is too large', 413)
  }
  const value = payload as Record<string, unknown>
  if (value.version !== 1 || !Array.isArray(value.shapes)) {
    throw new ReviewRouteError('Invalid spatial annotation payload version', 400)
  }
  for (const shape of value.shapes) {
    if (!shape || typeof shape !== 'object' || Array.isArray(shape)) {
      throw new ReviewRouteError('Spatial shape is invalid', 400)
    }
    const s = shape as Record<string, unknown>
    const kind = s.kind
    if (kind === 'arrow') {
      if (!validPoint(s.from) || !validPoint(s.to)) {
        throw new ReviewRouteError('Arrow shape has invalid coordinates', 400)
      }
    } else if (kind === 'ellipse') {
      if (!isFinite01(s.cx) || !isFinite01(s.cy) || !isFinite01(s.rx) || !isFinite01(s.ry)) {
        throw new ReviewRouteError('Ellipse shape has invalid coordinates', 400)
      }
    } else if (kind === 'freehand') {
      if (!Array.isArray(s.points) || s.points.length < 2 || !s.points.every(validPoint)) {
        throw new ReviewRouteError('Freehand shape has invalid points', 400)
      }
    } else {
      throw new ReviewRouteError('Unsupported spatial shape kind', 400)
    }
  }
  return true
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
