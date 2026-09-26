BEGIN;

INSERT INTO recovery.stage_executions (
    pipeline_run_id,
    stage_name,
    attempt_number,
    status,
    input_dataset_version_id,
    started_at,
    finished_at
)
SELECT
    pr.pipeline_run_id,
    'BUILD_GOLD',
    2,
    'SUCCEEDED',
    dv.dataset_version_id,
    NOW() - INTERVAL '3 minutes',
    NOW() - INTERVAL '1 minute'
FROM recovery.pipeline_runs pr
JOIN recovery.dataset_versions dv
    ON dv.pipeline_run_id = pr.pipeline_run_id
WHERE pr.run_key = 'batch_20260925_001'
  AND dv.layer = 'SILVER';

COMMIT;