# Complete Technical Incident Summary (Redis, Celery, Timeouts)

## Context

This report summarizes the full chain of production-like issues we hit while running Onyx on Kubernetes/OpenShift.  
The visible user symptoms were:

- uploads failing intermittently
- files stuck in `DELETING` or `FAILED`
- chat responses streaming partially then stopping
- API startup failures tied to document index availability

These were not caused by a single bug. They were multiple interacting infra/runtime issues across Redis, Celery, OpenSearch, nginx/Route, and timeout configuration.

---

## 1) Redis / Queue Observability Problems

### Symptom
- Team expected delete queues to be empty, but delete flow was still stuck.
- `LLEN user_file_delete` often showed `0`, creating a false impression that no backlog existed.

### Technical reality
- Celery in this setup used Redis DB `15` for broker queues.
- Priority queue keys were used (for example `user_file_delete:1`), not only base queue names.
- The real backlog was in `user_file_delete:1` (hundreds of messages), while `user_file_delete` could be empty.

### Why this mattered
- We were checking the wrong queue key and briefly debugging the wrong hypothesis.
- Backlog depth directly affected delete latency and DB state cleanup.

### Remediation implemented
- Standardized queue inspection on Redis DB 15.
- Added helper script to list list-type queue lengths sorted descending:
  - `scripts/redis-list-queue-lengths.sh`
- Established runbook pattern: inspect all list keys, then drill into specific queues (`LLEN`, `LRANGE`).

---

## 2) Celery Queue Starvation and Worker Topology Issues

### Symptom
- `user_file_delete` tasks were delayed for long periods.
- `user_file` table accumulated rows stuck in `DELETING`.
- `celery-worker-user-file-processing` had heavy indexing logs, while other workers looked mostly idle.

### Technical reality
- One mixed worker consumed:
  - `user_file_processing`
  - `user_file_project_sync`
  - `user_file_delete`
- Indexing tasks are heavier and longer-lived than delete tasks.
- Under load, delete jobs were starved by indexing workloads (head-of-line blocking/resource contention).

### Why this mattered
- Delete pipeline completion requires async worker progress.
- Starvation causes state drift:
  - UI sees stale status
  - Postgres rows remain in `DELETING`
  - storage/index cleanup lags behind

### Remediation implemented
- Split delete traffic into a dedicated worker deployment:
  - `new_manifests_values_yaml/10-celery-worker-user-file-delete-dedicated.yaml`
- Removed `user_file_delete` from mixed user-file worker queue list:
  - `new_manifests_values_yaml/10-celery-workers-additional.yaml`
- Kept dedicated delete capacity with explicit concurrency/prefetch settings.

---

## 3) Celery Beat Reliability Problems

### Symptom
- Beat failed to run with permission error on schedule file.
- Periodic recovery/re-enqueue behavior was inconsistent.

### Technical reality
- Beat attempted to write `celerybeat-schedule` in a non-writable path.
- Error: permission denied (`_gdbm` schedule file write failure).

### Why this mattered
- Onyx relies on periodic tasks for background housekeeping/retry workflows.
- Without healthy beat, stuck states are less likely to self-heal.

### Remediation implemented
- Updated beat command to write schedule under `/tmp`:
  - `--schedule=/tmp/celerybeat-schedule`
- Applied in:
  - `new_manifests_values_yaml/09-celery-workers-core.yaml`
  - `manifests/10-celery-beat.yaml`

---

## 4) OpenSearch Availability and API Startup Failures

### Symptom
- API startup failed with:
  - `Could not connect to a document index within the specified timeout`
- OpenSearch sometimes refused connections or crash-looped.
- Upload/index tasks failed because document index setup could not complete.

### Technical reality
- OpenSearch readiness was not equivalent to "port open".
- At one point OpenSearch failed to boot due to invalid discovery value typo (`single-nod` vs `single-node`).
- API init only checked TCP (`nc -z`), so API could start race against an unhealthy index backend.

### Why this mattered
- API startup path verifies/sets up document index.
- If OpenSearch is not cluster-healthy, API and workers fail noisy and repeatedly.

### Remediation implemented
- Hardened API init container to wait for actual OpenSearch cluster health:
  - authenticated call to `/_cluster/health`
  - wait for `green|yellow`
- File updated:
  - `implementation/openshift/manifests/app/api.yaml`

---

## 5) Upload 404 Failures (nginx Path Rewrite)

### Symptom
- Upload request returned `404`.
- API log showed `POST /` instead of upload endpoint path.

