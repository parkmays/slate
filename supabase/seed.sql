-- SLATE — Seed Data for Local Testing
-- Owned by: Windsurf SWE
--
-- One test project in each mode with 3 clips each.
-- Sufficient to run the review portal locally without real media.
-- Clips with proxyStatus = 'ready' and known proxy_r2_key values.

-- Insert test users
INSERT INTO auth.users (id, email, email_confirmed_at, created_at) VALUES
('00000000-0000-0000-0000-000000000001', 'test@example.com', NOW(), NOW()),
('00000000-0000-0000-0000-000000000002', 'reviewer@example.com', NOW(), NOW());

-- Insert test projects
INSERT INTO projects (id, name, mode, status, created_at, updated_at) VALUES
('proj-narrative-001', 'Test Narrative Project', 'narrative', 'active', NOW(), NOW()),
('proj-documentary-001', 'Test Documentary Project', 'documentary', 'active', NOW(), NOW());

-- Insert test clips - Narrative Project
INSERT INTO clips (
    id, project_id, checksum, source_path, source_size, source_format, source_fps,
    source_timecode_start, duration, narrative_meta, project_mode, proxy_status,
    proxy_path, proxy_r2_key, proxy_generated_at, sync_status, review_status,
    transcription_status, created_at, updated_at
) VALUES
(
    'clip-narr-001',
    'proj-narrative-001',
    'abc123hash001',
    '/Volumes/CARD_A/A001_C001_230415_R1BK.mxf',
    1073741824,
    'mxf',
    23.976,
    '01:00:00:00',
    120.5,
    '{"sceneNumber":"01","shotCode":"A","takeNumber":1,"cameraId":"A"}',
    'narrative',
    'ready',
    '/tmp/proxies/clip-narr-001.mp4',
    'proxies/clip-narr-001.mp4',
    NOW() - INTERVAL '1 hour',
    'completed',
    'new',
    'pending',
    NOW() - INTERVAL '2 hours',
    NOW() - INTERVAL '2 hours'
),
(
    'clip-narr-002',
    'proj-narrative-001',
    'abc123hash002',
    '/Volumes/CARD_A/A001_C002_230415_R1BK.mxf',
    1073741824,
    'mxf',
    23.976,
    '01:00:00:00',
    95.2,
    '{"sceneNumber":"01","shotCode":"B","takeNumber":1,"cameraId":"A"}',
    'narrative',
    'ready',
    '/tmp/proxies/clip-narr-002.mp4',
    'proxies/clip-narr-002.mp4',
    NOW() - INTERVAL '1 hour',
    'completed',
    'circled',
    'pending',
    NOW() - INTERVAL '2 hours',
    NOW() - INTERVAL '2 hours'
),
(
    'clip-narr-003',
    'proj-narrative-001',
    'abc123hash003',
    '/Volumes/CARD_A/A001_C003_230415_R1BK.mxf',
    1073741824,
    'mxf',
    23.976,
    '01:00:00:00',
    180.0,
    '{"sceneNumber":"02","shotCode":"A","takeNumber":1,"cameraId":"B"}',
    'narrative',
    'ready',
    '/tmp/proxies/clip-narr-003.mp4',
    'proxies/clip-narr-003.mp4',
    NOW() - INTERVAL '1 hour',
    'completed',
    'flagged',
    'pending',
    NOW() - INTERVAL '2 hours',
    NOW() - INTERVAL '2 hours'
);

