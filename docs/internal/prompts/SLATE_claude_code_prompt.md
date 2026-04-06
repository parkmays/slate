# SLATE — Claude Code Build Prompt
## AI-Powered Dailies Processing & Review Platform
### Version: Phase 1 MVP | Target: macOS Desktop + Web Review Portal
### Author: Mountain Top Pictures | Stack: Swift/SwiftUI + Next.js + Supabase

---

## HOW TO USE THIS PROMPT

Paste this entire document into Claude Code at the start of a new session.
Claude Code should read it fully before writing a single line of code.
Each section is marked with its execution order. Work top to bottom, checkpoint
to checkpoint. Do not skip ahead. When a checkpoint is reached, stop and confirm
output before proceeding.

---

## SECTION 0 — PROJECT CONTEXT & GROUND RULES

You are building SLATE, a professional film production tool for Mountain Top
Pictures, a Los Angeles-based film and TV production company. The primary users
are DITs (Digital Imaging Technicians), post coordinators, directors, and
producers on active film and documentary shoots.

### Non-negotiable rules for this entire codebase:

1. **Never delete or move original media.** SLATE is read-only with respect to
   source files. It copies to project folders, creates proxies, and writes
   metadata — it never modifies or removes originals.

2. **All AI decisions are advisory and overrideable.** Every score, flag, or
   auto-selection the system makes must be manually overrideable by the user
   with a single click. No AI action is permanent.

3. **Checksums on everything.** Every file that moves through the system must
   be verified with SHA-256 before and after. Alert loudly on any mismatch.
   Production data is irreplaceable.

4. **Offline-first.** The desktop app must function completely without internet.
   Cloud sync is additive, never required for core functionality.

5. **Performance is a feature.** This runs on active shoots where waiting is
   not acceptable. Proxy generation, sync processing, and UI interactions all
   have hard latency budgets defined in Section 3. Benchmark and enforce them.

6. **Dual-mode architecture from day one.** The data model must support both
   Narrative mode (scene/shot/take hierarchy) and Documentary mode
   (subject/day/clip hierarchy) from the first commit. Do not build narrative
   mode and "add doc mode later." The shared Clip object is the foundation of
   everything.

---

## SECTION 1 — REPOSITORY & PROJECT STRUCTURE

### Initialize the monorepo

```
slate/
├── apps/
│   ├── desktop/          # macOS SwiftUI app (Xcode project)
│   └── web/              # Next.js 14 web review portal
├── packages/
│   ├── sync-engine/      # Audio sync core (Swift package, shared with desktop)
│   ├── ingest-daemon/    # Watch folder background service (Swift)
│   ├── ai-pipeline/      # ML model wrappers (CoreML + MLX, Swift)
│   ├── shared-types/     # Shared TypeScript types for web + API
│   └── export-writers/   # NLE XML/EDL generation (Swift)
├── supabase/
│   ├── migrations/       # All database schema migrations
│   ├── functions/        # Edge functions (proxy URL signing, link generation)
│   └── seed.sql          # Development seed data
├── scripts/
│   ├── bootstrap.sh      # One-command dev environment setup
│   ├── benchmark.sh      # Performance regression tests
│   └── test-sync.sh      # Sync accuracy test harness
├── docs/
│   ├── architecture.md   # System architecture decisions
│   ├── data-model.md     # Clip object spec and hierarchy docs
│   └── api.md            # Internal API documentation
├── .env.example
├── CLAUDE.md             # Claude Code project memory file (see Section 9)
└── README.md
```

### CLAUDE.md (create this file first)

```markdown
# SLATE — Claude Code Project Memory

## What this project is
SLATE is a film production dailies tool. It ingests camera footage, syncs
audio, scores takes, and assembles rough cuts. It never deletes media.

## Critical constraints
- Original media: READ ONLY. Never move, rename, or delete source files.
- Checksums: SHA-256 verify every file transfer. Fail loudly on mismatch.
- Dual mode: Every data structure must support both Narrative and Documentary
  hierarchy from the start.
- Performance budgets: See docs/architecture.md Section "Latency budgets"
- Apple Silicon only (M1+). Use MLX for ML inference, VideoToolbox for transcode.

## Key files
- packages/shared-types/src/clip.ts — The universal Clip object. Read before
  touching any data model code.
- supabase/migrations/ — All schema changes go here, never direct DB edits.
- apps/desktop/Sources/SLATECore/ — Core business logic, no UI code here.
- apps/desktop/Sources/SLATEUI/ — All SwiftUI views.

## Commands
- `./scripts/bootstrap.sh` — full dev setup
- `./scripts/benchmark.sh` — run performance suite
- `supabase db reset` — reset local DB to seed state
- `cd apps/web && npm run dev` — start web portal dev server

## Current phase: Phase 1 MVP
Out of scope for Phase 1: AI scoring, transcription, iOS app, Frame.io,
Airtable sync, multi-user presence, voice annotations.
```

---

## SECTION 2 — DATA MODEL (BUILD THIS FIRST, BEFORE ANY UI)

The data model is the foundation of everything. Do not write UI code until the
data model is locked. All engineers and Claude Code sessions must read this
before touching models.

### 2.1 — The Universal Clip Object

This is the core entity. Everything in SLATE is ultimately a Clip.

**TypeScript definition (packages/shared-types/src/clip.ts):**

