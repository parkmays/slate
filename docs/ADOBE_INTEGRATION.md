# Adobe product integration (SLATE)

This document records the **primary integration story** for SLATE, **Frame.io V4 entitlement and auth** (from the official Getting Started guide), and **backend-oriented token and rate-limit handling**. For interchange validation, see [EXPORT_NLE_VALIDATION.md](EXPORT_NLE_VALIDATION.md). For collaborative review in SLATE, see [REVIEW_PARITY_AND_E2E.md](REVIEW_PARITY_AND_E2E.md).

## 1. Primary integration story (decision)

| Layer | Role in SLATE |
|--------|----------------|
| **File interchange (shipped)** | SLATE remains the editorial source of truth. [export-writers](../packages/export-writers) produces **Premiere Pro XML** (XMEML), **CMX 3600 EDL**, FCPXML, Resolve XML, AAF, etc. Editors import these into Premiere or other NLEs—no Adobe plugin required. |
| **Optional cloud (Frame.io V4)** | Teams already on **Adobe-provisioned Frame.io** can use the **Frame.io V4 REST API** for review and asset workflows. SLATE can integrate as a **secondary** consumer or publisher (e.g. sync proxies/metadata) while GRDB + Supabase remain canonical for the desktop product unless you explicitly move to a Frame-first model. |
| **In-app (UXP)** | A **Premiere Pro UXP** panel is appropriate for **in-editor** actions (e.g. call Frame.io or a future SLATE HTTP API). The repo includes a **minimal panel** under [`integrations/adobe-uxp-premiere`](../integrations/adobe-uxp-premiere) that performs one authenticated `GET /v4/me` call. Production flows should prefer **server-side tokens** (see below), not long-lived secrets in panels. |

**Non-goals for this scaffold:** Full OAuth inside the panel, bidirectional SLATE ↔ Frame.io sync, and CEP/After Effects scripting—these are follow-on projects.

## 2. Frame.io V4 entitlement and authentication (validated against Getting Started)

The following is aligned with [Frame.io V4 Getting Started](https://next.developer.frame.io/platform/v4/docs/getting-started) and [V4 overview](https://next.developer.frame.io/platform/v4/docs/overview).

### Account and product entitlement

- **V4 API** targets **Frame.io V4** accounts. The overview states that using the documented V4 endpoints requires a **Frame.io V4 account administered via the Adobe Admin Console** (legacy-only accounts use different docs/APIs).
- **Adobe Developer Console:** The Getting Started guide states that the first step is to create a **Project** in the [Adobe Developer Console](https://developer.adobe.com/developer-console/docs/guides/getting-started/) and add the **Frame.io API** to that project. Console “Projects” are **your OAuth/API application**, not Frame.io “projects” inside the product.

### OAuth 2.0 and Adobe IMS

- The V4 API uses **OAuth 2.0** and **[Adobe IMS](https://experienceleague.adobe.com/en/docs/commerce-admin/start/admin/ims/adobe-ims-integration-overview)** for user authentication; each request sends an **access token** in the `Authorization: Bearer` header.
- **AuthZ** (what the user can do) is determined by **roles and permissions inside Frame.io**, not by varying IMS scopes alone—scopes are described as **static**; fine-grained permission is in the product.
- **Developer setup (Postman / apps):** The guide describes adding an **OAuth Web App** credential to the Console project, setting `IMS_CLIENT_ID` and `IMS_CLIENT_SECRET`, and using the **authorization code** flow so Postman can obtain a Bearer token. It explicitly warns that **client secrets must not ship in client-side code**—appropriate for a web app with a **server**, not for distributing secrets inside a UXP panel binary.

### Verifying tokens and discovering `account_id`

- After authentication, call **`GET https://api.frame.io/v4/me`** (see official Postman collection: “GET me” under Users). A successful **200** response includes user info; use the **`account_id`** value as the path prefix for most other V4 routes (e.g. `/v4/accounts/{account_id}/…`).

### OpenAPI and SDKs

- **OpenAPI:** `https://api.frame.io/v4/openapi.json`
- **SDKs:** Official TypeScript (`frameio` on npm) and Python (`frameio` on PyPI) are documented in the same guide.

## 3. Token storage and rate limiting (backend-oriented design)

### Where tokens should live

| Deployment | Token handling |
|------------|----------------|
| **SLATE backend (Supabase Edge Functions, or other server)** | Prefer **short-lived access tokens** and **refresh** via OAuth using **client secret stored only on the server**. Map Frame.io `account_id` / workspace IDs to SLATE projects in your database. Never log tokens. |
| **UXP panel (Premiere)** | **Do not** embed OAuth client secrets. Options: (1) **Manual paste** of a Bearer token for **development only** (as in the sample panel); (2) **Device/user login** via system browser + localhost redirect handled by a **small local or remote service** that exchanges the code for tokens; (3) **SLATE-issued API tokens** from your backend after the user signs in to SLATE (same pattern as other first-party APIs). |
| **Adobe IMS vs Frame.io** | Console credentials and IMS token exchange are **Adobe-side**; Frame.io **resource** calls use the resulting **Bearer** token against `api.frame.io`. |

### Rate limiting and 429 handling

Per the Getting Started guide:

- Limits vary **by resource/operation** (rough range cited: **10 requests/minute** up to **100 requests/second**), enforced **per account**, with **leaky-bucket** behavior.
- Responses may include: `x-ratelimit-limit`, `x-ratelimit-remaining`, `x-ratelimit-window` (window in **ms**).
- On **429**, wait **at least one second**, then retry with **exponential backoff** (double wait on repeated 429s). On **5xx**, wait **≥30 seconds** before retry; cap automated retries.

### Pagination

- List endpoints use **cursor** pagination via `links.next` (opaque `after` parameter). Do not construct cursor strings manually; follow `links.next` from the previous response.

## 4. Related links

- [Premiere UXP](https://developer.adobe.com/premiere-pro/uxp/)
- [Photoshop UXP](https://developer.adobe.com/photoshop/uxp/2022/)
- [Adobe Developer Console](https://developer.adobe.com/console)
- [Frame.io V4 API reference](https://next.developer.frame.io/platform/v4/api/current/)
- Community AE resources: [docsforadobe.dev](https://docsforadobe.dev/?app=after-effects) (not a substitute for official Adobe docs)
- Legacy CEP: [Adobe-CEP/CEP-Resources](https://github.com/Adobe-CEP/CEP-Resources)
