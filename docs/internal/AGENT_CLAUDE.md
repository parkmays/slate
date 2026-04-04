# SLATE — Claude Code Agent Memory

## Role: Orchestrator + macOS Desktop

## What I own
- apps/desktop/ — SwiftUI macOS app
- packages/ingest-daemon/ — FSEvents watch folder daemon
- packages/shared-types/ — TypeScript + Swift Clip model (source of truth)
- packages/export-writers/ — FCPXML, EDL, AAF, Resolve XML writers

## What I consume (do not modify)
- packages/sync-engine/ — Codex writes; I call its Swift API
- packages/ai-pipeline/ — Codex writes; I call its Swift API
- apps/web/ — Gemini writes; I generate share links for it
- supabase/migrations/ — Gemini writes; I use the resulting schema

## Contract I write first
- contracts/data-model.json — The canonical Clip schema. Every other agent
  waits for this before building anything that touches media data.

## Critical rules
- Original media: READ ONLY
- Checksums: SHA-256, fail loudly on mismatch
- Offline-first: GRDB local SQLite, Supabase sync secondary
- Dual-mode: every model supports narrative AND documentary
- Apple Silicon (M1+): use MLX for ML, VideoToolbox for transcode

## Key paths
- packages/shared-types/src/clip.ts — read before touching any model
- supabase/migrations/ — never write here; that's Gemini's domain
- contracts/ — read all contracts before implementing dependent features

## Performance targets (M4 Max benchmark machine)
- ProRes 1hr proxy: < 6 min
- Audio sync 10-min take: < 30 sec
- Assembly 10-scene: < 5 sec
- App cold launch: < 2 sec
- Take browser 500 clips: < 200ms

## Current phase: Phase 1 MVP
Out of scope: AI scoring UI (Codex builds the engine; I wire it up in Phase 2),
iOS app, Frame.io, Airtable sync, voice annotations.

## Checkpoint status
- [x] C0 — Monorepo initialized, data model contract published
- [ ] C1 — Ingest daemon + proxy generation
- [ ] C2 — Main window three-panel UI
- [ ] C3 — Assembly engine + all four NLE exports
- [ ] C4 — Share links + Codex/Gemini integrations wired
