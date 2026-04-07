# SLATE Premiere UXP panel (spike)

This folder is a **minimal UXP shell** for Phase 4. It documents the architecture split:

- **UXP panel (this spike):** HTML/JS UI, `fetch` to Supabase + SLATE web API, download proxies via signed R2 URLs from `supabase/functions/v1/sign-proxy-url`.
- **Timeline automation:** Premiere’s classic **ExtendScript** DOM is **not** exposed to UXP. A production build should either:
  - **v1:** Download proxies to a folder and let the editor import manually, or
  - **v2:** Add a **CEP/ExtendScript** bridge panel to build sequences programmatically.

## Load in Premiere

1. Install **Adobe UXP Developer Tools**.
2. **Add Plugin** → select this directory (contains `manifest.json`).
3. Launch Premiere Pro (24+) and open **Plugins → Development → SLATE** (label may vary).

## Next steps

- Bundle a thin client with `esbuild`/`vite` if you add React.
- Reuse `apps/web` Supabase session patterns (PKCE) and API routes for assembly lists.
