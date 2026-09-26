BEGIN;

-- Retry mart_pending_by_department ให้สำเร็จ
UPDATE recovery.dataset_artifacts da
SET
    status = 'COMPLETED',
    row_count = 180
FROM recovery.dataset_versions dv
WHERE da.dataset_version_id = dv.dataset_version_id
  AND dv.version_key = 'gold_batch_20260925_001'
  AND da.artifact_name = 'mart_pending_by_department.csv';


-- สร้าง artifact ที่ยังขาด
INSERT INTO recovery.dataset_artifacts (
    dataset_version_id,
    artifact_name,
    artifact_path,
    status,
    row_count
)
SELECT
    dataset_version_id,
    'mart_fund_category_summary.csv',
    'data/processed/gold/mart_fund_category_summary.csv',
    'COMPLETED',
    42
FROM recovery.dataset_versions
WHERE version_key = 'gold_batch_20260925_001'
ON CONFLICT (
    dataset_version_id,
    artifact_name
)
DO UPDATE SET
    artifact_path = EXCLUDED.artifact_path,
    status = EXCLUDED.status,
    row_count = EXCLUDED.row_count;

COMMIT;