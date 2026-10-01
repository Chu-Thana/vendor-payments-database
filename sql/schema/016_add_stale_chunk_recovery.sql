CREATE OR REPLACE FUNCTION recovery.recover_stale_chunk_attempt(
    p_dataset_chunk_id BIGINT,
    p_stale_before TIMESTAMPTZ
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_chunk_execution_id BIGINT;
    v_attempt_number INTEGER;
    v_started_at TIMESTAMPTZ;
BEGIN
    SELECT
        chunk_execution_id,
        attempt_number,
        started_at
    INTO
        v_chunk_execution_id,
        v_attempt_number,
        v_started_at
    FROM recovery.chunk_executions
    WHERE dataset_chunk_id = p_dataset_chunk_id
      AND status = 'RUNNING'
    ORDER BY attempt_number DESC
    LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    IF v_started_at IS NULL
       OR v_started_at > p_stale_before THEN
        RETURN NULL;
    END IF;

    UPDATE recovery.chunk_executions
    SET
        status = 'FAILED',
        finished_at = clock_timestamp(),
        error_message =
            'Automatically recovered stale RUNNING chunk attempt. '
            || 'attempt_number='
            || v_attempt_number
            || ', started_at='
            || COALESCE(
                v_started_at::TEXT,
                'NULL'
            )
    WHERE chunk_execution_id =
        v_chunk_execution_id;

    UPDATE recovery.dataset_chunks
    SET
        status = 'FAILED',
        row_count = NULL,
        checksum = NULL,
        updated_at = clock_timestamp()
    WHERE dataset_chunk_id =
        p_dataset_chunk_id;

    RETURN v_chunk_execution_id;
END;
$$;