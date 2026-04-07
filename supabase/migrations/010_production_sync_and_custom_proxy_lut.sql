-- SLATE v1.4: Production sync external ids + custom .cube proxy LUT path (desktop parity with data-model.json)
-- Applied: 2026-04-07

-- 1. External production databases (clip row linkage)
ALTER TABLE clips
  ADD COLUMN IF NOT EXISTS airtable_record_id TEXT,
  ADD COLUMN IF NOT EXISTS shotgrid_entity_id TEXT,
  ADD COLUMN IF NOT EXISTS editorial_updated_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_clips_airtable_record_id ON clips(airtable_record_id)
  WHERE airtable_record_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_clips_shotgrid_entity_id ON clips(shotgrid_entity_id)
  WHERE shotgrid_entity_id IS NOT NULL;

-- 2. Custom LUT: optional path/key for a user-supplied .cube (baked in desktop proxy gen)
ALTER TABLE clips
  ADD COLUMN IF NOT EXISTS custom_proxy_lut_path TEXT;

-- 3. Widen proxy_lut preset constraint to allow sentinel for custom cube path flow
ALTER TABLE clips
  DROP CONSTRAINT IF EXISTS clips_proxy_lut_check;
ALTER TABLE clips
  ADD CONSTRAINT clips_proxy_lut_check
  CHECK (
    proxy_lut IS NULL
    OR proxy_lut IN (
      'arri_logc3_rec709',
      'bm_film_gen5_rec709',
      'red_ipp2_rec709',
      'none',
      'custom_cube'
    )
  );

-- 4. Optional project-level metadata for server routing (secrets stay in Edge env / desktop GRDB)
ALTER TABLE projects
  ADD COLUMN IF NOT EXISTS airtable_base_id TEXT,
  ADD COLUMN IF NOT EXISTS shotgrid_site TEXT;

COMMENT ON COLUMN clips.airtable_record_id IS 'Airtable record id in the per-show base (Production Sync)';
COMMENT ON COLUMN clips.editorial_updated_at IS 'Last editorial/review change in SLATE — used for LWW vs Airtable';
COMMENT ON COLUMN clips.custom_proxy_lut_path IS 'Optional path or storage key for a .cube used when proxy_lut = custom_cube';

-- 5. Align review_status check with web portal + Swift (legacy seed values kept for compatibility)
ALTER TABLE clips
  DROP CONSTRAINT IF EXISTS clips_review_status_check;
ALTER TABLE clips
  ADD CONSTRAINT clips_review_status_check
  CHECK (
    review_status IN (
      'unreviewed', 'circled', 'flagged', 'x', 'deprioritized',
      'new', 'in_review', 'approved', 'rejected', 'alternate'
    )
  );
