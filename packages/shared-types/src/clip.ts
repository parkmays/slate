/**
 * SLATE — Canonical Clip data model
 * Source of truth: contracts/data-model.json (version 1.0)
 * Author: Claude Code (Orchestrator)
 *
 * All agents consume these types. Do not modify without bumping
 * data-model.json version and notifying all agents.
 */

// ─── Enumerations ────────────────────────────────────────────────────────────

export type SourceFormat = 'BRAW' | 'ARRIRAW' | 'ProRes422HQ' | 'H264' | 'MXF' | 'R3D';

export type ProxyStatus = 'pending' | 'processing' | 'ready' | 'error';

export type AIProcessingStatus = 'pending' | 'processing' | 'ready' | 'error';

export type ReviewStatus = 'unreviewed' | 'circled' | 'flagged' | 'x' | 'deprioritized';

export type ApprovalStatus = 'pending' | 'reviewed' | 'approved';

export type ProjectMode = 'narrative' | 'documentary';

export type SyncConfidence = 'high' | 'medium' | 'low' | 'manual_required' | 'unsynced';

export type SyncMethod = 'waveform_correlation' | 'timecode' | 'manual' | 'none';

export type AudioTrackRole = 'boom' | 'lav' | 'mix' | 'iso' | 'unknown';

export type AnnotationType = 'text' | 'voice';

export type ScoreFlag = 'info' | 'warning' | 'error';

export type AssemblyClipRole = 'primary' | 'broll' | 'interview';

// ─── Supporting types ─────────────────────────────────────────────────────────

export interface NarrativeMeta {
  sceneNumber: string;
  shotCode: string;
  takeNumber: number;
  cameraId: string;
  scriptPage: string | null;
  setUpDescription: string | null;
  director: string | null;
  dp: string | null;
}

export interface DocumentaryMeta {
  subjectName: string;
  /** UUID */
  subjectId: string;
  shootingDay: number;
  sessionLabel: string;
  location: string | null;
  topicTags: string[];
  interviewerOffscreen: boolean;
}

export interface AudioTrack {
  trackIndex: number;
  role: AudioTrackRole;
  channelLabel: string;
  /** Hz */
  sampleRate: number;
  bitDepth: number;
}

export interface SyncResult {
  confidence: SyncConfidence;
  method: SyncMethod;
  offsetFrames: number;
  driftPPM: number;
  /** Seconds from start of clip */
  clapDetectedAt: number | null;
  /** ISO 8601 */
  verifiedAt: string | null;
}

export interface ScoreReason {
  dimension: string;
  /** 0–100 */
  score: number;
  flag: ScoreFlag;
  message: string;
  /** HH:MM:SS:FF */
  timecode: string | null;
}

export interface AIScores {
  /** Composite 0–100 */
  composite: number;
  focus: number;
  exposure: number;
  stability: number;
  audio: number;
  /** Narrative only — null in documentary mode */
  performance: number | null;
  /** Documentary only — null in narrative mode */
  contentDensity: number | null;
  /** ISO 8601 */
  scoredAt: string;
  modelVersion: string;
  reasoning: ScoreReason[];
}

export interface Annotation {
  /** UUID */
  id: string;
  /** UUID */
  userId: string;
  userDisplayName: string;
  /** Provenance — e.g. `SoundReport` for mixer log imports */
  source?: string | null;
  /** HH:MM:SS:FF */
  timecodeIn: string;
  /** Seconds from clip/proxy start; mirrors Postgres `annotations.time_offset_seconds`. */
  timeOffsetSeconds?: number | null;
  /** HH:MM:SS:FF — null if point annotation */
  timecodeOut: string | null;
  body: string;
  type: AnnotationType;
  voiceUrl: string | null;
  /** ISO 8601 */
  createdAt: string;
  /** ISO 8601 */
  resolvedAt: string | null;
}

// ─── Core Clip ────────────────────────────────────────────────────────────────

