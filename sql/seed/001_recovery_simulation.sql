BEGIN;

INSERT INTO recovery.pipeline_runs (
    run_key,
    mode,
    status,
    source_file,
    source_row_count,
    started_at
)
VALUES (
    'batch_20260925_001',
    'FULL',
    'RUNNING',
    'vendor_payments.csv',
    3350000,
    NOW()
);


INSERT INTO recovery.dataset_versions (
    pipeline_run_id,
    version_key,
    layer,
    status,
    row_count,
    validated_at
)
SELECT
    pipeline_run_id,
    'silver_batch_20260925_001',
    'SILVER',
    'VALIDATED',
    3350000,
    NOW()
FROM recovery.pipeline_runs
WHERE run_key = 'batch_20260925_001';


INSERT INTO recovery.stage_executions (
    pipeline_run_id,
    stage_name,
    attempt_number,
    status,
    output_dataset_version_id,
    started_at,
    finished_at
)
SELECT
    pr.pipeline_run_id,
    'TRANSFORM_SILVER',
    1,
    'SUCCEEDED',
    dv.dataset_version_id,
    NOW() - INTERVAL '15 minutes',
    NOW() - INTERVAL '10 minutes'
FROM recovery.pipeline_runs pr
JOIN recovery.dataset_versions dv
    ON dv.pipeline_run_id = pr.pipeline_run_id
WHERE pr.run_key = 'batch_20260925_001'
  AND dv.layer = 'SILVER';


INSERT INTO recovery.stage_executions (
    pipeline_run_id,
    stage_name,
    attempt_number,
    status,
    input_dataset_version_id,
    started_at,
    finished_at
)
SELECT
    pr.pipeline_run_id,
    'CHECK_SILVER',
    1,
    'SUCCEEDED',
    dv.dataset_version_id,
    NOW() - INTERVAL '9 minutes',
    NOW() - INTERVAL '8 minutes'
FROM recovery.pipeline_runs pr
JOIN recovery.dataset_versions dv
    ON dv.pipeline_run_id = pr.pipeline_run_id
WHERE pr.run_key = 'batch_20260925_001'
  AND dv.layer = 'SILVER';


INSERT INTO recovery.validation_results (
    dataset_version_id,
    validation_name,
    status,
    metrics,
    report_path
)
SELECT
    dataset_version_id,
    'silver_output_validation',
    'PASS',
    jsonb_build_object(
        'row_count', 3350000,
        'missing_required_columns', 0,
        'duplicate_source_hashes', 0
    ),
    'reports/silver_output_validation_report.txt'
FROM recovery.dataset_versions
WHERE version_key = 'silver_batch_20260925_001';


INSERT INTO recovery.dataset_artifacts (
    dataset_version_id,
    artifact_name,
    artifact_path,
    status,
    row_count
)
SELECT
    dataset_version_id,
    'vendor_payments_silver.csv',
    'data/processed/silver/vendor_payments_silver.csv',
    'VALIDATED',
    3350000
FROM recovery.dataset_versions
WHERE version_key = 'silver_batch_20260925_001';


INSERT INTO recovery.stage_executions (
    pipeline_run_id,
    stage_name,
    attempt_number,
    status,
    input_dataset_version_id,
    started_at,
    finished_at,
    error_message
)
SELECT
    pr.pipeline_run_id,
    'BUILD_GOLD',
    1,
    'FAILED',
    dv.dataset_version_id,
    NOW() - INTERVAL '7 minutes',
    NOW() - INTERVAL '5 minutes',
    'Simulated Gold build failure.'
FROM recovery.pipeline_runs pr
JOIN recovery.dataset_versions dv
    ON dv.pipeline_run_id = pr.pipeline_run_id
WHERE pr.run_key = 'batch_20260925_001'
  AND dv.layer = 'SILVER';


COMMIT;