```typescript
export type ClipStatus = 'pending' | 'processing' | 'ready' | 'error'
export type ReviewStatus = 'unreviewed' | 'circled' | 'flagged' | 'x' | 'deprioritized'
export type SyncConfidence = 'high' | 'medium' | 'low' | 'manual_required' | 'unsynced'
export type ProjectMode = 'narrative' | 'documentary'

export interface AudioTrack {
  trackIndex: number
  role: 'boom' | 'lav' | 'mix' | 'iso' | 'unknown'
  channelLabel: string
  sampleRate: number
  bitDepth: number
}

export interface SyncResult {
  confidence: SyncConfidence
  method: 'waveform_correlation' | 'timecode' | 'manual' | 'none'
  offsetFrames: number        // positive = audio leads video
  driftPPM: number            // parts per million drift detected
  clapDetectedAt?: number     // seconds into audio file
  verifiedAt?: string         // ISO timestamp when manually verified
}

export interface AIScores {
  composite: number           // 0–100 weighted composite
  focus: number               // 0–100 subject focus quality
  exposure: number            // 0–100 exposure correctness
  stability: number           // 0–100 camera stability
  audio: number               // 0–100 audio technical quality
  performance?: number        // 0–100 narrative mode only
  contentDensity?: number     // 0–100 documentary mode only
  scoredAt: string            // ISO timestamp
  modelVersion: string        // e.g. "slate-vision-v1.2"
  reasoning: ScoreReason[]    // per-dimension human-readable explanations
}

export interface ScoreReason {
  dimension: string
  score: number
  flag: 'info' | 'warning' | 'error'
  message: string             // e.g. "Focus soft at 0:02 — subject blinked"
  timecode?: string           // e.g. "00:00:02:14"
}

export interface Annotation {
  id: string
  userId: string
  userDisplayName: string
  timecodeIn: string          // e.g. "00:01:23:12"
  timecodeOut?: string
  body: string
  type: 'text' | 'voice'
  voiceUrl?: string
  createdAt: string
  resolvedAt?: string
}

// THE UNIVERSAL CLIP OBJECT
export interface Clip {
  // Identity
  id: string                  // UUID v4
  projectId: string
  checksum: string            // SHA-256 of original file

  // Source media (READ ONLY paths — never modify these files)
  sourcePath: string          // Absolute path to original camera file
  sourceSize: number          // Bytes
  sourceFormat: string        // e.g. "BRAW", "ARRIRAW", "ProRes422HQ"
  sourceFps: number           // e.g. 23.976, 25, 29.97
  sourceTimecodeStart: string // e.g. "01:00:00:00"
  duration: number            // Seconds

  // Proxy (generated by SLATE, safe to delete/regenerate)
  proxyPath?: string
  proxyStatus: ClipStatus
  proxyChecksum?: string

  // Narrative mode metadata (null in documentary mode)
  narrativeMeta?: {
    sceneNumber: string       // e.g. "12A"
    shotCode: string          // e.g. "A", "B", "OTS"
    takeNumber: number
    cameraId: string          // e.g. "A", "B"
    scriptPage?: string
    setUpDescription?: string
    director?: string
    dp?: string
  }

  // Documentary mode metadata (null in narrative mode)
  documentaryMeta?: {
    subjectName: string
    subjectId: string
    shootingDay: number
    sessionLabel: string      // e.g. "Interview A", "B-roll Morning"
    location?: string
    topicTags: string[]       // User-assigned e.g. ["origin", "conflict"]
    interviewerOffscreen: boolean
  }

  // Audio
  audioTracks: AudioTrack[]
  syncResult: SyncResult
  syncedAudioPath?: string    // Path to merged/synced audio file

  // AI Processing
  aiScores?: AIScores
  transcriptId?: string       // FK to separate transcripts table
  aiProcessingStatus: ClipStatus

  // Review
  reviewStatus: ReviewStatus
  annotations: Annotation[]
  approvalStatus: 'pending' | 'reviewed' | 'approved'
  approvedBy?: string
  approvedAt?: string

  // System
  ingestedAt: string
  updatedAt: string
  projectMode: ProjectMode    // Inherited from parent project
}
```

**Swift equivalent (apps/desktop/Sources/SLATECore/Models/Clip.swift):**
Generate a Swift struct that exactly mirrors the TypeScript definition above.
Use `Codable` for all types. Use `URL` for path fields. Use `Date` for
timestamp fields. All optional fields in TS map to Optional in Swift.

### 2.2 — Hierarchy Models

```typescript
// Narrative hierarchy
export interface NarrativeProject {
  id: string
  name: string
  mode: 'narrative'
  productionCompany: string
  director: string
  dp: string
  createdAt: string
  scriptPath?: string         // Path to uploaded script for flub detection
  scenes: NarrativeScene[]
}

export interface NarrativeScene {
  id: string
  projectId: string
  sceneNumber: string         // e.g. "12A"
  description: string
  location?: string
  dayNight?: 'day' | 'night' | 'dawn' | 'dusk'
  interiorExterior?: 'int' | 'ext' | 'int/ext'
  setups: NarrativeSetup[]
  completionStatus: 'not_started' | 'in_progress' | 'complete'
}

export interface NarrativeSetup {
  id: string
  sceneId: string
  shotCode: string            // e.g. "A", "B", "OTS", "CU"
  description: string         // e.g. "Wide two-shot"
  lens?: string
  frameSize?: string
  circledTakeId?: string      // Which take the director selected
  clips: Clip[]               // All takes of this setup
}

// Documentary hierarchy
export interface DocumentaryProject {
  id: string
  name: string
  mode: 'documentary'
  productionCompany: string
  director: string
  createdAt: string
  shootingDays: ShootingDay[]
}

export interface ShootingDay {
  id: string
  projectId: string
  dayNumber: number
  date: string                // ISO date
  location?: string
  subjects: DocumentarySubject[]
}

export interface DocumentarySubject {
  id: string
  shootingDayId: string
  name: string
  role?: string               // e.g. "Climber", "Director", "Narrator"
  sessions: DocumentarySession[]
}

export interface DocumentarySession {
  id: string
  subjectId: string
  label: string               // e.g. "Interview A", "B-roll Morning"
  clips: Clip[]
  assemblyOrder?: string[]    // Ordered clip IDs for paper cut
}
```

### 2.3 — Supabase Schema

Create these tables in `supabase/migrations/001_initial_schema.sql`:

