# Premiere Pro UXP — Frame.io V4 probe

Minimal [UXP](https://developer.adobe.com/premiere-pro/uxp/) panel for **Premiere Pro** that calls **`GET https://api.frame.io/v4/me`** with a pasted Bearer token. Used to verify Adobe IMS–issued tokens against Frame.io V4 during integration work.

**Security:** Treat pasted tokens as **development-only**. Production panels should use OAuth with a **server-held client secret** or **SLATE backend–issued** tokens (see [docs/ADOBE_INTEGRATION.md](../../docs/ADOBE_INTEGRATION.md)).

## Requirements

- Premiere Pro **25.1+** (manifest `minVersion`; match your install or lower the field if Adobe documents compatibility).
- A Frame.io **V4** account under **Adobe Admin Console** provisioning, plus API access configured in [Adobe Developer Console](https://developer.adobe.com/console).

## Load in development

1. Install [Adobe UXP Developer Tools](https://developer.adobe.com/premiere-pro/uxp/plugins/) (see current Adobe instructions).
2. Open **UXP Developer Tools** and use **Add Plugin** (or load manifest) pointing at this folder’s **`manifest.json`**.
3. Launch Premiere Pro and open the panel **SLATE Frame.io** from the Plugins / UXP menu (exact location depends on Premiere version).

## Authenticated request

1. Obtain a Bearer access token using the Frame.io V4 Postman flow or your OAuth implementation (see Frame.io [Getting Started](https://next.developer.frame.io/platform/v4/docs/getting-started)).
2. Paste the token into the panel and click **GET /v4/me**.
3. A **200** response includes user metadata and **`account_id`** for subsequent API calls.

## Network permissions

The manifest allows **`https://api.frame.io` only**. If you add OAuth callback hosts or IMS endpoints in-panel, extend `requiredPermissions.network.domains` (or follow Adobe’s `oauth-workflow-sample` pattern with `"domains": "all"` for local development only).

## References

- [AdobeDocs/uxp-premiere-pro-samples](https://github.com/AdobeDocs/uxp-premiere-pro-samples) (official manifests and OAuth sample)
