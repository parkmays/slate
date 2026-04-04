import { describe, expect, it } from 'vitest'
import {
  buildClipSearchMatch,
  buildReviewOpsSummary,
  clipLabel,
} from '@/lib/review-insights'
import type { ReviewClip } from '@/lib/review-types'

function makeClip(overrides: Partial<ReviewClip> = {}): ReviewClip {
  return {
    id: 'clip-1',
    projectId: 'project-1',
    reviewStatus: 'circled',
    proxyStatus: 'ready',
    duration: 96,
    sourceFps: 24,
    sourceTimecodeStart: '01:00:00:00',
    narrativeMeta: {
      sceneNumber: '24',
      shotCode: 'C',
      takeNumber: 2,
      cameraId: 'A Cam',
    },
    documentaryMeta: null,
    aiScores: {
      composite: 84,
      focus: 82,
      exposure: 80,
      stability: 78,
      audio: 88,
      performance: 81,
      contentDensity: 70,
      scoredAt: '2026-04-01T10:00:00.000Z',
      modelVersion: 'hybrid-local-v2',
      reasoning: [
        {
          dimension: 'performance',
          score: 81,
          flag: 'info',
          message: 'Performance lands after the pickup.',
          timecode: '01:00:05:00',
        },
      ],
    },
    annotations: [
      {
        id: 'annotation-1',
        userId: 'user-1',
        userDisplayName: 'Director',
        timecodeIn: '01:00:03:00',
        timecodeOut: null,
        body: 'Love this beat, @editor keep the softer pickup.',
        type: 'text',
        voiceUrl: null,
        createdAt: '2026-04-01T10:10:00.000Z',
        resolvedAt: null,
        isResolved: false,
        mentions: ['editor'],
        replies: [
          {
            id: 'reply-1',
            annotationId: 'annotation-1',
            userId: 'user-2',
            userDisplayName: 'Producer',
            body: 'Agree, this one feels most natural.',
            createdAt: '2026-04-01T10:12:00.000Z',
            mentions: [],
          },
        ],
      },
    ],
    projectMode: 'narrative',
    transcriptText: 'Keep the softer pickup and let the pause breathe.',
    transcriptStatus: 'ready',
    transcriptSegments: [
      {
        id: 'segment-1',
        startSeconds: 3,
        endSeconds: 8,
        startTimecode: '01:00:03:00',
        endTimecode: '01:00:08:00',
        text: 'Keep the softer pickup and let the pause breathe.',
        speaker: 'Talent',
      },
    ],
    syncResult: {
      confidence: 'high',
      method: 'waveform_correlation',
      offsetFrames: 0,
      driftPPM: 0,
      verifiedAt: '2026-04-01T10:00:00.000Z',
    },
    metadata: {
      camera: {
        model: 'Alexa Mini',
      },
      lens: '50mm',
      location: 'Stage 4',
    },
    aiProcessingStatus: 'ready',
    ...overrides,
  }
}

describe('review-insights', () => {
  it('indexes transcript, annotations, metadata, and AI reasoning for search', () => {
    const clip = makeClip()

    expect(buildClipSearchMatch(clip, 'softer pickup')?.reasons.map((reason) => reason.kind)).toEqual(
      expect.arrayContaining(['transcript', 'annotation'])
    )
    expect(buildClipSearchMatch(clip, 'alexa mini')?.reasons[0]?.kind).toBe('metadata')
    expect(buildClipSearchMatch(clip, 'performance lands')?.reasons[0]?.kind).toBe('ai')
    expect(buildClipSearchMatch(clip, clipLabel(clip))?.reasons[0]?.kind).toBe('label')
  })

  it('builds workflow and pipeline summaries for the ops panel', () => {
    const clips = [
      makeClip(),
      makeClip({
        id: 'clip-2',
        reviewStatus: 'flagged',
        proxyStatus: 'processing',
        transcriptStatus: 'error',
        aiProcessingStatus: 'error',
        aiScores: {
          composite: 42,
          focus: 40,
          exposure: 44,
          stability: 45,
          audio: 50,
          performance: 36,
          contentDensity: 20,
          scoredAt: '2026-04-01T10:15:00.000Z',
          modelVersion: 'hybrid-local-v2',
          reasoning: [],
        },
        annotations: [],
        syncResult: {
          confidence: 'manual_required',
          method: 'manual',
          offsetFrames: 14,
          driftPPM: 0,
          verifiedAt: null,
        },
      }),
    ]

    const summary = buildReviewOpsSummary(clips)

    expect(summary.totalClips).toBe(2)
    expect(summary.readyToAssembleCount).toBe(0)
    expect(summary.followUpCount).toBe(2)
    expect(summary.proxy.processing).toBe(1)
    expect(summary.transcript.error).toBe(1)
    expect(summary.ai.error).toBe(1)
    expect(summary.sync.manualRequired).toBe(1)
    expect(summary.smartSelects[0]?.clipId).toBe('clip-1')
    expect(summary.watchlist[0]?.clipId).toBe('clip-2')
    expect(summary.recentActivity[0]?.kind).toBe('reply')
  })
})
