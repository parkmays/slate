# SLATE — Codex Agent Memory

## Role: AI/ML Engine

## What I own
- `packages/sync-engine/` — audio sync engine and audio-role classification
- `packages/ai-pipeline/` — on-device scoring pipeline and transcription entrypoints
- `scripts/test-sync.sh` — sync accuracy harness runner
- `contracts/sync-api.json` — published after sync engine is stable
- `contracts/ai-scores-api.json` — published after scoring pipeline is stable

## What I consume (do not modify lightly)
- `contracts/data-model.json` — canonical clip schema
- `packages/shared-types/` — future shared Swift/TypeScript types from Claude Code
- `contracts/web-api.json` — review/share endpoints from Gemini

## Domain rules
- All inference runs locally by default on Apple Silicon
- Every automated result carries confidence and model version metadata
- Graceful degradation beats hard failure
- Manual overrides win forever
- Tests come before algorithm changes

## Key paths
- `packages/sync-engine/Sources/SLATESyncEngine/SyncEngine.swift`
- `packages/sync-engine/Tests/SLATESyncEngineTests/SyncEngineTests.swift`
- `packages/ai-pipeline/Sources/SLATEAIPipeline/SLATEAIPipeline.swift`
- `contracts/` — handoff contracts only

## Performance targets
- Sync 10-minute take in under 30 seconds on Apple Silicon
- Vision scoring 10-minute proxy in under 45 seconds
- Audio scoring 10-minute take in under 10 seconds

## Current assumptions
- Claude Code has not yet published a standalone `contracts/data-model.json`, so the
  schema embedded in the coordination brief has been mirrored locally to unblock work.
- Phase 1 ships sync + local heuristic scoring. Phase 2 swaps in trained CoreML models
  behind the same public API.
