import { describe, expect, it } from 'vitest'
import { secondsToTimecode, timecodeToSeconds } from '@/lib/timecode'

describe('timecode helpers', () => {
  it('uses the true source fps for 23.976 clips instead of rounding to 24', () => {
    expect(secondsToTimecode(60, 23.976)).toBe('00:00:59:23')
  })

  it('parses SMPTE back to seconds with the clip fps', () => {
    expect(timecodeToSeconds('00:01:00:00', 23.976)).toBeCloseTo(1440 / 23.976, 4)
  })
})
