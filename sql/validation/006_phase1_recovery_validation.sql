-- ============================================================
-- Phase 1 Recovery Metadata Validation
-- ============================================================


-- 1. Recovery schema tables
SELECT
    table_schema,
    table_name
FROM information_schema.tables
WHERE table_schema = 'recovery'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;


-- 2. Recovery views
SELECT
    table_schema,
    table_name
FROM information_schema.views
WHERE table_schema = 'recovery'
ORDER BY table_name;


-- 3. Pipeline stage dependencies
SELECT
    stage_order,
    stage_name,
    predecessor_stage_name,
    is_active
FROM recovery.pipeline_stages
ORDER BY stage_order;


-- 4. Pipeline run summary
SELECT
    run_key,
    status,
    started_at,
    finished_at
FROM recovery.pipeline_runs
ORDER BY pipeline_run_id;


-- 5. Full successful recovery simulation
SELECT
    ps.stage_order,
    se.stage_name,
    se.attempt_number,
    se.status,
    se.error_message
FROM recovery.stage_executions se
JOIN recovery.pipeline_runs pr
    ON pr.pipeline_run_id = se.pipeline_run_id
JOIN recovery.pipeline_stages ps
    ON ps.stage_name = se.stage_name
WHERE pr.run_key = 'batch_20260926_003'
ORDER BY
    ps.stage_order,
    se.attempt_number;


-- 6. Latest attempts for successful recovery run
SELECT
    lsa.stage_name,
    lsa.attempt_number,
    lsa.status
FROM recovery.latest_stage_attempts lsa
JOIN recovery.pipeline_runs pr
    ON pr.pipeline_run_id = lsa.pipeline_run_id
WHERE pr.run_key = 'batch_20260926_003'
ORDER BY (
    SELECT stage_order
    FROM recovery.pipeline_stages ps
    WHERE ps.stage_name = lsa.stage_name
);


-- 7. Gold artifact state
SELECT
    dv.version_key,
    da.artifact_name,
    da.status,
    da.row_count,
    da.checksum
FROM recovery.dataset_artifacts da
JOIN recovery.dataset_versions dv
    ON dv.dataset_version_id = da.dataset_version_id
WHERE dv.version_key = 'gold_batch_20260925_001'
ORDER BY da.artifact_name;


-- 8. Artifact retry history
SELECT
    dv.version_key,
    da.artifact_name,
    ae.attempt_number,
    ae.status,
    ae.error_message
FROM recovery.artifact_executions ae
JOIN recovery.dataset_artifacts da
    ON da.dataset_artifact_id = ae.dataset_artifact_id
JOIN recovery.dataset_versions dv
    ON dv.dataset_version_id = da.dataset_version_id
WHERE dv.version_key = 'gold_batch_20260925_001'
ORDER BY
    da.artifact_name,
    ae.attempt_number;


-- 9. Artifact consistency
SELECT
    dv.version_key,
    da.artifact_name,
    da.status AS artifact_status,
    laa.attempt_number,
    laa.status AS latest_attempt_status
FROM recovery.dataset_artifacts da
JOIN recovery.dataset_versions dv
    ON dv.dataset_version_id = da.dataset_version_id
LEFT JOIN recovery.latest_artifact_attempts laa
    ON laa.dataset_artifact_id = da.dataset_artifact_id
WHERE dv.version_key = 'gold_batch_20260925_001'
ORDER BY da.artifact_name;


-- 10. Monitoring view
SELECT
    run_key,
    pipeline_status,
    current_stage,
    retry_attempt_count,
    failed_attempt_count,
    latest_failed_stage
FROM recovery.pipeline_monitoring
ORDER BY pipeline_run_id;