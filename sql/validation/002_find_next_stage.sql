WITH pipeline_sequence AS (
    SELECT *
    FROM (
        VALUES
            (1, 'TRANSFORM_SILVER'),
            (2, 'CHECK_SILVER'),
            (3, 'BUILD_GOLD'),
            (4, 'CHECK_GOLD'),
            (5, 'UPLOAD_S3'),
            (6, 'LOAD_REDSHIFT'),
            (7, 'CROSS_LAYER_VALIDATION')
    ) AS stages(stage_order, stage_name)
),

target_run AS (
    SELECT pipeline_run_id
    FROM recovery.pipeline_runs
    WHERE run_key = 'batch_20260925_001'
),

latest_attempts AS (
    SELECT DISTINCT ON (se.stage_name)
        se.stage_name,
        se.attempt_number,
        se.status
    FROM recovery.stage_executions se
    JOIN target_run tr
        ON tr.pipeline_run_id = se.pipeline_run_id
    ORDER BY
        se.stage_name,
        se.attempt_number DESC
)

SELECT
    ps.stage_order,
    ps.stage_name AS next_stage,
    la.attempt_number AS latest_attempt_number,
    la.status AS latest_status
FROM pipeline_sequence ps
LEFT JOIN latest_attempts la
    ON la.stage_name = ps.stage_name
WHERE
    la.status IS NULL
    OR la.status <> 'SUCCEEDED'
ORDER BY ps.stage_order
LIMIT 1;