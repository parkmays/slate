import React from 'react'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import ReviewClient from '../client'
import type {
  ReviewClip,
  ReviewProjectData,
  ReviewShareLink,
} from '@/lib/review-types'

const subscription = vi.hoisted(() => {
  let state = 'SUBSCRIBED'
  const handlers = new Map<string, (payload: any) => void>()

  const channel: any = {
    on: vi.fn((kind: string, filter: { event?: string }, handler: (payload: any) => void) => {
      if (kind === 'broadcast' && filter.event) {
        handlers.set(filter.event, handler)
      }
      return channel
    }),
    send: vi.fn().mockResolvedValue('ok'),
    subscribe: vi.fn((callback?: (status: string) => void) => {
      callback?.(state)
      return channel
    }),
  }

  const client = {
    channel: vi.fn(() => channel),
    removeAllChannels: vi.fn().mockResolvedValue([]),
  }

  return {
    client,
    emit(event: string, payload: any) {
      handlers.get(event)?.(payload)
    },
    setState(nextState: string) {
      state = nextState
    },
    reset() {
      state = 'SUBSCRIBED'
      handlers.clear()
      channel.on.mockClear()
      channel.subscribe.mockClear()
      client.channel.mockClear()
      client.removeAllChannels.mockClear()
    },
  }
})

vi.mock('@/lib/supabase', () => ({
  createBrowserSupabaseClient: vi.fn(() => subscription.client),
}))

const shareLink: ReviewShareLink = {
  id: 'share-1',
  project_id: 'project-1',
  token: 'valid-token',
  scope: 'project',
  scope_id: null,
  password_hash: null,
  expires_at: '2026-04-01T12:00:00.000Z',
  role: 'editor',
  view_count: 3,
  permissions: {
    canComment: true,
    canFlag: true,
    canRequestAlternate: true,
  },
  project: {
    id: 'project-1',
    name: 'Review Flow Test',
    mode: 'narrative',
  },
  created_by: 'user-1',
  created_at: '2026-03-29T12:00:00.000Z',
}

const projectData: ReviewProjectData = {
  grouped: {
    'Scene 12': ['clip-1'],
  },
  clips: [
    {
      id: 'clip-1',
      projectId: 'project-1',
      reviewStatus: 'unreviewed',
      proxyStatus: 'ready',
      duration: 102,
      sourceFps: 24,
      sourceTimecodeStart: '01:00:00:00',
      narrativeMeta: {
        sceneNumber: '12',
        shotCode: 'B',
        takeNumber: 2,
        cameraId: 'A Cam',
      },
      documentaryMeta: null,
      aiScores: {
        composite: 72,
        focus: 75,
        exposure: 70,
        stability: 71,
        audio: 73,
        performance: null,
        contentDensity: null,
        scoredAt: '2026-03-29T10:00:00.000Z',
        modelVersion: 'heuristic-v1',
        reasoning: [],
      },
      annotations: [],
      projectMode: 'narrative',
      transcriptText: 'This is a transcript line.',
      transcriptStatus: 'ready',
      transcriptSegments: [
        {
          id: 'segment-1',
          startSeconds: 0,
          endSeconds: 4,
          startTimecode: '01:00:00:00',
          endTimecode: '01:00:04:00',
          text: 'This is a transcript line.',
          speaker: 'Talent',
        },
      ],
      syncResult: {
        confidence: 'high',
        method: 'waveform_correlation',
        offsetFrames: 0,
        driftPPM: 0,
        verifiedAt: '2026-03-29T10:00:00.000Z',
      },
      metadata: {
        camera: { model: 'A Cam' },
      },
      aiProcessingStatus: 'ready',
    } satisfies ReviewClip,
  ],
}

function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

