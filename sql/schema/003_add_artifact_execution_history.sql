BEGIN;


CREATE TABLE recovery.artifact_executions (
    artifact_execution_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    dataset_artifact_id BIGINT NOT NULL
        REFERENCES recovery.dataset_artifacts(dataset_artifact_id),

    attempt_number INTEGER NOT NULL
        CHECK (attempt_number > 0),

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

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (
        dataset_artifact_id,
        attempt_number
    ),

    CHECK (
        finished_at IS NULL
        OR started_at IS NULL
        OR finished_at >= started_at
    )
);


CREATE INDEX idx_artifact_executions_artifact
    ON recovery.artifact_executions(dataset_artifact_id);


CREATE INDEX idx_artifact_executions_status
    ON recovery.artifact_executions(status);


CREATE OR REPLACE VIEW recovery.latest_artifact_attempts AS

SELECT DISTINCT ON (
    dataset_artifact_id
)
    artifact_execution_id,
    dataset_artifact_id,
    attempt_number,
    status,
    started_at,
    finished_at,
    error_message

FROM recovery.artifact_executions

ORDER BY
    dataset_artifact_id,
    attempt_number DESC;


COMMIT;