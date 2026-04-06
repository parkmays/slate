-- Playback-aligned annotation ordering: store offset in seconds (proxy timeline, 0 = clip start).
-- Replaces reliance on the legacy generated `timecode_seconds` column (always NULL in 001).

ALTER TABLE annotations
  ADD COLUMN IF NOT EXISTS time_offset_seconds DOUBLE PRECISION;

COMMENT ON COLUMN annotations.time_offset_seconds IS
  'Seconds from the start of the proxy/clip timeline when the note was placed; used for ordering and bounds checks.';

CREATE INDEX IF NOT EXISTS idx_annotations_clip_time_offset
  ON annotations (clip_id, time_offset_seconds, created_at);
