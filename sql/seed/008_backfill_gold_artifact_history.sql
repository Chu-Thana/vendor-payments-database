BEGIN;

INSERT INTO recovery.artifact_executions (
    dataset_artifact_id,
    attempt_number,
    status,
    started_at,
    finished_at
)
SELECT
    da.dataset_artifact_id,
    1,
    'SUCCEEDED',
    NOW() - INTERVAL '20 minutes',
    NOW() - INTERVAL '19 minutes'

FROM recovery.dataset_artifacts da

JOIN recovery.dataset_versions dv
    ON dv.dataset_version_id = da.dataset_version_id

WHERE dv.version_key = 'gold_batch_20260925_001'

  AND da.artifact_name IN (
      'mart_spending_by_fiscal_year.csv',
      'mart_spending_by_department.csv',
      'mart_spending_by_supplier_top_n.csv',
      'mart_fund_category_summary.csv'
  )

  AND NOT EXISTS (
      SELECT 1
      FROM recovery.artifact_executions ae
      WHERE ae.dataset_artifact_id = da.dataset_artifact_id
  );

COMMIT;