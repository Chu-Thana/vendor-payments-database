CREATE OR REPLACE FUNCTION recovery.get_pending_dataset_chunks(
    p_dataset_version_id BIGINT
)
RETURNS TABLE (
    dataset_chunk_id BIGINT,
    chunk_id TEXT,
    chunk_index INTEGER,
    source_start_row BIGINT,
    source_end_row BIGINT,
    status TEXT,
    attempt_count BIGINT
)
LANGUAGE sql
AS $$
    SELECT
        dc.dataset_chunk_id,
        dc.chunk_id,
        dc.chunk_index,
        dc.source_start_row,
        dc.source_end_row,
        dc.status,
        COUNT(ce.chunk_execution_id) AS attempt_count
    FROM recovery.dataset_chunks dc
    LEFT JOIN recovery.chunk_executions ce
        ON ce.dataset_chunk_id = dc.dataset_chunk_id
    WHERE dc.dataset_version_id = p_dataset_version_id
      AND dc.status <> 'VALIDATED'
    GROUP BY
        dc.dataset_chunk_id,
        dc.chunk_id,
        dc.chunk_index,
        dc.source_start_row,
        dc.source_end_row,
        dc.status
    ORDER BY dc.chunk_index;
$$;