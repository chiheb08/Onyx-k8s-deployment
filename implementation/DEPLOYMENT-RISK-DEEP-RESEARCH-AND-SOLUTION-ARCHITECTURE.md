# Deep Research: Onyx Deployment Risks, Root Causes, and Solution Architecture

This document is a deep operational investigation for your environment, focused on why behavior becomes inconsistent under load and how to design a resilient architecture.

Scope of symptoms observed:

- intermittent 504 and backend unreachable behavior
- file upload/indexing delays and missing retrieval after "indexed"
- occasional UI freeze/no answer until refresh
- Vespa instability and inconsistent search outcomes

---

## 1) Executive diagnosis

Your issues are most likely **multi-causal** and emerge when several weak points combine:

1. **Version drift and component mismatch** (older nightly images mixed with other versions)
2. **Async pipeline pressure** (queue lag, worker saturation, retries)
3. **Storage and index bottlenecks** (Vespa + underlying storage jitter)
4. **Timeout mismatch across tiers** (browser/ingress/api/model/db)
5. **Insufficient observability and SLOs** (hard to detect and contain regressions quickly)

In production systems, this combination creates the pattern you reported: "sometimes works, sometimes fails".

---

## 2) Deep risk map (what can fail and why)

## 2.1 Ingress/API timeout chain risk

**Failure mode**
- User gets 504 while backend continues processing or is blocked on upstream dependencies.

**Typical triggers**
- NGINX upstream timeout lower than API/model latency tail.
- API worker threads blocked on model inference or DB/Redis contention.
- Burst of long-running requests after connector sync window.

**Mitigation architecture**
- Standardize timeout budget by tier:
  - client -> ingress -> api -> model/db
- Set explicit per-endpoint timeout classes (chat streaming vs upload vs indexing callbacks).
- Add circuit breaker/retry with jitter only where idempotent.

---

## 2.2 Async indexing pipeline race/backlog risk

**Failure mode**
- File marked uploaded/indexed in one subsystem but not fully queryable in retrieval path.

**Typical triggers**
- Queue lag in docfetching/docprocessing.
- Partial failure after metadata commit but before Vespa feed success.
- Retry storms causing out-of-order updates.

**Mitigation architecture**
- Introduce explicit indexing state machine with checkpoints:
  - `UPLOADED -> PARSED -> CHUNKED -> EMBEDDED -> VESPA_COMMITTED -> SEARCHABLE`
- Emit event ID / document ID through each stage.
- Add dead-letter queue for repeated failures.
- Make progress visibility part of admin diagnostics.

---

## 2.3 Vespa + storage latency risk

**Failure mode**
- Search quality and indexing throughput become non-deterministic under load.

**Why this happens**
- Vespa feed/query can become sensitive to storage latency and memory pressure.
- Network-attached storage jitter can amplify feed latency and merge/fusion behavior.

