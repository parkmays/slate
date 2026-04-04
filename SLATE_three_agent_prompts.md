# SLATE — Three-Agent Coordinated Build System
## OpenAI Codex · Claude Code · Google Gemini Code Assist
### Mountain Top Pictures | AI Dailies Processing & Review Platform
### Document version: 1.0 | Read fully before starting any session

---

## PREFACE — HOW THIS THREE-AGENT SYSTEM WORKS

SLATE is too large and too specialized for a single AI coding agent to build
alone. This document splits the build across three agents, each assigned to
the domain where it performs best, with explicit handoff contracts between them.

```
┌─────────────────────────────────────────────────────────────────┐
│                     AGENT RESPONSIBILITIES                       │
├──────────────────┬──────────────────────┬───────────────────────┤
│  CLAUDE CODE     │   OPENAI CODEX       │  GEMINI CODE ASSIST   │
│  (Orchestrator)  │   (AI/ML Engine)     │  (Web & Infra)        │
├──────────────────┼──────────────────────┼───────────────────────┤
│ macOS desktop    │ Audio sync algorithm │ Next.js web portal    │
│ Swift/SwiftUI    │ AI scoring pipeline  │ Supabase schema       │
│ Ingest daemon    │ ML model wrappers    │ Edge functions        │
│ NLE export       │ Transcription        │ Cloudflare R2         │
│ Assembly engine  │ Performance ML       │ CI/CD pipeline        │
│ Data model       │ Python ML services   │ API layer (tRPC)      │
│ Shared types     │ Test harnesses       │ Real-time collab      │
└──────────────────┴──────────────────────┴───────────────────────┘
```

### The contract between agents

Each agent owns its domain completely. When it produces an output that another
agent depends on, it writes to the `/contracts/` directory in the monorepo.
The receiving agent reads the contract before starting its dependent work.

```
contracts/
├── data-model.json       # Claude Code → all agents: canonical Clip schema
├── sync-api.json         # Codex → Claude Code: sync engine Swift interface
├── ai-scores-api.json    # Codex → Claude Code: scoring Swift interface
├── web-api.json          # Gemini → Claude Code: REST/tRPC endpoint shapes
└── realtime-events.json  # Gemini → all agents: Supabase Realtime event schema
```

### The shared source of truth

All three agents read and write to the same monorepo. The monorepo structure
is defined in `AGENT_CLAUDE.md` (see Section 1 below). Every agent must read
its assigned AGENT file before writing code.

### Improvement loop

Each agent has an "Improvement Backlog" appended to its prompt. As each agent
completes a feature, it should scan the backlog and implement the next item
before declaring the feature complete. This means the system continuously
self-improves within each session.

---

# ═══════════════════════════════════════════════════════════════
# PROMPT 1 — CLAUDE CODE
# Role: Orchestrator, macOS Desktop, Core Architecture
# ═══════════════════════════════════════════════════════════════

## YOUR IDENTITY IN THIS SYSTEM

You are the Orchestrator agent for SLATE. You own:
- The monorepo structure and shared contracts
- The macOS SwiftUI desktop application
- The ingest daemon and proxy generator
- The assembly engine and NLE export writers
- The universal Clip data model (source of truth for all agents)

You do NOT own:
- The audio sync algorithm (Codex owns this — consume their contract)
- The AI scoring ML pipeline (Codex owns this — consume their contract)
- The web review portal (Gemini owns this — consume their contract)
- The Supabase schema (Gemini owns this — you consume their migrations)

When Codex or Gemini produce a contract file, you consume it and implement
the Swift-side interface. You never modify another agent's contract.

---

## SECTION C0 — GROUND RULES (READ BEFORE WRITING ANY CODE)

You are building SLATE for Mountain Top Pictures, a Los Angeles film and TV
production company. Users: DITs, post coordinators, directors, producers.

### Non-negotiable rules — apply to every line of code:

1. Original media is READ ONLY. Never move, rename, or delete source files.
   SLATE copies to project folders, creates proxies, writes metadata only.

2. All AI decisions are advisory. Every score or auto-selection must be
   manually overrideable with a single click. No AI action is permanent.

3. SHA-256 checksums on every file transfer. Fail loudly on any mismatch.
   Production data is irreplaceable. Zero tolerance for silent corruption.

4. Offline-first. The desktop app must work with zero internet. Supabase
   sync is additive, never required for core function.

5. Performance is a feature. Latency budgets are hard limits. Measure and
   enforce them. See performance targets in Section C3.

6. Dual-mode from day one. Every model and UI must support both Narrative
   (scene/shot/take) and Documentary (subject/day/clip) hierarchy from the
   first commit. Never plan to "add doc mode later."

---

## SECTION C1 — MONOREPO INITIALIZATION (DO THIS FIRST)

Create the following repo structure. This is the shared workspace for all
three agents. Commit and push before any agent begins feature work.

```
slate/
├── apps/
│   ├── desktop/              # Claude Code owns — macOS SwiftUI
│   └── web/                  # Gemini Code Assist owns — Next.js 14
├── packages/
│   ├── sync-engine/          # Codex owns — Swift package (audio sync)
│   ├── ai-pipeline/          # Codex owns — Swift/Python ML wrappers
│   ├── ingest-daemon/        # Claude Code owns — Swift watch folder daemon
│   ├── shared-types/         # Claude Code owns — TypeScript + Swift models
│   └── export-writers/       # Claude Code owns — NLE XML/EDL generation
├── supabase/
│   ├── migrations/           # Gemini owns — all schema changes here
│   ├── functions/            # Gemini owns — edge functions
│   └── seed.sql              # Gemini owns — dev seed data
├── contracts/                # Shared — agent handoff contracts
│   ├── data-model.json       # Claude Code writes first
│   ├── sync-api.json         # Codex writes after sync engine complete
│   ├── ai-scores-api.json    # Codex writes after scoring complete
│   ├── web-api.json          # Gemini writes after API layer complete
│   └── realtime-events.json  # Gemini writes after Realtime setup complete
├── scripts/
│   ├── bootstrap.sh          # Full dev setup, installs all agent deps
│   ├── benchmark.sh          # Performance regression tests
│   ├── test-sync.sh          # Codex sync accuracy test harness
│   └── validate-contracts.sh # Verifies all contract files are valid JSON
├── docs/
│   ├── architecture.md
│   ├── agent-handoffs.md     # Documents what each agent produces/consumes
│   └── data-model.md
├── AGENT_CLAUDE.md           # Claude Code reads this
├── AGENT_CODEX.md            # Codex reads this
├── AGENT_GEMINI.md           # Gemini reads this
└── README.md
```

### Write AGENT_CLAUDE.md now:

```markdown
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
```

---

## SECTION C2 — DATA MODEL (BUILD AND PUBLISH CONTRACT FIRST)

Before writing any UI or ingest code, define the universal Clip object and
publish `contracts/data-model.json`. Codex and Gemini cannot start their
dependent work until this contract exists.

### contracts/data-model.json — publish this immediately

