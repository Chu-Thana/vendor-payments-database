BEGIN;

ALTER TABLE recovery.stage_executions
DROP CONSTRAINT IF EXISTS stage_executions_stage_name_check;


-- Temporarily move old downstream stages out of the way.
UPDATE recovery.pipeline_stages
SET stage_order = 106
WHERE stage_name = 'LOAD_REDSHIFT';

UPDATE recovery.pipeline_stages
SET stage_order = 107
WHERE stage_name = 'CROSS_LAYER_VALIDATION';


-- Existing UPLOAD_S3 remains stage 5.
UPDATE recovery.pipeline_stages
SET
    stage_order = 5,
    predecessor_stage_name = 'CHECK_GOLD',
    is_active = TRUE
WHERE stage_name = 'UPLOAD_S3';


INSERT INTO recovery.pipeline_stages (
    stage_name,
    stage_order,
    predecessor_stage_name,
    is_active
)
VALUES
    (
        'REDSHIFT_CREATE_SCHEMAS',
        6,
        'UPLOAD_S3',
        TRUE
    ),
    (
        'REDSHIFT_CREATE_BATCH_LANDING_TABLES',
        7,
        'REDSHIFT_CREATE_SCHEMAS',
        TRUE
    ),
    (
        'REDSHIFT_COPY_BATCH_GOLD',
        8,
        'REDSHIFT_CREATE_BATCH_LANDING_TABLES',
        TRUE
    ),
    (
        'REDSHIFT_CREATE_ANALYTICS_VIEWS',
        9,
        'REDSHIFT_COPY_BATCH_GOLD',
        TRUE
    ),
    (
        'REDSHIFT_VALIDATE_ANALYTICS',
        10,
        'REDSHIFT_CREATE_ANALYTICS_VIEWS',
        TRUE
    )
ON CONFLICT (stage_name)
DO UPDATE SET
    stage_order = EXCLUDED.stage_order,
    predecessor_stage_name = EXCLUDED.predecessor_stage_name,
    is_active = EXCLUDED.is_active;


UPDATE recovery.pipeline_stages
SET
    stage_order = 11,
    predecessor_stage_name = 'REDSHIFT_VALIDATE_ANALYTICS',
    is_active = TRUE
WHERE stage_name = 'CROSS_LAYER_VALIDATION';


UPDATE recovery.pipeline_stages
SET
    is_active = FALSE
WHERE stage_name = 'LOAD_REDSHIFT';


COMMIT;