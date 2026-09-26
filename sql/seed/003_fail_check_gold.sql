BEGIN;

INSERT INTO recovery.stage_executions (
    pipeline_run_id,
    stage_name,
    attempt_number,
    status,
    started_at,
    finished_at,
    error_message
)
SELECT
    pipeline_run_id,
    'CHECK_GOLD',
    1,
    'FAILED',
    NOW() - INTERVAL '2 minutes',
    NOW() - INTERVAL '1 minute',
    'Simulated Gold validation failure.'
FROM recovery.pipeline_runs
WHERE run_key = 'batch_20260925_001';

COMMIT;