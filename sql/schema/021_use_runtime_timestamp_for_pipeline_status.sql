BEGIN;

CREATE OR REPLACE FUNCTION recovery.refresh_pipeline_status(
    p_pipeline_run_id BIGINT
)
RETURNS TEXT
LANGUAGE plpgsql
AS $function$
DECLARE
    v_failed_count INTEGER;
    v_incomplete_count INTEGER;
    v_new_status TEXT;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM recovery.pipeline_runs
        WHERE pipeline_run_id = p_pipeline_run_id
    ) THEN
        RAISE EXCEPTION
            'Pipeline run % does not exist.',
            p_pipeline_run_id;
    END IF;


    SELECT COUNT(*)
    INTO v_failed_count
    FROM recovery.pipeline_stages ps
    LEFT JOIN recovery.latest_stage_attempts lsa
        ON lsa.pipeline_run_id = p_pipeline_run_id
       AND lsa.stage_name = ps.stage_name
    WHERE ps.is_active = TRUE
      AND lsa.status = 'FAILED';


    SELECT COUNT(*)
    INTO v_incomplete_count
    FROM recovery.pipeline_stages ps
    LEFT JOIN recovery.latest_stage_attempts lsa
        ON lsa.pipeline_run_id = p_pipeline_run_id
       AND lsa.stage_name = ps.stage_name
    WHERE ps.is_active = TRUE
      AND (
          lsa.status IS NULL
          OR lsa.status NOT IN (
              'SUCCEEDED',
              'SKIPPED'
          )
      );


    IF v_failed_count > 0 THEN
        v_new_status := 'FAILED';

    ELSIF v_incomplete_count = 0 THEN
        v_new_status := 'SUCCEEDED';

    ELSE
        v_new_status := 'RUNNING';
    END IF;


    UPDATE recovery.pipeline_runs
    SET
        status = v_new_status,
        finished_at = CASE
            WHEN v_new_status IN ('SUCCEEDED', 'FAILED')
            THEN clock_timestamp()
            ELSE NULL
        END
    WHERE pipeline_run_id = p_pipeline_run_id;


    RETURN v_new_status;
END;
$function$;

COMMIT;