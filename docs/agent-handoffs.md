# SLATE — Agent Handoff Documentation

This document describes what each agent produces, what it consumes, and
the sequence of events that unlocks each dependent agent's work.

---

## Dependency graph

```
Claude Code (C0)
  └─ publishes contracts/data-model.json
        ├─ Codex (X0) begins sync-engine + ai-pipeline
        │     ├─ publishes contracts/sync-api.json      ─────────┐
        │     └─ publishes contracts/ai-scores-api.json ─────────┤
        │                                                         │
        └─ Gemini (G0) begins Supabase schema + web portal        │
              ├─ publishes contracts/web-api.json        ─────────┤
              └─ publishes contracts/realtime-events.json ────────┤
                                                                   │
Claude Code (C3) wires all four contracts into desktop app ◄───────┘
```

---

## Claude Code produces

| Output | When | Consumers |
|---|---|---|
| `contracts/data-model.json` | C0 (Day 1) | Codex (X0), Gemini (G0) |
| `packages/shared-types/src/clip.ts` | C0 | Gemini (Next.js types) |
| `packages/shared-types/Sources/SLATESharedTypes/Clip.swift` | C0 | Codex, IngestDaemon, ExportWriters, Desktop |
| NLE export files (FCPXML, EDL, AAF, XML) | C3 | End users / NLEs |
| Share link calls → Gemini edge function | C4 | Web portal |

## Claude Code consumes

| Input | From | When needed |
|---|---|---|
| `contracts/sync-api.json` | Codex | C4 — wiring SyncManager.swift |
| `contracts/ai-scores-api.json` | Codex | C4 (Phase 2) — wiring AIManager.swift |
| `contracts/web-api.json` | Gemini | C4 — wiring ShareLinkManager.swift |
| `contracts/realtime-events.json` | Gemini | C4 — Supabase Realtime subscriptions |
| `supabase/migrations/` | Gemini | C1+ — schema for GRDB mirroring |

---

## Codex produces

| Output | When | Consumers |
|---|---|---|
| `packages/sync-engine/` Swift package | X3 | Claude Code (SyncManager.swift) |
| `contracts/sync-api.json` | X3 | Claude Code |
| `packages/ai-pipeline/` Swift package | X8 | Claude Code (AIManager.swift) |
| `contracts/ai-scores-api.json` | X8 | Claude Code, Gemini |
| `scripts/test-sync.sh` fixtures | X1 | CI, Claude Code |

## Codex consumes

| Input | From | When |
|---|---|---|
| `contracts/data-model.json` | Claude Code | X0 — before writing any model-touching code |

---

## Gemini produces

| Output | When | Consumers |
|---|---|---|
| `supabase/migrations/` | G0 | Claude Code (GRDB schema mirror), Codex |
| `supabase/functions/` | G4 | Claude Code (ShareLinkManager.swift) |
| `contracts/web-api.json` | G5 | Claude Code |
| `contracts/realtime-events.json` | G5 | Claude Code, Codex |
| `apps/web/` | G1–G6 | End users (browser) |

## Gemini consumes

| Input | From | When |
|---|---|---|
| `contracts/data-model.json` | Claude Code | G0 — before writing schema |
| `packages/shared-types/src/clip.ts` | Claude Code | G1 — TypeScript types in Next.js |
| `contracts/ai-scores-api.json` | Codex | G5 — displaying scores in portal |

---

## Signaling between agents

When an agent completes a checkpoint that unblocks another agent, it should:
1. Update its `AGENT_*.md` checkpoint status
2. Commit the new contract file(s) to `contracts/`
3. Add a commit message like: `[C0] Claude Code: data-model.json published — Codex and Gemini may begin`

Receiving agents should `git pull` and read the new contract before building
anything that depends on it.
