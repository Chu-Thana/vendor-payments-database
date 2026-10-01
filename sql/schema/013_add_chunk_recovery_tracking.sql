CREATE TABLE recovery.dataset_chunks (
    dataset_chunk_id BIGSERIAL PRIMARY KEY,

    dataset_version_id BIGINT NOT NULL
        REFERENCES recovery.dataset_versions(dataset_version_id)
        ON DELETE CASCADE,

    chunk_id TEXT NOT NULL,

    chunk_index INTEGER NOT NULL,

    source_start_row BIGINT,
    source_end_row BIGINT,

    status TEXT NOT NULL DEFAULT 'CREATED'
        CHECK (
            status IN (
                'CREATED',
                'PROCESSING',
                'COMPLETED',
                'VALIDATED',
                'FAILED'
            )
        ),

    row_count BIGINT,
    checksum TEXT,

    created_at TIMESTAMPTZ NOT NULL
        DEFAULT clock_timestamp(),

    updated_at TIMESTAMPTZ NOT NULL
        DEFAULT clock_timestamp(),

    UNIQUE (
        dataset_version_id,
        chunk_id
    ),

    UNIQUE (
        dataset_version_id,
        chunk_index
    )
);


CREATE TABLE recovery.chunk_executions (
    chunk_execution_id BIGSERIAL PRIMARY KEY,

    dataset_chunk_id BIGINT NOT NULL
        REFERENCES recovery.dataset_chunks(dataset_chunk_id)
        ON DELETE CASCADE,

    attempt_number INTEGER NOT NULL,

    status TEXT NOT NULL
        CHECK (
            status IN (
                'PENDING',
                'RUNNING',
                'SUCCEEDED',
                'FAILED'
            )
        ),

    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,

    error_message TEXT,

    created_at TIMESTAMPTZ NOT NULL
        DEFAULT clock_timestamp(),

    UNIQUE (
        dataset_chunk_id,
        attempt_number
    )
);


CREATE INDEX idx_dataset_chunks_dataset_version
    ON recovery.dataset_chunks(dataset_version_id);

CREATE INDEX idx_dataset_chunks_status
    ON recovery.dataset_chunks(status);

CREATE INDEX idx_chunk_executions_chunk
    ON recovery.chunk_executions(dataset_chunk_id);

CREATE INDEX idx_chunk_executions_status
    ON recovery.chunk_executions(status);