# SLATE Web Portal - Development Guide

## Overview

The SLATE web portal is a Next.js 14 application that provides secure video review and collaboration capabilities. It integrates with Supabase for real-time features and Cloudflare R2 for video storage.

## Architecture

### Tech Stack
- **Framework**: Next.js 14 with App Router
- **Styling**: TailwindCSS + shadcn/ui
- **State Management**: React hooks + Zustand
- **Real-time**: Supabase Realtime
- **Video**: HLS.js for adaptive streaming
- **Database**: Supabase (PostgreSQL)
- **Storage**: Cloudflare R2
- **Deployment**: Vercel

### Key Components

```
app/
├── review/[token]/
│   ├── page.tsx          # Server component (auth, data loading)
│   ├── client.tsx        # Client component (UI, real-time)
│   └── PasswordGate.tsx  # Password protection UI
components/
├── ClipList.tsx          # Clip browser with hierarchy support
├── VideoPlayer.tsx       # HLS player with annotation markers
├── AnnotationPanel.tsx   # Real-time annotation system
├── ReviewHeader.tsx      # Project info and actions
└── ui/                   # shadcn/ui components
```

## Getting Started

### Prerequisites
- Node.js 18+
- Supabase CLI
- Cloudflare R2 bucket (production)

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd slate

# Quick start (includes Supabase setup)
./scripts/dev-web.sh

# Or manual setup:
cd apps/web
npm install
cp .env.example .env.local
# Edit .env.local with your configuration
npm run dev
```

### Environment Variables

```env
# Required
NEXT_PUBLIC_SUPABASE_URL=your_supabase_url
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_supabase_anon_key

# Optional (production)
R2_ACCOUNT_ID=your_r2_account_id
R2_BUCKET_NAME=your_bucket_name
R2_ACCESS_KEY_ID=your_access_key
R2_SECRET_ACCESS_KEY=your_secret_key
```

## Features

### 1. Secure Share Links
- Token-based access control
- Password protection (optional)
- Configurable expiry
- Scoped permissions (project/scene/assembly)

### 2. Video Playback
- HLS adaptive streaming
- Custom controls with scrub bar
- Annotation markers on timeline
- Keyboard shortcuts
- Playback rate control

### 3. Real-time Collaboration
- Instant annotation sync
- Live user presence
- Real-time status updates
- Threaded replies

### 4. Dual Mode Support
- **Narrative**: Scene → Setup → Take hierarchy
- **Documentary**: Subject → Day → Clip organization

## API Integration

### Edge Functions

1. **generate-share-link**
   ```typescript
   POST /functions/v1/generate-share-link
   Body: {
     projectId: string,
     scope: 'project' | 'scene' | 'subject' | 'assembly',
     scopeId?: string,
     permissions: {
       canComment: boolean,
       canFlag: boolean,
       canRequestAlternate: boolean
     }
   }
   ```

2. **sign-proxy-url**
   ```typescript
   POST /functions/v1/sign-proxy-url
   Body: { clipId: string }
   Returns: { signedUrl: string, thumbnailUrl: string }
   ```

3. **sync-annotation**
   ```typescript
   POST /functions/v1/sync-annotation
   Body: {
     clipId: string,
     timecode: string,
     type: 'note' | 'flag' | 'bookmark' | 'question' | 'action',
     content: string,
     isPrivate?: boolean
   }
   ```

### Real-time Subscriptions

```typescript
// Annotations
supabase
  .channel(`annotations:${projectId}`)
  .on('postgres_changes', { 
    event: 'INSERT', 
    schema: 'public', 
    table: 'annotations' 
  }, handleNewAnnotation)
  .subscribe()
```

## Performance Optimizations

### 1. Video Streaming
- HLS adaptive bitrate
- Segment preloading
- Efficient buffering strategy
- Thumbnail generation

### 2. UI Performance
- React.memo for expensive components
- Virtual scrolling for large clip lists
- Debounced search/filter
- Optimistic updates

### 3. Network Optimization
- API response caching
- Image optimization
- Bundle splitting
- Edge function caching

## Testing

### Unit Tests
```bash
cd apps/web
npm run test
```

### E2E Tests
```bash
cd apps/web
npx playwright test
```

### Performance Testing
```bash
# Lighthouse CI
npm run build
npm run lighthouse
```

## Deployment

### Vercel (Recommended)

```bash
# Install Vercel CLI
npm i -g vercel

# Deploy
vercel --prod
```

### Environment Setup
1. Connect Vercel to your GitHub repo
2. Configure environment variables in Vercel dashboard
3. Set up custom domain (optional)

### CI/CD Pipeline

The `.github/workflows/ci.yml` includes:
- Contract validation
- Type checking
- Linting
- Testing
- Automatic deployment on main branch

## Troubleshooting

### Common Issues

1. **HLS.js not loading**
   - Check if HLSProvider is mounted
   - Verify CDN accessibility
   - Check browser console for errors

2. **Real-time not working**
   - Verify Supabase Realtime is enabled
   - Check RLS policies
   - Ensure proper channel names

3. **Video not playing**
   - Check R2 configuration
   - Verify signed URLs
   - Check CORS settings

4. **Annotations not saving**
   - Verify edge function deployment
   - Check permissions
   - Review Supabase logs

### Debug Mode

Enable debug logging:
```javascript
// In browser console
localStorage.setItem('slate-debug', 'true')
```

## Security Considerations

1. **Data Access**
   - All proxy access via signed URLs
   - RLS policies enforced
   - Token-based authentication

2. **XSS Protection**
   - Content Security Policy
   - Input sanitization
   - Safe HTML rendering

3. **Rate Limiting**
   - API rate limits
   - Share link view limits
   - DDoS protection

## Contributing

1. Follow the existing code style
2. Use TypeScript strictly
3. Add tests for new features
4. Update documentation
5. Ensure performance targets are met

## Performance Targets

- First paint: < 1.5s
- HLS player ready: < 2s
- Annotation sync: < 100ms
- Share link generation: < 500ms

## Support

- Documentation: `docs/` directory
- Issues: GitHub Issues
- Discussions: GitHub Discussions