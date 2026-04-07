# ASC MHL Vendor Acceptance Matrix

This matrix maps SLATE's current ASC MHL implementation to common interoperability expectations for Silverstack/MediaVerify-style workflows.

Scope: ingest offload manifests written by `packages/ingest-daemon/Sources/IngestDaemon/VerifiedCopyEngine.swift`, plus CI/runtime validation wiring.

## Status Legend

- `PASS`: Implemented and validated in repo.
- `PARTIAL`: Implemented but with practical caveats.
- `OPEN`: Not implemented yet.

## Compatibility Matrix

| Expectation | Vendor Rationale | SLATE Status | Evidence |
|---|---|---|---|
| ASC MHL v2 XML root (`hashlist`, namespace, schema location) | Parser compatibility for ingest/verify tooling | PASS | `MHLManifestWriter.write()` in `packages/ingest-daemon/Sources/IngestDaemon/VerifiedCopyEngine.swift` |
| Creator/process blocks (`creatorinfo`, `processinfo`) | Required provenance metadata | PASS | `MHLManifestWriter.write()` |
| Canonical per-file C4 hash | Chain portability and cross-tool trust | PASS | `hashFileC4()` + `c4String(...)` in `VerifiedCopyEngine.swift` |
| Per-file md5 + xxh64 | Mixed-tool compatibility and fast verification | PASS | `<md5>` and `<xxh64>` output in `MHLManifestWriter.write()` |
| `ascmhl/` folder generation model | Recognizable history location | PASS | `MHLManifestWriter.write()` creates `<historyRoot>/ascmhl` |
| Sequenced generation manifests | History continuity and deterministic ordering | PASS | `0001_*` naming with sequence tracking from chain |
| `ascmhl_chain.xml` update | Required chain pointer for latest generation(s) | PASS | `readChainEntries()` + `renderChainXML()` |
| Chain entries with C4 fingerprint | Directory schema requirement (`<c4>`) | PASS | Chain fingerprint now uses canonical C4 of generated `.mhl` |
| Root-relative `hash/path` values | Avoid filename collisions, preserve location fidelity | PASS | `relativePath(from:to:)` |
| `roothash` emission | Top-level completeness check | PASS | `computeRootDirectoryHashes(...)` + `<roothash>` |
| `directoryhash` emission | Directory-level content/structure verification | PASS | `<directoryhash>` entries for computed directories |
| Nested child-history references (`<references><hashlistreference>`) | Multi-card / nested history rollup | PASS | `listChildHistoryReferences(...)` and XML emission in writer |
| XSD validation in CI | Prevent schema regressions before shipping | PASS | `.github/workflows/desktop-ci.yml` + `scripts/validate-ascmhl.sh` |
| Local validation fallback when xmllint missing | Developer portability | PASS | Python well-formed fallback in `scripts/validate-ascmhl.sh` |
| Ignore-pattern persistence in emitted MHL | Stable scope/behavior across generations | OPEN | Not currently written to `<ignore>` |
| Rename lineage (`previousPath`) | Better renamed-file continuity across generations | OPEN | Not currently emitted |
| Multi-format directory/roothash (beyond xxh64) | Optional parity for stricter environments | PARTIAL | Currently xxh64 only |

## Operational Acceptance Checks

Use this quick checklist before a release candidate:

1. Run ingest tests:
   - `cd packages/ingest-daemon && swift test`
2. Run ASC MHL validator:
   - `bash scripts/validate-ascmhl.sh`
3. Confirm generated fixtures validate both:
   - manifest (`ASCMHL.xsd`)
   - chain (`ASCMHLDirectory.xsd`)
4. Spot-check generated top-level `.mhl` contains:
   - `<c4 action="verified"...>`
   - `<roothash>`
   - `<references>` (when child histories exist)

## Residual Risk Notes

- The implementation is now schema-valid and chain-capable for common vendor interoperability paths, but does not yet persist ignore patterns or rename lineage semantics.
- If a receiving pipeline requires strict parity on additional optional fields, treat the `OPEN` items as release blockers for that pipeline profile.