```sql
-- Projects (supports both modes via mode column)
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

-- Clips (the universal clip table — all media lives here)
CREATE TABLE clips (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  checksum TEXT NOT NULL,
  source_path TEXT NOT NULL,
  source_size BIGINT NOT NULL,
  source_format TEXT NOT NULL,
  source_fps NUMERIC(8,3) NOT NULL,
  source_timecode_start TEXT,
  duration NUMERIC(10,3) NOT NULL,
  proxy_path TEXT,
  proxy_status TEXT DEFAULT 'pending' CHECK (proxy_status IN ('pending','processing','ready','error')),
  proxy_checksum TEXT,
  narrative_meta JSONB,
  documentary_meta JSONB,
  audio_tracks JSONB DEFAULT '[]',
  sync_result JSONB DEFAULT '{"confidence":"unsynced","method":"none","offsetFrames":0,"driftPPM":0}',
  synced_audio_path TEXT,
  ai_scores JSONB,
  transcript_id UUID,
  ai_processing_status TEXT DEFAULT 'pending',
  review_status TEXT DEFAULT 'unreviewed' CHECK (review_status IN ('unreviewed','circled','flagged','x','deprioritized')),
  approval_status TEXT DEFAULT 'pending',
  approved_by TEXT,
  approved_at TIMESTAMPTZ,
  ingested_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Narrative hierarchy tables
CREATE TABLE narrative_scenes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  scene_number TEXT NOT NULL,
  description TEXT,
  location TEXT,
  day_night TEXT,
  interior_exterior TEXT,
  completion_status TEXT DEFAULT 'not_started',
  sort_order INTEGER DEFAULT 0
);

CREATE TABLE narrative_setups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  scene_id UUID REFERENCES narrative_scenes(id) ON DELETE CASCADE,
  shot_code TEXT NOT NULL,
  description TEXT,
  lens TEXT,
  frame_size TEXT,
  circled_take_id UUID REFERENCES clips(id)
);

-- Documentary hierarchy tables
CREATE TABLE shooting_days (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  day_number INTEGER NOT NULL,
  date DATE,
  location TEXT
);

CREATE TABLE documentary_subjects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shooting_day_id UUID REFERENCES shooting_days(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  role TEXT,
  sort_order INTEGER DEFAULT 0
);

CREATE TABLE documentary_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_id UUID REFERENCES documentary_subjects(id) ON DELETE CASCADE,
  label TEXT NOT NULL,
  assembly_order JSONB DEFAULT '[]'
);

-- Annotations
CREATE TABLE annotations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clip_id UUID REFERENCES clips(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  user_display_name TEXT NOT NULL,
  timecode_in TEXT NOT NULL,
  timecode_out TEXT,
  body TEXT NOT NULL,
  type TEXT DEFAULT 'text' CHECK (type IN ('text','voice')),
  voice_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  resolved_at TIMESTAMPTZ
);

-- Share links (for web review portal)
CREATE TABLE share_links (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  scope TEXT NOT NULL,          -- 'project', 'scene', 'subject', 'assembly'
  scope_id TEXT,                -- ID of the scoped entity
  token TEXT UNIQUE NOT NULL,   -- Random URL token
  expires_at TIMESTAMPTZ,
  password_hash TEXT,
  permissions JSONB DEFAULT '{"canComment":true,"canFlag":true,"canRequestAlternate":false}',
  created_by TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable Realtime on annotations and clips for collaborative review
ALTER PUBLICATION supabase_realtime ADD TABLE annotations;
ALTER PUBLICATION supabase_realtime ADD TABLE clips;

-- Indexes
CREATE INDEX idx_clips_project ON clips(project_id);
CREATE INDEX idx_clips_review_status ON clips(review_status);
CREATE INDEX idx_clips_checksum ON clips(checksum);
CREATE INDEX idx_annotations_clip ON annotations(clip_id);
CREATE INDEX idx_share_links_token ON share_links(token);
```

---

## SECTION 3 — INGEST ENGINE (Build order: 1st)

### 3.1 — Watch Folder Daemon

Build as a Swift package: `packages/ingest-daemon/`

This runs as a background LaunchAgent on macOS. It must survive app restarts.

**Requirements:**

```swift
// IngestDaemon.swift — key behaviors to implement:

// 1. Watch folder registry
//    - User registers folders via desktop app
//    - Stored in ~/Library/Application Support/SLATE/watchfolders.json
//    - Each entry: { path, projectId, mode: 'narrative'|'documentary' }

// 2. File detection
//    - Use FSEvents (not polling) for immediate detection
//    - Debounce 2 seconds — wait for file copy to complete before ingesting
//    - Detect by extension: .ari .arx .braw .mov .mxf .mp4 .r3d
//    - Skip: .DS_Store, dot-files, files < 1MB (thumbnails/metadata sidecars)
//    - Skip files already in the clips table (checksum match)

// 3. Ingest pipeline (for each detected file):
//    a. Compute SHA-256 checksum (stream, never load full file to RAM)
//    b. Check DB — if checksum exists, skip with "already ingested" log
//    c. Parse metadata (see 3.2)
//    d. Copy to project media folder (NEVER move — always copy)
//       Destination: ~/Movies/SLATE/{projectName}/Media/{scene}/{filename}
//    e. Verify copy checksum matches source checksum — HALT if mismatch
//    f. Insert clip record to Supabase (status: 'pending')
//    g. Dispatch to proxy generation queue (see 3.3)
//    h. Dispatch to sync queue (see Section 4)

// 4. Progress reporting
//    - Write progress to ~/Library/Application Support/SLATE/ingest.json
//    - Desktop app polls this file to update menu bar icon
//    - Format: { active: [{filename, progress, stage}], queued: N, errors: [] }

// 5. Error handling
//    - Checksum mismatch: log to errors array, alert user, DO NOT proceed
//    - Unsupported format: log warning, skip file
//    - Out of disk space: pause all ingest, alert user immediately
//    - Network/DB error: queue locally, retry with exponential backoff
```

### 3.2 — Metadata Parser

Parse scene/shot/take from multiple sources, in priority order:

```swift
// MetadataParser.swift

// Priority order (highest wins):
// 1. Embedded SMPTE timecode (most authoritative)
// 2. Sidecar .ALE file (Avid Log Exchange — used on many high-end productions)
// 3. Embedded XMP/EXIF metadata
// 4. Filename pattern matching

// Narrative filename patterns to support:
// Standard: A001C001_230415_R1BK.mxf → camera:A roll:001 clip:001 date:230415
// Simple:   Sc01_ShA_T3_CamA.mov → scene:01 shot:A take:3 cam:A
// Arri:     A001C0001_230415_ABCD.ari
// Blackmagic: Clip 001.braw (sequential — use timecode for scene mapping)

// Documentary filename patterns:
// Interview: RickRidgeway_Day1_IntA_001.mp4 → subject:RickRidgeway day:1 session:IntA clip:1
// B-roll:    BROLL_Day1_Forest_Morning_001.mov

// When pattern matching fails:
// - Create clip with narrativeMeta/documentaryMeta as nil
// - Flag for manual metadata entry in UI
// - Never block ingest on metadata failure

// Output: ParsedMetadata struct with confidence score (0–1) per field
// Confidence < 0.5 = show yellow indicator in UI "metadata uncertain"
```

