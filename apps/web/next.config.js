/** CSP for /review/* — Supabase Realtime, R2 playback, blob voice notes. */
function buildReviewContentSecurityPolicy() {
  const connect = new Set([
    "'self'",
    'https://*.supabase.co',
    'wss://*.supabase.co',
    'https://*.r2.cloudflarestorage.com',
  ])
  for (const raw of [process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.R2_PUBLIC_URL]) {
    if (!raw) {
      continue
    }
    try {
      const u = new URL(raw)
      connect.add(u.origin)
      if (u.protocol === 'https:') {
        connect.add(`wss://${u.host}`)
      }
    } catch {
      // ignore invalid env URLs
    }
  }
  return [
    "default-src 'self'",
    "script-src 'self' 'unsafe-inline' 'unsafe-eval' https://vercel.live",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob: https:",
    "font-src 'self' data:",
    `connect-src ${[...connect].join(' ')}`,
    "media-src 'self' blob: data:",
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "object-src 'none'",
  ].join('; ')
}

/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  swcMinify: true,
  images: {
    domains: [
      // Add your R2 domain here
      process.env.R2_PUBLIC_URL?.replace('https://', '') || '',
    ],
    formats: ['image/webp', 'image/avif'],
  },
  async headers() {
    return [
      {
        source: '/review/:token*',
        headers: [
          {
            key: 'X-Frame-Options',
            value: 'DENY',
          },
          {
            key: 'X-Content-Type-Options',
            value: 'nosniff',
          },
          {
            key: 'Referrer-Policy',
            value: 'strict-origin-when-cross-origin',
          },
          {
            key: 'Content-Security-Policy',
            value: buildReviewContentSecurityPolicy(),
          },
          {
            key: 'Permissions-Policy',
            value: 'camera=(), geolocation=(), microphone=(self), payment=()',
          },
        ],
      },
    ]
  },
}

module.exports = nextConfig
