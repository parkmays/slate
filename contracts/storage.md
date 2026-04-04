# SLATE Storage Contract v1.1

> **LOCKED** — Key convention below is canonical. The `sign-proxy-url` Edge Function
> and the desktop `R2Uploader` must derive object keys server-side using exactly
> this structure. No client-supplied key paths are accepted.

## Overview

This document defines the storage contract for SLATE media assets using Cloudflare R2 as the storage backend. It specifies the object naming conventions, access patterns, and security requirements for all media files.

## Storage Backend

- **Provider**: Cloudflare R2
- **Bucket**: Configured via environment variables (`slate-proxies` prod, `slate-proxies-dev` staging)
- **Region**: Global edge network (no explicit region — R2 auto-routes to closest PoP)
- **Access**: Presigned URLs for all client reads; server-side PUT for daemon uploads

## Environment Variables

```bash
# Cloudflare R2 Configuration
R2_ACCOUNT_ID="your-account-id"
R2_ACCESS_KEY_ID="your-access-key-id"
R2_SECRET_ACCESS_KEY="your-secret-access-key"
R2_BUCKET_NAME="slate-proxies"
R2_PUBLIC_DOMAIN="proxies.mountaintoppics.com"  # Optional custom domain
```

## Object Naming Convention (CANONICAL — DO NOT DEVIATE)

### Key Structure

```
{projectId}/{clipId}/proxy.mp4
```

Both IDs are UUID v4 strings (lowercase with hyphens). The filename is always
`proxy.mp4`. If a proxy is regenerated the old object is overwritten at the
same key.

### Sidecar Files

Sidecar files share the same prefix:

```
{projectId}/{clipId}/proxy.mp4     ← primary proxy (always present when proxyStatus = ready)
{projectId}/{clipId}/waveform.png  ← waveform thumbnail (generated post-sync)
{projectId}/{clipId}/thumb.jpg     ← poster frame (first usable frame)
```

### Multi-Angle Clips

When `cameraGroupId` is populated, additional camera angles are stored alongside
the A-cam primary:

```
{projectId}/{clipId}/proxy.mp4     ← A-cam (primary)
{projectId}/{clipId}/proxy_B.mp4   ← B-cam
{projectId}/{clipId}/proxy_C.mp4   ← C-cam
{projectId}/{clipId}/proxy_D.mp4   ← D-cam
```

The `sign-proxy-url` Edge Function accepts an optional `angle` parameter
(`"A"` | `"B"` | `"C"` | `"D"`) defaulting to `"A"`.

### Assembly Exports

```
{projectId}/assemblies/{assemblyId}/v{version}/{assemblyId}_v{version}.{ext}
```

### Naming Rules

1. **Project ID**: UUID v4 format
2. **Clip ID**: UUID v4 format
3. **Assembly ID**: UUID v4 format
4. **File Extensions**:
   - Proxies: Always `.mp4`
   - Audio sidecars: `.wav` for synced audio

### proxyPath Field on Clip

`Clip.proxyPath` stores the canonical R2 key, NOT a presigned URL:
```
r2://slate-proxies/{projectId}/{clipId}/proxy.mp4
```
Presigned URLs are generated on-demand by the Edge Function.

## Proxy File Specification

| Property | Value |
|---|---|
| Container | MP4 (ftyp: `mp42`) |
| Video codec | H.264 Baseline/Main |
| Resolution | 1920 × 1080 or 1280 × 720 (downscaled from source) |
| Frame rate | Match source (drop frame preserved) |
| Bitrate | ~8 Mbps VBR, max 12 Mbps |
| Audio | AAC stereo 48 kHz, 192 kbps (first two channels of primary audio) |
| **Color space** | **Rec.709 with viewing LUT applied (SDR — no HDR)** |

### LUT Application (LOCKED to Option A)

All log-encoded source footage receives a Rec.709 viewing LUT during proxy
generation. The applied LUT is recorded in `Clip.proxyLUT`; the resulting color
space is always `Clip.proxyColorSpace = "rec709"`.

| Source format | LUT applied | proxyLUT value |
|---|---|---|
| ARRIRAW | ARRI LogC3 → Rec.709 (K1S1) | `arri_logc3_rec709` |
| BRAW | Blackmagic Film Gen 5 → Rec.709 | `bm_film_gen5_rec709` |
| R3D | IPP2 → Rec.709 | `red_ipp2_rec709` |
| ProRes 422 HQ, H264, MXF | None (pass-through) | `none` |

## Access Patterns

### Upload Flow (Desktop Daemon)

1. ProxyGenerator writes proxy to a local temp path.
2. On success, daemon calls `R2Uploader.upload(localPath, projectId, clipId)`.
3. Uploader PUTs to `{projectId}/{clipId}/proxy.mp4` using S3-compatible API.
4. On HTTP 200, daemon sets `Clip.proxyStatus = .ready` and
   `Clip.proxyPath = "r2://\(bucket)/\(projectId)/\(clipId)/proxy.mp4"`.

### Download Flow (Web Portal / iOS)