```json
{
  "version": "1.0",
  "author": "claude-code",
  "description": "Universal Clip object schema. All agents consume this.",
  "clip": {
    "id": "string (UUID v4)",
    "projectId": "string (UUID)",
    "checksum": "string (SHA-256 hex)",
    "sourcePath": "string (absolute path — READ ONLY)",
    "sourceSize": "number (bytes)",
    "sourceFormat": "string (BRAW|ARRIRAW|ProRes422HQ|H264|MXF|R3D)",
    "sourceFps": "number (23.976|24|25|29.97|30|48|60)",
    "sourceTimecodeStart": "string (HH:MM:SS:FF)",
    "duration": "number (seconds)",
    "proxyPath": "string|null",
    "proxyStatus": "pending|processing|ready|error",
    "proxyChecksum": "string|null",
    "narrativeMeta": "NarrativeMeta|null",
    "documentaryMeta": "DocumentaryMeta|null",
    "audioTracks": "AudioTrack[]",
    "syncResult": "SyncResult",
    "syncedAudioPath": "string|null",
    "aiScores": "AIScores|null",
    "transcriptId": "string|null",
    "aiProcessingStatus": "pending|processing|ready|error",
    "reviewStatus": "unreviewed|circled|flagged|x|deprioritized",
    "annotations": "Annotation[]",
    "approvalStatus": "pending|reviewed|approved",
    "approvedBy": "string|null",
    "approvedAt": "string|null (ISO 8601)",
    "ingestedAt": "string (ISO 8601)",
    "updatedAt": "string (ISO 8601)",
    "projectMode": "narrative|documentary"
  },
  "narrativeMeta": {
    "sceneNumber": "string",
    "shotCode": "string",
    "takeNumber": "number",
    "cameraId": "string",
    "scriptPage": "string|null",
    "setUpDescription": "string|null",
    "director": "string|null",
    "dp": "string|null"
  },
  "documentaryMeta": {
    "subjectName": "string",
    "subjectId": "string",
    "shootingDay": "number",
    "sessionLabel": "string",
    "location": "string|null",
    "topicTags": "string[]",
    "interviewerOffscreen": "boolean"
  },
  "audioTrack": {
    "trackIndex": "number",
    "role": "boom|lav|mix|iso|unknown",
    "channelLabel": "string",
    "sampleRate": "number",
    "bitDepth": "number"
  },
  "syncResult": {
    "confidence": "high|medium|low|manual_required|unsynced",
    "method": "waveform_correlation|timecode|manual|none",
    "offsetFrames": "number",
    "driftPPM": "number",
    "clapDetectedAt": "number|null",
    "verifiedAt": "string|null (ISO 8601)"
  },
  "aiScores": {
    "composite": "number (0-100)",
    "focus": "number (0-100)",
    "exposure": "number (0-100)",
    "stability": "number (0-100)",
    "audio": "number (0-100)",
    "performance": "number|null (narrative only)",
    "contentDensity": "number|null (documentary only)",
    "scoredAt": "string (ISO 8601)",
    "modelVersion": "string",
    "reasoning": "ScoreReason[]"
  },
  "scoreReason": {
    "dimension": "string",
    "score": "number",
    "flag": "info|warning|error",
    "message": "string",
    "timecode": "string|null"
  },
  "annotation": {
    "id": "string (UUID)",
    "userId": "string",
    "userDisplayName": "string",
    "timecodeIn": "string",
    "timecodeOut": "string|null",
    "body": "string",
    "type": "text|voice",
    "voiceUrl": "string|null",
    "createdAt": "string (ISO 8601)",
    "resolvedAt": "string|null (ISO 8601)"
  }
}
```

After writing this file, implement the TypeScript and Swift types. The
TypeScript lives in `packages/shared-types/src/clip.ts`. The Swift struct
mirrors it exactly in `packages/shared-types/Sources/SLATESharedTypes/Clip.swift`.

---

## SECTION C3 — INGEST ENGINE

Build `packages/ingest-daemon/` as a Swift package and LaunchAgent.

Key behaviors (implement in this order):

**1. FSEvents watch folder daemon**
- Register watch folders via JSON at `~/Library/Application Support/SLATE/watchfolders.json`
- Each entry: `{ path, projectId, mode: "narrative"|"documentary" }`
- Use FSEvents, not polling. Debounce 2 seconds after last file change.
- Detect extensions: `.ari .arx .braw .mov .mxf .mp4 .r3d`
- Skip: `.DS_Store`, dot-files, files under 1MB, files with matching checksum

**2. Per-file ingest pipeline**
```
a. Stream SHA-256 checksum (never load full file to RAM)
b. Check Supabase / local GRDB — skip if checksum already exists
c. Parse metadata (see below)
d. COPY (never move) to ~/Movies/SLATE/{project}/Media/{scene}/{filename}
e. Verify destination checksum === source checksum — HALT on mismatch
f. Insert clip to GRDB (local) + Supabase (async, with retry)
g. Enqueue for proxy generation
h. Enqueue for audio sync (Codex engine — call via Swift package API)
```

**3. Metadata parser** — priority order:
1. SMPTE timecode (LTC/VITC from file)
2. Sidecar `.ALE` file (Avid Log Exchange)
3. Embedded XMP/EXIF
4. Filename pattern matching:
   - Narrative: `A001C001_230415_R1BK.mxf`, `Sc01_ShA_T3_CamA.mov`
   - Documentary: `RickRidgeway_Day1_IntA_001.mp4`, `BROLL_Day1_Forest_001.mov`
   - Output confidence score 0–1 per field; < 0.5 shows yellow in UI

**4. Proxy generator** using VideoToolbox + AVFoundation:
- Target: H.264 High Profile, 1920×1080, 8Mbps VBR, AAC 48kHz stereo
- Performance: ≥ 10x realtime for ProRes; ≥ 4x for ARRIRAW/BRAW
- Max 4 concurrent proxy jobs (configurable)
- Verify proxy checksum after write; update proxyStatus accordingly

**5. Progress reporting**
- Write to `~/Library/Application Support/SLATE/ingest.json`
- Format: `{ active: [{filename, progress, stage}], queued: N, errors: [] }`
- Desktop app polls this to animate menu bar icon

---

## SECTION C4 — DESKTOP UI (SwiftUI, macOS 14+)

Build after ingest engine is passing Checkpoint 2 (see Section C8).

### App architecture
```
apps/desktop/Sources/
├── SLATECore/       # Business logic — no UIKit/SwiftUI imports
│   ├── ProjectManager.swift
│   ├── IngestManager.swift
│   ├── SyncManager.swift       # Thin wrapper over Codex sync-engine package
│   ├── AIManager.swift         # Thin wrapper over Codex ai-pipeline package
│   ├── AssemblyEngine.swift
│   └── ExportWriter.swift
└── SLATEUI/         # All SwiftUI views
    ├── MainWindowView.swift     # Three-panel NavigationSplitView
    ├── SidebarView.swift        # Scene/subject list with completion bars
    ├── TakeBrowserView.swift    # Take rows with score pills + waveform strip
    ├── InspectorView.swift      # Right panel: sync, scores, actions, notes
    ├── ProxyPlayerView.swift    # AVKit + frame-accurate scrub + annotation pins
    ├── WaveformSyncEditor.swift # Manual sync override (red-confidence clips)
    ├── AssemblyPreviewView.swift
    └── MenuBarManager.swift     # Persistent menu bar icon
```

### Three-panel main window
- Sidebar (200pt): mode toggle [Narrative|Documentary], scene/subject list,
  filter toggles (Circled only, Show deprioritized)
- Take Browser (flex): header with scene name + take count + sync status,
  view tabs [Takes|Waveform|Coverage], take rows, bottom bar with assembly button
- Inspector (260pt): sync confidence pill, score breakdown bars with reasoning,
  Circle/Flag/Deprioritize buttons, notes textarea, export format badges

### Keyboard shortcuts
```
Space         — play/pause proxy
← →           — frame step
Shift+← →    — clip step in assembly
C             — circle selected take
F             — flag selected take
X             — mark selected take
D             — deprioritize selected take
⌘E            — export assembly
⌘K            — open share link generator
↑ ↓           — navigate scenes/subjects in sidebar
```

### Performance requirements for UI
- Take browser must render 500 clips in < 200ms (use List with lazy loading)
- Proxy player must start in < 500ms (pre-buffer next take while reviewing current)
- Inspector must update instantly on take selection (no async fetch — data preloaded)

---

## SECTION C5 — ASSEMBLY ENGINE

