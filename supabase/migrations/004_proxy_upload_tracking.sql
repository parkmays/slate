-- R2 proxy upload metadata + widen proxy_status for upload lifecycle

ALTER TABLE clips ADD COLUMN IF NOT EXISTS proxy_r2_url TEXT;
ALTER TABLE clips ADD COLUMN IF NOT EXISTS proxy_r2_uploaded_at TIMESTAMPTZ;

ALTER TABLE clips
  DROP CONSTRAINT IF EXISTS clips_proxy_status_check;

ALTER TABLE clips
  ADD CONSTRAINT clips_proxy_status_check
  CHECK (proxy_status IN (
    'pending',
    'processing',
    'ready',
    'uploading',
    'completed',
    'failed',
    'error'
  ));
