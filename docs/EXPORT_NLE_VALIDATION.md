# Editorial export validation (NLE round-trip)

For Adobe ecosystem context (Premiere UXP, Frame.io V4 API, token handling), see [ADOBE_INTEGRATION.md](ADOBE_INTEGRATION.md).

Use this checklist when validating [`packages/export-writers`](../packages/export-writers) output beyond automated unit tests (`ExportWritersTests`).

## Automated coverage

- Swift tests under `packages/export-writers/Tests/ExportWritersTests/` call `dryRun` and `export` for each [`ExportFormat`](../packages/export-writers/Sources/ExportWriters/ExportWriter.swift) and assert XML/EDL/JSON structure.
- **AAF** runs the bundled Python `aaf_bridge.py` helper (via `/usr/bin/env python3`); failures surface as [`ExportWriterError.externalToolUnavailable`](../packages/export-writers/Sources/ExportWriters/ExportWriter.swift) if resources are missing or `python3` is unavailable.

## Manual QA per format

| Format | Target app | Verify |
|--------|------------|--------|
| FCPXML | Final Cut Pro | Timeline opens; keywords/markers/audio roles appear; relink if proxies are offline. |
| CMX 3600 EDL | Premiere / Resolve / Avid | Reel names and `FROM CLIP NAME` comments match assembly; locators land near expected timecode. |
| Premiere XML | Adobe Premiere Pro | Bins, markers, Essential Sound metadata import. |
| DaVinci Resolve XML | DaVinci Resolve | Subject bins / smart-bin hints; color flags if used. |
| AAF | Media Composer | Track layout matches; relink to proxy/mezzanine paths from manifest. |
| Assembly archive | SLATE / tooling | JSON opens; checksums and clip IDs match GRDB/export context. |

## External tools

If an export returns `externalToolUnavailable` or `externalToolFailed`, install the tool named in the error message and document the version in release notes.
