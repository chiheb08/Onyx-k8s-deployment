-- Bootstrap vLLM as default LLM provider (run AFTER first admin user exists).
-- Adjust api_base and model name for your vLLM deployment.
--
-- oc exec -it statefulset/onyx-postgres -n onyx -- \
--   psql -U postgres -d postgres -f - < docs/vllm-provider-bootstrap.sql

-- Example: single vLLM provider with Llama model
-- Provider type MUST be openai_compatible for vLLM OpenAI API

INSERT INTO llm_provider (
    name,
    provider,
    api_key,
    api_base,
    default_model_name,
    is_public,
    deployment_name
)
VALUES (
    'vLLM',
    'openai_compatible',
    'not-needed',
    'http://vllm-service.vllm.svc.cluster.local:8000/v1',
    'meta-llama/Llama-3.1-8B-Instruct',
    true,
    NULL
)
ON CONFLICT DO NOTHING;

-- Set as default flow (adjust IDs after inspecting tables):
-- SELECT id, name FROM llm_provider;
-- UPDATE llm_model_flow SET is_default = false;
-- UPDATE llm_model_flow SET is_default = true WHERE model_configuration_id = <id>;
