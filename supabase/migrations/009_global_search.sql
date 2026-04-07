-- Global command-palette search across transcript lines, annotations, and tags.

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS review_search_documents (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  clip_id UUID REFERENCES clips(id) ON DELETE CASCADE,
  source_type TEXT NOT NULL CHECK (source_type IN ('transcript', 'annotation', 'tag')),
  source_id TEXT NOT NULL,
  time_offset_seconds NUMERIC,
  body TEXT NOT NULL,
  body_tsv tsvector GENERATED ALWAYS AS (to_tsvector('english', coalesce(body, ''))) STORED,
  embedding vector(1536),
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (source_type, source_id)
);

CREATE INDEX IF NOT EXISTS idx_review_search_documents_project
  ON review_search_documents (project_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_review_search_documents_tsv
  ON review_search_documents USING gin (body_tsv);

CREATE INDEX IF NOT EXISTS idx_review_search_documents_embedding
  ON review_search_documents USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);

CREATE TRIGGER update_review_search_documents_updated_at
  BEFORE UPDATE ON review_search_documents
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
