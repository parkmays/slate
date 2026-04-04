-- SLATE v1.2: Proxy LUT tracking + multi-cam camera groups
-- Mirrors data-model.json v1.2 and storage.md locked R2 key convention.
-- Applied: 2026-04-03

-- 1. Proxy LUT and color space columns on clips
ALTER TABLE clips
  ADD COLUMN IF NOT EXISTS proxy_lut TEXT,
  ADD COLUMN IF NOT EXISTS proxy_color_space TEXT,
  ADD COLUMN IF NOT EXISTS camera_group_id UUID,
  ADD COLUMN IF NOT EXISTS camera_angle TEXT CHECK (camera_angle IN ('A', 'B', 'C', 'D'));

-- 2. Constrain proxy_lut to known values (nullable = no LUT / pass-through)
ALTER TABLE clips
  DROP CONSTRAINT IF EXISTS clips_proxy_lut_check;
ALTER TABLE clips
  ADD CONSTRAINT clips_proxy_lut_check
  CHECK (proxy_lut IN ('arri_logc3_rec709', 'bm_film_gen5_rec709', 'red_ipp2_rec709', 'none'));

-- 3. Constrain proxy_color_space
ALTER TABLE clips
  DROP CONSTRAINT IF EXISTS clips_proxy_color_space_check;
ALTER TABLE clips
  ADD CONSTRAINT clips_proxy_color_space_check
  CHECK (proxy_color_space IN ('rec709', 'log'));

-- 4. Widen proxy_status to match Swift model (adds 'ready' alongside 'completed')
ALTER TABLE clips
  DROP CONSTRAINT IF EXISTS clips_proxy_status_check;
ALTER TABLE clips
  ADD CONSTRAINT clips_proxy_status_check
  CHECK (proxy_status IN ('pending', 'processing', 'ready', 'completed', 'failed', 'error'));

-- 5. Index for camera group lookups (multi-cam sync grouping)
CREATE INDEX IF NOT EXISTS idx_clips_camera_group_id ON clips(camera_group_id);
CREATE INDEX IF NOT EXISTS idx_clips_proxy_lut ON clips(proxy_lut);

-- 6. assembly_versions table — queried by sign-proxy-url edge function
CREATE TABLE IF NOT EXISTS assembly_versions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    assembly_id UUID NOT NULL REFERENCES assemblies(id) ON DELETE CASCADE,
    version INTEGER NOT NULL,
    format TEXT NOT NULL,
    clips JSONB NOT NULL DEFAULT '[]',
    file_path TEXT,
    byte_count BIGINT,
    exported_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_assembly_versions_assembly_id ON assembly_versions(assembly_id);
CREATE INDEX IF NOT EXISTS idx_assembly_versions_created_at ON assembly_versions(created_at);
