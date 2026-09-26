BEGIN;


-- ============================================================
-- Start a new artifact build attempt
-- ============================================================

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
    -- Lock artifact so concurrent workers cannot start
    -- the same artifact attempt at the same time.
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


    -- Validated or published artifacts should be treated
    -- as immutable for the same dataset version.
    IF v_artifact_status IN ('VALIDATED', 'PUBLISHED') THEN
        RAISE EXCEPTION
            'Artifact % cannot be rebuilt because its status is %.',
            p_dataset_artifact_id,
            v_artifact_status;
    END IF;


    -- Prevent two RUNNING attempts for the same artifact.
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


    SELECT
        COALESCE(MAX(attempt_number), 0) + 1
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
        NOW()
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


-- ============================================================
-- Finish an artifact build attempt
-- ============================================================

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
    SELECT
        dataset_artifact_id,
        status
    INTO
        v_dataset_artifact_id,
        v_execution_status
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
        RAISE EXCEPTION
            'row_count cannot be negative.';
    END IF;


    IF p_success THEN

        UPDATE recovery.artifact_executions
        SET
            status = 'SUCCEEDED',
            finished_at = NOW(),
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
            finished_at = NOW(),
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