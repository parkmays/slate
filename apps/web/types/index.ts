export type {
  AnnotationType,
  ReviewAIScores as AIScores,
  ReviewAnnotation as Annotation,
  ReviewAnnotationReply as AnnotationReply,
  ReviewAssemblyClipRange as AssemblyClip,
  ReviewAssemblyData as Assembly,
  ReviewClip as Clip,
  ReviewPresenceUser,
  ReviewProjectData,
  ReviewShareLink as ShareLink,
  ReviewStatus,
  ReviewTranscriptSegment,
} from '@/lib/review-types'

export interface PlayerState {
  currentTime: number
  duration: number
  isPlaying: boolean
  isBuffering: boolean
  volume: number
  isMuted: boolean
  playbackRate: number
}

export interface ReviewState {
  selectedClipId: string | null
  annotations: import('@/lib/review-types').ReviewAnnotation[]
  isAddingAnnotation: boolean
  selectedAnnotationId: string | null
  filter: {
    type?: import('@/lib/review-types').AnnotationType
  }
}
