/**
 * Fixed-window rate limiter (in-process). Best-effort on serverless multi-instance
 * deployments; combine with edge/WAF limits for strong guarantees.
 */

import { NextResponse } from 'next/server'

interface Bucket {
  count: number
  windowStart: number
}

const store = new Map<string, Bucket>()

function envInt(name: string, fallback: number): number {
  const raw = process.env[name]
  if (!raw) {
    return fallback
  }
  const n = Number.parseInt(raw, 10)
  return Number.isFinite(n) && n > 0 ? n : fallback
}

export type ReviewRateLimitKind = 'annotate' | 'reply' | 'resolve' | 'proxy' | 'unlock' | 'alternate' | 'status'

const WINDOW_MS = 60_000

const DEFAULT_MAX: Record<ReviewRateLimitKind, number> = {
  annotate: 45,
  reply: 60,
  resolve: 60,
  proxy: 90,
  unlock: 12,
  alternate: 20,
  status: 90,
}

function maxFor(kind: ReviewRateLimitKind): number {
  const envName = `REVIEW_RL_${kind.toUpperCase()}_PER_MINUTE`
  return envInt(envName, DEFAULT_MAX[kind])
}

function prune(key: string, now: number, windowMs: number): void {
  const b = store.get(key)
  if (b && now - b.windowStart > windowMs) {
    store.delete(key)
  }
}

export function checkReviewRateLimit(
  kind: ReviewRateLimitKind,
  fingerprint: string
): { ok: true } | { ok: false; retryAfterSeconds: number } {
  const max = maxFor(kind)
  const key = `${kind}:${fingerprint}`
  const now = Date.now()
  prune(key, now, WINDOW_MS)

  let bucket = store.get(key)
  if (!bucket || now - bucket.windowStart > WINDOW_MS) {
    bucket = { count: 1, windowStart: now }
    store.set(key, bucket)
    return { ok: true }
  }

  if (bucket.count >= max) {
    const retryAfterMs = WINDOW_MS - (now - bucket.windowStart)
    const retryAfterSeconds = Math.max(1, Math.ceil(retryAfterMs / 1000))
    return { ok: false, retryAfterSeconds }
  }

  bucket.count += 1
  return { ok: true }
}

export function rateLimitFingerprint(ip: string, shareToken: string): string {
  const prefix = shareToken.slice(0, 16)
  return `${ip}:${prefix}`
}

export function rateLimitResponse(retryAfterSeconds: number): NextResponse {
  return NextResponse.json(
    { error: 'Too many requests' },
    {
      status: 429,
      headers: { 'Retry-After': String(retryAfterSeconds) },
    }
  )
}
