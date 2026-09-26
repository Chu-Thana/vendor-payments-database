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
    SELECT dataset_version_id, version_key
    FROM recovery.dataset_versions
    WHERE version_key = 'gold_batch_20260925_001'
),

artifact_state AS (
    SELECT
        e.artifact_name,
        da.status,
        da.row_count
    FROM expected_artifacts e
    CROSS JOIN target_dataset td
    LEFT JOIN recovery.dataset_artifacts da
        ON da.dataset_version_id = td.dataset_version_id
       AND da.artifact_name = e.artifact_name
)

SELECT
    COUNT(*) AS expected_artifact_count,

    COUNT(*) FILTER (
        WHERE status IN (
            'COMPLETED',
            'VALIDATED',
            'PUBLISHED'
        )
    ) AS completed_artifact_count,

    COUNT(*) FILTER (
        WHERE status = 'FAILED'
    ) AS failed_artifact_count,

    COUNT(*) FILTER (
        WHERE status IS NULL
    ) AS missing_artifact_count,

    CASE
        WHEN COUNT(*) FILTER (
            WHERE status IN (
                'COMPLETED',
                'VALIDATED',
                'PUBLISHED'
            )
        ) = COUNT(*)
        THEN 'PASS'
        ELSE 'FAIL'
    END AS validation_status

FROM artifact_state;