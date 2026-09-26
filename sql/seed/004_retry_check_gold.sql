BEGIN;

INSERT INTO recovery.stage_executions (
    pipeline_run_id,
    stage_name,
    attempt_number,
    status,
    started_at,
    finished_at
)
SELECT
    pipeline_run_id,
    'CHECK_GOLD',
    2,
    'SUCCEEDED',
    NOW() - INTERVAL '2 minutes',
    NOW() - INTERVAL '1 minute'
FROM recovery.pipeline_runs
WHERE run_key = 'batch_20260925_001';

COMMIT;