### 3.3 — Proxy Generator

```swift
// ProxyGenerator.swift — uses VideoToolbox + AVFoundation

// Target spec:
//   Codec: H.264 (High Profile)
//   Resolution: 1920×1080 (letterbox/pillarbox to preserve AR)
//   Bitrate: 8 Mbps VBR
//   Audio: AAC 48kHz stereo (mix of all ISO tracks for proxy — ISO preserved in sync)
//   Frame rate: Match source
//   Color: Apply project LUT if configured, else Rec.709 clip

// Performance target:
//   M4 Max: 10x realtime or faster for ProRes/H.264 sources
//   ARRIRAW/BRAW: 4x realtime minimum (these require decode)
//   Measure and log actual speed per clip, alert if below 2x

// Implementation notes:
//   - Use AVAssetExportSession with VideoToolbox hardware acceleration
//   - For ARRIRAW: use ARRI SDK if available, else ffmpeg subprocess
//   - For BRAW: Blackmagic RAW SDK (must be installed separately — check and warn)
//   - Process proxies in parallel — max concurrent = (CPU core count / 2)
//   - Write proxy to: ~/Movies/SLATE/{projectName}/Proxies/{clipId}.mp4
//   - After write: verify proxy checksum, update clip.proxyStatus = 'ready'
//   - On failure: update clip.proxyStatus = 'error', log reason
```

---

## SECTION 4 — AUDIO SYNC ENGINE (Build order: 2nd)

This is the hardest and most critical component. Budget more time than expected.
Build a comprehensive test suite before writing the sync algorithm.

### 4.1 — Test Harness (Build this first)

```bash
# scripts/test-sync.sh
# Required test cases — must pass before shipping:

# Test 1: Perfect slate (clap at frame 0)
# Test 2: Delayed clap (clap at 3 seconds into take)
# Test 3: Double clap (second clap is the real one)
# Test 4: Missed slate (no clap — timecode fallback)
# Test 5: Noisy set (clap partially obscured by background noise)
# Test 6: Multi-cam (sync camera A and B to same audio)
# Test 7: Long take drift (20+ minute interview, check drift every 5 min)
# Test 8: Multiple ISO tracks (boom + 2x lav — all three must sync)

# Each test: provide known-offset source files, verify sync result within 1 frame
# Log: method used, confidence score, detected offset, actual offset, error in frames
```

### 4.2 — Sync Algorithm

```swift
// AudioSyncEngine.swift

// STEP 1: Timecode check
//   - Read camera LTC/VITC timecode from video file
//   - Read audio file timecode (if Ambient/Sound Devices recorder)
//   - If both present and within 10ms: use timecode sync (confidence: high)
//   - If one is missing or they disagree >10ms: fall through to waveform

// STEP 2: Clap detection via onset detection
//   - Compute audio onset strength using spectral flux
//   - Find the highest-energy transient in first 10 seconds of audio
//   - Find the corresponding transient in the camera's reference audio track
//   - Cross-correlate a 100ms window around each transient
//   - If correlation coefficient > 0.85: use clap sync (confidence: high)
//   - If 0.60–0.85: use clap sync (confidence: medium — show yellow)
//   - If < 0.60: fall through to full-file correlation

// STEP 3: Full-file waveform correlation (fallback)
//   - Downsample both to 1kHz for speed
//   - Compute normalized cross-correlation across ±30 second search window
//   - Pick offset at peak correlation
//   - If peak correlation > 0.70: use result (confidence: medium)
//   - If < 0.70: mark as manual_required (confidence: low — show red)

// STEP 4: Drift correction
//   - For takes > 5 minutes: divide into 1-minute segments
//   - Compute sync correlation at each segment boundary
//   - If drift > 5ms per minute: apply linear drift correction
//   - Report drift in PPM to clip.syncResult.driftPPM

// STEP 5: Multi-track assignment
//   - For each ISO track: compute RMS and spectral centroid
//   - Classify: high RMS + broad spectrum = boom, high RMS + narrow spectrum = lav
//   - Store role assignment in audioTracks[].role
//   - User can override track roles in UI

// Output: SyncResult struct — write to clip.syncResult in DB
// Also: write merged audio file to clip.syncedAudioPath

// Performance target: < 30 seconds for a 10-minute take on M4 Max
```

### 4.3 — Manual Sync Override UI

```swift
// WaveformSyncEditor.swift — SwiftUI view for red-confidence syncs

// Display:
//   - Top track: camera reference audio waveform (full take)
//   - Bottom track: external audio waveform (full take)
//   - Zoom controls: 1x / 10x / 100x / 1000x
//   - Playback: scrub both tracks in sync, play aligned region
//   - Offset control: drag bottom track left/right, or type frame offset

// Interaction:
//   - Snap-to-transient: click near a transient to snap cursor to it
//   - Link transients: click one in top, one in bottom — sets offset
//   - Confirm: writes offset to syncResult, confidence = 'high' (manually set)

// This editor appears automatically for any clip with syncConfidence = 'manual_required'
```

---

## SECTION 5 — DESKTOP UI (Build order: 3rd)

Built in SwiftUI targeting macOS 14+. Apple Silicon required.

### 5.1 — App Architecture

```
SLATEApp/
├── App.swift                   # App entry point, menu bar integration
├── AppState.swift              # Global ObservableObject state
├── SLATECore/                  # Business logic (no UI imports)
│   ├── ProjectManager.swift
│   ├── IngestManager.swift
│   ├── SyncManager.swift
│   ├── AssemblyEngine.swift
│   └── ExportWriter.swift
└── SLATEUI/                    # All SwiftUI views
    ├── MainWindow/
    │   ├── MainWindowView.swift         # Root split view
    │   ├── SidebarView.swift            # Scene/subject list
    │   ├── TakeBrowserView.swift        # Main take grid
    │   └── InspectorView.swift          # Right panel
    ├── Player/
    │   ├── ProxyPlayerView.swift        # AVKit proxy playback
    │   └── WaveformView.swift           # Waveform visualization
    ├── Review/
    │   ├── AnnotationView.swift
    │   └── ApprovalView.swift
    ├── Setup/
    │   ├── ProjectCreationView.swift
    │   └── WatchFolderView.swift
    └── Shared/
        ├── ScoreBadgeView.swift
        └── SyncConfidenceView.swift
```

