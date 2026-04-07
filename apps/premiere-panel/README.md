# SLATE Premiere UXP panel (spike)

This folder is a **minimal UXP shell** for live marker sync. It documents the architecture split:

- **UXP panel (this spike):** HTML/JS UI, realtime subscription to `clip:{clipId}` channels, and `fetch` to SLATE web APIs for annotation create/reply flows.
- **Timeline automation:** Premiere’s classic **ExtendScript** DOM is **not** exposed to UXP. A production build should either:
  - **v1:** Download proxies to a folder and let the editor import manually, or
  - **v2:** Add a **CEP/ExtendScript** bridge panel to build sequences programmatically.

## Load in Premiere

1. Install **Adobe UXP Developer Tools**.
2. **Add Plugin** → select this directory (contains `manifest.json`).
3. Launch Premiere Pro (24+) and open **Plugins → Development → SLATE** (label may vary).

## Next steps

- Bundle a thin client with `esbuild`/`vite` if you add React.
- Replace `plotMarkerOnActiveSequence()` stub with host-specific timeline marker APIs.
- Reuse `apps/web` Supabase session patterns (PKCE) for first-party auth flows.
