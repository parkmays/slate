-- Face clusters and user-assigned cast labels.

CREATE TABLE IF NOT EXISTS face_clusters (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  clip_id UUID NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
  cluster_key TEXT NOT NULL,
  display_name TEXT,
  character_name TEXT,
  representative_frame_seconds NUMERIC,
  representative_thumbnail_url TEXT,
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (clip_id, cluster_key)
);

ALTER TABLE face_clusters ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Face clusters viewable by project crew"
  ON face_clusters
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM clips c
      JOIN projects p ON p.id = c.project_id
      WHERE c.id = face_clusters.clip_id
    )
  );

CREATE INDEX IF NOT EXISTS idx_face_clusters_clip_id
  ON face_clusters (clip_id, created_at);

CREATE TRIGGER update_face_clusters_updated_at
  BEFORE UPDATE ON face_clusters
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