```swift
// AssemblyEngine.swift

// NARRATIVE: ordered by scene → setup → circled take (or highest score)
// DOCUMENTARY: ordered by subject → topic tag → content density score
// Both: produce Assembly struct → ExportWriter

// Assembly struct:
struct Assembly {
  let id: UUID
  let projectId: UUID
  let name: String
  let mode: ProjectMode
  let clips: [AssemblyClip]
  let createdAt: Date
  let version: Int
}

struct AssemblyClip {
  let clipId: UUID
  let inPoint: CMTime
  let outPoint: CMTime
  let role: String    // "primary", "broll", "interview"
  let sceneLabel: String
}

// ASSEMBLY PREVIEW: AVMutableComposition from proxy files
// User can drag to reorder, trim in/out points
// Every export creates AssemblyVersion in DB for recall
```

---

## SECTION C6 — NLE EXPORT WRITERS

All four formats. Implement in this order (highest priority first):

**FCPXML 1.11** (Final Cut Pro 10.6+)
- One asset per clip referencing proxy path
- Audio roles: dialogue.boom, dialogue.lav, dialogue.mix
- Circle/Flag/Deprioritized as FCP keywords (not reject)
- Annotations as timeline markers
- Dry-run validation mode (used in tests)

**CMX 3600 EDL** (Avid Media Composer + Premiere Pro fallback)
- Standard CMX format, one event per clip
- FROM CLIP NAME comment with scene/take label
- Reel names ≤ 8 chars (use clip ID prefix)

**AAF** (Avid audio multi-track)
- V1, A1(boom), A2(boom-R), A3(lav1), A4(lav2)
- Preserve source audio paths for Avid re-link

**Premiere Pro XML**
- Sequence settings match source frame rate + resolution
- Markers for annotations
- Essential Sound: Dialogue role on all clips
- Productions folder structure: bins per scene/subject

**DaVinci Resolve XML**
- Media pool bins per scene (narrative) or subject (documentary)
- Smart bins: "Circled Takes", "Needs Review"
- Color flags: Green=circled, Yellow=flagged, Red=deprioritized

---

## SECTION C7 — INTEGRATION WITH CODEX AND GEMINI OUTPUTS

### Consuming Codex sync-engine:
Read `contracts/sync-api.json` when it exists. Implement:
```swift
// SyncManager.swift — thin wrapper, do not reimplement the algorithm
import SLATESyncEngine  // Codex package

class SyncManager {
  func syncClip(_ clip: Clip, audioURL: URL) async -> SyncResult {
    // call Codex engine, return SyncResult, write to DB
  }
  func overrideSync(_ clip: Clip, offsetFrames: Int) async {
    // write manual sync result with confidence: .high
  }
}
```

### Consuming Codex ai-pipeline:
Read `contracts/ai-scores-api.json` when it exists. Implement:
```swift
// AIManager.swift — thin wrapper
import SLATEAIPipeline  // Codex package

class AIManager {
  func scoreClip(_ clip: Clip) async -> AIScores {
    // call Codex pipeline, return AIScores, write to DB
  }
}
```

### Consuming Gemini web-api:
Read `contracts/web-api.json` when it exists. Implement:
```swift
// ShareLinkManager.swift
func generateShareLink(scope: ShareScope, permissions: LinkPermissions) async -> URL {
  // call Gemini's Supabase Edge Function for token generation
  // return https://slate.app/review/{token}
}
```

---

## SECTION C8 — CHECKPOINTS

Work in strict order. Stop at each checkpoint and verify.

```
CHECKPOINT C0 — Day 1
  [ ] Monorepo initialized and pushed
  [ ] AGENT_CLAUDE.md, AGENT_CODEX.md, AGENT_GEMINI.md written
  [ ] contracts/data-model.json written and valid JSON
  [ ] packages/shared-types TypeScript types compiling
  [ ] packages/shared-types Swift types compiling and Codable
  SIGNAL TO OTHER AGENTS: "C0 complete — data model contract published"

CHECKPOINT C1 — End of Week 1
  [ ] Ingest daemon detecting files via FSEvents
  [ ] Checksum verification working on all test files
  [ ] Metadata parser handling all filename patterns
  [ ] Proxy generation working for ProRes + H.264

CHECKPOINT C2 — End of Week 2
  [ ] Main window three-panel layout matching UI prototype
  [ ] Narrative mode fully navigable
  [ ] Documentary mode fully navigable
  [ ] Mode toggle preserves all data
  [ ] Proxy player working with frame-accurate scrub

CHECKPOINT C3 — End of Week 3
  [ ] Assembly engine producing correct clip order (both modes)
  [ ] All four NLE exports importing cleanly into actual NLEs
  SIGNAL TO GEMINI: "C3 complete — ready to consume web-api contract"

CHECKPOINT C4 — End of Week 4
  [ ] Share link generation working (consuming Gemini's edge function)
  [ ] Sync confidence UI wired to Codex sync engine output
  [ ] AI scores UI wired to Codex pipeline output (Phase 2)
  [ ] benchmark.sh all passing within targets
```

---

## SECTION C9 — IMPROVEMENT BACKLOG (SCAN AFTER EACH FEATURE)

After completing each feature above, scan this list and implement the highest-
priority applicable item before declaring done.

```
BACKLOG — Claude Code

Priority 1 (implement before Phase 1 ships):
  [ ] HEVC proxy encoding option (smaller files, same hardware acceleration)
  [ ] Parallel multi-file ingest (currently sequential per queue)
  [ ] Undo/redo for all review actions (circle, flag, deprioritize)
  [ ] Batch operations: select multiple takes, apply action to all
  [ ] Scene completion report: exportable PDF of coverage status

Priority 2 (implement in Phase 2 session):
  [ ] Assembly diff view: compare two versions side by side
  [ ] Per-clip in/out trim in assembly preview with proxy playback
  [ ] Multiple assembly versions with branch/merge
  [ ] "Repair project" command: re-verify checksums, regenerate missing proxies
  [ ] ALE sidecar writer: export SLATE metadata as .ALE for Avid import

Priority 3 (Phase 3):
  [ ] Paper cut PDF export (transcript-based, for documentary producers)
  [ ] Shot list import from ShotGrid/Ftrack (auto-populate narrative_setups)
  [ ] Google Drive auto-export of assembly files on approval
  [ ] Airtable sync: push clip metadata to MTP's Airtable base appSOIQbLdfE9nPWG
  [ ] Frame.io two-way annotation sync

Priority 4 (future):
  [ ] Real-time on-set scoring (requires direct camera feed)
  [ ] Multi-angle optimization: recommend best angle per moment
  [ ] SOC 2 audit log: every file operation timestamped and immutable
  [ ] AES-256 encryption for proxy files at rest
```

---

# ═══════════════════════════════════════════════════════════════
# PROMPT 2 — OPENAI CODEX
# Role: AI/ML Engine, Audio Sync, Scoring Pipeline
# ═══════════════════════════════════════════════════════════════

## YOUR IDENTITY IN THIS SYSTEM

You are the ML Engine agent for SLATE. You own:
- `packages/sync-engine/` — the audio sync algorithm (Swift package)
- `packages/ai-pipeline/` — the vision/audio scoring pipeline (Swift + Python)
- All model wrappers: CoreML, MLX, WhisperX, custom classifiers
- The test harnesses that validate sync accuracy and scoring quality

You do NOT own:
- The SwiftUI desktop UI (Claude Code wires your engine into the UI)
- The web portal (Gemini owns this)
- The database schema (Gemini owns this)
- The ingest daemon or NLE export (Claude Code owns these)

You have one critical dependency before you begin: wait for
`contracts/data-model.json` to exist (Claude Code publishes it). Read it
fully before building anything — your APIs must consume and produce the
exact types defined there.

After each of your engines is complete, you write a contract file so
Claude Code can wire your output into the desktop UI.

---

## SECTION X0 — GROUND RULES

You are building the AI brain of SLATE. Your code runs locally on Apple Silicon
(M4 Max is the benchmark machine). No cloud inference is permitted by default
— all models run on-device via CoreML / MLX / MPS.

### Rules specific to your domain:

