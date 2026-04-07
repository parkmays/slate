-- Day-player share link access controls.
-- Adds role-based access and optional expiry for review share links.

ALTER TABLE share_links
  ALTER COLUMN expires_at DROP NOT NULL;

COMMENT ON COLUMN share_links.expires_at IS
  'Optional expiry timestamp. NULL means the share link does not expire.';

ALTER TABLE share_links
  ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'viewer';

ALTER TABLE share_links
  DROP CONSTRAINT IF EXISTS share_links_role_check;

ALTER TABLE share_links
  ADD CONSTRAINT share_links_role_check
  CHECK (role IN ('viewer', 'commenter', 'editor'));

-- Backfill role from legacy permissions for existing links.
UPDATE share_links
SET role = CASE
  WHEN COALESCE((permissions ->> 'canComment')::BOOLEAN, FALSE) = FALSE THEN 'viewer'
  WHEN COALESCE((permissions ->> 'canFlag')::BOOLEAN, FALSE)
    AND COALESCE((permissions ->> 'canRequestAlternate')::BOOLEAN, FALSE) THEN 'editor'
  ELSE 'commenter'
END;

DROP POLICY IF EXISTS "Share links are publicly viewable by token" ON share_links;

CREATE POLICY "Share links are publicly viewable by token" ON share_links
  FOR SELECT USING (
    revoked_at IS NULL
    AND (expires_at IS NULL OR expires_at > NOW())
  );

-- Note: the current web app uses the service-role key on server routes. Service-role
-- queries bypass RLS, so share-token authorization for clips/annotations remains
-- enforced in application code (requireShareLinkAccess + route-level checks).
COMMENT ON TABLE clips IS
  'Share-token access is currently enforced in application code; service-role queries bypass RLS.';

COMMENT ON TABLE annotations IS
  'Share-token access is currently enforced in application code; service-role queries bypass RLS.';
