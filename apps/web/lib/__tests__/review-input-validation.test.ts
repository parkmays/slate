import { describe, expect, it } from 'vitest'
import { assertValidTimecodeIn } from '@/lib/review-input-validation'

describe('assertValidTimecodeIn', () => {
  it('accepts canonical SMPTE with : or ; (drop-frame)', () => {
    expect(() => assertValidTimecodeIn('01:00:00:00')).not.toThrow()
    expect(() => assertValidTimecodeIn('00:00:00;00')).not.toThrow()
  })

  it('rejects garbage and empty-looking strings', () => {
    expect(() => assertValidTimecodeIn('not-a-timecode')).toThrow(/Invalid timecode format/)
    expect(() => assertValidTimecodeIn('1-2-3-4')).toThrow(/Invalid timecode format/)
  })
})
