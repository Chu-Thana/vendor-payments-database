BEGIN;

ALTER TABLE recovery.pipeline_stages
ADD COLUMN IF NOT EXISTS predecessor_stage_name TEXT;


DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'pipeline_stages_predecessor_stage_name_fkey'
    ) THEN
        ALTER TABLE recovery.pipeline_stages
        ADD CONSTRAINT pipeline_stages_predecessor_stage_name_fkey
        FOREIGN KEY (predecessor_stage_name)
        REFERENCES recovery.pipeline_stages(stage_name);
    END IF;
END
$$;


UPDATE recovery.pipeline_stages
SET predecessor_stage_name = CASE stage_name
    WHEN 'TRANSFORM_SILVER'
        THEN NULL

    WHEN 'CHECK_SILVER'
        THEN 'TRANSFORM_SILVER'

    WHEN 'BUILD_GOLD'
        THEN 'CHECK_SILVER'

    WHEN 'CHECK_GOLD'
        THEN 'BUILD_GOLD'

    WHEN 'UPLOAD_S3'
        THEN 'CHECK_GOLD'

    WHEN 'LOAD_REDSHIFT'
        THEN 'UPLOAD_S3'

    WHEN 'CROSS_LAYER_VALIDATION'
        THEN 'LOAD_REDSHIFT'
END;


CREATE OR REPLACE FUNCTION recovery.start_stage_attempt(
    p_pipeline_run_id BIGINT,
    p_stage_name TEXT,
    p_input_dataset_version_id BIGINT DEFAULT NULL,
    p_output_dataset_version_id BIGINT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_attempt_number INTEGER;
    v_stage_execution_id BIGINT;
    v_predecessor_stage TEXT;
    v_predecessor_status TEXT;
BEGIN
    -- Lock pipeline run while creating the next attempt.
    PERFORM 1
    FROM recovery.pipeline_runs
    WHERE pipeline_run_id = p_pipeline_run_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Pipeline run % does not exist.',
            p_pipeline_run_id;
    END IF;


    -- Read stage configuration and predecessor.
    SELECT predecessor_stage_name
    INTO v_predecessor_stage
    FROM recovery.pipeline_stages
    WHERE stage_name = p_stage_name
      AND is_active = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Stage % does not exist or is inactive.',
            p_stage_name;
    END IF;


    -- A stage may start only after its predecessor has completed.
    IF v_predecessor_stage IS NOT NULL THEN

        SELECT status
        INTO v_predecessor_status
        FROM recovery.latest_stage_attempts
        WHERE pipeline_run_id = p_pipeline_run_id
          AND stage_name = v_predecessor_stage;

        IF v_predecessor_status IS NULL THEN
            RAISE EXCEPTION
                'Stage % cannot start because predecessor % has not run.',
                p_stage_name,
                v_predecessor_stage;
        END IF;

        IF v_predecessor_status NOT IN (
            'SUCCEEDED',
            'SKIPPED'
        ) THEN
            RAISE EXCEPTION
                'Stage % cannot start because predecessor % status is %.',
                p_stage_name,
                v_predecessor_stage,
                v_predecessor_status;
        END IF;

    END IF;


    -- Prevent duplicate concurrent attempts.
    IF EXISTS (
        SELECT 1
        FROM recovery.stage_executions
        WHERE pipeline_run_id = p_pipeline_run_id
          AND stage_name = p_stage_name
          AND status = 'RUNNING'
    ) THEN
        RAISE EXCEPTION
            'Stage % already has a RUNNING attempt for pipeline run %.',
            p_stage_name,
            p_pipeline_run_id;
    END IF;


    SELECT
        COALESCE(MAX(attempt_number), 0) + 1
    INTO v_attempt_number
    FROM recovery.stage_executions
    WHERE pipeline_run_id = p_pipeline_run_id
      AND stage_name = p_stage_name;


    INSERT INTO recovery.stage_executions (
        pipeline_run_id,
        stage_name,
        attempt_number,
        status,
        input_dataset_version_id,
        output_dataset_version_id,
        started_at
    )
    VALUES (
        p_pipeline_run_id,
        p_stage_name,
        v_attempt_number,
        'RUNNING',
        p_input_dataset_version_id,
        p_output_dataset_version_id,
        clock_timestamp()
    )
    RETURNING stage_execution_id
    INTO v_stage_execution_id;


    UPDATE recovery.pipeline_runs
    SET
        status = 'RUNNING',
        started_at = COALESCE(
            started_at,
            clock_timestamp()
        ),
        finished_at = NULL
    WHERE pipeline_run_id = p_pipeline_run_id;


    RETURN v_stage_execution_id;
END;
$$;

COMMIT;