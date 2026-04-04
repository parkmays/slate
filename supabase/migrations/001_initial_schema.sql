-- SLATE Initial Schema
-- Supports both Narrative (scene/shot/take) and Documentary (subject/day/clip) modes

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Projects table
CREATE TABLE projects (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    mode TEXT NOT NULL CHECK (mode IN ('narrative', 'documentary')),
    status TEXT NOT NULL DEFAULT 'setup' CHECK (status IN ('setup', 'ingest', 'review', 'assembly', 'complete')),
    
    -- Project settings
    settings JSONB NOT NULL DEFAULT '{}',
    
    -- Metadata
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Crew members for projects
CREATE TABLE project_crew (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('director', 'dp', 'editor', 'producer', 'dit')),
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(project_id, user_id)
);

-- Locations for projects
CREATE TABLE locations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('studio', 'location', 'interior', 'exterior')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Clips table - the core entity
CREATE TABLE clips (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    
    -- File information (NEVER store the actual file)
    checksum TEXT NOT NULL UNIQUE,
    file_path TEXT NOT NULL,
    file_size BIGINT NOT NULL,
    
    -- Technical metadata
    duration_seconds NUMERIC NOT NULL,
    frame_rate NUMERIC NOT NULL,
    resolution JSONB NOT NULL, -- {"width": 3840, "height": 2160}
    audio_channels INTEGER NOT NULL,
    audio_sample_rate INTEGER NOT NULL,
    format JSONB NOT NULL, -- {"container": "mov", "codec": "prores"}
    
    -- Timecode
    timecode_start TEXT NOT NULL, -- SMPTE format
    timecode_source TEXT NOT NULL CHECK (timecode_source IN ('source', 'burnin', 'auto')),
    
    -- Camera metadata
    metadata JSONB NOT NULL DEFAULT '{}',
    
    -- Hierarchy - supports both modes
    hierarchy JSONB NOT NULL, -- {"mode": "narrative", "narrative": {...}} or {"mode": "documentary", "documentary": {...}}
    
    -- Proxy information
    proxy_status TEXT NOT NULL DEFAULT 'pending' CHECK (proxy_status IN ('pending', 'processing', 'completed', 'failed')),
    proxy_r2_key TEXT,
    proxy_generated_at TIMESTAMPTZ,
    
    -- Sync information
    sync_status TEXT NOT NULL DEFAULT 'pending' CHECK (sync_status IN ('pending', 'processing', 'completed', 'failed')),
    sync_offset_frames INTEGER DEFAULT 0,
    sync_confidence NUMERIC,
    sync_processed_at TIMESTAMPTZ,
    
    -- Transcription
    transcription_status TEXT NOT NULL DEFAULT 'pending' CHECK (transcription_status IN ('pending', 'processing', 'completed', 'failed')),
    transcription_text TEXT,
    transcription_language TEXT,
    transcription_processed_at TIMESTAMPTZ,
    
    -- AI Scores
    ai_scores JSONB,
    ai_scores_processed_at TIMESTAMPTZ,
    
    -- Review status
    review_status TEXT NOT NULL DEFAULT 'new' CHECK (review_status IN ('new', 'in_review', 'approved', 'rejected', 'alternate')),
    approval_status JSONB NOT NULL DEFAULT '{}',
    flags JSONB NOT NULL DEFAULT '{}',
    
    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Annotations table
CREATE TABLE annotations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clip_id UUID NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
    
    -- Author information
    author_id UUID NOT NULL,
    author_name TEXT NOT NULL,
    
    -- Timing
    timecode TEXT NOT NULL, -- SMPTE format
    timecode_seconds NUMERIC GENERATED ALWAYS AS (
        -- Convert SMPTE to seconds for easier querying
        -- Implementation depends on timecode format
        NULL -- Will be updated via trigger
    ) STORED,
    
    -- Content
    type TEXT NOT NULL CHECK (type IN ('note', 'flag', 'bookmark', 'question', 'action')),
    content TEXT NOT NULL,
    is_private BOOLEAN NOT NULL DEFAULT FALSE,
    is_resolved BOOLEAN NOT NULL DEFAULT FALSE,
    
    -- Timestamps
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Annotation replies
CREATE TABLE annotation_replies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    annotation_id UUID NOT NULL REFERENCES annotations(id) ON DELETE CASCADE,
    
    author_id UUID NOT NULL,
    author_name TEXT NOT NULL,
    content TEXT NOT NULL,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Assemblies table
CREATE TABLE assemblies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    
    name TEXT NOT NULL,
    version TEXT NOT NULL,
    
    -- Assembly metadata
    metadata JSONB NOT NULL DEFAULT '{}',
    
    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Assembly clips (junction table)
CREATE TABLE assembly_clips (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    assembly_id UUID NOT NULL REFERENCES assemblies(id) ON DELETE CASCADE,
    clip_id UUID NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
    
    "order" INTEGER NOT NULL,
    in_point TEXT NOT NULL, -- SMPTE
    out_point TEXT NOT NULL, -- SMPTE
    duration TEXT NOT NULL, -- SMPTE
    notes TEXT,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(assembly_id, "order")
);

-- Share links table
CREATE TABLE share_links (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    
    token TEXT NOT NULL UNIQUE,
    scope TEXT NOT NULL CHECK (scope IN ('project', 'scene', 'subject', 'assembly')),
    scope_id UUID, -- UUID of the specific scene/subject/assembly
    
    -- Security
    password_hash TEXT, -- bcrypt hash, null = no password
    expires_at TIMESTAMPTZ NOT NULL,
    
    -- Permissions
    permissions JSONB NOT NULL DEFAULT '{"canComment": true, "canFlag": true, "canRequestAlternate": true}',
    
    -- Metadata
    created_by UUID NOT NULL,
    view_count INTEGER NOT NULL DEFAULT 0,
    last_viewed_at TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX idx_clips_project_id ON clips(project_id);
CREATE INDEX idx_clips_hierarchy ON clips USING GIN(hierarchy);
CREATE INDEX idx_clips_review_status ON clips(review_status);
CREATE INDEX idx_clips_checksum ON clips(checksum);
CREATE INDEX idx_annotations_clip_id ON annotations(clip_id);
CREATE INDEX idx_annotations_timecode ON annotations(timecode_seconds);
CREATE INDEX idx_share_links_token ON share_links(token);
CREATE INDEX idx_share_links_expires_at ON share_links(expires_at);

-- Full-text search on transcription text
CREATE INDEX idx_clips_transcription_text ON clips USING GIN(to_tsvector('english', transcription_text));

-- Enable Row Level Security
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE clips ENABLE ROW LEVEL SECURITY;
ALTER TABLE annotations ENABLE ROW LEVEL SECURITY;
ALTER TABLE assemblies ENABLE ROW LEVEL SECURITY;
ALTER TABLE share_links ENABLE ROW LEVEL SECURITY;

-- RLS Policies (simplified for MVP - will be expanded)
CREATE POLICY "Users can view their own projects" ON projects
    FOR SELECT USING (
        id IN (
            SELECT project_id FROM project_crew WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Users can insert their own projects" ON projects
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Users can update their own projects" ON projects
    FOR UPDATE USING (
        id IN (
            SELECT project_id FROM project_crew WHERE user_id = auth.uid()
        )
    );

-- Share links are publicly viewable by token
CREATE POLICY "Share links are publicly viewable by token" ON share_links
    FOR SELECT USING (expires_at > NOW());

-- Annotations are viewable by project crew
CREATE POLICY "Annotations viewable by project crew" ON annotations
    FOR SELECT USING (
        clip_id IN (
            SELECT id FROM clips WHERE project_id IN (
                SELECT project_id FROM project_crew WHERE user_id = auth.uid()
            )
        )
    );

-- Enable Realtime
ALTER TABLE clips REPLICA IDENTITY FULL;
ALTER TABLE annotations REPLICA IDENTITY FULL;
ALTER TABLE assemblies REPLICA IDENTITY FULL;

-- Publication for Realtime
CREATE PUBLICATION slate_publication FOR TABLE clips, annotations, assemblies;

-- Functions and triggers for updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_projects_updated_at BEFORE UPDATE ON projects
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_clips_updated_at BEFORE UPDATE ON clips
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_annotations_updated_at BEFORE UPDATE ON annotations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_assemblies_updated_at BEFORE UPDATE ON assemblies
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to convert SMPTE timecode to seconds
CREATE OR REPLACE FUNCTION smpte_to_seconds(timecode TEXT)
RETURNS NUMERIC AS $$
DECLARE
    hours INTEGER;
    minutes INTEGER;
    seconds INTEGER;
    frames INTEGER;
    frame_rate NUMERIC;
BEGIN
    -- Parse HH:MM:SS:FF format
    SELECT 
        CAST(SPLIT_PART(timecode, ':', 1) AS INTEGER),
        CAST(SPLIT_PART(timecode, ':', 2) AS INTEGER),
        CAST(SPLIT_PART(timecode, ':', 3) AS INTEGER),
        CAST(SPLIT_PART(timecode, ':', 4) AS INTEGER)
    INTO hours, minutes, seconds, frames;
    
    -- Get frame rate from the clip (this is a simplified version)
    -- In production, we'd pass the clip_id or frame_rate as parameter
    frame_rate := 24; -- Default, should be parameterized
    
    RETURN hours * 3600 + minutes * 60 + seconds + (frames / frame_rate);
END;
$$ LANGUAGE plpgsql;

-- Update trigger for annotation timecode_seconds
CREATE OR REPLACE FUNCTION update_annotation_timecode_seconds()
RETURNS TRIGGER AS $$
BEGIN
    NEW.timecode_seconds = smpte_to_seconds(NEW.timecode);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_annotation_timecode_seconds_trigger
    BEFORE INSERT OR UPDATE ON annotations
    FOR EACH ROW EXECUTE FUNCTION update_annotation_timecode_seconds();