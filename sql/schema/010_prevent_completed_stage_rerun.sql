BEGIN;

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

    v_latest_stage_status TEXT;
BEGIN
    -- Lock pipeline run
    PERFORM 1
    FROM recovery.pipeline_runs
    WHERE pipeline_run_id = p_pipeline_run_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Pipeline run % does not exist.',
            p_pipeline_run_id;
    END IF;


    -- Read stage configuration
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


    -- Check predecessor
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


    -- Check current stage state
    SELECT status
    INTO v_latest_stage_status
    FROM recovery.latest_stage_attempts
    WHERE pipeline_run_id = p_pipeline_run_id
      AND stage_name = p_stage_name;


    IF v_latest_stage_status IN (
        'SUCCEEDED',
        'SKIPPED'
    ) THEN
        RAISE EXCEPTION
            'Stage % cannot be started because it is already % for pipeline run %.',
            p_stage_name,
            v_latest_stage_status,
            p_pipeline_run_id;
    END IF;


    IF v_latest_stage_status = 'RUNNING' THEN
        RAISE EXCEPTION
            'Stage % already has a RUNNING attempt for pipeline run %.',
            p_stage_name,
            p_pipeline_run_id;
    END IF;


    -- FAILED or never-run stage may start
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