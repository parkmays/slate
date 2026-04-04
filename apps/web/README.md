# SLATE Web Portal

The external review surface for SLATE’s Phase 1 MVP. This app is intentionally narrow: validate a share token, open a review page, sign a proxy URL, post annotations, and keep clip status in sync.

## What’s covered

- Token-based review access, including expired and password-protected links
- Proxy URL signing through `sign-proxy-url`
- Annotation writes through `sync-annotation`
- Clip review status updates through the local `/api/review-status` route
- Per-clip realtime updates using the `clip:{clipId}` contract
- Vitest coverage for the review client and API routes
- Playwright smoke coverage for the review flow in deterministic mock mode

## Local setup

```bash
cd "/Users/parker/Downloads/AI DAILY/AI Powered Dailies/AI DAILY/slate/apps/web"
npm install
```

Create `.env.local` with the local Supabase values you want the Next app to use:

```env
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-local-anon-key
SUPABASE_SERVICE_ROLE_KEY=your-local-service-role-key
```

For proxy signing against local or shared R2 storage, the edge function also expects:

```env
R2_ACCOUNT_ID=your-r2-account-id
R2_BUCKET_NAME=your-bucket-name
R2_ACCESS_KEY_ID=your-r2-access-key
R2_SECRET_ACCESS_KEY=your-r2-secret
```

## CI checks

Run the same checks the workflow now expects:

```bash
npm run type-check
npm run lint
npm run test
npm run build
npm run test:e2e
```

`npm run test:e2e` starts Next in mock review mode so the smoke tests stay deterministic and don’t require live Supabase data.

## Seeded local review workflow

This is the reproducible path future agents should use when they need a contract-accurate local smoke pass instead of the mock-mode Playwright suite.

1. Start local Supabase from the repo root:

```bash
cd "/Users/parker/Downloads/AI DAILY/AI Powered Dailies/AI DAILY/slate"
supabase start
supabase db reset
```

2. Confirm the seeded records from [`/Users/parker/Downloads/AI DAILY/AI Powered Dailies/AI DAILY/slate/supabase/seed.sql`](/Users/parker/Downloads/AI DAILY/AI Powered Dailies/AI DAILY/slate/supabase/seed.sql):

- valid review token: `valid-share-token`
- expired review token: `expired-token`
- password-protected review token: `password-protected-token`
- seeded narrative clip for proxy signing: `clip-narr-001`

3. Start the web app:

```bash
cd "/Users/parker/Downloads/AI DAILY/AI Powered Dailies/AI DAILY/slate/apps/web"
npm run dev
```

4. Open the seeded review link in the browser:

```text
http://127.0.0.1:3000/review/valid-share-token
```

5. Exercise the contract endpoints directly with seeded payloads:

Generate share link:

```bash
curl -X POST "http://127.0.0.1:54321/functions/v1/generate-share-link" \
  -H "Authorization: Bearer <supabase-jwt>" \
  -H "Content-Type: application/json" \
  -d '{
    "projectId": "proj-narrative-001",
    "scope": "project",
    "expiryHours": 24,
    "permissions": {
      "canComment": true,
      "canFlag": true,
      "canRequestAlternate": true
    }
  }'
```

Sign proxy URL:

```bash
curl -X POST "http://127.0.0.1:54321/functions/v1/sign-proxy-url" \
  -H "X-Share-Token: valid-share-token" \
  -H "Content-Type: application/json" \
  -d '{"clipId": "clip-narr-001"}'
```

Create synced annotation:

```bash
curl -X POST "http://127.0.0.1:54321/functions/v1/sync-annotation" \
  -H "X-Share-Token: valid-share-token" \
  -H "Content-Type: application/json" \
  -d '{
    "clipId": "clip-narr-001",
    "timecode": "00:00:12:00",
    "type": "note",
    "content": "Seeded review smoke note",
    "isPrivate": false,
    "authorName": "Local Smoke Tester"
  }'
```

6. Validate the browser behavior:

- `/review/expired-token` shows the expired access state
- `/review/password-protected-token` shows the password gate
- `/review/valid-share-token` loads the clip list, proxy shell, and annotation thread

## Notes

- The review route is the only required product surface in this round; there is no internal dashboard work hidden behind these checks.
- The Playwright suite uses mock review fixtures, while the seeded workflow above is the contract-accurate local pass for Supabase and edge functions.