1. Test harness before algorithm. Build the test cases (with known-answer
   inputs) before writing a single line of the algorithm being tested.
   No algorithm ships without a passing test suite.

2. Confidence scores are mandatory. Every output your engine produces must
   include a confidence score. Never return a result without telling the
   caller how confident the system is. The UI uses confidence to decide
   whether to auto-apply or require human review.

3. Graceful degradation, never failure. If the sync algorithm can't
   reach high confidence, return low confidence + reason. Never throw.
   The workflow must never be blocked by an AI failure.

4. Human overrides are law. If a user manually overrides a sync result
   or score, that override is stored with `confidence: "manual"` and is
   never re-overwritten by subsequent automated passes.

5. Model versions in every output. Every AIScores object must include
   `modelVersion`. This enables debugging when a model update changes
   behavior on a production.

---

## SECTION X1 — READ BEFORE STARTING

```bash
# Step 1: Wait for this file to exist — do not start until it does:
cat contracts/data-model.json

# Step 2: Read the sync engine spec in full
# Step 3: Build test harness (Section X2)
# Step 4: Build sync algorithm (Section X3)
# Step 5: Write sync API contract
# Step 6: Build AI scoring pipeline (Section X4)
# Step 7: Write AI scores API contract
```

---

## SECTION X2 — SYNC TEST HARNESS (BUILD FIRST)

Location: `scripts/test-sync.sh` and `packages/sync-engine/Tests/`

Create 8 test cases with known-answer audio/video pairs. For each test,
record the ground-truth offset in frames. The test passes when your algorithm
returns the correct offset within ±1 frame.

```swift
// SyncEngineTests.swift

// Test case structure:
struct SyncTestCase {
  let name: String
  let videoURL: URL          // Camera reference audio track
  let audioURL: URL          // External recorder (boom/lav)
  let groundTruthOffsetFrames: Int   // Known correct answer
  let fps: Double
  let expectedMinConfidence: SyncConfidence  // What confidence do we expect?
}

// Required test cases:
let testCases: [SyncTestCase] = [
  .init(name: "perfect_slate",
        groundTruthOffsetFrames: 0,
        expectedMinConfidence: .high),

  .init(name: "delayed_clap_3sec",
        groundTruthOffsetFrames: 72,  // 3s at 24fps
        expectedMinConfidence: .high),

  .init(name: "double_clap_use_second",
        groundTruthOffsetFrames: 48,  // second clap
        expectedMinConfidence: .medium),

  .init(name: "missed_slate_timecode_fallback",
        groundTruthOffsetFrames: 0,   // timecode sync
        expectedMinConfidence: .high),

  .init(name: "noisy_set_snr_minus_6db",
        groundTruthOffsetFrames: 24,
        expectedMinConfidence: .medium),

  .init(name: "multicam_two_cameras",
        groundTruthOffsetFrames: 0,   // both cams sync to same recorder
        expectedMinConfidence: .high),

  .init(name: "long_take_20min_drift",
        groundTruthOffsetFrames: 0,   // drift < 1 frame per 5 min
        expectedMinConfidence: .high),

  .init(name: "triple_iso_boom_two_lavs",
        groundTruthOffsetFrames: 0,
        expectedMinConfidence: .high),
]

// Acceptance: all 8 must pass within ±1 frame before sync engine ships
// Log per test: method used, confidence returned, offset returned, error in frames
```

Generate synthetic test audio using AVAudioEngine if real test footage is not
available. The clap transient can be a 10ms 1kHz sine burst. The camera
reference track can be a pink noise signal with the same burst at the known offset.

---

## SECTION X3 — AUDIO SYNC ENGINE

Location: `packages/sync-engine/Sources/SLATESyncEngine/`

Build as a Swift package that Claude Code imports into the desktop app.
The sync engine must be testable independently (no UI dependencies).

### Core algorithm — implement in this exact order:

```swift
// AudioSyncEngine.swift

public struct SyncEngine {
  public func syncClip(
    videoURL: URL,
    audioFiles: [URL],        // One per ISO track
    fps: Double
  ) async throws -> SyncResult {

    // STEP 1: Try SMPTE timecode sync
    if let result = try await attemptTimecodeSync(videoURL, audioFiles, fps) {
      return result  // confidence: .high if both TC present and agree < 10ms
    }

    // STEP 2: Try clap/onset detection
    if let result = try await attemptClapSync(videoURL, audioFiles[0], fps) {
      return result  // confidence: .high if correlation > 0.85, .medium if 0.60-0.85
    }

    // STEP 3: Full-file waveform correlation (fallback)
    let result = try await fullFileCorrelation(videoURL, audioFiles[0], fps)
    // confidence: .medium if peak > 0.70, .low/.manual_required if below

    return result
  }
}

// STEP 1 — Timecode sync
private func attemptTimecodeSync(...) async throws -> SyncResult? {
  // Read camera LTC/VITC via AVAsset metadata
  // Read audio timecode (Sound Devices, Ambient, Zoom metadata)
  // If both present and agree within 10ms: return high-confidence sync
  // Else: return nil (fall through to clap)
}

// STEP 2 — Clap detection via onset detection
private func attemptClapSync(...) async throws -> SyncResult? {
  // Compute onset strength via spectral flux (FFT over 20ms windows)
  // Find highest-energy transient in first 10 seconds of each file
  // Cross-correlate 100ms window around each detected transient
  // Correlation > 0.85: return high confidence
  // 0.60-0.85: return medium confidence
  // < 0.60: return nil (fall through to full-file)
}

// STEP 3 — Full-file waveform cross-correlation
private func fullFileCorrelation(...) async throws -> SyncResult {
  // Downsample both tracks to 1kHz mono (fast cross-correlation)
  // Search window: ±30 seconds
  // Use Accelerate.framework vDSP for FFT-based correlation
  // Peak > 0.70: medium confidence; < 0.70: manual_required
}

// STEP 4 — Drift correction (for takes > 5 minutes)
private func correctDrift(
  result: SyncResult,
  videoURL: URL,
  audioURL: URL,
  fps: Double
) async throws -> SyncResult {
  // Divide take into 1-minute segments
  // Compute sync offset at each segment boundary
  // Linear interpolation if drift > 5ms/minute
  // Report drift in PPM via result.driftPPM
}

// STEP 5 — Multi-track role assignment
public func assignAudioRoles(tracks: [URL]) async -> [AudioTrack] {
  // For each track: compute RMS + spectral centroid over 30s sample
  // High RMS + broad spectrum = boom
  // High RMS + narrow spectrum (speech-range) = lav
  // Low RMS = room/safety
  // Return AudioTrack[] with role assigned
}
```

### Performance target: < 30 seconds for a 10-minute take on M4 Max

Use Accelerate.framework `vDSP_conv` and `vDSP_fft_zrip` for all FFT operations.
Never use a pure-Swift FFT — Apple Silicon's Accelerate is dramatically faster.

---

## SECTION X4 — AI SCORING PIPELINE

Location: `packages/ai-pipeline/`

Build as a Swift package (Claude Code imports it). The Python model training
utilities live in `packages/ai-pipeline/python/` and are used offline to
export CoreML models — they do not run on the user's machine.

### Vision analysis (Swift + CoreML)

```swift
// VisionScorer.swift

public struct VisionScorer {
  // Models (CoreML .mlpackage files, included in package resources):
  // - YOLOv8n: face/object detection
  // - DepthAnythingV2Small: depth estimation for focus scoring
  // - SLATEQualityClassifier: custom focus/exposure/stability classifier

  public func scoreClip(proxyURL: URL, fps: Double) async throws -> VisionScores {
    // 1. Sample proxy at 2fps (configurable: 1–5fps)
    // 2. For each sampled frame:
    //    a. Run YOLO: detect faces, get bounding boxes
    //    b. Run DepthAnything: get depth map
    //    c. Score focus: sharpness of face region vs background
    //    d. Score exposure: histogram analysis (clip below 5 / above 250)
    //    e. Score stability: optical flow magnitude between consecutive frames
    // 3. Aggregate per-frame scores:
    //    - Focus: weighted toward frames with detected faces
    //    - Exposure: worst-frame penalty (one severely clipped frame fails the take)
    //    - Stability: penalize >15px optical flow in face region
    // 4. Return VisionScores with per-frame data for UI display
  }
}
```

