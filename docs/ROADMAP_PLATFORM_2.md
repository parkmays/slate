# Platform 2.0 vertical slices

Themes from [`CHANGELOG.md`](../CHANGELOG.md) (Unreleased / 2.0.0), ordered as **independent vertical slices**. Each slice should ship with a contract update under `contracts/` and a demo path.

1. **Transcription + language packs** — server/client fields already exist in places; wire ASR jobs, storage, and review UI (web transcript tab + desktop metadata).
2. **Cloud / offload AI scoring** — queue scoring on workers; desktop shows job status via existing realtime/proxy patterns.
3. **Richer motion / composition** — extend vision scoring beyond focus/exposure/stability; version `contracts/ai-scores-api.json`.
4. **Plugin boundary for models** — stable C ABI or CoreML plug-in discovery; document in `packages/ai-pipeline`.
5. **Live recording sync** — only if product commits; highest risk; depends on capture pipeline.

Dependencies: slice 1 unlocks narrative/documentary “performance” and density scores that need text. Slices 2–4 can proceed in parallel after shared-types/contracts are agreed.
