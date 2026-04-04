const DEFAULT_FRAME_RATE = 24
const NON_INTEGER_FPS_EPSILON = 0.01

function safeFrameRate(frameRate: number): number {
  return Number.isFinite(frameRate) && frameRate > 0 ? frameRate : DEFAULT_FRAME_RATE
}

export function nominalFrameRate(frameRate: number): number {
  const safeRate = safeFrameRate(frameRate)

  if (Math.abs(safeRate - 23.976) < NON_INTEGER_FPS_EPSILON) {
    return 24
  }

  if (Math.abs(safeRate - 29.97) < NON_INTEGER_FPS_EPSILON) {
    return 30
  }

  if (Math.abs(safeRate - 59.94) < NON_INTEGER_FPS_EPSILON) {
    return 60
  }

  return Math.max(Math.round(safeRate), 1)
}

export function secondsToTimecode(seconds: number, frameRate: number): string {
  const safeRate = safeFrameRate(frameRate)
  const displayRate = nominalFrameRate(safeRate)
  const totalFrames = Math.max(0, Math.round(seconds * safeRate))
  const frames = totalFrames % displayRate
  const totalWholeSeconds = Math.floor(totalFrames / displayRate)
  const secs = totalWholeSeconds % 60
  const mins = Math.floor(totalWholeSeconds / 60) % 60
  const hours = Math.floor(totalWholeSeconds / 3600)

  return [hours, mins, secs, frames]
    .map((part) => String(part).padStart(2, '0'))
    .join(':')
}

export function timecodeToSeconds(timecode: string, frameRate: number): number {
  const safeRate = safeFrameRate(frameRate)
  const displayRate = nominalFrameRate(safeRate)
  const parts = timecode.split(/[:;]/)

  if (parts.length !== 4) {
    return 0
  }

  const [hours, minutes, seconds, frames] = parts.map((part) => Number.parseInt(part, 10) || 0)
  const totalFrames = (
    ((((hours * 60) + minutes) * 60) + seconds) * displayRate
  ) + frames

  return totalFrames / safeRate
}