### 5.2 — Main Window Layout

```swift
// MainWindowView.swift
// Three-panel layout: Sidebar | Take Browser | Inspector
// Matches the prototype in the SLATE UI artifact exactly.

// Sidebar (200pt fixed):
//   - Mode toggle at top: [Narrative] [Documentary]
//   - Narrative: scene list with completion bar (green=circled/amber=partial/red=none)
//   - Documentary: subject list with clip count
//   - Filter section: Circled only toggle, Show deprioritized toggle
//   - Keyboard: ↑↓ to navigate scenes, Enter to select

// Take Browser (flexible):
//   - Header: scene/subject name, take count, sync status
//   - View toggle: Takes | Waveform | Coverage
//   - Takes view: vertical list of TakeRowView
//   - Each row: thumbnail placeholder, take label, score pills, waveform strip
//   - Score pills: Focus / Audio / Performance — color-coded (green≥80, amber≥60, red<60)
//   - Deprioritized takes: 60% opacity, shown only when filter is on
//   - Bottom bar: scene completion status, "Assemble rough cut" button
//   - Keyboard: C=circle, F=flag, X=mark, D=deprioritize, Space=play/pause

// Inspector (260pt fixed):
//   - Sync confidence indicator (green/yellow/red pill)
//   - AI score breakdown: labeled progress bars per dimension
//   - Score reasoning: human-readable explanation per flag
//   - Action buttons: Circle | Flag | Deprioritize
//   - Notes textarea
//   - Export format badges: FCPXML | EDL | Premiere XML | Resolve XML
```

### 5.3 — Menu Bar Integration

```swift
// MenuBarManager.swift
// Persistent menu bar icon (appears even when main window is closed)

// Icon states:
//   - Idle: static SLATE icon
//   - Ingesting: animated spinner, show N files remaining
//   - Syncing: animated waveform icon
//   - Error: red badge with count

// Menu items:
//   - "Open SLATE" — brings main window to front
//   - "Today's Dailies" — shows quick summary popover
//     └── N files ingested | N synced | N ready for review
//   - "Ingest Status" → submenu with active file list
//   - "Pause Ingest" toggle
//   - Separator
//   - "Preferences" → opens settings sheet
```

### 5.4 — Proxy Player

```swift
// ProxyPlayerView.swift
// Uses AVKit for playback. Frame-accurate scrubbing required.

// Controls:
//   - Play/pause (Space)
//   - Frame step (← →)
//   - Scene step (Shift + ← →)
//   - Timecode display (always visible, updates at frame rate)
//   - Annotation marker overlay: colored tick marks on scrubber for annotations
//   - Click scrubber: jump to frame, drop annotation pin

// Performance: proxy playback must be instant (no buffering spinner)
// Pre-load the next take's proxy while reviewing current take
```

---

## SECTION 6 — ASSEMBLY ENGINE (Build order: 4th)

```swift
// AssemblyEngine.swift

// NARRATIVE ASSEMBLY:
// Input: Project, filtered to a scene (or whole project)
// Algorithm:
//   1. For each scene, iterate setups in shot order
//   2. For each setup: use circledTakeId if set, else highest composite AI score
//   3. Build ordered clip list: [clipId, inPoint, outPoint, role]
//   4. inPoint = clip start timecode, outPoint = clip end timecode (full take by default)
//   5. Directors can trim in/out points per clip in assembly preview
// Output: Assembly struct → passed to ExportWriter

// DOCUMENTARY ASSEMBLY:
// Input: Project, filtered to subject(s) or topic tags
// Algorithm:
//   1. Gather all circled clips matching filter
//   2. Sort by: subject order (user-defined) then chronological within subject
//   3. If topic tags specified: filter to clips tagged with those topics
//   4. Use documentarySession.assemblyOrder if set (manual paper cut)
//   5. Else: sort by AI contentDensity score descending
// Output: Assembly struct → passed to ExportWriter

// ASSEMBLY PREVIEW:
//   - Render assembly as AVMutableComposition using proxy files
//   - Playback in ProxyPlayerView with scene/clip markers
//   - User can drag to reorder clips, trim in/out points
//   - "Export" button triggers ExportWriter with final assembly

// VERSION HISTORY:
//   - Every export creates an AssemblyVersion record in DB
//   - Store: assembly struct JSON, export timestamp, user, NLE format
//   - User can recall any prior version from sidebar
```

---

## SECTION 7 — NLE EXPORT WRITERS (Build order: 5th)

All four formats must export correctly. Test against actual NLE imports.

```swift
// ExportWriter.swift — dispatches to format-specific writers

// FCPXML Writer (highest priority — richest format):
//   Version: FCPXML 1.11 (FCP 10.6+)
//   Structure:
//     <fcpxml version="1.11">
//       <resources>
//         <format> — source format definition
//         <asset> — one per clip, references proxy path
//         <effect> — audio roles
//       </resources>
//       <library>
//         <event name="{projectName}">
//           <project name="{assemblyName}">
//             <sequence> — the timeline
//               <spine> — ordered clips
//                 <clip> — per clip with audio/video roles
//   Key details:
//   - Circle = keyword "Circled" on clip
//   - Flag = keyword "Flagged"
//   - Deprioritized = keyword "Deprioritized" (not rejected)
//   - Annotations export as markers on the timeline
//   - Audio roles: dialogue.boom, dialogue.lav, dialogue.mix
//   - Multi-angle clips for multi-cam setups
//   - Test: import into FCP 10.6, verify clip order, roles, markers

// CMX 3600 EDL Writer (Avid + Premiere):
//   Standard CMX 3600 format
//   One event per clip with FROM CLIP NAME comment
//   Reel names: clip IDs (or scene/take labels if < 8 chars)
//   Frame rates: 23.976 (non-drop), 24, 25, 29.97DF, 30
//   Export separate AAF for audio (see below)
//   Test: import into Avid Media Composer 2023+

// AAF Writer (Avid audio):
//   Multi-track audio AAF
//   Track layout: V1, A1(boom), A2(boom-R), A3(lav1), A4(lav2)
//   Preserve source audio paths for Avid MediaManager re-link
//   Test: import into Avid, verify all audio tracks present

// Premiere Pro XML Writer:
//   Premiere sequence XML format
//   Sequence settings match source frame rate and resolution
//   Markers for annotations
//   Essential Sound panel metadata: Dialogue role on all clips
//   Productions folder structure: bins per scene/subject
//   Test: import into Premiere Pro 2024

// DaVinci Resolve XML Writer:
//   Resolve XML timeline format
//   Media pool bins: one per scene (narrative) or subject (documentary)
//   Smart bins: "Circled Takes", "Needs Review"
//   Color flags: Green=circled, Yellow=flagged, Red=deprioritized
//   Fairlight track layout preserved from AAF
//   Test: import into DaVinci Resolve 18+

// All writers: include a dry-run mode that validates XML structure
// without writing files. Run in tests.
```