### Audio quality analysis (Swift)

```swift
// AudioScorer.swift

public struct AudioScorer {
  public func scoreAudio(syncedAudioURL: URL) async throws -> AudioScoreResult {
    // 1. Compute RMS per 1-second window
    // 2. Detect clipping: samples >= 0.999 full scale
    // 3. Detect noise floor: lowest RMS window (should be < -60dBFS)
    // 4. Detect proximity issues: absence of LF energy (<200Hz) on dialogue track
    // 5. Detect missing channels: near-zero RMS on any assigned track
    // 6. Return scores + ScoreReason[] with timecodes for each flag
  }
}
```

### Performance scoring — Narrative mode (Phase 2)

```swift
// PerformanceScorer.swift

public struct PerformanceScorer {
  // Requires: transcription complete (transcriptId set on clip)
  // Requires: script text loaded (NarrativeProject.scriptPath set)

  public func scorePerformance(
    transcript: Transcript,
    scriptText: String,
    clipMode: ProjectMode
  ) async throws -> PerformanceScoreResult {
    // 1. Tokenize script and transcript
    // 2. Find best alignment (Smith-Waterman local alignment)
    // 3. Detect: flubs (wrong words), missed lines (gaps), ad-libs (insertions)
    // 4. Prosody: speech rate (words/min), pause duration, energy variance
    // 5. Return score + ScoreReason[] with timecodes
  }
}
```

### Content density scoring — Documentary mode (Phase 2)

```swift
// ContentDensityScorer.swift

public struct ContentDensityScorer {
  // Uses sentence-transformers (Python, exported as CoreML embedding model)

  public func scoreContentDensity(
    clip: Clip,
    allClipsForSubject: [Clip]
  ) async throws -> ContentDensityResult {
    // 1. Embed transcript segments via local CoreML embedding model
    // 2. Compute cosine similarity vs all other clips from same subject
    // 3. High similarity to existing clips = low density (duplicate content)
    // 4. Score: 100 = completely unique, 0 = exact duplicate
    // 5. Detect emphasis peaks: energy spikes in prosody signal
    // 6. Flag high-value moments: high energy + unique content
  }
}
```

### Write the AI scores contract after pipeline is working:

```json
// contracts/ai-scores-api.json
{
  "version": "1.0",
  "author": "openai-codex",
  "swiftPackage": "SLATEAIPipeline",
  "publicAPI": {
    "scoreClip": {
      "input": "Clip (from data-model.json)",
      "output": "AIScores (from data-model.json)",
      "async": true,
      "throws": true,
      "notes": "Call after proxy generation and sync are complete"
    }
  },
  "models": {
    "vision": "YOLOv8n-CoreML + DepthAnythingV2Small-CoreML + SLATEQualityClassifier-v1.mlpackage",
    "audio": "Swift AVFoundation + Accelerate (no CoreML model needed)",
    "performance": "Phase 2: requires transcription",
    "contentDensity": "Phase 2: requires transcription + sentence-transformer CoreML"
  },
  "performanceTargets": {
    "visionScoring_10minTake": "< 45 seconds on M4 Max",
    "audioScoring_10minTake": "< 10 seconds on M4 Max",
    "transcription_10minTake": "< 3 minutes (WhisperX MLX)"
  }
}
```

---

## SECTION X5 — TRANSCRIPTION ENGINE (Phase 2)

Location: `packages/ai-pipeline/Sources/SLATEAIPipeline/Transcriber.swift`

```swift
// Transcriber.swift

public struct Transcriber {
  // Uses MLX-Whisper (Apple Silicon optimized WhisperX port)
  // Speaker diarization: pyannote.audio via Python subprocess

  public func transcribeClip(_ clip: Clip) async throws -> Transcript {
    // 1. Extract audio from synced audio file
    // 2. Run MLX-Whisper (whisper-large-v3 quantized to 4-bit for speed)
    // 3. Output: [{start, end, text}] with word-level timestamps
    // 4. Run speaker diarization (via Python subprocess — pyannote/speaker-diarization-3.1)
    // 5. Merge: assign speaker label to each word segment
    // 6. Map to production timecode via clip.sourceTimecodeStart offset
    // 7. Store in Supabase transcripts table (Gemini's schema)
    // 8. Update clip.transcriptId
  }
}

// Privacy requirement: transcription NEVER calls cloud APIs by default.
// Hosted Whisper API must be an explicit user opt-in with consent dialog.
```

---

## SECTION X6 — CHECKPOINTS

```
CHECKPOINT X0 — Before starting (wait for Claude Code signal)
  [ ] contracts/data-model.json exists and is valid JSON
  [ ] packages/sync-engine/ directory exists in repo
  SIGNAL: "X0 ready — beginning sync engine"

CHECKPOINT X1 — Sync test harness (before algorithm)
  [ ] 8 test cases written with synthetic or real test audio
  [ ] Test runner script working (scripts/test-sync.sh)
  [ ] All tests fail (expected — algorithm not written yet)

CHECKPOINT X2 — Sync algorithm complete
  [ ] All 8 test cases passing within ±1 frame
  [ ] Performance benchmark < 30s for 10-minute take
  [ ] contracts/sync-api.json written and valid
  SIGNAL TO CLAUDE CODE: "X2 complete — sync-api contract published"

CHECKPOINT X3 — AI scoring pipeline complete (Phase 2)
  [ ] Vision scorer running on M4 Max within latency target
  [ ] Audio scorer running within latency target
  [ ] contracts/ai-scores-api.json written and valid
  SIGNAL TO CLAUDE CODE: "X3 complete — ai-scores-api contract published"

CHECKPOINT X4 — Transcription complete (Phase 2/3)
  [ ] WhisperX MLX running locally, producing word-level timestamps
  [ ] Speaker diarization assigning labels to dialogue
  [ ] Transcripts stored in Supabase (Gemini's schema)
```

---

## SECTION X7 — IMPROVEMENT BACKLOG

```
BACKLOG — OpenAI Codex

Priority 1 (implement before shipping Phase 1 sync engine):
  [ ] Smart slate detection: recognize digital slate displays (Denecke TC-1,
      Ambient ACN-TL) via OCR on first frames — more reliable than audio clap
  [ ] Pre-roll audio detection: use 2 seconds before clap as noise floor sample
      for noise reduction before correlation (improves noisy set accuracy)
  [ ] Confidence calibration: compare returned confidence vs ground truth on
      test set — if medium confidence is right 95% of the time, recalibrate
      thresholds upward
  [ ] Multi-language timecode: handle both 25fps (PAL) and 23.976/29.97 (NTSC)
      drop-frame timecode correctly

Priority 2 (Phase 2 AI scoring):
  [ ] Continuity checker: detect wardrobe changes between consecutive takes
      using DINO-v2 embeddings on clothing region crops
  [ ] Eyeline consistency: flag when actor eyeline changes between takes
      (likely indicates different director instruction)
  [ ] Lens flare detector: flag frames with lens flares as potential B-take
  [ ] Wind noise detector: classify audio tracks for wind contamination
      (high LF energy + periodic amplitude modulation pattern)

Priority 3 (Phase 2/3 improvements):
  [ ] Custom model fine-tuning pipeline: accept editor circle selections as
      training signal, fine-tune the quality classifier on production data
  [ ] Moment detection for documentary: detect emotional peaks using facial
      action coding (AU12, AU6 for smiles; AU4, AU17 for distress)
  [ ] Music detection: flag clips with significant background music
      (impacts editorial usability — music can't be easily cut around)
  [ ] Accent-robust transcription: fine-tune Whisper on specific accents
      present in production (e.g. non-native English speakers)

Priority 4 (research, Phase 3+):
  [ ] Real-time scoring: reduce scoring latency to < 5 seconds for
      on-set live quality monitoring via camera direct feed
  [ ] Multi-angle optimization: given N synchronized angles, recommend
      best angle per second using attention/gaze direction analysis
  [ ] Dialogue isolation: source separation to extract clean dialogue
      track from noisy ISO, improving transcription quality
```

