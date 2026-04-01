# Onyx 2.9.3 Stability Recovery and Upgrade Plan

This document is a practical production recovery guide for your current Onyx deployment issues:

- file upload/indexing is inconsistent
- indexed files are not reliably retrieved by LLM answers
- answer generation sometimes freezes in UI
- intermittent backend unreachable / frequent 504s
- Vespa instability and query/index behavior issues

---

## 0) Executive recommendation

1. **Stabilize first, upgrade second**.
2. **Treat this as a systems issue**, not one single bug:
   - request timeouts
   - background queue lag
   - Vespa indexing/search pressure
   - model server latency spikes
   - reverse proxy limits
3. **Upgrade to latest stable line in controlled phases** (not direct in-place swap on production during incident).

Latest upstream release is visible here: [Onyx releases](https://github.com/onyx-dot-app/onyx).

---

## 1) Critical finding in current manifests

Your current Kubernetes manifests are pinned to old nightly images (`nightly-20241004`) for backend/web/model-server, while Vespa is pinned to `8.526.15`.

This can create behavior drift versus what your team thinks is running as "2.9.3", especially when:

- frontend and backend are not from the same release line
- workers and API are on mismatched schema/feature expectations
- Vespa schema or runtime behavior lags current Onyx assumptions

**Immediate action:** confirm real runtime versions from pods (not docs/UI labels only).

---

## 2) Fast stabilization actions (same day)

## 2.1 Stop random 504s first

504s are usually queueing/latency symptoms, not root cause.

- Increase NGINX upstream timeouts (`proxy_connect_timeout`, `proxy_send_timeout`, `proxy_read_timeout`) for long-running chat/index endpoints.
- Ensure API readiness/liveness probes are not too strict under load (avoid restart loops).
- Confirm API replicas >1 to reduce single-pod saturation.
- Ensure worker queues are not starved (docprocessing/docfetching/primary all healthy).

## 2.2 Protect backend from overload

- Put resource requests/limits on API and workers that reflect real load.
- Limit concurrency where needed to avoid DB/Vespa thundering herd.
- If model server is slow, requests pile up and look like "backend unreachable".

## 2.3 Reduce user-facing freeze behavior

- Check frontend->API timeout behavior and retry logic.
- Check websocket/SSE path stability through ingress/proxy.
- Verify browser-side request failures correspond to backend logs (correlation by request ID/time window).

---

## 3) File upload + indexing inconsistency playbook

Symptoms usually come from one of these failure modes:

1. **Upload stored but ingestion task delayed/failed** (queue lag, worker crash, retry storm)
2. **Metadata in Postgres but chunks missing in Vespa** (partial indexing)
3. **Index complete but retrieval quality poor** (embedding/model mismatch, filter mismatch)
4. **Retrieval works but generation times out** (LLM/model-server latency)

### Required checks

- Verify task pipeline end-to-end per document:
  - upload accepted -> task enqueued -> chunking complete -> embeddings complete -> Vespa upsert complete -> searchable
- Track one sample doc with timestamps across logs.
- Confirm no silent failures in docfetching/docprocessing queues.
- Validate Vespa document count for uploaded source against expected chunk count.

---

## 4) Vespa-specific stability controls

For Vespa instability, apply operational guardrails:

- Ensure persistent volume latency is acceptable (NFS jitter causes unpredictable indexing/query behavior).
- Tune worker indexing concurrency to avoid overdriving Vespa.
- Monitor:
  - feed latency
  - query latency p95/p99
  - memory pressure
  - restart count
- Keep Vespa and Onyx versions aligned to tested combinations where possible.

If Vespa is IO-bound or under memory pressure, retrieval becomes non-deterministic under load ("sometimes finds, sometimes misses").

---

## 5) Observability baseline (mandatory before upgrade)

Add a minimum incident dashboard with:

- API p50/p95/p99 latency and 5xx/504 rate
- worker queue depth and task age
- worker success/failure/retry counts by task type
- model-server latency and timeout count
- Vespa query/feed latency and error rate
- Postgres connections, slow queries, lock wait

Without this, upgrades are blind and regressions are hard to prove.

---

## 6) Upgrade strategy (recommended)

## Phase A - staging parity

Create a staging environment that mirrors production:

- same storage class behavior
- same ingress/proxy timeouts
- same connector load profile
- same auth + model providers

## Phase B - version alignment

- Move all Onyx services (web/api/workers/model server) to one consistent release line.
- Avoid mixed nightly + old pinned versions.
- Run DB migrations once in controlled rollout.

## Phase C - workload validation

Run these acceptance tests before prod:

1. Upload 50-100 mixed documents
2. Verify indexing completion SLA
3. Ask deterministic questions with known answers from uploaded docs
4. Run concurrent users (e.g., 20-50) to test timeout behavior
5. Validate no 504 spike under moderate sustained load

## Phase D - production canary

- Shift 5-10% traffic first
- Monitor error budget and latency
- Roll forward only if stable for a full business cycle

---

## 7) Concrete remediation list for your cluster

1. **Version truth check**
   - Confirm actual image tags running in pods (api/web/workers/model-server/vespa).
2. **Unify version set**
   - Eliminate mixed old nightly tags across components.
3. **Timeout tuning**
   - Increase proxy/API/model timeouts for long operations.
4. **Queue health**
   - Ensure docfetching/docprocessing are running with balanced concurrency.
5. **Vespa health**
   - Validate storage latency and resource sizing; reduce indexing burst if needed.
6. **End-to-end trace test**
   - Pick 3 failing documents and trace upload -> index -> retrieve -> generate.
7. **Release upgrade**
   - Move to latest tested release line after staging pass.

---

## 8) Why this will fix the observed behavior

Your symptoms are classic distributed bottleneck signals:

- **504 + freeze** => upstream latency/queue saturation/proxy timeout mismatch
- **indexed but not found** => partial indexing or retrieval/index mismatch
- **random backend unreachable** => overload/restarts/dependency lag (DB, model server, Vespa)

A stable system requires aligned versions, bounded queue pressure, visible latency metrics, and controlled rollout.

---

## 9) Suggested immediate next 48h execution plan

Day 1:

- collect version truth + baseline metrics
- tune timeouts and resource limits
- validate worker queue health

Day 2:

- run controlled indexing/retrieval load test
- identify top bottleneck (API, model server, Vespa, DB)
- finalize upgrade target + canary plan

---

## 10) Optional follow-up document

If needed, create a second doc with exact Kubernetes patch snippets (timeouts, probes, resource requests, HPA, queue concurrency) customized to your current manifests.