export interface Clip {
  /** UUID v4 */
  id: string;
  /** UUID — references Project.id */
  projectId: string;
  /** SHA-256 hex (lowercase, 64 chars) */
  checksum: string;
  /** Absolute path to original — READ ONLY, never mutate */
  sourcePath: string;
  /** Bytes */
  sourceSize: number;
  sourceFormat: SourceFormat;
  /** e.g. 23.976, 24, 25, 29.97, 30, 48, 60 */
  sourceFps: number;
  /** HH:MM:SS:FF (drop-frame uses ';' separator for 29.97) */
  sourceTimecodeStart: string;
  /** Duration in seconds */
  duration: number;

  proxyPath: string | null;
  proxyStatus: ProxyStatus;
  /** SHA-256 hex */
  proxyChecksum: string | null;

  /** Populated when projectMode === 'narrative', otherwise null */
  narrativeMeta: NarrativeMeta | null;
  /** Populated when projectMode === 'documentary', otherwise null */
  documentaryMeta: DocumentaryMeta | null;

  audioTracks: AudioTrack[];
  syncResult: SyncResult;
  syncedAudioPath: string | null;

  /** Provided by Codex ai-pipeline — advisory only */
  aiScores: AIScores | null;
  /** UUID referencing transcript in Supabase */
  transcriptId: string | null;
  aiProcessingStatus: AIProcessingStatus;

  reviewStatus: ReviewStatus;
  annotations: Annotation[];

  approvalStatus: ApprovalStatus;
  approvedBy: string | null;
  /** ISO 8601 */
  approvedAt: string | null;

  /** ISO 8601 */
  ingestedAt: string;
  /** ISO 8601 */
  updatedAt: string;

  projectMode: ProjectMode;
  /** Camera and lens metadata extracted from source file */
  cameraMetadata?: CameraMetadata;
}

// ─── Notification Types ───────────────────────────────────────────────────────

export interface DeliveryTarget {
  name: string;
  method: DeliveryMethod;
  address: string; // phone number, email, or Slack webhook URL
}

export type DeliveryMethod = 'iMessage' | 'email' | 'slack';

// ─── Camera Metadata ─────────────────────────────────────────────────────────

export interface CameraMetadata {
  cameraModel?: string;
  cameraSerialNumber?: string;
  lensModel?: string;
  focalLength?: number;     // mm
  aperture?: number;        // f-stop
  iso?: number;             // ISO rating
  recordingFormat?: string; // e.g., "ProRes 422 HQ", "BRAW"
  recordingDate?: string;   // ISO 8601
  codec?: string;           // FourCC string
  width?: number;
  height?: number;
  frameRate?: number;
  colorSpace?: string;
  duration?: number;        // seconds
  bitrate?: number;         // bits per second
}

// ─── Project ──────────────────────────────────────────────────────────────────

export interface Project {
  /** UUID v4 */
  id: string;
  name: string;
  mode: ProjectMode;
  /** ISO 8601 */
  createdAt: string;
  /** ISO 8601 */
  updatedAt: string;
  /** Delivery targets for notifications */
  notificationTargets: DeliveryTarget[];
  /** Auto-deliver when assembly is ready */
  autoDeliverOnAssembly: boolean;
}

// ─── Assembly ─────────────────────────────────────────────────────────────────

export interface AssemblyClip {
  /** UUID — references Clip.id */
  clipId: string;
  /** Seconds */
  inPoint: number;
  /** Seconds */
  outPoint: number;
  role: AssemblyClipRole;
  sceneLabel: string;
}

export interface Assembly {
  /** UUID v4 */
  id: string;
  /** UUID — references Project.id */
  projectId: string;
  name: string;
  mode: ProjectMode;
  clips: AssemblyClip[];
  /** ISO 8601 */
  createdAt: string;
  version: number;
}

// ─── Ingest progress (written by daemon, polled by desktop) ──────────────────

export interface IngestProgressItem {
  filename: string;
  /** 0.0–1.0 */
  progress: number;
  stage: 'checksum' | 'copy' | 'verify' | 'proxy' | 'sync' | 'complete' | 'error';
  error?: string;
}

export interface IngestProgressReport {
  active: IngestProgressItem[];
  queued: number;
  errors: Array<{ filename: string; message: string; timestamp: string }>;
}

// ─── Watch folder config ──────────────────────────────────────────────────────

export interface WatchFolder {
  path: string;
  projectId: string;
  mode: ProjectMode;
}
