BEGIN;


-- ============================================================
-- 1. Pipeline stage catalog
-- ============================================================

CREATE TABLE IF NOT EXISTS recovery.pipeline_stages (
    stage_name TEXT PRIMARY KEY,

    stage_order INTEGER NOT NULL UNIQUE
        CHECK (stage_order > 0),

    is_active BOOLEAN NOT NULL DEFAULT TRUE
);


INSERT INTO recovery.pipeline_stages (
    stage_name,
    stage_order
)
VALUES
    ('TRANSFORM_SILVER', 1),
    ('CHECK_SILVER', 2),
    ('BUILD_GOLD', 3),
    ('CHECK_GOLD', 4),
    ('UPLOAD_S3', 5),
    ('LOAD_REDSHIFT', 6),
    ('CROSS_LAYER_VALIDATION', 7)
ON CONFLICT (stage_name) DO UPDATE
SET stage_order = EXCLUDED.stage_order;


-- ============================================================
-- 2. Link validation result to the exact stage attempt
-- ============================================================

ALTER TABLE recovery.validation_results
ADD COLUMN IF NOT EXISTS stage_execution_id BIGINT;


DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'validation_results_stage_execution_id_fkey'
    ) THEN
        ALTER TABLE recovery.validation_results
        ADD CONSTRAINT validation_results_stage_execution_id_fkey
        FOREIGN KEY (stage_execution_id)
        REFERENCES recovery.stage_executions(stage_execution_id);
    END IF;
END
$$;


CREATE INDEX IF NOT EXISTS idx_validation_results_stage_execution
    ON recovery.validation_results(stage_execution_id);


-- ============================================================
-- 3. Latest attempt for every stage in every pipeline run
-- ============================================================

CREATE OR REPLACE VIEW recovery.latest_stage_attempts AS

SELECT DISTINCT ON (
    pipeline_run_id,
    stage_name
)
    stage_execution_id,
    pipeline_run_id,
    stage_name,
    attempt_number,
    status,
    input_dataset_version_id,
    output_dataset_version_id,
    started_at,
    finished_at,
    error_message
FROM recovery.stage_executions
ORDER BY
    pipeline_run_id,
    stage_name,
    attempt_number DESC;


-- ============================================================
-- 4. Current recovery position for each pipeline run
-- ============================================================

CREATE OR REPLACE VIEW recovery.current_recovery_state AS

SELECT
    pr.pipeline_run_id,
    pr.run_key,
    pr.status AS pipeline_status,

    ps.stage_order,

    ps.stage_name AS current_stage,

    lsa.attempt_number AS latest_attempt_number,

    lsa.status AS latest_stage_status,

    lsa.error_message

FROM recovery.pipeline_runs pr

CROSS JOIN LATERAL (

    SELECT
        stages.stage_order,
        stages.stage_name

    FROM recovery.pipeline_stages stages

    LEFT JOIN recovery.latest_stage_attempts latest
        ON latest.pipeline_run_id = pr.pipeline_run_id
       AND latest.stage_name = stages.stage_name

    WHERE stages.is_active = TRUE
      AND (
          latest.status IS NULL
          OR latest.status NOT IN (
              'SUCCEEDED',
              'SKIPPED'
          )
      )

    ORDER BY stages.stage_order

    LIMIT 1

) ps

LEFT JOIN recovery.latest_stage_attempts lsa
    ON lsa.pipeline_run_id = pr.pipeline_run_id
   AND lsa.stage_name = ps.stage_name;


COMMIT;