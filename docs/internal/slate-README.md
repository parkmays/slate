# SLATE - Video Dailies Processing & Review Platform

A professional video dailies processing and review platform built for Mountain Top Pictures. SLATE enables seamless collaboration between DITs, editors, directors, and producers on film and TV productions.

## Architecture Overview

SLATE is built as a coordinated three-agent system:

```
┌──────────────────┬──────────────────────┬──────────────────────┐
│  Claude Code     │   OpenAI Codex       │  Google Gemini       │
│  (Orchestrator)  │   (AI/ML Engine)     │  (Web & Infra)       │
├──────────────────┼──────────────────────┼──────────────────────┤
│ macOS desktop    │ Audio sync algorithm │ Next.js web portal   │
│ Swift/SwiftUI    │ AI scoring pipeline  │ Supabase schema      │
│ Ingest daemon    │ ML model wrappers    │ Edge functions       │
│ NLE export       │ Transcription        │ Cloudflare R2        │
│ Assembly engine  │ Performance ML       │ CI/CD pipeline       │
│ Data model       │ Python ML services   │ API layer            │
│ Shared types     │ Test harnesses       │ Real-time collab     │
└──────────────────┴──────────────────────┴──────────────────────┘
```

## Features

### Core Functionality
- **Dual Mode Support**: Narrative (scene/shot/take) and Documentary (subject/day/clip) hierarchies
- **Original Media Protection**: Never moves, renames, or deletes source files
- **Offline-First Desktop**: Full functionality without internet connection
- **Real-time Collaboration**: Instant annotation sync across all platforms
- **AI-Powered Insights**: Automated technical scoring and content analysis

### Technical Features
- **SHA-256 Checksums**: Fail-loud data integrity verification
- **Adaptive Streaming**: HLS video with automatic quality adjustment
- **NLE Integration**: Export to FCPXML, EDL, AAF, and Resolve XML
- **Performance Targets**: Sub-6 minute ProRes proxy generation for 1-hour footage

## Quick Start

### Prerequisites
- macOS 14+ (for desktop app)
- Node.js 20+
- Docker (for Supabase)
- Cloudflare R2 account (production)

### Installation

```bash
# Clone the repository
git clone https://github.com/mountaintop-pictures/slate.git
cd slate

# Run bootstrap script
./scripts/bootstrap.sh

# Start development environment
./scripts/dev.sh
```

### Bootstrap Script
The bootstrap script handles:
- Installing all dependencies for all agents
- Setting up Supabase locally
- Configuring environment variables
- Building shared type packages

## Project Structure

```
slate/
├── apps/
│   ├── desktop/              # Claude Code: macOS SwiftUI app
│   └── web/                  # Gemini: Next.js review portal
├── packages/
│   ├── sync-engine/          # Codex: Audio sync Swift package
│   ├── ai-pipeline/          # Codex: ML wrappers and services
│   ├── ingest-daemon/        # Claude: Watch folder daemon
│   ├── shared-types/         # Claude: TypeScript/Swift models
│   └── export-writers/       # Claude: NLE export formats
├── supabase/
│   ├── migrations/           # Gemini: Database schema
│   ├── functions/            # Gemini: Edge functions
│   └── seed.sql              # Gemini: Test data
├── contracts/                # Inter-agent communication
│   ├── data-model.json       # Canonical data schema
│   ├── sync-api.json         # Sync engine interface
│   ├── ai-scores-api.json    # AI pipeline interface
│   ├── web-api.json          # Web portal endpoints
│   └── realtime-events.json  # Realtime event schema
└── scripts/                  # Development and deployment tools
```

## Agent Coordination

### Contract System
Each agent publishes contracts describing their interfaces:

1. **Claude Code** publishes `data-model.json` first
2. Other agents wait for required contracts before starting
3. Updates to contracts trigger coordinated updates

### Communication Protocol
- All agents read from `contracts/SIGNALS.md` for coordination
- Format: `{AGENT} {CHECKPOINT} complete — {timestamp}`
- Never block on another agent - stub interfaces when needed

## Development Workflow

### For Web Developers (Gemini)
```bash
cd apps/web
npm run dev
```

### For Desktop Developers (Claude)
```bash
cd apps/desktop
swift build

# Create a signed local .app bundle
../../scripts/build-desktop-app.sh

# Create a drag-install DMG
../../scripts/package-desktop-dmg.sh
```

### Build In Xcode
The desktop app now includes a generated Xcode project alongside the Swift Package build path.

