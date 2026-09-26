BEGIN;


-- ============================================================
-- Start a new pipeline stage attempt
-- ============================================================

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
BEGIN
    -- Lock the pipeline run so concurrent workers cannot
    -- calculate the same attempt number at the same time.
    PERFORM 1
    FROM recovery.pipeline_runs
    WHERE pipeline_run_id = p_pipeline_run_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Pipeline run % does not exist.',
            p_pipeline_run_id;
    END IF;


    -- Stage must exist in the configured pipeline.
    IF NOT EXISTS (
        SELECT 1
        FROM recovery.pipeline_stages
        WHERE stage_name = p_stage_name
          AND is_active = TRUE
    ) THEN
        RAISE EXCEPTION
            'Stage % does not exist or is inactive.',
            p_stage_name;
    END IF;


    -- Only one RUNNING attempt for the same stage/run.
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
        NOW()
    )
    RETURNING stage_execution_id
    INTO v_stage_execution_id;


    UPDATE recovery.pipeline_runs
    SET
        status = 'RUNNING',
        started_at = COALESCE(started_at, NOW()),
        finished_at = NULL
    WHERE pipeline_run_id = p_pipeline_run_id;


    RETURN v_stage_execution_id;
END;
$$;


-- ============================================================
-- Finish a pipeline stage attempt
-- ============================================================

CREATE OR REPLACE FUNCTION recovery.finish_stage_attempt(
    p_stage_execution_id BIGINT,
    p_success BOOLEAN,
    p_error_message TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_pipeline_run_id BIGINT;
    v_execution_status TEXT;
BEGIN
    SELECT
        pipeline_run_id,
        status
    INTO
        v_pipeline_run_id,
        v_execution_status
    FROM recovery.stage_executions
    WHERE stage_execution_id = p_stage_execution_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Stage execution % does not exist.',
            p_stage_execution_id;
    END IF;


    IF v_execution_status <> 'RUNNING' THEN
        RAISE EXCEPTION
            'Stage execution % cannot be finished because its status is %.',
            p_stage_execution_id,
            v_execution_status;
    END IF;


    IF p_success THEN

        UPDATE recovery.stage_executions
        SET
            status = 'SUCCEEDED',
            finished_at = NOW(),
            error_message = NULL
        WHERE stage_execution_id = p_stage_execution_id;

    ELSE

        UPDATE recovery.stage_executions
        SET
            status = 'FAILED',
            finished_at = NOW(),
            error_message = COALESCE(
                p_error_message,
                'Pipeline stage failed.'
            )
        WHERE stage_execution_id = p_stage_execution_id;


        UPDATE recovery.pipeline_runs
        SET status = 'FAILED'
        WHERE pipeline_run_id = v_pipeline_run_id;

    END IF;
END;
$$;


COMMIT;