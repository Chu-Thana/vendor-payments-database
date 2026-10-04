BEGIN;

INSERT INTO recovery.pipeline_stages (
    stage_name,
    stage_order,
    predecessor_stage_name,
    is_active
)
VALUES (
    'GROUPED_CROSS_LAYER_VALIDATION',
    12,
    'CROSS_LAYER_VALIDATION',
    TRUE
)
ON CONFLICT (stage_name)
DO UPDATE SET
    stage_order = EXCLUDED.stage_order,
    predecessor_stage_name = EXCLUDED.predecessor_stage_name,
    is_active = EXCLUDED.is_active;

COMMIT;