BEGIN;

CREATE OR REPLACE FUNCTION recovery.finish_stage_attempt(
    p_stage_execution_id BIGINT,
    p_success BOOLEAN,
    p_error_message TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $function$
DECLARE
    v_pipeline_run_id BIGINT;
    v_execution_status TEXT;
BEGIN
    SELECT
        pipeline_run_id,
        status
    INTO
        v_pipeline_run_id,
        v_execution_status
    FROM recovery.stage_executions
    WHERE stage_execution_id = p_stage_execution_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Stage execution % does not exist.',
            p_stage_execution_id;
    END IF;

    IF v_execution_status <> 'RUNNING' THEN
        RAISE EXCEPTION
            'Stage execution % cannot be finished because its status is %.',
            p_stage_execution_id,
            v_execution_status;
    END IF;

    IF p_success THEN

        UPDATE recovery.stage_executions
        SET
            status = 'SUCCEEDED',
            finished_at = clock_timestamp(),
            error_message = NULL
        WHERE stage_execution_id = p_stage_execution_id;

    ELSE

        UPDATE recovery.stage_executions
        SET
            status = 'FAILED',
            finished_at = clock_timestamp(),
            error_message = COALESCE(
                p_error_message,
                'Pipeline stage failed.'
            )
        WHERE stage_execution_id = p_stage_execution_id;

    END IF;

    PERFORM recovery.refresh_pipeline_status(
        v_pipeline_run_id
    );
END;
$function$;

COMMIT;