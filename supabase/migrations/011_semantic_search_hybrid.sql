-- SLATE semantic search v1: token-hash embeddings + hybrid ranking RPC.
-- Uses pgvector already provisioned in prior migrations.

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION slate_text_embedding(input_text TEXT)
RETURNS vector(1536)
LANGUAGE sql
IMMUTABLE
AS $$
  WITH normalized AS (
    SELECT lower(regexp_replace(coalesce(input_text, ''), '[^a-z0-9\s]+', ' ', 'g')) AS t
  ),
  tokens AS (
    SELECT token
    FROM regexp_split_to_table((SELECT t FROM normalized), '\s+') AS token
    WHERE length(token) > 1
  ),
  bucketed AS (
    SELECT
      (((('x' || substr(md5(token), 1, 8))::bit(32)::int % 1536) + 1536) % 1536) + 1 AS idx,
      count(*)::float8 AS weight
    FROM tokens
    GROUP BY 1
  ),
  dense AS (
    SELECT gs AS idx, coalesce(bucketed.weight, 0.0) AS value
    FROM generate_series(1, 1536) AS gs
    LEFT JOIN bucketed ON bucketed.idx = gs
  ),
  norm AS (
    SELECT sqrt(sum(value * value)) AS l2 FROM dense
  ),
  normalized_dense AS (
    SELECT
      idx,
      CASE
        WHEN (SELECT l2 FROM norm) > 0 THEN value / (SELECT l2 FROM norm)
        ELSE 0.0
      END AS value
    FROM dense
  )
  SELECT (
    '[' || string_agg(to_char(value, 'FM999990.000000'), ',' ORDER BY idx) || ']'
  )::vector(1536)
  FROM normalized_dense;
$$;

CREATE OR REPLACE FUNCTION slate_set_search_embedding()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.body IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.body IS DISTINCT FROM OLD.body OR NEW.embedding IS NULL)
  THEN
    NEW.embedding := slate_text_embedding(NEW.body);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_review_search_embedding ON review_search_documents;
CREATE TRIGGER set_review_search_embedding
  BEFORE INSERT OR UPDATE OF body, embedding
  ON review_search_documents
  FOR EACH ROW
  EXECUTE FUNCTION slate_set_search_embedding();

UPDATE review_search_documents
SET embedding = slate_text_embedding(body)
WHERE embedding IS NULL;

CREATE OR REPLACE FUNCTION search_review_documents_hybrid(
  p_project_id UUID,
  p_query TEXT,
  p_limit INT DEFAULT 20
)
RETURNS TABLE (
  id UUID,
  clip_id UUID,
  source_type TEXT,
  source_id TEXT,
  time_offset_seconds NUMERIC,
  body TEXT,
  metadata JSONB,
  score DOUBLE PRECISION
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  q_embed vector(1536);
  normalized_query TEXT;
BEGIN
  normalized_query := trim(coalesce(p_query, ''));
  IF normalized_query = '' THEN
    RETURN;
  END IF;

  q_embed := slate_text_embedding(normalized_query);

  RETURN QUERY
  WITH text_candidates AS (
    SELECT
      d.id,
      d.clip_id,
      d.source_type,
      d.source_id,
      d.time_offset_seconds,
      d.body,
      d.metadata,
      ts_rank_cd(d.body_tsv, websearch_to_tsquery('english', normalized_query)) AS text_rank
    FROM review_search_documents d
    WHERE d.project_id = p_project_id
      AND d.body_tsv @@ websearch_to_tsquery('english', normalized_query)
    ORDER BY text_rank DESC
    LIMIT GREATEST(COALESCE(p_limit, 20) * 8, 64)
  ),
  vector_candidates AS (
    SELECT
      d.id,
      d.clip_id,
      d.source_type,
      d.source_id,
      d.time_offset_seconds,
      d.body,
      d.metadata,
      0::double precision AS text_rank,
      CASE
        WHEN d.embedding IS NOT NULL THEN 1 - (d.embedding <=> q_embed)
        ELSE 0
      END AS vector_rank
    FROM review_search_documents d
    WHERE d.project_id = p_project_id
      AND d.embedding IS NOT NULL
    ORDER BY d.embedding <=> q_embed
    LIMIT GREATEST(COALESCE(p_limit, 20) * 8, 64)
  ),
  candidates AS (
    SELECT id, clip_id, source_type, source_id, time_offset_seconds, body, metadata, text_rank, 0::double precision AS vector_rank
    FROM text_candidates
    UNION ALL
    SELECT id, clip_id, source_type, source_id, time_offset_seconds, body, metadata, text_rank, vector_rank
    FROM vector_candidates
  ),
  ranked AS (
    SELECT
      id,
      clip_id,
      source_type,
      source_id,
      time_offset_seconds,
      body,
      metadata,
      max(text_rank) AS text_rank,
      max(vector_rank) AS vector_rank
    FROM candidates
    GROUP BY id, clip_id, source_type, source_id, time_offset_seconds, body, metadata
  )
  SELECT
    ranked.id,
    ranked.clip_id,
    ranked.source_type,
    ranked.source_id,
    ranked.time_offset_seconds,
    ranked.body,
    ranked.metadata,
    (ranked.text_rank * 0.55 + ranked.vector_rank * 0.45)::double precision AS score
  FROM ranked
  ORDER BY score DESC
  LIMIT GREATEST(COALESCE(p_limit, 20), 1);
END;
$$;
