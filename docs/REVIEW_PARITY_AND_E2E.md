# Collaborative review: parity notes and E2E coverage

## Desktop ↔ cloud

- [`RealtimeManager`](../apps/desktop/Sources/SLATECore/RealtimeManager.swift) subscribes to Supabase Realtime channels described in [`contracts/realtime-events.json`](../contracts/realtime-events.json) and forwards events to `NotificationCenter` (e.g. `.annotationAdded`, `.clipUpdated`, `.realtimeClipIngested`).
- Share links and signed proxy URLs use [`ShareLinkService`](../apps/desktop/Sources/SLATECore/ShareLinkService.swift) against [`contracts/web-api.json`](../contracts/web-api.json).

## Web portal

- Playwright tests live in [`apps/web/e2e/`](../apps/web/e2e/): password gate, expired links, annotations, status, alternates, AI scores panel (`review.spec.ts`).
- **Transcript** UI: when clip metadata includes `transcription_text` / segments, the review client exposes a **Transcript** inspector tab (`client.tsx`). Mocked E2E can assert the tab and placeholder states without a live ASR backend.

## Frame.io–style backlog (optional slices)

Adobe / Frame.io V4 integration options (file interchange, UXP, cloud API) are summarized in [`docs/ADOBE_INTEGRATION.md`](ADOBE_INTEGRATION.md).

Use [`.cursor/agents/frame-io-parity-architect.md`](../.cursor/agents/frame-io-parity-architect.md) as a matrix: @mentions, resolve workflows, drawing-on-frame, version compare, notification depth. Pick 1–2 items per release; tie email/in-app notifications to project digest settings where applicable.

## Staging E2E (manual)

1. Desktop: sign in, enable sync, open a project.
2. Web: open share link, post annotation.
3. Desktop: confirm notification-driven refresh or realtime updates for that clip/project.
