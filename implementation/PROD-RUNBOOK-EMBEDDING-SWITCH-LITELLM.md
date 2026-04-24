# Production Runbook: Fix LiteLLM Embedding Switch

This runbook is for the exact failure pattern:
- UI fails to switch embedding model (422, missing `model_dim`, `api_url: null`)
- Indexing is unstable due to Vespa backpressure (`429 Too Many Requests`)

Use this sequence in production to switch embeddings safely.

---

## 0) Preconditions

- You have admin access to Onyx API.
- You can run `kubectl`/`oc` in the Onyx namespace.
- You know:
  - Onyx URL (`ONYX_URL`)
  - Onyx admin token (`ONYX_ADMIN_TOKEN`)
  - LiteLLM embeddings endpoint (`LITELLM_EMBED_URL`, example: `http://litellm:4000/v1/embeddings`)
  - LiteLLM API key (`LITELLM_API_KEY`)
  - Target embedding model (`TARGET_MODEL`)

Recommended exports:

```bash
export NS="onyx-infra"
export ONYX_URL="https://your-onyx-url"
export ONYX_ADMIN_TOKEN="change-me"
export LITELLM_EMBED_URL="http://litellm:4000/v1/embeddings"
export LITELLM_API_KEY="change-me"
export TARGET_MODEL="Qwen/Qwen3-VL-Embedding-8B"
```

---

## 1) Baseline snapshot (rollback checkpoint)

```bash
curl -sS -H "Authorization: Bearer $ONYX_ADMIN_TOKEN" \
  "$ONYX_URL/api/search-settings/get-all-search-settings" | jq .
```

Save this output before any change.

---

## 2) Validate LiteLLM embedding endpoint and fetch dimension

```bash
curl -sS -X POST "$LITELLM_EMBED_URL" \
  -H "Authorization: Bearer $LITELLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"$TARGET_MODEL\",\"input\":[\"healthcheck embedding\"]}" | jq .
```

Get dimension:

```bash
export MODEL_DIM="$(curl -sS -X POST "$LITELLM_EMBED_URL" \
  -H "Authorization: Bearer $LITELLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"$TARGET_MODEL\",\"input\":[\"healthcheck embedding\"]}" \
  | jq '.data[0].embedding | length')"

echo "MODEL_DIM=$MODEL_DIM"
```

If this fails, stop here and fix LiteLLM/provider routing first.

---

## 3) Reduce indexing pressure before switch (avoid Vespa 429 storm)

Update config values (ConfigMap used by your deployment):
- `CELERY_WORKER_DOCPROCESSING_CONCURRENCY=1`
- `NUM_INDEXING_WORKERS=1`
- `INDEX_BATCH_SIZE=8`
- `INDEXING_EMBEDDING_MODEL_NUM_THREADS=2`
- `CELERY_WORKER_LIGHT_PREFETCH_MULTIPLIER=1`
- `ENABLE_MULTIPASS_INDEXING=false`
- `ENABLE_CONTEXTUAL_RAG=false`
- `ENABLE_OPENSEARCH_INDEXING_FOR_ONYX=false` (during heavy reindex window)

Then restart workloads:

```bash
kubectl -n "$NS" rollout restart deployment onyx-api-server
kubectl -n "$NS" rollout restart deployment celery-worker-docprocessing
```

Wait for healthy pods before proceeding.

---

## 4) Apply embedding switch via API (skip buggy UI path)

```bash
curl -sS -X POST "$ONYX_URL/api/search-settings/set-new-search-settings" \
  -H "Authorization: Bearer $ONYX_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"model_name\": \"$TARGET_MODEL\",
    \"model_dim\": $MODEL_DIM,
    \"normalize\": true,
    \"query_prefix\": \"\",
    \"passage_prefix\": \"\",
    \"provider_type\": \"litellm\",
    \"api_key\": \"$LITELLM_API_KEY\",
    \"api_url\": \"$LITELLM_EMBED_URL\",
    \"multipass_indexing\": false,
    \"enable_contextual_rag\": false,
    \"embedding_precision\": \"float\",
    \"reduced_dimension\": null,
    \"switchover_type\": \"reindex\"
  }" | jq .
```

Success returns an object with a new `id`.

---

## 5) Monitor progress and failure signals

Check secondary/current model state:

```bash
watch -n 5 "curl -sS -H 'Authorization: Bearer $ONYX_ADMIN_TOKEN' \
  '$ONYX_URL/api/search-settings/get-all-search-settings' | jq '.current_settings.model_name, .secondary_settings.model_name'"
```

Docprocessing logs:

```bash
kubectl -n "$NS" logs deploy/celery-worker-docprocessing --tail=200 -f
```

Watch for:
- `401/403` -> bad LiteLLM key or auth policy
- `404` -> wrong `api_url` (must be embeddings endpoint)
- `429` -> Vespa still overloaded (reduce concurrency further, pause heavy connector runs)

---

## 6) Post-switch validation

After reindex/swap completes:

```bash
curl -sS -H "Authorization: Bearer $ONYX_ADMIN_TOKEN" \
  "$ONYX_URL/api/search-settings/get-all-search-settings" | jq .
```

Confirm:
- `current_settings.model_name == $TARGET_MODEL`
- `secondary_settings == null` (or absent after completion)

Run a known-answer query in UI/API to validate retrieval quality.

---

## 7) Rollback (if quality or stability regresses)

Option A: Reapply previous embedding settings from snapshot via same endpoint.

Option B: set switchover to `instant` only in emergency to recover service quickly, then reindex in a maintenance window.

---

## 8) Permanent fix (engineering follow-up)

Patch and redeploy frontend/backend pair so UI always sends:
- `model_dim`
- non-null `api_url` for LiteLLM

Known problematic area in this repo:
- `new_onyx/web/src/app/admin/embeddings/pages/EmbeddingFormPage.tsx`

Until patched in deployed version, keep using API-based switch for production changes.
