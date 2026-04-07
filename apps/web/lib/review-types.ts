export type ReviewStatus = 'unreviewed' | 'circled' | 'flagged' | 'x' | 'deprioritized'

export type AnnotationType = 'text' | 'voice'

export type SpatialShapeKind = 'arrow' | 'ellipse' | 'freehand'

export interface SpatialPoint {
  x: number
  y: number
}

export interface SpatialShapeBase {
  id: string
  kind: SpatialShapeKind
  stroke: string
  strokeWidthNorm: number
}

export interface SpatialArrowShape extends SpatialShapeBase {
  kind: 'arrow'
  from: SpatialPoint
  to: SpatialPoint
}

export interface SpatialEllipseShape extends SpatialShapeBase {
  kind: 'ellipse'
  cx: number
  cy: number
  rx: number
  ry: number
}

export interface SpatialFreehandShape extends SpatialShapeBase {
  kind: 'freehand'
  points: SpatialPoint[]
}

export type SpatialShape = SpatialArrowShape | SpatialEllipseShape | SpatialFreehandShape

export interface SpatialAnnotationPayload {
  version: 1
  shapes: SpatialShape[]
}

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

export type ShareLinkRole = 'viewer' | 'commenter' | 'editor'

export interface ReviewAnnotation {
  id: string
  userId: string
  userDisplayName: string
  timecodeIn: string
  /** Seconds from clip/proxy start; aligned with DB `time_offset_seconds` and playback `currentTime`. */
  timeOffsetSeconds?: number | null
  timecodeOut: string | null
  body: string
  type: AnnotationType
  voiceUrl: string | null
  spatialData: SpatialAnnotationPayload | null
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

export interface ReviewFaceCluster {
  id: string
  clip_id: string
  cluster_key: string
  display_name: string | null
  character_name: string | null
  representative_thumbnail_url: string | null
  metadata: Record<string, unknown>
}

export interface ScriptLineAnchor {
  id: string
  text: string
  startSeconds: number
  endSeconds: number
}

export interface ClipScriptContext {
  scriptId: string
  sceneNumber: string
  sceneSlugline: string
  confidence: number
  mappingSource: string
  lineAnchors: ScriptLineAnchor[]
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
  scriptContext?: ClipScriptContext | null
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
  expires_at: string | null
  role: ShareLinkRole
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
