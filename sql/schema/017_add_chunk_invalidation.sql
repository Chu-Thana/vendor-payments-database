CREATE OR REPLACE FUNCTION recovery.invalidate_dataset_chunk(
    p_dataset_chunk_id BIGINT,
    p_reason TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE recovery.dataset_chunks
    SET
        status = 'FAILED',
        row_count = NULL,
        checksum = NULL,
        updated_at = clock_timestamp()
    WHERE dataset_chunk_id = p_dataset_chunk_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Dataset chunk % does not exist.',
            p_dataset_chunk_id;
    END IF;
END;
$$;