# Onyx File Upload + Indexing in Production (Deep Research)

## Context

You asked whether file upload and indexing model features are production-ready, why behavior is slow/inconsistent in your current version, and which environment variables should be configured for reliable operation.

Your current pain points match known upstream patterns:

- upload/indexing can be delayed, inconsistent, or appear complete before retrieval is truly usable
- RAG retrieval can fail even when docs appear indexed
- reindex/model-change operations can produce timeouts/backlogs

---

## 1) Deep-research findings from upstream

## 1.1 Similar issues are reported by others

Relevant issue/PR patterns in upstream Onyx:

- Indexing not working / connectors stuck / not processing as expected: [Issue #6660](https://github.com/onyx-dot-app/onyx/issues/6660)
- RAG can fail despite uploaded/indexed documents: [Issue #8088](https://github.com/onyx-dot-app/onyx/issues/8088)
- Historical Vespa query/indexing failures and timeouts: [Issue #3267](https://github.com/onyx-dot-app/onyx/issues/3267)
- Bugfix around S3 write ordering before marking index state: [PR #8216](https://github.com/onyx-dot-app/onyx/pull/8216)
- Embedding settings/reindex behavior and related fixes: [Issue #2270](https://github.com/onyx-dot-app/onyx/issues/2270), [PR #4157](https://github.com/onyx-dot-app/onyx/pull/4157), [PR #4439](https://github.com/onyx-dot-app/onyx/pull/4439)

## 1.2 Architecture evidence from DeepWiki

DeepWiki’s indexed map of the Onyx repo shows:

- document indexing and retrieval are spread across Celery pipeline + Vespa/OpenSearch modules
- OpenSearch migration tasks exist (not just static backend toggle)
- retrieval depends on multiple systems being healthy, not only "index complete"

Reference: [DeepWiki Onyx Overview](https://deepwiki.com/onyx-dot-app/onyx)

---

## 2) Can file upload + indexing be handled in production?

Short answer: **Yes, but only with production controls.**

It is not "fire-and-forget" in real deployments. If you deploy defaults without queue sizing, storage tuning, and timeout budgets, you will get exactly what you described: slow uploads, stale/partial retrieval, intermittent 504, and "frozen" answers.

### Production viability conditions

You can operate reliably if you enforce all of the following:

1. **Version consistency** across web/api/workers/model servers
2. **Dedicated worker capacity** for docfetching/docprocessing/user-file-processing
3. **Stable object storage path** (S3 endpoint/certs/credentials, low error rate)
4. **Index backend health** (Vespa memory/storage/latency)
5. **Timeout budget alignment** from ingress -> API -> model/index dependencies
6. **Operational visibility** (queue age, task failure rate, indexing SLA, retrieval hit rate)

---

## 3) Why your current `2.12` likely struggles with embedding model changes

If embedding model swaps are unreliable in your deployment, likely causes:

- old version behavior around search-setting application / reindex state handling
- insufficient resources during index swap/reindex window
- timeout settings too low for long-running re-embedding and index migration operations
- queue saturation where migration/indexing tasks starve behind other workloads

Upstream has had multiple fixes around embedding settings and reindex state transitions ([Issue #2270](https://github.com/onyx-dot-app/onyx/issues/2270), [PR #4439](https://github.com/onyx-dot-app/onyx/pull/4439)).

---

## 4) Environment variables to configure (priority list)

The variables below are directly tied to upload/index/retrieval behavior in Onyx config code and Helm values.

## 4.1 Critical for upload path

1. `MAX_ALLOWED_UPLOAD_SIZE_MB`
   - hard ceiling for uploads
   - suggested starting point: `250` (or lower if proxy/object storage limits are lower)
2. `DEFAULT_USER_FILE_MAX_UPLOAD_SIZE_MB`
   - per-user default cap
   - suggested: `100`
3. `MAX_FILE_SIZE_BYTES`
   - ingestion parser cap
   - verify alignment with upload limits
4. `MAX_DOCUMENT_CHARS`
   - parser/indexing safety cap for giant docs

## 4.2 Critical for object storage correctness

1. `FILE_STORE_BACKEND=s3`
2. `S3_FILE_STORE_BUCKET_NAME`
3. `S3_ENDPOINT_URL` (leave blank for AWS S3 native endpoint mode, set explicitly for S3-compatible/internal storage)
4. `S3_AWS_ACCESS_KEY_ID`
5. `S3_AWS_SECRET_ACCESS_KEY`
6. `S3_VERIFY_SSL` (`true` in production with proper cert chain)
7. `S3_GENERATE_LOCAL_CHECKSUM` (set based on provider compatibility)

## 4.3 Critical for indexing throughput/stability

1. `CELERY_WORKER_DOCPROCESSING_CONCURRENCY`
   - default logic is 6; tune to avoid Vespa overload
2. `CELERY_WORKER_DOCFETCHING_CONCURRENCY`
   - default logic is 1; raise gradually based on source count
3. `CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY`
   - default logic is 2; increase for heavy user-upload workflows
4. `CELERY_WORKER_PRIMARY_CONCURRENCY`
5. `CELERY_WORKER_LIGHT_CONCURRENCY`
6. `CELERY_WORKER_HEAVY_CONCURRENCY`
7. `CELERY_WORKER_LIGHT_PREFETCH_MULTIPLIER`
8. `NUM_INDEXING_WORKERS`
   - legacy fallback for docprocessing concurrency

## 4.4 Critical for embedding/reindex behavior

1. `DISABLE_INDEX_UPDATE_ON_SWAP`
   - controls whether primary index updates pause during embedding model swap
2. `ENABLE_MULTIPASS_INDEXING`
   - improves retrieval quality at higher indexing cost
3. `INDEXING_EMBEDDING_MODEL_NUM_THREADS`
   - API embedding parallelism; tune carefully with provider limits
4. `INDEXING_MODEL_SERVER_HOST`
5. `MODEL_SERVER_HOST`

## 4.5 Critical for timeout and user-perceived freezes

1. `LLM_SOCKET_READ_TIMEOUT`
   - too low => premature failures; too high => long hanging requests
2. `QA_TIMEOUT`
3. NGINX/Gateway timeout settings (connect/send/read) aligned with backend behavior

## 4.6 Optional but relevant if OpenSearch enabled

1. `ENABLE_OPENSEARCH_INDEXING_FOR_ONYX`
2. `ENABLE_OPENSEARCH_RETRIEVAL_FOR_ONYX`
3. `DEFAULT_OPENSEARCH_CLIENT_TIMEOUT_S`
4. `DEFAULT_OPENSEARCH_QUERY_TIMEOUT_S`

---

## 5) Suggested starting values (safe baseline)

These are practical starting points, not universal truths:

```env
# Upload and parsing guards
MAX_ALLOWED_UPLOAD_SIZE_MB=250
DEFAULT_USER_FILE_MAX_UPLOAD_SIZE_MB=100
MAX_FILE_SIZE_BYTES=2147483648
MAX_DOCUMENT_CHARS=5000000

# Storage backend
FILE_STORE_BACKEND=s3
S3_FILE_STORE_BUCKET_NAME=onyx-file-store-bucket
S3_ENDPOINT_URL=https://your-s3-endpoint:443
S3_VERIFY_SSL=true
S3_GENERATE_LOCAL_CHECKSUM=false

# Queue/workers
CELERY_WORKER_DOCFETCHING_CONCURRENCY=1
CELERY_WORKER_DOCPROCESSING_CONCURRENCY=4
CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY=2
CELERY_WORKER_PRIMARY_CONCURRENCY=4
CELERY_WORKER_LIGHT_CONCURRENCY=12
CELERY_WORKER_HEAVY_CONCURRENCY=2
CELERY_WORKER_LIGHT_PREFETCH_MULTIPLIER=4

# Indexing behavior
DISABLE_INDEX_UPDATE_ON_SWAP=true
ENABLE_MULTIPASS_INDEXING=false
INDEXING_EMBEDDING_MODEL_NUM_THREADS=4

# Timeouts
LLM_SOCKET_READ_TIMEOUT=120
QA_TIMEOUT=120

# OpenSearch (optional)
ENABLE_OPENSEARCH_INDEXING_FOR_ONYX=false
ENABLE_OPENSEARCH_RETRIEVAL_FOR_ONYX=false
```

Then tune from metrics, not intuition.

---

## 6) What to do now in your environment

## Step A: version + runtime sanity

- Ensure every Onyx component runs the same release line (web/api/workers/model server)
- Confirm no mixed old nightly images are still active

## Step B: upload/index readiness checks

- synthetic upload test (small/medium/large files)
- track pipeline time:
  - upload accepted
  - queued
  - processed
  - searchable
- alert if queue age or indexing lag breaches SLA

## Step C: embedding model change runbook

- execute model swap in staging first
- monitor queue growth, Vespa latency, and error rate
- keep rollback path (previous model) ready

## Step D: retrieval validation

- for each upload test doc, run deterministic Q/A assertions
- verify that "indexed" status correlates with actual retrieval success, not only task completion

---

## 7) Final verdict

- **Can production handle upload/indexing?** Yes, with proper worker sizing, storage reliability, and timeout/queue controls.
- **Is your current behavior expected when under-configured or version-mismatched?** Yes.
- **Should you rely on defaults only?** No.
- **Can you change embedding model safely?** Yes, but it requires a controlled reindex/migration process and enough index/worker capacity.

---

## References

- Onyx issues list: [GitHub Issues](https://github.com/onyx-dot-app/onyx/issues)
- Onyx file/index issue examples: [#6660](https://github.com/onyx-dot-app/onyx/issues/6660), [#8088](https://github.com/onyx-dot-app/onyx/issues/8088), [#3267](https://github.com/onyx-dot-app/onyx/issues/3267)
- Upload/index consistency fix example: [PR #8216](https://github.com/onyx-dot-app/onyx/pull/8216)
- Embedding/reindex related history: [#2270](https://github.com/onyx-dot-app/onyx/issues/2270), [#4157](https://github.com/onyx-dot-app/onyx/pull/4157), [#4439](https://github.com/onyx-dot-app/onyx/pull/4439)
- Deep architecture index: [DeepWiki Onyx](https://deepwiki.com/onyx-dot-app/onyx)
- Helm chart values (service and env defaults): [Onyx Helm chart](https://github.com/onyx-dot-app/onyx/tree/main/deployment/helm/charts/onyx)