-- Insert test clips - Documentary Project
INSERT INTO clips (
    id, project_id, checksum, source_path, source_size, source_format, source_fps,
    source_timecode_start, duration, documentary_meta, project_mode, proxy_status,
    proxy_path, proxy_r2_key, proxy_generated_at, sync_status, review_status,
    transcription_status, created_at, updated_at
) VALUES
(
    'clip-doc-001',
    'proj-documentary-001',
    'def456hash001',
    '/Volumes/CARD_B/INTERVIEW_DAY1_001.mov',
    2147483648,
    'mov',
    23.976,
    '01:00:00:00',
    300.0,
    '{"subjectName":"John Doe","subjectId":"subj-001","shootingDay":1,"sessionLabel":"Interview A"}',
    'documentary',
    'ready',
    '/tmp/proxies/clip-doc-001.mp4',
    'proxies/clip-doc-001.mp4',
    NOW() - INTERVAL '1 hour',
    'completed',
    'new',
    'completed',
    NOW() - INTERVAL '2 hours',
    NOW() - INTERVAL '2 hours'
),
(
    'clip-doc-002',
    'proj-documentary-001',
    'def456hash002',
    '/Volumes/CARD_B/BROLL_DAY1_FOREST_001.mov',
    1073741824,
    'mov',
    23.976,
    '01:00:00:00',
    60.0,
    '{"subjectName":"B-Roll","subjectId":"broll-001","shootingDay":1,"sessionLabel":"Forest"}',
    'documentary',
    'ready',
    '/tmp/proxies/clip-doc-002.mp4',
    'proxies/clip-doc-002.mp4',
    NOW() - INTERVAL '1 hour',
    'completed',
    'new',
    'pending',
    NOW() - INTERVAL '2 hours',
    NOW() - INTERVAL '2 hours'
),
(
    'clip-doc-003',
    'proj-documentary-001',
    'def456hash003',
    '/Volumes/CARD_B/INTERVIEW_DAY1_002.mov',
    2147483648,
    'mov',
    23.976,
    '01:00:00:00',
    450.0,
    '{"subjectName":"Jane Smith","subjectId":"subj-002","shootingDay":1,"sessionLabel":"Interview B"}',
    'documentary',
    'ready',
    '/tmp/proxies/clip-doc-003.mp4',
    'proxies/clip-doc-003.mp4',
    NOW() - INTERVAL '1 hour',
    'completed',
    'unreviewed',
    'completed',
    NOW() - INTERVAL '2 hours',
    NOW() - INTERVAL '2 hours'
);

-- Insert sample AI scores for some clips
UPDATE clips SET 
    ai_scores = '{
        "technical": {
            "focus": 85,
            "exposure": 78,
            "stability": 92,
            "audioLevel": 88,
            "overall": 86,
            "issues": []
        },
        "content": {
            "transcript": {
                "text": "This is a sample transcript for testing purposes.",
                "language": "en",
                "words": [
                    {"start": 0.0, "end": 0.5, "text": "This"},
                    {"start": 0.5, "end": 1.0, "text": "is"},
                    {"start": 1.0, "end": 1.5, "text": "a"},
                    {"start": 1.5, "end": 2.0, "text": "sample"}
                ]
            },
            "contentDensity": 65,
            "keywords": ["sample", "test", "transcript"],
            "emotion": "neutral",
            "energy": 50,
            "sentiment": "neutral"
        },
        "performance": null,
        "reasons": [
            {
                "dimension": "vision",
                "score": 85,
                "flag": "success",
                "message": "Visual analysis completed successfully"
            }
        ]
    }',
    ai_scores_processed_at = NOW() - INTERVAL '30 minutes'
WHERE id IN ('clip-narr-001', 'clip-doc-001');

-- Insert sample annotations
INSERT INTO annotations (
    id, clip_id, author_id, author_name, timecode, timecode_seconds,
    type, content, is_private, created_at, updated_at
) VALUES
(
    'annot-001',
    'clip-narr-001',
    '00000000-0000-0000-0000-000000000002',
    'Test Reviewer',
    '00:00:10:00',
    10.0,
    'note',
    'Good performance from the actor in this take',
    false,
    NOW() - INTERVAL '1 hour',
    NOW() - INTERVAL '1 hour'
),
(
    'annot-002',
    'clip-narr-002',
    '00000000-0000-0000-0000-000000000002',
    'Test Reviewer',
    '00:00:05:12',
    5.5,
    'flag',
    'Focus seems soft here',
    false,
    NOW() - INTERVAL '45 minutes',
    NOW() - INTERVAL '45 minutes'
),
(
    'annot-003',
    'clip-doc-001',
    '00000000-0000-0000-0000-000000000002',
    'Test Reviewer',
    '00:01:30:00',
    90.0,
    'note',
    'Key moment in the interview - good soundbite',
    false,
    NOW() - INTERVAL '30 minutes',
    NOW() - INTERVAL '30 minutes'
);