1. Open Xcode.
2. Choose `File > Open...`.
3. Open `/Users/parker/Downloads/AI DAILY/AI Powered Dailies/AI DAILY/slate/apps/desktop/SLATE.xcodeproj`.
4. Wait for package resolution to finish.
5. In the scheme picker, choose `SLATE`.
6. In the destination picker, choose `My Mac`.
7. If you want cloud services enabled while running from Xcode, open `Product > Scheme > Edit Scheme...`,
   then add environment variables such as:
   `SLATE_SUPABASE_URL`, `SLATE_SUPABASE_ANON_KEY`, and optionally `SLATE_GEMMA_ENABLED=1`.
   For headless cloud auth fallbacks you can also add:
   `SLATE_GOOGLE_DRIVE_ACCESS_TOKEN`, `SLATE_DROPBOX_ACCESS_TOKEN`, or `SLATE_FRAMEIO_ACCESS_TOKEN`.
8. Press `Cmd+B` to build or `Cmd+R` to run.

If you want a distributable `.app` bundle or DMG after the Xcode build succeeds, use:

```bash
./scripts/build-desktop-app.sh
./scripts/package-desktop-dmg.sh
```

### For ML Engineers (Codex)
```bash
cd packages/ai-pipeline
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Optional Gemma 4 Local Insight Layer
SLATE can enrich narrative performance scoring with a local Gemma 4 helper built around the official
`google/gemma-4-E2B-it` Hugging Face loading pattern. The Swift pipeline keeps its existing local
heuristics and will only call Gemma when you opt in.

```bash
cd packages/ai-pipeline
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt

export SLATE_GEMMA_ENABLED=1
export SLATE_GEMMA_MODEL_ID=google/gemma-4-E2B-it
```

Useful optional overrides:
- `SLATE_GEMMA_PYTHON_EXECUTABLE=/path/to/python3`
- `SLATE_GEMMA_PORT=8797`
- `SLATE_GEMMA_ENABLE_THINKING=1`
- `HF_TOKEN=...` if your Hugging Face setup requires an authenticated download

When enabled, the AI pipeline auto-starts a bundled Python helper on demand, loads Gemma once, and
adds Gemma-backed performance reasoning on top of the existing numeric pacing heuristics.

## Performance Benchmarks

Target performance on M4 Max:
- ProRes 1hr proxy: < 6 min
- Audio sync 10-min take: < 30 sec
- Assembly 10-scene: < 5 sec
- App cold launch: < 2 sec
- Take browser 500 clips: < 200ms
- Review page first paint: < 1.5s

Run benchmarks:
```bash
./scripts/benchmark.sh
```

## Deployment

### Web Portal
```bash
cd apps/web
vercel --prod
```

### Desktop App
```bash
./scripts/build-desktop-app.sh
./scripts/package-desktop-dmg.sh
./scripts/generate-desktop-update-feed.sh --download-url "https://example.com/SLATE.dmg"
./scripts/notarize-desktop-app.sh --keychain-profile "AC_PASSWORD"
```

Artifacts are written to `dist/desktop/`.
The current repo packages a local `.app` bundle and DMG directly from the Swift Package target.
Use `--sign-identity "Developer ID Application: ..."` when you want a real distribution signature;
without it, the build script uses ad-hoc signing for local packaging.

Cloud sync now supports in-app OAuth for Google Drive, Dropbox, and Frame.io, with environment-token
fallbacks still available for CI or other headless flows. The desktop Cloud Sync sheet can push and
pull footage, assembly archives, and comment manifests.

To enable manual update checks inside the About sheet:
- Set `SLATE_DESKTOP_UPDATE_FEED_URL=https://.../appcast.json` before packaging, or inject the same
  URL into the generated app bundle through `build-desktop-app.sh`.
- Publish the JSON feed produced by `generate-desktop-update-feed.sh` next to your signed DMG.
- Notarize and staple the `.app` and `.dmg` with `notarize-desktop-app.sh` before distributing them.

### Supabase
```bash
cd supabase
supabase db push  # Deploy migrations
supabase functions deploy  # Deploy edge functions
```

## Security

### Data Protection
- Original media: READ ONLY
- Checksum verification on all transfers
- Encrypted storage and transmission
- Audit logging for all access

### Access Control
- Role-based permissions
- Expiring share links
- Password protection options
- SSO support (enterprise)

## Monitoring

- Performance: Custom benchmarks + Lighthouse CI
- Errors: Sentry integration
- Usage: Custom analytics dashboard
- Costs: Cloudflare R2 monitoring

## Contributing

1. Read your agent's `AGENT_*.md` file
2. Check `contracts/` for dependencies
3. Follow the coding standards for your stack
4. Update relevant contracts when changing interfaces
5. Add tests for new functionality

## License

© 2024 Mountain Top Pictures. All rights reserved.

## Support

- Internal: Slack #slate-dev
- Documentation: `docs/` directory
- Issues: GitHub Projects
