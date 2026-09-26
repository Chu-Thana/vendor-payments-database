BEGIN;


-- Attempt 1: failed
INSERT INTO recovery.artifact_executions (
    dataset_artifact_id,
    attempt_number,
    status,
    started_at,
    finished_at,
    error_message
)
SELECT
    da.dataset_artifact_id,
    1,
    'FAILED',
    NOW() - INTERVAL '10 minutes',
    NOW() - INTERVAL '9 minutes',
    'Simulated artifact build failure.'
FROM recovery.dataset_artifacts da
JOIN recovery.dataset_versions dv
    ON dv.dataset_version_id = da.dataset_version_id
WHERE dv.version_key = 'gold_batch_20260925_001'
  AND da.artifact_name = 'mart_pending_by_department.csv';


-- Attempt 2: succeeded
INSERT INTO recovery.artifact_executions (
    dataset_artifact_id,
    attempt_number,
    status,
    started_at,
    finished_at
)
SELECT
    da.dataset_artifact_id,
    2,
    'SUCCEEDED',
    NOW() - INTERVAL '5 minutes',
    NOW() - INTERVAL '4 minutes'
FROM recovery.dataset_artifacts da
JOIN recovery.dataset_versions dv
    ON dv.dataset_version_id = da.dataset_version_id
WHERE dv.version_key = 'gold_batch_20260925_001'
  AND da.artifact_name = 'mart_pending_by_department.csv';


COMMIT;