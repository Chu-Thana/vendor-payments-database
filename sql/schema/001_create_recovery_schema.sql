CREATE SCHEMA IF NOT EXISTS recovery;


CREATE TABLE recovery.pipeline_runs (
    pipeline_run_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    run_key TEXT NOT NULL UNIQUE,

    pipeline_name TEXT NOT NULL DEFAULT 'vendor_payments_batch_etl',

    mode TEXT NOT NULL
        CHECK (mode IN ('FULL', 'SAMPLE')),

    status TEXT NOT NULL
        CHECK (
            status IN (
                'CREATED',
                'RUNNING',
                'SUCCEEDED',
                'FAILED'
            )
        ),

    source_file TEXT,

    source_row_count BIGINT
        CHECK (
            source_row_count IS NULL
            OR source_row_count >= 0
        ),

    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CHECK (
        finished_at IS NULL
        OR started_at IS NULL
        OR finished_at >= started_at
    )
);


CREATE TABLE recovery.dataset_versions (
    dataset_version_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    pipeline_run_id BIGINT NOT NULL
        REFERENCES recovery.pipeline_runs(pipeline_run_id),

    version_key TEXT NOT NULL UNIQUE,

    layer TEXT NOT NULL
        CHECK (
            layer IN (
                'RAW',
                'SILVER',
                'GOLD'
            )
        ),

    status TEXT NOT NULL
        CHECK (
            status IN (
                'CREATED',
                'BUILDING',
                'TRANSFORMED',
                'VALIDATED',
                'PUBLISHED',
                'FAILED'
            )
        ),

    row_count BIGINT
        CHECK (
            row_count IS NULL
            OR row_count >= 0
        ),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    validated_at TIMESTAMPTZ,

    published_at TIMESTAMPTZ,

    UNIQUE (
        pipeline_run_id,
        layer
    )
);


CREATE TABLE recovery.stage_executions (
    stage_execution_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    pipeline_run_id BIGINT NOT NULL
        REFERENCES recovery.pipeline_runs(pipeline_run_id),

    stage_name TEXT NOT NULL
        CHECK (
            stage_name IN (
                'TRANSFORM_SILVER',
                'CHECK_SILVER',
                'BUILD_GOLD',
                'CHECK_GOLD',
                'UPLOAD_S3',
                'LOAD_REDSHIFT',
                'CROSS_LAYER_VALIDATION'
            )
        ),

    attempt_number INTEGER NOT NULL DEFAULT 1
        CHECK (attempt_number > 0),

    status TEXT NOT NULL
        CHECK (
            status IN (
                'PENDING',
                'RUNNING',
                'SUCCEEDED',
                'FAILED',
                'SKIPPED'
            )
        ),

    input_dataset_version_id BIGINT
        REFERENCES recovery.dataset_versions(dataset_version_id),

    output_dataset_version_id BIGINT
        REFERENCES recovery.dataset_versions(dataset_version_id),

    started_at TIMESTAMPTZ,

    finished_at TIMESTAMPTZ,

    error_message TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (
        pipeline_run_id,
        stage_name,
        attempt_number
    ),

    CHECK (
        finished_at IS NULL
        OR started_at IS NULL
        OR finished_at >= started_at
    )
);


CREATE TABLE recovery.validation_results (
    validation_result_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    dataset_version_id BIGINT NOT NULL
        REFERENCES recovery.dataset_versions(dataset_version_id),

    validation_name TEXT NOT NULL,

    status TEXT NOT NULL
        CHECK (
            status IN (
                'PASS',
                'PASS_WITH_WARNINGS',
                'FAIL'
            )
        ),

    metrics JSONB NOT NULL DEFAULT '{}'::JSONB,

    report_path TEXT,

    validated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


CREATE TABLE recovery.dataset_artifacts (
    dataset_artifact_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    dataset_version_id BIGINT NOT NULL
        REFERENCES recovery.dataset_versions(dataset_version_id),

    artifact_name TEXT NOT NULL,

    artifact_path TEXT NOT NULL,

    status TEXT NOT NULL
        CHECK (
            status IN (
                'CREATED',
                'WRITING',
                'COMPLETED',
                'VALIDATED',
                'PUBLISHED',
                'FAILED'
            )
        ),

    row_count BIGINT
        CHECK (
            row_count IS NULL
            OR row_count >= 0
        ),

    checksum TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (
        dataset_version_id,
        artifact_name
    )
);


CREATE INDEX idx_dataset_versions_run
    ON recovery.dataset_versions(pipeline_run_id);


CREATE INDEX idx_dataset_versions_status
    ON recovery.dataset_versions(status);


CREATE INDEX idx_stage_executions_run
    ON recovery.stage_executions(pipeline_run_id);


CREATE INDEX idx_stage_executions_status
    ON recovery.stage_executions(status);


CREATE INDEX idx_validation_results_dataset
    ON recovery.validation_results(dataset_version_id);


CREATE INDEX idx_dataset_artifacts_dataset
    ON recovery.dataset_artifacts(dataset_version_id);


CREATE INDEX idx_dataset_artifacts_status
    ON recovery.dataset_artifacts(status);