### Technical reality
- Gateway routing/proxy path handling was wrong.
- `/api/...` was not being rewritten correctly before forwarding to FastAPI routes.

### Why this mattered
- Request hit backend root path, not actual upload API route.
- Looked like app failure, but root cause was reverse proxy URI handling.

### Remediation implemented
- Updated nginx gateway to official-style route matching and rewrite:
  - `location ~ ^/(api|openapi\.json)(/.*)?$`
  - rewrite strips `/api` prefix correctly
- Increased API gateway timeouts for long uploads.
- Updated in:
  - `new_manifests_values_yaml/10-nginx-gateway.yaml`

---

## 6) Upload "File too large or connection slow" Failures

### Symptom
- User-facing upload error indicating size limit or slow connection.

### Technical reality
- Effective limit is the minimum across multiple layers:
  - app env limits (`MAX_ALLOWED_UPLOAD_SIZE_MB`, etc.)
  - nginx `client_max_body_size`
  - OpenShift Route timeout
- Mismatched values caused early rejection/timeout despite backend capacity.

### Remediation implemented
- Aligned upload-related app limits in OpenShift config:
  - `implementation/openshift/manifests/configmap-env.yaml`
- Ensured nginx `client_max_body_size` was high enough.
- Added/increased Route timeout annotation:
  - `haproxy.router.openshift.io/timeout`
  - in `implementation/openshift/manifests/routes/onyx-route.yaml`

---

## 7) Chat Streaming Stops Mid-Answer (but full answer after refresh)

### Symptom
- Chat answer starts streaming, then stops abruptly.
- Refresh reveals full answer already persisted.

### Technical reality
- Backend processing could complete, but stream transport was interrupted.
- Proxy behavior around buffering/connection headers impacted SSE/stream stability.

### Why this mattered
- Users perceived crashes even when model completion succeeded.
- UX degraded and looked nondeterministic.

### Remediation implemented
- Stream-safe nginx settings for API route:
  - `proxy_buffering off`
  - `proxy_request_buffering off`
  - `proxy_cache off`
  - `gzip off`
  - `add_header X-Accel-Buffering no`
- Extended nginx API read/send timeouts.
- Increased OpenShift Route timeout to 30m.
- Updated in:
  - `implementation/openshift/manifests/configmap-nginx.yaml`
  - `implementation/openshift/manifests/routes/onyx-route.yaml`

---

## 8) LLM Upstream Read Timeouts (LiteLLM/OpenAI compatible)

### Symptom
- Stack traces with `httpx.ReadTimeout` and LiteLLM API connection timeout errors during generation.

### Technical reality
- Model provider response latency exceeded socket read timeout.
- Especially visible under larger prompts/chunks or provider-side load.

### Remediation implemented
- Raised:
  - `LLM_SOCKET_READ_TIMEOUT` from 180 to 300
- File updated:
  - `implementation/openshift/manifests/configmap-env.yaml`

---

## 9) Architectural Lesson Learned

The incident was a distributed-systems failure chain, not a single service outage:

1. Queue visibility gaps delayed diagnosis.
2. Mixed worker topology caused queue starvation.
3. Beat reliability reduced self-healing.
4. Index backend readiness races broke startup and processing.
5. Proxy rewrite/stream settings introduced false "app crash" signals.
6. Timeout budgets were inconsistent across app/proxy/route/provider layers.

Stability required fixing all layers together.

---

## 10) Final Stabilization Checklist

- Verify OpenSearch is cluster-healthy before API startup.
- Keep delete queue isolated from heavy indexing load.
- Monitor Redis DB 15 queue depths (including priority keys).
- Keep beat writable schedule path and healthy.
- Align upload/LLM timeouts across:
  - Onyx env
  - nginx
  - OpenShift Route
  - upstream model provider behavior
- Keep streaming path unbuffered through proxy chain.

---

## 11) Key Files Changed During Incident

- `new_manifests_values_yaml/10-celery-worker-user-file-delete-dedicated.yaml`
- `new_manifests_values_yaml/10-celery-workers-additional.yaml`
- `new_manifests_values_yaml/09-celery-workers-core.yaml`
- `manifests/10-celery-beat.yaml`
- `new_manifests_values_yaml/10-nginx-gateway.yaml`
- `implementation/openshift/manifests/app/api.yaml`
- `implementation/openshift/manifests/configmap-env.yaml`
- `implementation/openshift/manifests/configmap-nginx.yaml`
- `implementation/openshift/manifests/routes/onyx-route.yaml`
- `scripts/redis-list-queue-lengths.sh`

