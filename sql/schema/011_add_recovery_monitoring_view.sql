BEGIN;

CREATE OR REPLACE VIEW recovery.pipeline_monitoring AS

WITH retry_summary AS (
    SELECT
        pipeline_run_id,

        COUNT(*) FILTER (
            WHERE attempt_number > 1
        ) AS retry_attempt_count,

        COUNT(*) FILTER (
            WHERE status = 'FAILED'
        ) AS failed_attempt_count

    FROM recovery.stage_executions
    GROUP BY pipeline_run_id
),

latest_failure AS (
    SELECT DISTINCT ON (
        pipeline_run_id
    )
        pipeline_run_id,
        stage_name,
        attempt_number,
        error_message,
        finished_at

    FROM recovery.stage_executions

    WHERE status = 'FAILED'

    ORDER BY
        pipeline_run_id,
        finished_at DESC NULLS LAST,
        stage_execution_id DESC
),

latest_dataset AS (
    SELECT DISTINCT ON (
        pipeline_run_id,
        layer
    )
        pipeline_run_id,
        layer,
        version_key,
        status,
        row_count

    FROM recovery.dataset_versions

    ORDER BY
        pipeline_run_id,
        layer,
        dataset_version_id DESC
)

SELECT
    pr.pipeline_run_id,
    pr.run_key,
    pr.mode,
    pr.status AS pipeline_status,

    crs.current_stage,
    crs.latest_attempt_number,
    crs.latest_stage_status,

    COALESCE(
        rs.retry_attempt_count,
        0
    ) AS retry_attempt_count,

    COALESCE(
        rs.failed_attempt_count,
        0
    ) AS failed_attempt_count,

    lf.stage_name AS latest_failed_stage,
    lf.attempt_number AS latest_failed_attempt,
    lf.error_message AS latest_error_message,

    silver.version_key AS silver_version,
    silver.status AS silver_status,
    silver.row_count AS silver_row_count,

    gold.version_key AS gold_version,
    gold.status AS gold_status,
    gold.row_count AS gold_row_count,

    pr.started_at,
    pr.finished_at,
    pr.created_at

FROM recovery.pipeline_runs pr

LEFT JOIN recovery.current_recovery_state crs
    ON crs.pipeline_run_id = pr.pipeline_run_id

LEFT JOIN retry_summary rs
    ON rs.pipeline_run_id = pr.pipeline_run_id

LEFT JOIN latest_failure lf
    ON lf.pipeline_run_id = pr.pipeline_run_id

LEFT JOIN latest_dataset silver
    ON silver.pipeline_run_id = pr.pipeline_run_id
   AND silver.layer = 'SILVER'

LEFT JOIN latest_dataset gold
    ON gold.pipeline_run_id = pr.pipeline_run_id
   AND gold.layer = 'GOLD';

COMMIT;