---

## SECTION 8 — WEB REVIEW PORTAL (Build order: 6th)

### 8.1 — Next.js App Structure

```
apps/web/
├── app/
│   ├── layout.tsx
│   ├── page.tsx                  # Redirect to /login or dashboard
│   ├── dashboard/
│   │   └── page.tsx              # Authenticated user project list
│   └── review/
│       └── [token]/
│           ├── page.tsx          # Guest review page (no login)
│           ├── loading.tsx
│           └── error.tsx
├── components/
│   ├── Player/
│   │   ├── HLSPlayer.tsx         # hls.js video player
│   │   └── ScrubBar.tsx          # Annotation tick marks
│   ├── Review/
│   │   ├── AnnotationPanel.tsx
│   │   ├── CommentThread.tsx
│   │   └── FlagControls.tsx
│   └── Assembly/
│       └── ClipList.tsx
├── lib/
│   ├── supabase.ts               # Supabase client
│   ├── realtime.ts               # Realtime subscription setup
│   └── share-links.ts            # Token validation
└── middleware.ts                 # Token auth for /review routes
```

### 8.2 — Guest Review Flow

```typescript
// app/review/[token]/page.tsx

// 1. Validate token in middleware (not in page):
//    - SELECT from share_links WHERE token = $1 AND expires_at > NOW()
//    - If not found or expired: return 404
//    - If password_hash set: show password prompt (hash with bcrypt, compare)
//    - Attach link metadata to request headers for the page

// 2. Page loads:
//    - Fetch assembly or scene/subject based on link scope
//    - Fetch clips with proxy HLS URLs (signed URLs from Cloudflare R2)
//    - Fetch existing annotations for display
//    - Subscribe to Supabase Realtime: annotations channel for this project

// 3. HLS Player (HLSPlayer.tsx):
//    - Use hls.js for adaptive proxy streaming
//    - Proxy stored in R2 as HLS segments (transcode on desktop, upload segments)
//    - Fallback: direct proxy URL if HLS not available
//    - Custom scrub bar with colored tick marks per annotation
//    - Timecode overlay

// 4. Annotation:
//    - Click scrub bar or press N: drop annotation pin at current timecode
//    - Text input appears inline — submit with Enter
//    - Immediately appears for all viewers via Realtime subscription
//    - If link.permissions.canFlag: show Circle/Flag buttons
//    - If link.permissions.canRequestAlternate: show "Request alternate take" button

// 5. Realtime updates:
//    - Subscribe: supabase.channel('annotations:{projectId}')
//    - On INSERT: append to annotation list, scroll to it
//    - On UPDATE: update existing annotation
//    - Show "N people viewing" presence indicator
```

### 8.3 — Proxy Upload for Web Streaming

Desktop app uploads proxies to Cloudflare R2 when web sharing is enabled:

```swift
// R2Uploader.swift

// Upload flow:
//   1. User enables web sharing for a project
//   2. Upload all ready proxies to R2: slate-proxies/{projectId}/{clipId}/
//   3. If HLS enabled: also upload segmented HLS files
//   4. Store R2 URL in clip.proxyUrl (new field)
//   5. Generate signed URLs via Supabase Edge Function (24h expiry)
//   6. Never upload original media — proxies only

// Cloudflare R2 config:
//   Bucket: slate-proxies-{region}
//   CORS: allow from *.slate.app and localhost
//   Signed URLs: use Cloudflare R2 presigned URLs, 24h TTL
```

---

## SECTION 9 — TESTING STRATEGY

### Unit tests (run on every commit)

```
// Audio sync: test all 8 cases in Section 4.1 test harness
// Metadata parser: test all filename pattern variants
// Export writers: validate XML output against NLE schemas
// Checksum verification: test mismatch detection
// Share link: test expiry, password, permission enforcement
```

### Integration tests (run before each phase release)

```
// Full ingest pipeline: mount test card, verify clips in DB, proxies on disk
// Sync pipeline: use test footage with known offsets, verify accuracy
// Assembly: generate assembly for a 10-scene narrative project, verify clip order
// Export: import FCPXML into FCP, EDL into Avid, XML into Premiere and Resolve
// Web portal: guest review flow end-to-end with annotation sync
```

### Performance benchmarks (scripts/benchmark.sh)

```
// Target machine: MacBook Pro M4 Max (14-core)
// Metric                    Target          Alert threshold
// ─────────────────────────────────────────────────────────
// Proxy: ProRes 1hr         < 6 min         > 10 min
// Proxy: BRAW 1hr           < 15 min        > 25 min
// Sync: 10-min take         < 30 sec        > 60 sec
// Sync: 2-hr interview      < 5 min         > 10 min
// Assembly: 10-scene        < 5 sec         > 15 sec
// Export: FCPXML 100 clips  < 3 sec         > 10 sec
// App launch cold           < 2 sec         > 4 sec
// Take browser: 500 clips   < 200ms render  > 500ms
```

---

## SECTION 10 — IMPROVEMENT ROADMAP

These are planned improvements beyond Phase 1 MVP, in priority order.
Each is labeled with its target phase.