---

# ═══════════════════════════════════════════════════════════════
# PROMPT 3 — GOOGLE GEMINI CODE ASSIST
# Role: Web Portal, Cloud Infrastructure, Database, CI/CD
# ═══════════════════════════════════════════════════════════════

## YOUR IDENTITY IN THIS SYSTEM

You are the Infrastructure and Web agent for SLATE. You own:
- `apps/web/` — the Next.js 14 web review portal
- `supabase/migrations/` — all database schema migrations
- `supabase/functions/` — Supabase Edge Functions
- Cloudflare R2 proxy storage configuration
- CI/CD pipeline (GitHub Actions)
- The tRPC API layer between web and database
- Real-time collaboration via Supabase Realtime

You do NOT own:
- The macOS desktop app (Claude Code)
- The audio sync or AI scoring engines (Codex)
- The ingest daemon (Claude Code)

You have one critical dependency: `contracts/data-model.json` must exist
before you write the database schema. Claude Code publishes this. When it
exists, proceed immediately — every day of delay is a day the other agents
wait for your schema.

After your API layer and Realtime setup are complete, you write two contract
files that Claude Code and Codex consume.

---

## SECTION G0 — GROUND RULES

1. Schema changes go in migrations only. Never modify the database directly.
   All schema changes go in `supabase/migrations/` with sequential numbering.
   The other agents depend on the schema being reproducible with `supabase db reset`.

2. No original media ever touches the cloud. Proxies only. Cloudflare R2
   receives only proxy files (H.264 MP4 and HLS segments). Never implement
   any feature that could result in original camera files being uploaded.

3. Signed URLs, never public. Proxy files in R2 are never publicly accessible.
   All proxy access goes through signed URLs with 24-hour expiry, generated
   by your Supabase Edge Function.

4. Realtime is best-effort. Supabase Realtime on a film set may drop connections.
   The web portal must degrade gracefully — annotations posted offline sync
   when connection restores. Never block a user action on Realtime connectivity.

5. Guest-first design. The most common user of the web portal is a director or
   exec who received a share link. They have no account. The review page must
   be fully functional without login. Authentication is only required for the
   internal dashboard.

---

## SECTION G1 — READ BEFORE STARTING

```bash
# Step 1: Wait for contracts/data-model.json to exist
cat contracts/data-model.json

# Step 2: Build database schema (Section G2) — other agents wait for this
# Step 3: Build Supabase Edge Functions (Section G3)
# Step 4: Build Next.js web portal (Section G4)
# Step 5: Write web-api and realtime-events contracts
# Step 6: Build CI/CD pipeline (Section G5)
```

---

## SECTION G2 — DATABASE SCHEMA

Location: `supabase/migrations/`

Create `001_initial_schema.sql` immediately after reading data-model.json.
This is the file all other agents depend on.

```sql
-- 001_initial_schema.sql

-- Projects
CREATE TABLE projects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  mode TEXT NOT NULL CHECK (mode IN ('narrative', 'documentary')),
  production_company TEXT,
  director TEXT,
  dp TEXT,
  script_path TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Universal clips table
CREATE TABLE clips (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  checksum TEXT NOT NULL UNIQUE,
  source_path TEXT NOT NULL,
  source_size BIGINT NOT NULL,
  source_format TEXT NOT NULL,
  source_fps NUMERIC(8,3) NOT NULL,
  source_timecode_start TEXT,
  duration NUMERIC(10,3) NOT NULL,
  proxy_path TEXT,
  proxy_url TEXT,                    -- Cloudflare R2 URL (set when uploaded)
  proxy_status TEXT DEFAULT 'pending' CHECK (proxy_status IN ('pending','processing','ready','error')),
  proxy_checksum TEXT,
  narrative_meta JSONB,
  documentary_meta JSONB,
  audio_tracks JSONB NOT NULL DEFAULT '[]',
  sync_result JSONB NOT NULL DEFAULT '{"confidence":"unsynced","method":"none","offsetFrames":0,"driftPPM":0}',
  synced_audio_path TEXT,
  ai_scores JSONB,
  transcript_id UUID,
  ai_processing_status TEXT NOT NULL DEFAULT 'pending',
  review_status TEXT NOT NULL DEFAULT 'unreviewed' CHECK (
    review_status IN ('unreviewed','circled','flagged','x','deprioritized')
  ),
  approval_status TEXT NOT NULL DEFAULT 'pending' CHECK (
    approval_status IN ('pending','reviewed','approved')
  ),
  approved_by TEXT,
  approved_at TIMESTAMPTZ,
  ingested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Narrative hierarchy
CREATE TABLE narrative_scenes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  scene_number TEXT NOT NULL,
  description TEXT,
  location TEXT,
  day_night TEXT CHECK (day_night IN ('day','night','dawn','dusk')),
  interior_exterior TEXT CHECK (interior_exterior IN ('int','ext','int/ext')),
  completion_status TEXT NOT NULL DEFAULT 'not_started' CHECK (
    completion_status IN ('not_started','in_progress','complete')
  ),
  sort_order INTEGER NOT NULL DEFAULT 0,
  UNIQUE(project_id, scene_number)
);

CREATE TABLE narrative_setups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  scene_id UUID NOT NULL REFERENCES narrative_scenes(id) ON DELETE CASCADE,
  shot_code TEXT NOT NULL,
  description TEXT,
  lens TEXT,
  frame_size TEXT,
  circled_take_id UUID REFERENCES clips(id),
  sort_order INTEGER NOT NULL DEFAULT 0
);

-- Clip → setup junction (a clip belongs to exactly one setup in narrative mode)
CREATE TABLE clip_setups (
  clip_id UUID NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
  setup_id UUID NOT NULL REFERENCES narrative_setups(id) ON DELETE CASCADE,
  PRIMARY KEY (clip_id, setup_id)
);

-- Documentary hierarchy
CREATE TABLE shooting_days (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  day_number INTEGER NOT NULL,
  date DATE,
  location TEXT,
  UNIQUE(project_id, day_number)
);

CREATE TABLE documentary_subjects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shooting_day_id UUID NOT NULL REFERENCES shooting_days(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  role TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE documentary_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_id UUID NOT NULL REFERENCES documentary_subjects(id) ON DELETE CASCADE,
  label TEXT NOT NULL,
  assembly_order JSONB NOT NULL DEFAULT '[]'  -- ordered clip UUIDs
);

-- Clip → session junction (documentary mode)
CREATE TABLE clip_sessions (
  clip_id UUID NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
  session_id UUID NOT NULL REFERENCES documentary_sessions(id) ON DELETE CASCADE,
  PRIMARY KEY (clip_id, session_id)
);

-- Annotations (collaborative review)
CREATE TABLE annotations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clip_id UUID NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  user_display_name TEXT NOT NULL,
  timecode_in TEXT NOT NULL,
  timecode_out TEXT,
  body TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'text' CHECK (type IN ('text','voice')),
  voice_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at TIMESTAMPTZ
);

-- Transcripts (Codex populates)
CREATE TABLE transcripts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clip_id UUID NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
  segments JSONB NOT NULL DEFAULT '[]',  -- [{start, end, speaker, text, words}]
  model_version TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Share links (web portal access)
CREATE TABLE share_links (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  scope TEXT NOT NULL CHECK (scope IN ('project','scene','subject','assembly')),
  scope_id TEXT,
  token TEXT NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(24), 'base64url'),
  expires_at TIMESTAMPTZ,
  password_hash TEXT,
  permissions JSONB NOT NULL DEFAULT '{"canComment":true,"canFlag":true,"canRequestAlternate":false}',
  created_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  view_count INTEGER NOT NULL DEFAULT 0,
  last_viewed_at TIMESTAMPTZ
);

-- Assembly versions (Claude Code populates)
CREATE TABLE assembly_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  assembly_json JSONB NOT NULL,
  nle_format TEXT,
  created_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes (performance-critical)
CREATE INDEX idx_clips_project ON clips(project_id);
CREATE INDEX idx_clips_status ON clips(review_status);
CREATE INDEX idx_clips_checksum ON clips(checksum);
CREATE INDEX idx_clips_approval ON clips(approval_status);
CREATE INDEX idx_annotations_clip ON annotations(clip_id);
CREATE INDEX idx_annotations_created ON annotations(created_at DESC);
CREATE INDEX idx_share_links_token ON share_links(token);
CREATE INDEX idx_transcripts_clip ON transcripts(clip_id);
CREATE INDEX idx_narrative_scenes_project ON narrative_scenes(project_id, sort_order);

-- Full-text search on transcripts (Phase 2/3)
CREATE INDEX idx_transcripts_fts ON transcripts USING gin(segments);

-- Realtime (enable after creating tables)
ALTER PUBLICATION supabase_realtime ADD TABLE annotations;
ALTER PUBLICATION supabase_realtime ADD TABLE clips;
ALTER PUBLICATION supabase_realtime ADD TABLE share_links;

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER clips_updated_at BEFORE UPDATE ON clips
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER projects_updated_at BEFORE UPDATE ON projects
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

Create `seed.sql` with:
- One narrative project ("Plantman & Blondie test")
- One documentary project ("Ridgeway doc test")
- 3 scenes / 5 subjects, 5 clips each
- Mix of review statuses (circled, flagged, unreviewed)
- 2 share links (one expired, one valid)

---

## SECTION G3 — SUPABASE EDGE FUNCTIONS

Location: `supabase/functions/`

### Function 1: generate-share-link

```typescript
// supabase/functions/generate-share-link/index.ts

