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
BEGIN
    PERFORM 1
    FROM recovery.pipeline_runs
    WHERE pipeline_run_id = p_pipeline_run_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pipeline run % does not exist.', p_pipeline_run_id;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM recovery.pipeline_stages
        WHERE stage_name = p_stage_name
          AND is_active = TRUE
    ) THEN
        RAISE EXCEPTION 'Stage % does not exist or is inactive.', p_stage_name;
    END IF;

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

    SELECT COALESCE(MAX(attempt_number), 0) + 1
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
        started_at = COALESCE(started_at, clock_timestamp()),
        finished_at = NULL
    WHERE pipeline_run_id = p_pipeline_run_id;

    RETURN v_stage_execution_id;
END;
$$;


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
    SELECT pipeline_run_id, status
    INTO v_pipeline_run_id, v_execution_status
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
            finished_at = clock_timestamp(),
            error_message = NULL
        WHERE stage_execution_id = p_stage_execution_id;
    ELSE
        UPDATE recovery.stage_executions
        SET
            status = 'FAILED',
            finished_at = clock_timestamp(),
            error_message = COALESCE(
                p_error_message,
                'Pipeline stage failed.'
            )
        WHERE stage_execution_id = p_stage_execution_id;
    END IF;

    PERFORM recovery.refresh_pipeline_status(v_pipeline_run_id);
END;
$$;


CREATE OR REPLACE FUNCTION recovery.start_artifact_attempt(
    p_dataset_artifact_id BIGINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_artifact_status TEXT;
    v_attempt_number INTEGER;
    v_execution_id BIGINT;
BEGIN
    SELECT status
    INTO v_artifact_status
    FROM recovery.dataset_artifacts
    WHERE dataset_artifact_id = p_dataset_artifact_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Artifact % does not exist.',
            p_dataset_artifact_id;
    END IF;

    IF v_artifact_status IN ('VALIDATED', 'PUBLISHED') THEN
        RAISE EXCEPTION
            'Artifact % cannot be rebuilt because its status is %.',
            p_dataset_artifact_id,
            v_artifact_status;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM recovery.artifact_executions
        WHERE dataset_artifact_id = p_dataset_artifact_id
          AND status = 'RUNNING'
    ) THEN
        RAISE EXCEPTION
            'Artifact % already has a RUNNING attempt.',
            p_dataset_artifact_id;
    END IF;

    SELECT COALESCE(MAX(attempt_number), 0) + 1
    INTO v_attempt_number
    FROM recovery.artifact_executions
    WHERE dataset_artifact_id = p_dataset_artifact_id;

    INSERT INTO recovery.artifact_executions (
        dataset_artifact_id,
        attempt_number,
        status,
        started_at
    )
    VALUES (
        p_dataset_artifact_id,
        v_attempt_number,
        'RUNNING',
        clock_timestamp()
    )
    RETURNING artifact_execution_id
    INTO v_execution_id;

    UPDATE recovery.dataset_artifacts
    SET
        status = 'WRITING',
        row_count = NULL,
        checksum = NULL
    WHERE dataset_artifact_id = p_dataset_artifact_id;

    RETURN v_execution_id;
END;
$$;


CREATE OR REPLACE FUNCTION recovery.finish_artifact_attempt(
    p_artifact_execution_id BIGINT,
    p_success BOOLEAN,
    p_row_count BIGINT DEFAULT NULL,
    p_checksum TEXT DEFAULT NULL,
    p_error_message TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_dataset_artifact_id BIGINT;
    v_execution_status TEXT;
BEGIN
    SELECT dataset_artifact_id, status
    INTO v_dataset_artifact_id, v_execution_status
    FROM recovery.artifact_executions
    WHERE artifact_execution_id = p_artifact_execution_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Artifact execution % does not exist.',
            p_artifact_execution_id;
    END IF;

    IF v_execution_status <> 'RUNNING' THEN
        RAISE EXCEPTION
            'Artifact execution % cannot be finished because its status is %.',
            p_artifact_execution_id,
            v_execution_status;
    END IF;

    IF p_row_count IS NOT NULL AND p_row_count < 0 THEN
        RAISE EXCEPTION 'row_count cannot be negative.';
    END IF;

    IF p_success THEN
        UPDATE recovery.artifact_executions
        SET
            status = 'SUCCEEDED',
            finished_at = clock_timestamp(),
            error_message = NULL
        WHERE artifact_execution_id = p_artifact_execution_id;

        UPDATE recovery.dataset_artifacts
        SET
            status = 'COMPLETED',
            row_count = p_row_count,
            checksum = p_checksum
        WHERE dataset_artifact_id = v_dataset_artifact_id;
    ELSE
        UPDATE recovery.artifact_executions
        SET
            status = 'FAILED',
            finished_at = clock_timestamp(),
            error_message = COALESCE(
                p_error_message,
                'Artifact build failed.'
            )
        WHERE artifact_execution_id = p_artifact_execution_id;

        UPDATE recovery.dataset_artifacts
        SET
            status = 'FAILED',
            row_count = NULL,
            checksum = NULL
        WHERE dataset_artifact_id = v_dataset_artifact_id;
    END IF;
END;
$$;

COMMIT;