1. Client calls `POST /functions/v1/sign-proxy-url` with `{ clipId, projectId }`.
2. Edge Function verifies JWT and derives key as:
   ```typescript
   const key = `${projectId}/${clipId}/proxy.mp4`;
   ```
3. Function returns `{ url, expiresAt }` (24-hour expiry).
4. Client loads URL into `<video>` or HLS.js player.
5. If `expiresAt` is within 5 minutes, client re-fetches before playback.

### Presigned URL Lifetime

- **Duration: 24 hours** (increased from 1 hour — dailies reviews span a full shoot day)
- The Edge Function must never accept a raw `key` parameter from the client.
  Always derive the key server-side from validated `clipId` + `projectId`.

### Public Assets

- Proxy files may be made public after processing
- Public URL pattern: `{R2_PUBLIC_URL}/{projectId}/proxies/{clipId}.mp4`
- Access control via Supabase RLS policies

## Security Requirements

### Presigned URL Parameters

```javascript
// Upload URLs
{
  method: "PUT",
  contentType: "application/octet-stream",
  expiresIn: 3600,  // 1 hour
  checksum: "SHA256",  // Required for integrity
  maxFileSize: 107374182400  // 100GB
}

// Download URLs
{
  method: "GET",
  expiresIn: 3600,  // 1 hour
  range: "bytes",  // Supported for seeking
  responseHeaders: {
    "Cache-Control": "public, max-age=31536000",
    "Access-Control-Allow-Origin": "*"
  }
}
```

### Access Control

1. **Authentication**: Supabase JWT or share token
2. **Authorization**: Row Level Security (RLS) policies
3. **Audit Logging**: All access logged to Supabase audit table

## Lifecycle Management

### Retention Policy

| Object Type | Retention | Notes |
|-------------|-----------|-------|
| Originals | Permanent | Never delete automatically |
| Proxies | 90 days after assembly export | Can be regenerated |
| Audio Syncs | 90 days | Can be regenerated |
| Assemblies | Permanent | Versioned exports |
| Temp Uploads | 24 hours | Cleanup job runs daily |

### Versioning

- Assembly exports are versioned
- Keep all versions permanently
- Storage cost: ~$0.015/GB/month

## Edge Function Implementation

### Required Endpoints

#### `sign-proxy-url`
```typescript
// GET /functions/v1/sign-proxy-url
// Query: clipId, projectId
// Returns: Presigned URL for proxy download
```

#### `generate-upload-url`
```typescript
// POST /functions/v1/generate-upload-url
// Body: { projectId, clipId, fileSize, checksum }
// Returns: Presigned upload URL
```

#### `confirm-upload`
```typescript
// POST /functions/v1/confirm-upload
// Body: { projectId, clipId, objectKey }
// Action: Triggers ingest pipeline
```

## Monitoring

### Metrics to Track

1. **Storage Usage**: Per-project breakdown
2. **Bandwidth**: Egress costs by region
3. **Request Count**: API rate limiting
4. **Error Rate**: Failed uploads/downloads
5. **Processing Time**: Upload to proxy ready

### Alerts

- Storage usage > 80% of quota
- Egress costs > $100/day
- Error rate > 5%
- Processing queue > 100 items

## Migration Guide

### From Local Storage

1. Export existing metadata to Supabase
2. Batch upload originals to R2
3. Update file paths in database
4. Regenerate proxies
5. Update all client configurations

### Backup Strategy

- R2 provides 99.999999999% (11 9s) durability
- Cross-region replication automatic
- Optional: Additional backup to AWS S3 Glacier

## Cost Optimization

### Recommendations

1. Enable R2 zero-egress for proxies
2. Use appropriate proxy bitrates (8 Mbps for 4K)
3. Implement smart caching in clients
4. Monitor and delete unused temp files

### Estimated Costs (per 1TB/month)

- Storage: $15
- Requests (Class A): $4.50 (1M operations)
- Egress: $0 (within R2 zero-egress)
- **Total**: ~$20/TB/month

## Compliance

### Data Residency

- R2 allows region selection
- Data replicated within selected region
- GDPR compliant for EU regions

### Encryption

- All data encrypted at rest (AES-256)
- All data encrypted in transit (TLS 1.3)
- Customer-managed keys available (enterprise)

## Testing

### Unit Tests

- Presigned URL generation
- Object naming validation
- Access control verification

### Integration Tests

- Upload/download flow
- Edge function responses
- Error handling scenarios

### Load Tests

- Concurrent uploads (100+)
- Large file transfers (>50GB)
- Bandwidth saturation testing

## Troubleshooting

### Common Issues

1. **Presigned URL expired**
   - Solution: Refresh URL before expiration
   - Prevention: Use shorter expiration with refresh

2. **CORS errors**
   - Solution: Check R2 bucket CORS configuration
   - Prevention: Pre-flight OPTIONS requests

3. **Checksum mismatch**
   - Solution: Re-upload with correct checksum
   - Prevention: Calculate checksum client-side

### Debug Tools

- R2 access logs
- Cloudflare Analytics
- Supabase function logs
- Client-side error tracking
