WITH latest_attempts AS (
    SELECT DISTINCT ON (
        se.pipeline_run_id,
        se.stage_name
    )
        se.pipeline_run_id,
        se.stage_name,
        se.attempt_number,
        se.status,
        se.stage_execution_id
    FROM recovery.stage_executions se
    JOIN recovery.pipeline_runs pr
        ON pr.pipeline_run_id = se.pipeline_run_id
    WHERE pr.run_key = 'batch_20260925_001'
    ORDER BY
        se.pipeline_run_id,
        se.stage_name,
        se.attempt_number DESC
)
SELECT
    stage_name,
    attempt_number,
    status
FROM latest_attempts
WHERE status = 'FAILED'
ORDER BY stage_execution_id
LIMIT 1;