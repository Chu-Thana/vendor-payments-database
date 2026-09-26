BEGIN;

INSERT INTO recovery.pipeline_runs (
    run_key,
    mode,
    status
)
VALUES (
    'batch_20260926_002',
    'FULL',
    'CREATED'
);

COMMIT;
