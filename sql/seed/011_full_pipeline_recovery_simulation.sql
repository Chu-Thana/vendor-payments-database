BEGIN;

DO $$
DECLARE
    v_run_id BIGINT;
    v_stage_execution_id BIGINT;
BEGIN

    -- ========================================================
    -- Create pipeline run
    -- ========================================================

    INSERT INTO recovery.pipeline_runs (
        run_key,
        mode,
        status
    )
    VALUES (
        'batch_20260926_003',
        'FULL',
        'CREATED'
    )
    RETURNING pipeline_run_id
    INTO v_run_id;


    -- ========================================================
    -- 1. TRANSFORM_SILVER
    -- ========================================================

    SELECT recovery.start_stage_attempt(
        v_run_id,
        'TRANSFORM_SILVER'
    )
    INTO v_stage_execution_id;

    PERFORM recovery.finish_stage_attempt(
        v_stage_execution_id,
        TRUE,
        NULL
    );


    -- ========================================================
    -- 2. CHECK_SILVER
    -- ========================================================

    SELECT recovery.start_stage_attempt(
        v_run_id,
        'CHECK_SILVER'
    )
    INTO v_stage_execution_id;

    PERFORM recovery.finish_stage_attempt(
        v_stage_execution_id,
        TRUE,
        NULL
    );


    -- ========================================================
    -- 3. BUILD_GOLD - attempt 1 fails
    -- ========================================================

    SELECT recovery.start_stage_attempt(
        v_run_id,
        'BUILD_GOLD'
    )
    INTO v_stage_execution_id;

    PERFORM recovery.finish_stage_attempt(
        v_stage_execution_id,
        FALSE,
        'Simulated BUILD_GOLD failure.'
    );


    -- ========================================================
    -- BUILD_GOLD - attempt 2 succeeds
    -- ========================================================

    SELECT recovery.start_stage_attempt(
        v_run_id,
        'BUILD_GOLD'
    )
    INTO v_stage_execution_id;

    PERFORM recovery.finish_stage_attempt(
        v_stage_execution_id,
        TRUE,
        NULL
    );


    -- ========================================================
    -- 4. CHECK_GOLD
    -- ========================================================

    SELECT recovery.start_stage_attempt(
        v_run_id,
        'CHECK_GOLD'
    )
    INTO v_stage_execution_id;

    PERFORM recovery.finish_stage_attempt(
        v_stage_execution_id,
        TRUE,
        NULL
    );


    -- ========================================================
    -- 5. UPLOAD_S3
    -- ========================================================

    SELECT recovery.start_stage_attempt(
        v_run_id,
        'UPLOAD_S3'
    )
    INTO v_stage_execution_id;

    PERFORM recovery.finish_stage_attempt(
        v_stage_execution_id,
        TRUE,
        NULL
    );


    -- ========================================================
    -- 6. LOAD_REDSHIFT
    -- ========================================================

    SELECT recovery.start_stage_attempt(
        v_run_id,
        'LOAD_REDSHIFT'
    )
    INTO v_stage_execution_id;

    PERFORM recovery.finish_stage_attempt(
        v_stage_execution_id,
        TRUE,
        NULL
    );


    -- ========================================================
    -- 7. CROSS_LAYER_VALIDATION
    -- ========================================================

    SELECT recovery.start_stage_attempt(
        v_run_id,
        'CROSS_LAYER_VALIDATION'
    )
    INTO v_stage_execution_id;

    PERFORM recovery.finish_stage_attempt(
        v_stage_execution_id,
        TRUE,
        NULL
    );

END
$$;

COMMIT;