describe('ReviewClient', () => {
  beforeEach(() => {
    subscription.reset()

    vi.stubGlobal(
      'fetch',
      vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
        const url = String(input)

        if (url === '/api/proxy-url') {
          return jsonResponse({
            signedUrl: 'https://cdn.example.com/mock-video.m3u8',
            thumbnailUrl: 'https://cdn.example.com/mock-thumb.jpg',
            expiresAt: '2026-04-01T12:00:00.000Z',
          })
        }

        if (url === '/api/face-clusters/clip-1') {
          return jsonResponse({ clusters: [] })
        }

        if (url === '/api/annotations' && init?.method === 'POST') {
          const payload = JSON.parse(String(init.body))
          return jsonResponse(
            {
              annotation: {
                id: 'annotation-new',
                userId: 'share-token',
                userDisplayName: 'Reviewer',
                timecodeIn: payload.timecodeIn,
                timecodeOut: null,
                body: payload.body,
                type: payload.type,
                voiceUrl: null,
                createdAt: '2026-03-29T12:05:00.000Z',
                resolvedAt: null,
                isResolved: false,
                mentions: [],
                replies: [],
              },
            },
            201
          )
        }

        if (url === '/api/clips/clip-1/status') {
          return jsonResponse({ clipId: 'clip-1', status: 'circled' })
        }

        if (url === '/api/clips/clip-1/request-alternate') {
          return jsonResponse(
            {
              annotation: {
                id: 'alternate-1',
                userId: 'share-token',
                userDisplayName: 'Reviewer',
                timecodeIn: '00:00:00:00',
                timecodeOut: null,
                body: 'REQUEST ALTERNATE: Need an alt.',
                type: 'text',
                voiceUrl: null,
                createdAt: '2026-03-29T12:06:00.000Z',
                resolvedAt: null,
                isResolved: false,
                mentions: [],
                replies: [],
              },
            },
            201
          )
        }

        throw new Error(`Unexpected fetch: ${url}`)
      })
    )
  })

  it('renders the selected clip and requests a proxy URL', async () => {
    render(<ReviewClient shareLink={shareLink} projectData={projectData} token="valid-token" />)

    expect(screen.getByText('Review Flow Test')).toBeInTheDocument()

    await waitFor(() => {
      expect(screen.getByTestId('proxy-player-shell')).toBeInTheDocument()
    })

    expect(global.fetch).toHaveBeenCalledWith(
      '/api/proxy-url',
      expect.objectContaining({
        method: 'POST',
        headers: expect.objectContaining({
          'X-Share-Token': 'valid-token',
        }),
      })
    )
  })

  it('shows an explicit proxy error state when signing fails', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => jsonResponse({ error: 'Proxy missing' }, 404))
    )

    render(<ReviewClient shareLink={shareLink} projectData={projectData} token="valid-token" />)

    await waitFor(() => {
      expect(screen.getByTestId('proxy-player-error')).toBeInTheDocument()
    })

    expect(screen.getByText('Proxy missing')).toBeInTheDocument()
  })

  it('posts annotations and appends them to the panel', async () => {
    const user = userEvent.setup()

    render(<ReviewClient shareLink={shareLink} projectData={projectData} token="valid-token" />)

    await waitFor(() => {
      expect(screen.getByTestId('proxy-player-shell')).toBeInTheDocument()
    })

    await user.type(screen.getByTestId('annotation-textarea'), 'Need alternate for line read.')
    await user.click(screen.getByTestId('post-annotation'))

    await waitFor(() => {
      expect(screen.getByText('Need alternate for line read.')).toBeInTheDocument()
    })
  })

  it('applies realtime annotation updates', async () => {
    render(<ReviewClient shareLink={shareLink} projectData={projectData} token="valid-token" />)

    await waitFor(() => {
      expect(subscription.client.channel).toHaveBeenCalledWith('clip:clip-1')
    })

    subscription.emit('annotation_added', {
      payload: {
        annotation: {
          id: 'annotation-live',
          userId: 'share-token',
          userDisplayName: 'Live Reviewer',
          timecodeIn: '01:00:10:00',
          timecodeOut: null,
          body: 'Live note from realtime.',
          type: 'text',
          voiceUrl: null,
          createdAt: '2026-03-29T12:10:00.000Z',
          resolvedAt: null,
          isResolved: false,
          mentions: [],
          replies: [],
        },
      },
    })

    await waitFor(() => {
      expect(screen.getByText('Live note from realtime.')).toBeInTheDocument()
    })
  })

  it('shows the realtime warning banner when the channel is degraded', async () => {
    subscription.setState('CHANNEL_ERROR')

    render(<ReviewClient shareLink={shareLink} projectData={projectData} token="valid-token" />)

    await waitFor(() => {
      expect(screen.getByTestId('realtime-banner')).toBeInTheDocument()
    })

    expect(screen.getByText(/realtime connection is channel_error/i)).toBeInTheDocument()
  })
})