-- Insert share links for testing
INSERT INTO share_links (
    id, project_id, token, scope, scope_id, expires_at, password_hash,
    permissions, created_at
) VALUES
(
    'share-001',
    'proj-narrative-001',
    'valid-share-token',
    'project',
    NULL,
    NOW() + INTERVAL '7 days',
    NULL,
    '{"canComment": true, "canFlag": true, "canRequestAlternate": true}',
    NOW()
),
(
    'share-002',
    'proj-narrative-001',
    'expired-token',
    'project',
    NULL,
    NOW() - INTERVAL '1 day',
    NULL,
    '{"canComment": true, "canFlag": true, "canRequestAlternate": true}',
    NOW() - INTERVAL '8 days'
),
(
    'share-003',
    'proj-documentary-001',
    'password-protected-token',
    'project',
    NULL,
    NOW() + INTERVAL '7 days',
    '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj6ukx.LrUpm',
    '{"canComment": true, "canFlag": false, "canRequestAlternate": false}',
    NOW()
);

-- Insert project crew
INSERT INTO project_crew (
    id, project_id, user_id, role, name, email, created_at
) VALUES
(
    'crew-001',
    'proj-narrative-001',
    '00000000-0000-0000-0000-000000000001',
    'director',
    'Test Director',
    'director@example.com',
    NOW()
),
(
    'crew-002',
    'proj-narrative-001',
    '00000000-0000-0000-0000-000000000002',
    'editor',
    'Test Editor',
    'editor@example.com',
    NOW()
);

-- Enable RLS for testing
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE clips ENABLE ROW LEVEL SECURITY;
ALTER TABLE annotations ENABLE ROW LEVEL SECURITY;
ALTER TABLE share_links ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for testing
CREATE POLICY "Users can view their own projects" ON projects
    FOR ALL USING (auth.uid() = ANY(
        SELECT user_id FROM project_crew WHERE project_id = projects.id
    ));

CREATE POLICY "Users can view clips from their projects" ON clips
    FOR ALL USING (project_id IN (
        SELECT project_id FROM project_crew WHERE user_id = auth.uid()
    ));

CREATE POLICY "Users can view annotations for their clips" ON annotations
    FOR ALL USING (clip_id IN (
        SELECT id FROM clips WHERE project_id IN (
            SELECT project_id FROM project_crew WHERE user_id = auth.uid()
        )
    ));

-- Create a function to test the review workflow
CREATE OR REPLACE FUNCTION test_review_workflow()
RETURNS TABLE(
    step TEXT,
    status TEXT,
    details JSONB
) AS $$
BEGIN
    -- Step 1: Generate share link
    RETURN QUERY
    SELECT 
        'generate-share-link'::TEXT as step,
        'success'::TEXT as status,
        json_build_object(
            'token', (SELECT token FROM share_links WHERE token = 'valid-share-token' LIMIT 1)
        ) as details;
    
    -- Step 2: Sign proxy URL
    RETURN QUERY
    SELECT 
        'sign-proxy-url'::TEXT as step,
        'success'::TEXT as status,
        json_build_object(
            'clipId', (SELECT id FROM clips WHERE proxy_status = 'ready' LIMIT 1),
            'proxyR2Key', (SELECT proxy_r2_key FROM clips WHERE proxy_status = 'ready' LIMIT 1)
        ) as details;
    
    -- Step 3: Sync annotation
    RETURN QUERY
    SELECT 
        'sync-annotation'::TEXT as step,
        'success'::TEXT as status,
        json_build_object(
            'annotationCount', (SELECT COUNT(*) FROM annotations)
        ) as details;
    
    RETURN;
END;
$$ LANGUAGE plpgsql;

-- Create a view for easy testing of grouped clips
CREATE VIEW grouped_clips_view AS
SELECT 
    c.id,
    c.project_id,
    p.name as project_name,
    p.mode,
    CASE 
        WHEN p.mode = 'narrative' THEN c.narrative_meta->>'sceneNumber'
        ELSE c.documentary_meta->>'subjectName'
    END as group_key,
    c.*
FROM clips c
JOIN projects p ON c.project_id = p.id
ORDER BY p.mode, group_key, c.created_at;

-- Grant permissions for testing
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon, authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated;
GRANT SELECT ON ALL VIEWS IN SCHEMA public TO anon, authenticated;