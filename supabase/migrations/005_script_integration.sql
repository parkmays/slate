-- SLATE — Screenplay import and clip-to-script scene mapping (portal navigation by script page)

CREATE TABLE scripts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    title TEXT,
    total_pages INT NOT NULL,
    scenes JSONB NOT NULL,
    source_filename TEXT,
    parsed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE clip_script_mappings (
    clip_id UUID NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
    script_id UUID NOT NULL REFERENCES scripts(id) ON DELETE CASCADE,
    scene_number TEXT NOT NULL,
    confidence DOUBLE PRECISION NOT NULL,
    mapping_source TEXT NOT NULL,
    PRIMARY KEY (clip_id, script_id)
);

CREATE INDEX idx_scripts_project_id ON scripts(project_id);
