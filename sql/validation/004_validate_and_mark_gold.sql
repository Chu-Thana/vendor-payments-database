BEGIN;

WITH expected_artifacts AS (
    SELECT *
    FROM (
        VALUES
            ('mart_spending_by_fiscal_year.csv'),
            ('mart_spending_by_department.csv'),
            ('mart_spending_by_supplier_top_n.csv'),
            ('mart_pending_by_department.csv'),
            ('mart_fund_category_summary.csv')
    ) AS expected(artifact_name)
),

target_dataset AS (
    SELECT
        dataset_version_id
    FROM recovery.dataset_versions
    WHERE version_key = 'gold_batch_20260925_001'
      AND layer = 'GOLD'
),

validation_summary AS (
    SELECT
        td.dataset_version_id,

        COUNT(*) AS expected_count,

        COUNT(*) FILTER (
            WHERE da.status IN (
                'COMPLETED',
                'VALIDATED',
                'PUBLISHED'
            )
        ) AS completed_count,

        COUNT(*) FILTER (
            WHERE da.status = 'FAILED'
        ) AS failed_count,

        COUNT(*) FILTER (
            WHERE da.dataset_artifact_id IS NULL
        ) AS missing_count

    FROM target_dataset td
    CROSS JOIN expected_artifacts ea

    LEFT JOIN recovery.dataset_artifacts da
        ON da.dataset_version_id = td.dataset_version_id
       AND da.artifact_name = ea.artifact_name

    GROUP BY td.dataset_version_id
),

validated_dataset AS (
    UPDATE recovery.dataset_versions dv
    SET
        status = 'VALIDATED',
        validated_at = NOW()

    FROM validation_summary vs

    WHERE dv.dataset_version_id = vs.dataset_version_id
      AND vs.expected_count = 5
      AND vs.completed_count = 5
      AND vs.failed_count = 0
      AND vs.missing_count = 0

    RETURNING dv.dataset_version_id
)

UPDATE recovery.dataset_artifacts da
SET status = 'VALIDATED'
FROM validated_dataset vd
WHERE da.dataset_version_id = vd.dataset_version_id
  AND da.status = 'COMPLETED';

COMMIT;