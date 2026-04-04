# SLATE — Google Gemini Code Assist Agent Memory

## Role: Web Portal & Infrastructure

## What I own
- apps/web/ — Next.js 14 web portal for review and collaboration
- supabase/migrations/ — All database schema changes
- supabase/functions/ — Edge functions (share links, proxy signing, etc.)
- Cloudflare R2 integration for proxy storage
- CI/CD pipeline via GitHub Actions
- Vercel deployment configuration

## What I consume (do not modify)
- packages/shared-types/ — Claude Code writes; I use TypeScript types
- packages/sync-engine/ — Codex writes; I don't touch this
- packages/ai-pipeline/ — Codex writes; I don't touch this
- apps/desktop/ — Claude Code writes; I generate share links for it

## Contracts I write
- contracts/web-api.json — REST and edge function endpoints
- contracts/realtime-events.json — Supabase Realtime event schema

## Critical rules
- Original media: NEVER store or serve original files via web
- Share links: Must be token-based, expiring, and scoping-aware
- Realtime: All annotations sync instantly across all clients
- Performance: Review page must be interactive within 2 seconds
- Security: All proxy access via signed URLs with 24-hour expiry

## Key paths
- supabase/migrations/ — all schema changes must be versioned here
- apps/web/app/review/[token]/ — core review page
- supabase/functions/v1/ — all edge functions
- contracts/ — read all contracts before implementing dependent features

## Tech stack
- Next.js 14 with App Router (RSC)
- Supabase (Postgres + Realtime + Edge Functions)
- Cloudflare R2 for proxy storage
- TailwindCSS + shadcn/ui for styling
- hls.js for video playback
- tRPC for type-safe APIs

## Current phase: Phase 1 MVP
Out of scope: Mobile app, offline support, advanced analytics, SSO

## Performance targets
- Review page first paint: < 1.5s
- HLS player ready: < 2s
- Annotation sync: < 100ms
- Share link generation: < 500ms
- Proxy URL signing: < 200ms