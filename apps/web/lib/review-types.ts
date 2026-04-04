export type ReviewStatus = 'unreviewed' | 'circled' | 'flagged' | 'x' | 'deprioritized'

export type AnnotationType = 'text' | 'voice'

export interface ReviewAnnotationReply {
  id: string
  annotationId: string
  userId: string
  userDisplayName: string
  body: string
  createdAt: string
  mentions: string[]
}

export interface ReviewSharePermissions {
  canComment: boolean
  canFlag: boolean
  canRequestAlternate: boolean
}

export interface ReviewAnnotation {
  id: string
  userId: string
  userDisplayName: string
  timecodeIn: string
  timecodeOut: string | null
  body: string
  type: AnnotationType
  voiceUrl: string | null
  createdAt: string
  resolvedAt: string | null
  isResolved: boolean
  mentions: string[]
  replies: ReviewAnnotationReply[]
}

export interface ReviewAIScoreReason {
  dimension: string
  score: number
  flag: 'info' | 'warning' | 'error'
  message: string
  timecode: string | null
}

export interface ReviewAIScores {
  composite: number
  focus: number
  exposure: number
  stability: number
  audio: number
  performance: number | null
  contentDensity: number | null
  scoredAt: string
  modelVersion: string
  reasoning: ReviewAIScoreReason[]
}

export interface ReviewTranscriptSegment {
  id: string
  startSeconds: number
  endSeconds: number
  startTimecode: string
  endTimecode: string
  text: string
  speaker: string | null
}

export interface ReviewSyncResult {
  confidence: 'high' | 'medium' | 'low' | 'manual_required' | 'unsynced'
  method: string
  offsetFrames: number
  driftPPM: number
  verifiedAt: string | null
}

export interface ReviewAssemblyClipRange {
  id: string
  clipId: string
  label: string
  order: number
  timecodeIn: string
  timecodeOut: string
  duration: string | null
}

export interface ReviewAssemblyVersionDiff {
  available: boolean
  fromLabel: string | null
  toLabel: string | null
  added: Array<{ clipId: string; label: string }>
  removed: Array<{ clipId: string; label: string }>
  moved: Array<{ clipId: string; label: string; from: number; to: number }>
}

export interface ReviewAssemblyData {
  id: string
  title: string
  versionLabel: string
  artifactPath: string | null
  clips: ReviewAssemblyClipRange[]
}

export interface ReviewPresenceUser {
  id: string
  name: string
  activeAt: string
}

export interface ReviewClip {
  id: string
  projectId: string
  reviewStatus: ReviewStatus
  proxyStatus: 'pending' | 'processing' | 'ready' | 'error'
  duration: number
  sourceFps: number
  sourceTimecodeStart: string
  narrativeMeta: { sceneNumber: string; shotCode: string; takeNumber: number; cameraId: string } | null
  documentaryMeta: { subjectName: string; shootingDay: number; sessionLabel: string } | null
  aiScores: ReviewAIScores | null
  annotations: ReviewAnnotation[]
  projectMode: 'narrative' | 'documentary'
  transcriptText: string | null
  transcriptStatus: 'pending' | 'processing' | 'ready' | 'error'
  transcriptSegments: ReviewTranscriptSegment[]
  syncResult: ReviewSyncResult | null
  metadata: Record<string, unknown>
  aiProcessingStatus: 'pending' | 'processing' | 'ready' | 'error'
}

export interface ReviewShareLink {
  id: string
  project_id: string
  token: string
  scope: 'project' | 'scene' | 'subject' | 'assembly'
  scope_id: string | null
  password_hash: string | null
  expires_at: string
  view_count?: number
  last_viewed_at?: string | null
  revoked_at?: string | null
  notify_email?: string | null
  permissions: ReviewSharePermissions
  project: {
    id: string
    name: string
    mode: 'narrative' | 'documentary'
  }
  created_by?: string
  created_at?: string
}

export interface ReviewProjectData {
  grouped: Record<string, string[]>
  clips: ReviewClip[]
}
