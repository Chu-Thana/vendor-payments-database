BEGIN;


INSERT INTO recovery.pipeline_runs (
    run_key,
    mode,
    status,
    started_at
)
VALUES (
    'batch_20260926_001',
    'FULL',
    'RUNNING',
    NOW()
);


INSERT INTO recovery.dataset_versions (
    pipeline_run_id,
    version_key,
    layer,
    status
)
SELECT
    pipeline_run_id,
    'gold_batch_20260926_001',
    'GOLD',
    'BUILDING'
FROM recovery.pipeline_runs
WHERE run_key = 'batch_20260926_001';


INSERT INTO recovery.dataset_artifacts (
    dataset_version_id,
    artifact_name,
    artifact_path,
    status
)
SELECT
    dataset_version_id,
    'mart_spending_by_department.csv',
    'data/processed/gold/batch_20260926_001/mart_spending_by_department.csv',
    'CREATED'
FROM recovery.dataset_versions
WHERE version_key = 'gold_batch_20260926_001';


COMMIT;