### Phase 2 — AI Scoring Layer [8 weeks after Phase 1 ships]

```
IMPROVEMENT: Add on-device vision and audio quality scoring.

Models to integrate (all via CoreML / MLX on Apple Silicon):
  - Vision: YOLOv8n (face/object detection) → CoreML export
  - Depth: DepthAnything v2 Small → CoreML export
  - Custom classifier: trained on film QC frames (focus/exposure/stability)
    Training data: source from existing editorial metadata + human labels
  - Audio: custom PyTorch model for clipping/noise detection → CoreML

Scoring pipeline:
  1. Sample proxy at 2fps (configurable per project)
  2. Run vision models on sampled frames (batch on GPU via MPS)
  3. Run audio analysis on full audio track
  4. Aggregate frame scores → composite per clip
  5. Write to clip.aiScores, update UI in real time

Narrative: add script comparison
  1. Parse uploaded PDF/FDX script into searchable text
  2. Compare WhisperX transcript against script per take
  3. Flag flubs, missed lines, ad-libs
  4. Add to ScoreReason array with timecode

Documentary: add content density scoring
  1. Embed transcript segments via sentence-transformers (local)
  2. Score uniqueness vs other clips from same subject (cosine similarity)
  3. Detect emphasis and emotional peaks via prosody model
  4. Flag duplicate content across sessions

ACCEPTANCE: Scoring correlation ≥ 80% with editor's final take selections
            (measure on 3 real productions after shipping)
```

### Phase 2 — iOS Mobile Review App [parallel with AI scoring]

```
IMPROVEMENT: Ship iPhone/iPad review app for on-set director approval.

Architecture:
  - Swift/SwiftUI, targets iOS 17+
  - Shared SLATECore package with desktop (business logic reuse)
  - Separate SLATEUI-iOS for iOS-specific views

Key screens:
  1. Project list → today's dailies summary card
  2. Scene/subject list with completion indicators
  3. Take swipe view (swipe left/right between takes per setup)
  4. Inspector panel (score breakdown, annotation input)
  5. Approval flow: swipe up = Circle, swipe down = Deprioritize

Sync: CloudKit for offline-capable sync (annotations made offline sync on reconnect)
Push: APNs notification when dailies are ready ("17 takes ready for review")
Offline: Cache proxies locally (configurable quality: 720p for storage savings)

iPad-specific:
  - Split view: take list + player side by side
  - Pencil support for handwritten frame annotations (rasterize to image)
```

### Phase 3 — Transcription + Full-Text Search [6 weeks after Phase 2]

```
IMPROVEMENT: WhisperX transcription with speaker diarization + search.

Implementation:
  - Run WhisperX locally via Python subprocess (MLX-Whisper for Apple Silicon)
  - Speaker diarization via pyannote.audio (local model)
  - Store transcript as JSONB: [{start, end, speaker, text}]
  - Sync transcript to timecode via clip.sourceTimecodeStart

Full-text search:
  - Index transcripts in Supabase using pg_trgm (trigram index)
  - Search UI: global search bar → results show clip + timecode + snippet
  - "Jump to" button: opens clip player at matching timecode

Paper cut workflow:
  - Highlight transcript text → creates clip selection
  - Drag selections into assembly outline
  - Assembly outline → export as paper cut PDF + NLE EDL
  - Useful for documentary producers who work text-first

Privacy mode:
  - All transcription runs locally — never sent to cloud API
  - Hosted Whisper API available as optional opt-in (with explicit user consent)
```

### Phase 3 — Rough Cut Assembly v2 [parallel with transcription]

```
IMPROVEMENT: Smarter assembly with manual control and version branching.

New assembly features:
  - Drag-to-reorder clips in assembly timeline
  - Per-clip in/out point trimming (with proxy preview)
  - Multiple assembly versions ("Director's Cut A", "Short Cut")
  - Assembly branch/merge (fork a version, make changes, compare)
  - Story outline view for documentary (card-based like Story)

Assembly diff view:
  - Compare two assembly versions side by side
  - Highlighted differences: added clips, removed clips, reordered clips
  - "Sync to director's edits" button: apply director overrides from one version to another
```

### Phase 4 — Integrations [ongoing after Phase 3]

```
IMPROVEMENT: Connect SLATE to the rest of the production stack.

Frame.io integration:
  - Pull projects and assets from Frame.io via API
  - Push SLATE proxy + annotations back to Frame.io
  - Two-way comment sync (Frame.io ↔ SLATE)
  - Required: Frame.io API key per project

Airtable integration (custom for Mountain Top Pictures):
  - Sync clip metadata to existing Airtable Film Festivals base or new Dailies base
  - Fields to sync: scene, shot, take, review status, scores, notes
  - Trigger: on clip status change (circled, flagged, approved)
  - Bi-directional: changes in Airtable reflect in SLATE notes field
  - Use existing appSOIQbLdfE9nPWG base ID

Slack integration:
  - Post to #dailies channel when dailies are ready for review
  - Format: "{N} takes ready for Sc {X}–{Y} | Review → [link]"
  - Post when director approves an assembly
  - Configurable per project: which channel, what events

Google Workspace:
  - Save assembly exports to Google Drive automatically
  - Share review links via Gmail draft
  - Sync project calendar (shoot days) from Google Calendar

Shot.io / ShotGrid integration:
  - Pull shot list from active production
  - Populate narrative_setups automatically from shot list
  - Push daily progress report (takes completed, circled, flagged)
```

### Phase 4 — Advanced AI Features

```
IMPROVEMENT: Fine-tuned models for production-specific quality detection.

Custom scoring model training:
  - After 3+ productions, collect editor final selections as training signal
  - Fine-tune the vision classifier on MTP-specific footage
  - Result: model learns this production company's aesthetic preferences
  - Measure: correlation improvement over generic model

Continuity checker (narrative mode):
  - Compare consecutive takes of same setup using vision similarity
  - Flag: costume changes, prop position changes, eyeline inconsistencies
  - Show: side-by-side frame comparison at flagged timecodes

Real-time on-set scoring (future):
  - Run scoring pipeline during recording, not just after
  - DIT can see live quality score on monitoring station
  - Requires: low-latency pipeline, direct camera feed input
  - Target: < 5 second score latency during live capture

Multi-angle optimization (narrative mode):
  - Given multiple camera angles of same setup, recommend best angle per moment
  - Input: two synchronized camera feeds, director's circle selections
  - Output: suggested multi-cam cut point list
```