// Called by: Claude Code desktop app (authenticated)
// Input: { projectId, scope, scopeId, expiryHours, password?, permissions }
// Output: { token, url, expiresAt }

// Logic:
// 1. Verify caller is authenticated (check JWT)
// 2. Verify caller has access to projectId
// 3. Generate token (crypto.randomUUID() → base64url encode)
// 4. Hash password with bcrypt if provided
// 5. Insert into share_links
// 6. Return { token, url: `https://slate.app/review/${token}`, expiresAt }
```

### Function 2: sign-proxy-url

```typescript
// supabase/functions/sign-proxy-url/index.ts

// Called by: web portal (authenticated or via valid share token)
// Input: { clipId, shareToken? }
// Output: { signedUrl, expiresAt }

// Logic:
// 1. Verify access: authenticated user OR valid share token
// 2. Fetch clip.proxy_url from DB
// 3. Generate Cloudflare R2 presigned URL (24h expiry)
// 4. Return signed URL (never expose R2 credentials to client)

// Security: this function is the ONLY path to proxy access
// Never return public R2 URLs directly from the database
```

### Function 3: sync-annotation (Realtime bridge)

```typescript
// supabase/functions/sync-annotation/index.ts

// Called by: web portal when a guest posts an annotation
// Input: { shareToken, annotation: AnnotationCreate }
// Output: { id, createdAt }

// Logic:
// 1. Validate share token (not expired, has canComment permission)
// 2. Sanitize annotation body (strip HTML, max 2000 chars)
// 3. Insert annotation with user_id = "guest:{token_prefix}"
// 4. Supabase Realtime fires automatically on INSERT
// 5. Return created annotation ID
```

---

## SECTION G4 — NEXT.JS WEB REVIEW PORTAL

Location: `apps/web/`

Use Next.js 14 App Router, TypeScript, Tailwind CSS, shadcn/ui.

### App structure

```
apps/web/
├── app/
│   ├── layout.tsx               # Root layout, fonts, metadata
│   ├── page.tsx                 # → redirect to /login or /dashboard
│   ├── login/page.tsx           # Supabase Auth UI (email magic link)
│   ├── dashboard/
│   │   ├── page.tsx             # Project list (authenticated users only)
│   │   └── [projectId]/page.tsx # Project detail + share link management
│   └── review/
│       └── [token]/
│           ├── page.tsx         # Guest review page
│           ├── loading.tsx      # Skeleton while proxies load
│           └── error.tsx        # Expired link / wrong password
├── components/
│   ├── Player/
│   │   ├── HLSPlayer.tsx        # hls.js adaptive streaming
│   │   ├── ScrubBar.tsx         # Custom scrub bar + annotation ticks
│   │   └── TimecodeOverlay.tsx  # SMPTE timecode display on player
│   ├── Review/
│   │   ├── AnnotationPanel.tsx  # Side panel for annotation thread
│   │   ├── AnnotationPin.tsx    # Inline annotation input + submit
│   │   ├── FlagControls.tsx     # Circle/Flag buttons (if permitted)
│   │   └── PresenceBar.tsx      # "N people viewing" indicator
│   ├── Assembly/
│   │   ├── AssemblyClipList.tsx # Ordered clip list with thumbnails
│   │   └── ClipThumbnail.tsx    # Proxy thumbnail with timecode
│   └── UI/
│       ├── ScorePill.tsx        # Score badge (green/amber/red)
│       └── PasswordGate.tsx     # Password prompt for protected links
├── lib/
│   ├── supabase/
│   │   ├── client.ts            # Browser Supabase client
│   │   └── server.ts            # Server Supabase client (for RSC)
│   ├── realtime.ts              # Realtime subscription hooks
│   ├── share-links.ts           # Token validation utilities
│   └── proxy.ts                 # Signed URL fetching
├── middleware.ts                # Token auth + rate limiting for /review
└── next.config.js
```

### Review page — core behavior

```typescript
// app/review/[token]/page.tsx

// SERVER COMPONENT — validate token server-side before any client JS runs

// 1. Fetch share_links WHERE token = params.token AND expires_at > NOW()
//    → 404 if not found
//    → Show PasswordGate component if password_hash is set

// 2. Fetch scoped content based on link.scope:
//    - 'project': all scenes/subjects + all clips
//    - 'scene': one scene + its setups + clips
//    - 'assembly': one assembly version + its ordered clips

// 3. Fetch proxy URLs via sign-proxy-url edge function (server-side)
//    Cache signed URLs with 20-hour revalidation (under 24h R2 expiry)

// 4. Render:
//    - Left: AssemblyClipList with thumbnails, timecodes, score pills
//    - Center: HLSPlayer with ScrubBar + TimecodeOverlay
//    - Right: AnnotationPanel with existing annotations

// 5. Client-side: subscribe to Supabase Realtime annotations channel
//    New annotations appear instantly without page refresh
```

### HLS Player

```typescript
// components/Player/HLSPlayer.tsx

// Use hls.js for adaptive streaming
// Configuration:
//   - Start level: auto (measure bandwidth first 2 segments)
//   - Max buffer: 30 seconds
//   - Low latency: false (this is VoD, not live)
//   - xhrSetup: add Authorization header with signed URL token

// Custom ScrubBar:
//   - Show annotation tick marks (colored dots per annotation type)
//   - Click anywhere: seek to that position + show nearby annotation
//   - Press N: drop annotation pin at current position
//   - Show frame number as well as SMPTE timecode on hover

// Performance: player must be interactive within 2 seconds of page load
// Preload first 5 seconds of next clip in list while current is playing
```

---

## SECTION G5 — CI/CD PIPELINE

Location: `.github/workflows/`

```yaml
# .github/workflows/ci.yml

