-- SLATE review collaboration follow-up
-- Aligns the initial schema with the shipped web review portal feature set.

ALTER TABLE share_links
  ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS notify_email TEXT;

ALTER TABLE annotations
  ADD COLUMN IF NOT EXISTS voice_url TEXT,
  ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMPTZ;

UPDATE annotations
SET type = 'text'
WHERE type IN ('note', 'flag', 'bookmark', 'question', 'action');

ALTER TABLE annotations
  DROP CONSTRAINT IF EXISTS annotations_type_check;

ALTER TABLE annotations
  ADD CONSTRAINT annotations_type_check
  CHECK (type IN ('text', 'voice'));

CREATE INDEX IF NOT EXISTS idx_share_links_revoked_at ON share_links(revoked_at);
