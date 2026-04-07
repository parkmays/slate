# Prototype Demo Runbook

This runbook is for the prototype showing meeting and prioritizes deterministic local playback.

## Demo Fixture Path

- Canonical local fixture root: `AI Powered Dailies/AI DAILY/demo-assets/`
- Expected sample footage path: `AI Powered Dailies/AI DAILY/demo-assets/sample-presentation-footage/`

If your footage is currently elsewhere, copy or symlink it into that directory before rehearsal.

## Meeting Script (Happy Path)

1. Launch desktop app.
2. If auth is shown, click **Continue Offline** for local demo mode.
3. Open walkthrough and follow:
  - project selection
  - import footage
  - clip review / detail
  - share/review context
4. Import from the fixture folder above.
5. Open one clip in detail and verify local proxy playback.
6. Open multicam for one grouped shot (if present).
7. Show tooltip + shortcuts discoverability.
8. Open web review flow and walkthrough (local/mock-safe route).

## Fallback Path (If Any Cloud Call Fails)

1. Stay in desktop local mode.
2. Continue walkthrough and review features without share-link generation.
3. Explain cloud flows are intentionally bypassed for this prototype meeting.

## Rehearsal Checklist

- Fixture folder exists and is readable.
- Desktop walkthrough opens from first-run and from replay action.
- Keyboard shortcuts work on meeting hardware.
- Toolbar customization persists after relaunch.
- Web walkthrough opens and can replay.
- No blocking cloud dependency is required for the scripted flow.

## Presenter Shortcut Cheat Sheet

### Desktop

- `Command+N`: New project
- `Command+Shift+W`: Replay walkthrough
- `Command+Shift+T`: Customize toolbar
- `Command+I`: Open ingest progress

### Web Review

- `J / K / L`: Back 10s, play/pause, forward 10s
- `ArrowUp / ArrowDown`: Previous/next clip
- `/`: Focus clip search
- `C / F / X / D`: Quick review status (when flag permissions are enabled)
- `?`: Replay walkthrough