import type {
  ReviewAnnotation,
  ReviewClip,
  ReviewProjectData,
  ReviewShareLink,
} from '@/lib/review-types'

interface ReviewMockFixture {
  shareLink: ReviewShareLink
  projectData: ReviewProjectData
}

const seedPasswordHash = '$2a$10$0IYdUkuvr/M0blEViWklLOaK3XMUajQiiGcqbp9fxvetkrGA6VUxW'

function buildMockClip(overrides: Partial<ReviewClip> = {}): ReviewClip {
  return {
    id: 'mock-clip-1',
    projectId: 'mock-project-1',
    reviewStatus: 'unreviewed',
    proxyStatus: 'ready',
    duration: 112,
    sourceFps: 23.976,
    sourceTimecodeStart: '01:00:00:00',
    narrativeMeta: {
      sceneNumber: '12',
      shotCode: 'B',
      takeNumber: 3,
      cameraId: 'A Cam',
    },
    documentaryMeta: null,
    aiScores: {
      composite: 78,
      focus: 82,
      exposure: 75,
      stability: 77,
      audio: 80,
      performance: null,
      contentDensity: null,
      scoredAt: '2026-03-29T18:00:00.000Z',
      modelVersion: 'heuristic-v1',
      reasoning: [
        {
          dimension: 'focus',
          score: 82,
          flag: 'info',
          message: 'Focus stays consistent through the take.',
          timecode: '01:00:04:00',
        },
      ],
    },
    annotations: [],
    projectMode: 'narrative',
    transcriptText: 'The line lands cleanly here. Try a softer pickup on the second sentence.',
    transcriptStatus: 'ready',
    transcriptSegments: [
      {
        id: 'segment-1',
        startSeconds: 2,
        endSeconds: 6,
        startTimecode: '01:00:02:00',
        endTimecode: '01:00:06:00',
        text: 'The line lands cleanly here.',
        speaker: 'Talent',
      },
      {
        id: 'segment-2',
        startSeconds: 8,
        endSeconds: 12,
        startTimecode: '01:00:08:00',
        endTimecode: '01:00:12:00',
        text: 'Try a softer pickup on the second sentence.',
        speaker: 'Director',
      },
    ],
    syncResult: {
      confidence: 'high',
      method: 'waveform_correlation',
      offsetFrames: 1,
      driftPPM: 0,
      verifiedAt: '2026-03-29T18:00:00.000Z',
    },
    metadata: {
      camera: {
        model: 'A Cam',
      },
      lens: '50mm',
    },
    aiProcessingStatus: 'ready',
    ...overrides,
  }
}

function buildMockShareLink(
  token: string,
  overrides: Partial<ReviewShareLink> = {}
): ReviewShareLink {
  return {
    id: `share-${token}`,
    project_id: 'mock-project-1',
    token,
    scope: 'project',
    scope_id: null,
    password_hash: null,
    expires_at: '2026-04-30T18:00:00.000Z',
    view_count: 4,
    permissions: {
      canComment: true,
      canFlag: true,
      canRequestAlternate: true,
    },
    project: {
      id: 'mock-project-1',
      name: 'Playwright Review Project',
      mode: 'narrative',
    },
    created_by: 'mock-user',
    created_at: '2026-03-29T18:00:00.000Z',
    ...overrides,
  }
}

function buildProjectData(
  clips: ReviewClip[],
  annotationsByClip: Record<string, ReviewAnnotation[]> = {}
): ReviewProjectData {
  const hydratedClips = clips.map((clip) => ({
    ...clip,
    annotations: annotationsByClip[clip.id] ?? clip.annotations,
  }))

  return {
    grouped: hydratedClips.reduce<Record<string, string[]>>((acc, clip) => {
      const key = clip.narrativeMeta
        ? `Scene ${clip.narrativeMeta.sceneNumber}`
        : clip.documentaryMeta?.subjectName || 'Uncategorized'

      if (!acc[key]) {
        acc[key] = []
      }
      acc[key].push(clip.id)
      return acc
    }, {}),
    clips: hydratedClips,
  }
}

export function getMockReviewFixture(token: string): ReviewMockFixture | null {
  if (token === 'playwright-valid-token') {
    const clips = [
      buildMockClip(),
      buildMockClip({
        id: 'mock-clip-2',
        reviewStatus: 'circled',
        duration: 89,
        narrativeMeta: {
          sceneNumber: '12',
          shotCode: 'C',
          takeNumber: 1,
          cameraId: 'B Cam',
        },
      }),
    ]

    return {
      shareLink: buildMockShareLink(token),
      projectData: buildProjectData(clips, {
        'mock-clip-1': [
          {
            id: 'annotation-seeded-1',
            userId: 'seed-user',
            userDisplayName: 'Seed Reviewer',
            timecodeIn: '01:00:05:12',
            timecodeOut: null,
            body: 'Seeded note for smoke coverage.',
            type: 'text',
            voiceUrl: null,
            createdAt: '2026-03-29T18:02:00.000Z',
            resolvedAt: null,
            isResolved: false,
            mentions: [],
            replies: [
              {
                id: 'reply-seeded-1',
                annotationId: 'annotation-seeded-1',
                userId: 'seed-user-2',
                userDisplayName: 'Producer',
                body: '@editor please check the alt take too.',
                createdAt: '2026-03-29T18:03:00.000Z',
                mentions: ['editor'],
              },
            ],
          },
        ],
      }),
    }
  }

  if (token === 'playwright-password-token') {
    return {
      shareLink: buildMockShareLink(token, {
        password_hash: seedPasswordHash,
      }),
      projectData: buildProjectData([buildMockClip()]),
    }
  }

  if (token === 'playwright-assembly-token') {
    return {
      shareLink: buildMockShareLink(token, {
        scope: 'assembly',
        scope_id: 'assembly-1',
      }),
      projectData: buildProjectData([buildMockClip()]),
    }
  }

  if (token === 'playwright-expired-token') {
    return {
      shareLink: buildMockShareLink(token, {
        expires_at: '2026-03-01T18:00:00.000Z',
      }),
      projectData: buildProjectData([buildMockClip()]),
    }
  }

  return null
}
