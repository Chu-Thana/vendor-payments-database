SELECT
    dv.version_key,
    da.artifact_name,

    da.status AS artifact_status,

    laa.attempt_number AS latest_attempt_number,
    laa.status AS latest_attempt_status,

    CASE
        WHEN da.status IN ('VALIDATED', 'PUBLISHED')
             AND (
                 laa.status IS NULL
                 OR laa.status <> 'SUCCEEDED'
             )
        THEN 'INVALID'

        WHEN da.status = 'COMPLETED'
             AND (
                 laa.status IS NULL
                 OR laa.status <> 'SUCCEEDED'
             )
        THEN 'INVALID'

        WHEN da.status = 'FAILED'
             AND laa.status = 'SUCCEEDED'
        THEN 'INVALID'

        ELSE 'VALID'
    END AS consistency_status

FROM recovery.dataset_artifacts da

JOIN recovery.dataset_versions dv
    ON dv.dataset_version_id = da.dataset_version_id

LEFT JOIN recovery.latest_artifact_attempts laa
    ON laa.dataset_artifact_id = da.dataset_artifact_id

WHERE dv.version_key = 'gold_batch_20260925_001'

ORDER BY da.artifact_name;