**Evidence base**
- Vespa feeding guidance emphasizes storage throughput/latency impact on feed performance: [Vespa Feed Sizing Guide](https://docs.vespa.ai/en/performance/sizing-feeding.html)
- Vespa operations docs describe disruption/recovery constraints in Kubernetes: [Lifecycle Operations for Vespa on Kubernetes](https://docs.vespa.ai/en/operations/kubernetes/operations.html)

**Mitigation architecture**
- Prefer low-latency persistent storage class for Vespa data path.
- Constrain indexing concurrency to protect query path.
- Separate indexing windows from peak chat windows where possible.
- Add Vespa SLOs (query p95, feed p95, restart count, memory headroom).

---

## 2.4 Model-serving latency tail risk

**Failure mode**
- "LLM freezes" or delayed/no response that appears as UI bug.

**Typical triggers**
- Inference model server saturation (CPU/RAM or provider latency).
- Shared model pool for indexing and query path.
- Long context windows and high token settings during load spikes.

**Mitigation architecture**
- Keep separate inference and indexing model servers (already in your new manifests).
- Add request budget and concurrency limits per model endpoint.
- Enable adaptive load-shedding for non-critical requests.

---

## 2.5 Redis/Postgres contention risk

**Failure mode**
- Backend appears intermittently unreachable due to lock waits, pool starvation, or broker delays.

**Typical triggers**
- Undersized DB connection pools vs worker concurrency.
- Hot rows in task/connector states.
- Redis latency spikes causing queue and KV timeouts.

**Mitigation architecture**
- Per-service connection pool sizing tied to pod count.
- DB slow query tracking and lock wait alarms.
- Redis memory/latency SLO and eviction-policy review.

---

## 2.6 OpenSearch misconception risk

**Failure mode**
- Team expects OpenSearch enablement to "fix everything".

**Reality**
- OpenSearch can improve some text/search workflows but does **not** fix:
  - queue lag
  - model latency
  - ingress timeout mismatch
  - DB contention
  - storage jitter

**Operational note**
- OpenSearch adds JVM/node operational overhead; heap sizing still follows strict constraints: [OpenSearch heap guidance](https://opster.com/guides/opensearch/opensearch-basics/opensearch-heap-size-usage-and-jvm-garbage-collection/)

**Recommendation**
- Enable OpenSearch only after baseline stability is proven, then validate with A/B traffic.

---

## 3) Architecture blueprint to mitigate deployment risk

## 3.1 Target logical architecture

1. **Edge layer**
   - NGINX/Gateway with explicit timeout policies by route class.
2. **API layer**
   - stateless API pods, HPA on CPU + latency/requests.
3. **Async layer**
   - dedicated worker pools by queue type; bounded concurrency; DLQ.
4. **Data layer**
   - Postgres HA/managed option, Redis HA/sentinel or managed, Vespa on low-latency storage.
5. **Model layer**
   - split query and indexing model serving; isolate resource budgets.
6. **Observability layer**
   - Prometheus + dashboards + alerting + tracing with request/document correlation IDs.

## 3.2 Required platform controls

- PodDisruptionBudgets for API/web/workers.
- HorizontalPodAutoscaler for API/web/docprocessing.
- NetworkPolicies to reduce blast radius.
- ResourceQuota + LimitRange to avoid noisy-neighbor collapse.
- PriorityClass for critical control-plane workloads.

---

## 4) Concrete mitigations mapped to your current environment

## 4.1 Before next production rollout

- Unify Onyx image tags across api/web/workers/model servers.
- Confirm migration strategy (single-writer migration init, no parallel migration races).
- Add PV/PVC for Postgres and Vespa (mandatory for production durability).
- Keep OpenSearch indexing disabled initially (`ENABLE_OPENSEARCH_INDEXING_FOR_ONYX=false`).

## 4.2 During stabilization

- Run controlled load test with upload + retrieval + chat concurrently.
- Track one document across full pipeline with stage timestamps.
- Tune queue concurrency based on Vespa feed latency, not only CPU utilization.

## 4.3 After baseline is stable

- Canary OpenSearch for a subset of traffic/workspaces.
- Compare:
  - answer hit-rate
  - p95/p99 latency
  - timeout/error rates
  - worker backlog age
- Keep rollback toggle ready (feature flag + deployment rollback).

---

## 5) SLO and alerting model (minimum)

## 5.1 User-facing SLOs

- chat request success rate >= 99.5%
- upload-to-searchable p95 <= target SLA (define by doc size class)
- UI/API 504 rate <= 0.5% (15m rolling)

## 5.2 Platform SLOs

- API p95 latency budget by endpoint class
- queue age max threshold by queue (`docprocessing`, `docfetching`, `celery`)
- Vespa query/feed p95 budgets
- model-server timeout/error budgets

## 5.3 Alert design

- page only on user impact + sustained breach
- ticket on early saturation indicators (queue age growth, lock waits, rising retries)

---

## 6) Failure recovery playbooks (what to do during incident)

## Playbook A: 504 spike

1. Check ingress upstream timeout vs API p95.
2. Check API saturation and model-server latency.
3. Check queue age and worker health.
4. Reduce non-critical background concurrency temporarily.
5. Scale API/model workers if bottleneck confirmed.

## Playbook B: Indexed but not retrievable

1. Select sample doc ID.
2. Verify each pipeline stage checkpoint.
3. Confirm Vespa feed commit and query visibility.
4. Reconcile/reindex only affected documents (not full blast reindex first).

## Playbook C: Vespa instability

1. Check storage latency and pod restarts.
2. Reduce indexing concurrency to protect query path.
3. Validate memory headroom and GC pressure.
4. If repeated instability, isolate feed windows and throttle connector syncs.

---

## 7) Decision: should you redeploy with OpenSearch now?

**Recommendation: not as first move.**

Deploying OpenSearch now without fixing pipeline health and timeout budgets is likely to add complexity without resolving core instability.

Use this order instead:

1. stabilize versioning + timeouts + queue health + storage
2. prove baseline with load test and SLOs
3. then test OpenSearch as a controlled, reversible enhancement

---

## 8) 30/60/90 day architecture roadmap

## 0-30 days

- Baseline stabilization and visibility
- Version unification
- SLO + alerting implementation

## 31-60 days

- HPA/PDB/NetworkPolicy hardening
- Queue/DLQ and retry policy cleanup
- chaos-style failover drills (DB/Redis/Vespa dependency degradation)

## 61-90 days

- OpenSearch canary and decision
- cost/performance tuning
- capacity planning model for connector growth and document volume

---

## 9) References used

- Onyx repository and releases: [onyx-dot-app/onyx](https://github.com/onyx-dot-app/onyx)
- Onyx issue (lite mode dependency behavior): [Issue #9588](https://github.com/onyx-dot-app/onyx/issues/9588)
- Onyx PR (lite mode fix in progress): [PR #9744](https://github.com/onyx-dot-app/onyx/pull/9744)
- Vespa feed sizing/performance: [Vespa Feed Sizing Guide](https://docs.vespa.ai/en/performance/sizing-feeding.html)
- Vespa Kubernetes operations: [Lifecycle Operations for Vespa on Kubernetes](https://docs.vespa.ai/en/operations/kubernetes/operations.html)
- OpenSearch heap/GC operational guidance: [OpenSearch heap sizing](https://opster.com/guides/opensearch/opensearch-basics/opensearch-heap-size-usage-and-jvm-garbage-collection/)
- Gateway timeout standardization: [Kubernetes Gateway API HTTP timeouts](https://gateway-api.sigs.k8s.io/guides/http-timeouts/)

