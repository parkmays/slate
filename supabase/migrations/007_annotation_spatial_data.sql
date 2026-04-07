-- Spatial annotation payloads for frame-level markup in review UI.
-- Stored as versioned JSON so we can evolve shape schemas without table churn.

ALTER TABLE annotations
  ADD COLUMN IF NOT EXISTS spatial_data JSONB;

COMMENT ON COLUMN annotations.spatial_data IS
  'Optional versioned drawing payload (normalized 0..1 coordinates in video content space).';

-- Keep this intentionally loose; deep shape validation happens in API layer.
ALTER TABLE annotations
  DROP CONSTRAINT IF EXISTS annotations_spatial_data_type_check;

ALTER TABLE annotations
  ADD CONSTRAINT annotations_spatial_data_type_check
  CHECK (spatial_data IS NULL OR jsonb_typeof(spatial_data) = 'object');

CREATE INDEX IF NOT EXISTS idx_annotations_spatial_data_gin
  ON annotations
  USING gin (spatial_data);
