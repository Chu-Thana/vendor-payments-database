BEGIN;

-- สร้าง Gold dataset version สำหรับ run เดิม
INSERT INTO recovery.dataset_versions (
    pipeline_run_id,
    version_key,
    layer,
    status,
    row_count
)
SELECT
    pipeline_run_id,
    'gold_batch_20260925_001',
    'GOLD',
    'BUILDING',
    NULL
FROM recovery.pipeline_runs
WHERE run_key = 'batch_20260925_001';


-- จำลองว่า Gold สร้างได้ 3 marts แล้ว
INSERT INTO recovery.dataset_artifacts (
    dataset_version_id,
    artifact_name,
    artifact_path,
    status,
    row_count
)
SELECT
    dataset_version_id,
    'mart_spending_by_fiscal_year.csv',
    'data/processed/gold/mart_spending_by_fiscal_year.csv',
    'COMPLETED',
    7
FROM recovery.dataset_versions
WHERE version_key = 'gold_batch_20260925_001';


INSERT INTO recovery.dataset_artifacts (
    dataset_version_id,
    artifact_name,
    artifact_path,
    status,
    row_count
)
SELECT
    dataset_version_id,
    'mart_spending_by_department.csv',
    'data/processed/gold/mart_spending_by_department.csv',
    'COMPLETED',
    250
FROM recovery.dataset_versions
WHERE version_key = 'gold_batch_20260925_001';


INSERT INTO recovery.dataset_artifacts (
    dataset_version_id,
    artifact_name,
    artifact_path,
    status,
    row_count
)
SELECT
    dataset_version_id,
    'mart_spending_by_supplier_top_n.csv',
    'data/processed/gold/mart_spending_by_supplier_top_n.csv',
    'COMPLETED',
    100
FROM recovery.dataset_versions
WHERE version_key = 'gold_batch_20260925_001';


-- mart ที่ 4 ล้มเหลว
INSERT INTO recovery.dataset_artifacts (
    dataset_version_id,
    artifact_name,
    artifact_path,
    status
)
SELECT
    dataset_version_id,
    'mart_pending_by_department.csv',
    'data/processed/gold/mart_pending_by_department.csv',
    'FAILED'
FROM recovery.dataset_versions
WHERE version_key = 'gold_batch_20260925_001';


COMMIT;