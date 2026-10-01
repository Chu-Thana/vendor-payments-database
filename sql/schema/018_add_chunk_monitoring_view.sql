CREATE OR REPLACE VIEW recovery.chunk_recovery_monitoring AS

WITH chunk_summary AS (
    SELECT
        dataset_version_id,

        COUNT(*) AS total_chunks,

        COUNT(*) FILTER (
            WHERE status = 'VALIDATED'
        ) AS validated_chunks,

        COUNT(*) FILTER (
            WHERE status = 'FAILED'
        ) AS failed_chunks,

        COUNT(*) FILTER (
            WHERE status = 'PROCESSING'
        ) AS processing_chunks,

        COUNT(*) FILTER (
            WHERE status = 'CREATED'
        ) AS created_chunks,

        COALESCE(
            SUM(row_count) FILTER (
                WHERE status = 'VALIDATED'
            ),
            0
        ) AS validated_rows,

        MIN(chunk_index) FILTER (
            WHERE status <> 'VALIDATED'
        ) AS first_incomplete_chunk

    FROM recovery.dataset_chunks

    GROUP BY dataset_version_id
),

execution_summary AS (
    SELECT
        dc.dataset_version_id,

        COUNT(*) FILTER (
            WHERE ce.attempt_number > 1
        ) AS retry_attempts,

        MAX(
            ce.attempt_number
        ) AS max_attempt_number

    FROM recovery.dataset_chunks dc

    LEFT JOIN recovery.chunk_executions ce
        ON ce.dataset_chunk_id =
           dc.dataset_chunk_id

    GROUP BY dc.dataset_version_id
)

SELECT
    dv.dataset_version_id,
    dv.pipeline_run_id,
    dv.layer,
    dv.status AS dataset_status,

    COALESCE(
        cs.total_chunks,
        0
    ) AS total_chunks,

    COALESCE(
        cs.validated_chunks,
        0
    ) AS validated_chunks,

    COALESCE(
        cs.failed_chunks,
        0
    ) AS failed_chunks,

    COALESCE(
        cs.processing_chunks,
        0
    ) AS processing_chunks,

    COALESCE(
        cs.created_chunks,
        0
    ) AS created_chunks,

    COALESCE(
        cs.validated_rows,
        0
    ) AS validated_rows,

    cs.first_incomplete_chunk,

    COALESCE(
        es.retry_attempts,
        0
    ) AS retry_attempts,

    COALESCE(
        es.max_attempt_number,
        0
    ) AS max_attempt_number

FROM recovery.dataset_versions dv

LEFT JOIN chunk_summary cs
    ON cs.dataset_version_id =
       dv.dataset_version_id

LEFT JOIN execution_summary es
    ON es.dataset_version_id =
       dv.dataset_version_id

WHERE dv.layer = 'SILVER';