### Ongoing — Performance & Reliability

```
IMPROVEMENT: Continuously improve ingest speed and sync accuracy.

Ingest speed improvements:
  - HEVC proxy encoding (smaller files, same quality, hardware accelerated on M-series)
  - Parallel multi-file ingest (currently one at a time per queue)
  - Smart scheduling: ingest during low-activity periods

Sync accuracy improvements:
  - Build up labeled dataset from manual overrides (each manual correction = training data)
  - Fine-tune clap detection for common problem cases (noisy sets, wind)
  - Add "smart slate" support: detect digital slate displays (Denecke, Ambient)

Error recovery:
  - Automatic retry for failed proxies (disk full, app crash during write)
  - "Repair project" command: re-verify all checksums, regenerate missing proxies
  - Audit log: every file operation logged with timestamp and result

Security hardening:
  - End-to-end encryption for proxy files at rest (AES-256)
  - Share link audit log (who viewed, when, from which IP)
  - SOC 2 Type II compliance path (required for studio enterprise deals)
```

---

## SECTION 11 — EXECUTION ORDER & CHECKPOINTS

Work strictly in this order. At each checkpoint, stop and verify before continuing.

```
CHECKPOINT 0 — Environment (Day 1)
  [ ] Repo initialized with structure from Section 1
  [ ] CLAUDE.md written and committed
  [ ] Supabase project created, schema migrated (Section 2.3)
  [ ] Seed data: one narrative project, one documentary project, 5 clips each
  [ ] All shared types compiling (TypeScript + Swift)
  VERIFY: `supabase db reset` runs clean, seed data visible in Studio

CHECKPOINT 1 — Data Model (End of Week 1)
  [ ] Clip Swift struct compiling, Codable, round-trips through JSON
  [ ] All hierarchy models (NarrativeScene, DocumentarySubject, etc.) compiling
  [ ] ProjectManager can CRUD projects and clips via Supabase
  VERIFY: Insert a Clip via Swift, read it back, confirm all fields survive round-trip

CHECKPOINT 2 — Ingest Engine (End of Week 2)
  [ ] Watch folder daemon detects and copies test files
  [ ] Checksum verification passing on all test files
  [ ] Metadata parser handles all filename patterns in Section 3.2
  [ ] Proxy generation completing for ProRes and H.264 test files
  [ ] Menu bar icon showing progress
  VERIFY: Mount test card → proxies appear in ~/Movies/SLATE within 5 minutes

CHECKPOINT 3 — Audio Sync (End of Week 4)
  [ ] All 8 sync test cases passing (Section 4.1)
  [ ] Sync confidence display working in UI
  [ ] Manual sync editor functional for red-confidence clips
  [ ] Multi-track ISO assignment working
  VERIFY: Run benchmark.sh sync tests, all pass within latency targets

CHECKPOINT 4 — Desktop UI (End of Week 5)
  [ ] Main window with all three panels
  [ ] Narrative mode: scene list, setup list, take rows
  [ ] Documentary mode: subject list, clip list with transcript preview
  [ ] Mode toggle works without data loss
  [ ] Keyboard shortcuts all functional
  [ ] Proxy player working with frame-accurate scrubbing
  VERIFY: Walk through UI prototype from SLATE artifact — every element present

CHECKPOINT 5 — Assembly + Export (End of Week 6)
  [ ] Narrative assembly generating correct clip order
  [ ] Documentary assembly generating correct subject/topic order
  [ ] FCPXML imports cleanly into Final Cut Pro 10.6
  [ ] EDL imports cleanly into Avid Media Composer
  [ ] Premiere XML imports cleanly into Premiere Pro 2024
  [ ] Resolve XML imports cleanly into DaVinci Resolve 18
  VERIFY: Import all four formats into actual NLEs, confirm clip order and metadata

CHECKPOINT 6 — Web Review Portal (End of Week 7)
  [ ] Share link generation working from desktop app
  [ ] Guest review page loading with proxy playback
  [ ] Annotations syncing in real time between two browser windows
  [ ] Circle/flag from browser updating clip in Supabase
  [ ] Link expiry enforced
  VERIFY: Generate link on desktop, open on iPhone browser, leave annotation,
          confirm it appears instantly on desktop app

CHECKPOINT 7 — Beta Test (Week 8)
  [ ] benchmark.sh all passing within targets
  [ ] Sentry error reporting live
  [ ] Tested with real archive footage (Ridgeway doc or Plantman & Blondie)
  [ ] Zero data loss confirmed on test ingest (all checksums verified)
  [ ] Ship to 2–3 beta users on active productions
```

---

## SECTION 12 — KNOWN RISKS & MITIGATIONS

```
RISK: BRAW/ARRIRAW decode requires proprietary SDKs
MITIGATION: Check for SDK at startup, warn user if missing, fall back to ffmpeg
            subprocess for ARRIRAW. Document SDK installation in README.

RISK: Sync accuracy degrades on noisy sets
MITIGATION: Build test dataset from actual noisy set recordings. Tune algorithm
            before shipping. The manual sync editor is the fallback — never block
            the workflow, just flag for human review.

RISK: Large card volumes exceed VideoToolbox queue limits
MITIGATION: Implement backpressure in the ingest queue. Never queue more than
            8 proxy jobs simultaneously. Show accurate ETA to user.

RISK: Supabase Realtime drops connections on set (spotty WiFi)
MITIGATION: All writes go to local SQLite first (using GRDB), sync to Supabase
            when connection available. No data can be lost due to network drops.

RISK: Share link proxies too large for slow connections
MITIGATION: Generate two proxy tiers: 8Mbps (default) and 2Mbps (mobile).
            Web portal auto-selects based on measured bandwidth.

RISK: NLE import failures due to format version changes
MITIGATION: Version-lock NLE format targets. Run import tests as part of CI
            using NLE command-line tools where available. Maintain a test matrix.
```

---

*End of SLATE Claude Code Prompt — Phase 1 MVP*
*Mountain Top Pictures | Version 1.0 | Built with Claude Code*
