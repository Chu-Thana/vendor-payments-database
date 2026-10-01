CREATE OR REPLACE FUNCTION recovery.get_or_create_dataset_chunk(
    p_dataset_version_id BIGINT,
    p_chunk_id TEXT,
    p_chunk_index INTEGER,
    p_source_start_row BIGINT,
    p_source_end_row BIGINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_dataset_chunk_id BIGINT;
BEGIN
    INSERT INTO recovery.dataset_chunks (
        dataset_version_id,
        chunk_id,
        chunk_index,
        source_start_row,
        source_end_row
    )
    VALUES (
        p_dataset_version_id,
        p_chunk_id,
        p_chunk_index,
        p_source_start_row,
        p_source_end_row
    )
    ON CONFLICT (
        dataset_version_id,
        chunk_id
    )
    DO UPDATE SET
        chunk_index = EXCLUDED.chunk_index,
        source_start_row = EXCLUDED.source_start_row,
        source_end_row = EXCLUDED.source_end_row,
        updated_at = clock_timestamp()
    RETURNING dataset_chunk_id
    INTO v_dataset_chunk_id;

    RETURN v_dataset_chunk_id;
END;
$$;


CREATE OR REPLACE FUNCTION recovery.start_chunk_attempt(
    p_dataset_chunk_id BIGINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_existing_status TEXT;
    v_attempt_number INTEGER;
    v_chunk_execution_id BIGINT;
BEGIN
    SELECT status
    INTO v_existing_status
    FROM recovery.dataset_chunks
    WHERE dataset_chunk_id = p_dataset_chunk_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Dataset chunk % does not exist.',
            p_dataset_chunk_id;
    END IF;

    IF v_existing_status = 'VALIDATED' THEN
        RAISE EXCEPTION
            'Dataset chunk % is already VALIDATED.',
            p_dataset_chunk_id;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM recovery.chunk_executions
        WHERE dataset_chunk_id = p_dataset_chunk_id
          AND status = 'RUNNING'
    ) THEN
        RAISE EXCEPTION
            'Dataset chunk % already has a RUNNING attempt.',
            p_dataset_chunk_id;
    END IF;

    SELECT COALESCE(MAX(attempt_number), 0) + 1
    INTO v_attempt_number
    FROM recovery.chunk_executions
    WHERE dataset_chunk_id = p_dataset_chunk_id;

    INSERT INTO recovery.chunk_executions (
        dataset_chunk_id,
        attempt_number,
        status,
        started_at
    )
    VALUES (
        p_dataset_chunk_id,
        v_attempt_number,
        'RUNNING',
        clock_timestamp()
    )
    RETURNING chunk_execution_id
    INTO v_chunk_execution_id;

    UPDATE recovery.dataset_chunks
    SET
        status = 'PROCESSING',
        updated_at = clock_timestamp()
    WHERE dataset_chunk_id = p_dataset_chunk_id;

    RETURN v_chunk_execution_id;
END;
$$;


CREATE OR REPLACE FUNCTION recovery.finish_chunk_attempt(
    p_chunk_execution_id BIGINT,
    p_success BOOLEAN,
    p_row_count BIGINT,
    p_checksum TEXT,
    p_error_message TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_dataset_chunk_id BIGINT;
BEGIN
    SELECT dataset_chunk_id
    INTO v_dataset_chunk_id
    FROM recovery.chunk_executions
    WHERE chunk_execution_id = p_chunk_execution_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Chunk execution % does not exist.',
            p_chunk_execution_id;
    END IF;

    IF p_success THEN
        UPDATE recovery.chunk_executions
        SET
            status = 'SUCCEEDED',
            finished_at = clock_timestamp(),
            error_message = NULL
        WHERE chunk_execution_id = p_chunk_execution_id;

        UPDATE recovery.dataset_chunks
        SET
            status = 'VALIDATED',
            row_count = p_row_count,
            checksum = p_checksum,
            updated_at = clock_timestamp()
        WHERE dataset_chunk_id = v_dataset_chunk_id;

    ELSE
        UPDATE recovery.chunk_executions
        SET
            status = 'FAILED',
            finished_at = clock_timestamp(),
            error_message = p_error_message
        WHERE chunk_execution_id = p_chunk_execution_id;

        UPDATE recovery.dataset_chunks
        SET
            status = 'FAILED',
            row_count = NULL,
            checksum = NULL,
            updated_at = clock_timestamp()
        WHERE dataset_chunk_id = v_dataset_chunk_id;
    END IF;
END;
$$;