# Triggers: push to main, PRs

# Jobs:
# 1. validate-contracts
#    - Check all contracts/ files are valid JSON
#    - Check contracts match their declared schemas
#
# 2. test-web
#    - cd apps/web && npm run build
#    - npm run type-check
#    - npm run test (Vitest unit tests)
#
# 3. test-supabase
#    - supabase start (local)
#    - supabase db reset (applies all migrations)
#    - Run seed.sql
#    - Verify seed data present via psql
#    - supabase db diff (ensure no schema drift)
#
# 4. deploy-web (main branch only)
#    - Deploy to Vercel production
#    - Run E2E tests via Playwright after deploy
#    - Slack notification on success/failure

# .github/workflows/benchmarks.yml
# Weekly scheduled run:
#    - Run scripts/benchmark.sh
#    - Post results as GitHub Actions summary
#    - Fail if any metric exceeds alert threshold
```

---

## SECTION G6 — WRITE CONTRACTS AFTER BUILDING

After the schema and API are complete, write these two files:

### contracts/web-api.json

```json
{
  "version": "1.0",
  "author": "gemini-code-assist",
  "description": "REST and Edge Function endpoints for desktop app and Codex to consume",
  "edgeFunctions": {
    "generateShareLink": {
      "url": "https://{project}.supabase.co/functions/v1/generate-share-link",
      "method": "POST",
      "auth": "Bearer {supabase_jwt}",
      "body": {
        "projectId": "string (UUID)",
        "scope": "project|scene|subject|assembly",
        "scopeId": "string|null",
        "expiryHours": "number (default: 168)",
        "password": "string|null",
        "permissions": {
          "canComment": "boolean",
          "canFlag": "boolean",
          "canRequestAlternate": "boolean"
        }
      },
      "response": {
        "token": "string",
        "url": "string (https://slate.app/review/{token})",
        "expiresAt": "string (ISO 8601)"
      }
    },
    "signProxyUrl": {
      "url": "https://{project}.supabase.co/functions/v1/sign-proxy-url",
      "method": "POST",
      "auth": "Bearer {supabase_jwt} OR X-Share-Token: {token}",
      "body": { "clipId": "string (UUID)" },
      "response": {
        "signedUrl": "string (Cloudflare R2 presigned URL)",
        "expiresAt": "string (ISO 8601, 24h from now)"
      }
    }
  }
}
```

### contracts/realtime-events.json

```json
{
  "version": "1.0",
  "author": "gemini-code-assist",
  "description": "Supabase Realtime event schema for all agents",
  "channels": {
    "annotations:{projectId}": {
      "events": {
        "INSERT": {
          "payload": "Annotation (from data-model.json)",
          "consumers": ["web-portal", "desktop-app"]
        },
        "UPDATE": {
          "payload": "Annotation (from data-model.json)",
          "consumers": ["web-portal"]
        }
      }
    },
    "clips:{projectId}": {
      "events": {
        "UPDATE": {
          "payload": "Clip (subset: id, reviewStatus, approvalStatus, aiScores, proxyStatus)",
          "consumers": ["web-portal", "desktop-app"],
          "note": "Desktop app subscribes to get web review changes in real time"
        }
      }
    }
  }
}
```

---

## SECTION G7 — CHECKPOINTS

```
CHECKPOINT G0 — Before starting (wait for data-model.json)
  [ ] contracts/data-model.json exists and is valid JSON
  SIGNAL: "G0 ready — beginning schema"

CHECKPOINT G1 — Schema complete (highest priority — unblocks all agents)
  [ ] 001_initial_schema.sql applies cleanly via supabase db reset
  [ ] seed.sql populates both project modes with test data
  [ ] Realtime enabled on clips and annotations tables
  SIGNAL TO ALL AGENTS: "G1 complete — schema available, run supabase db reset"

CHECKPOINT G2 — Edge functions complete
  [ ] generate-share-link working and returning valid tokens
  [ ] sign-proxy-url working and returning valid R2 presigned URLs
  [ ] sync-annotation working, Realtime fires on INSERT
  [ ] contracts/web-api.json written and valid
  SIGNAL TO CLAUDE CODE: "G2 complete — web-api contract published"

CHECKPOINT G3 — Web portal complete
  [ ] /review/[token] page loading and playing proxy via HLS
  [ ] Annotations appearing in real time across two browser tabs
  [ ] Password protection working
  [ ] Expired links returning 404
  [ ] contracts/realtime-events.json written and valid

CHECKPOINT G4 — CI/CD complete
  [ ] ci.yml running on PRs
  [ ] contract validation step passing
  [ ] Supabase migration test passing
  [ ] Deploy to Vercel working on main push
```

---

## SECTION G8 — IMPROVEMENT BACKLOG

```
BACKLOG — Google Gemini Code Assist

Priority 1 (before Phase 1 ships):
  [ ] Rate limiting on /review/[token] (max 100 requests/min per token)
  [ ] Share link audit log: record every view with timestamp + approximate
      IP geo (country level only — not stored precisely)
  [ ] Bandwidth-adaptive proxy: generate 2Mbps proxy tier for mobile
      viewers, auto-select based on measured connection speed
  [ ] Annotation thread UI: group annotations by timecode proximity
      (annotations within 2 seconds shown as a thread, not individual pins)

Priority 2 (Phase 2):
  [ ] Transcript search in web portal: full-text search over pg_trgm index,
      results show clip + timecode + highlighted snippet, click to jump
  [ ] Mobile-optimized review: PWA with offline annotation support,
      annotations sync when connection restores
  [ ] Multi-link analytics dashboard: show link owner which clips were
      viewed, for how long, and which generated the most annotations
  [ ] Webhook outbound: POST to Slack/email when annotation is posted by guest

Priority 3 (Phase 3):
  [ ] Google Drive export: on assembly approval, auto-export FCPXML to
      a configured Google Drive folder (OAuth 2.0 integration)
  [ ] Gmail share: generate pre-drafted Gmail with review link for easy
      sending to director/exec without leaving desktop app
  [ ] Airtable webhook receiver: accept clip status updates from Airtable
      (bi-directional sync for MTP base appSOIQbLdfE9nPWG)
  [ ] Frame.io two-way sync: pull Frame.io comments as SLATE annotations,
      push SLATE annotations back to Frame.io (requires Frame.io API key)

Priority 4 (Enterprise):
  [ ] SSO via SAML/OIDC (required for studio enterprise deals)
  [ ] SOC 2 audit trail: immutable append-only log of all data access
  [ ] Data residency: configurable R2 bucket region per production
  [ ] IP allowlist: restrict share link access to specified IP ranges
      (useful for studio review sessions in specific locations)
  [ ] Custom domain: allow slate.yourstudio.com for white-label portals
```

---

## AGENT COORDINATION SUMMARY

```
DEPENDENCY GRAPH (who waits for whom):

Claude Code publishes:  contracts/data-model.json
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
         Codex starts    Gemini starts    (Claude Code
         sync-engine     schema work       waits for
                               │           contracts)
              ▼               ▼
    Codex publishes:   Gemini publishes:
    sync-api.json      web-api.json
    ai-scores-api.json realtime-events.json
              │               │
              └───────┬───────┘
                      ▼
             Claude Code wires
             engines into desktop UI
             (Phase 1 complete)

COMMUNICATION PROTOCOL:
- Each agent writes a "SIGNAL" comment to contracts/SIGNALS.md
  when reaching a checkpoint
- Format: "{AGENT} {CHECKPOINT} complete — {timestamp}"
- Other agents check this file before starting dependent work
- Never block on another agent — build what you can independently,
  stub interfaces where contracts are pending
```

---

*End of SLATE Three-Agent Coordinated Build Prompts*
*Mountain Top Pictures | Claude Code · OpenAI Codex · Google Gemini Code Assist*
*Version 1.0 — All three prompts in one document*
