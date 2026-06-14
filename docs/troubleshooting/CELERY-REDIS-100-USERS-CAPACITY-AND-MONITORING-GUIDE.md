# Celery + Redis 100 Users Capacity and Monitoring Guide

## 1) Goal and Scope

This guide gives a practical starting architecture for Onyx background processing at around **100 active users** with mixed chat, upload, indexing, and delete traffic.

It covers:

- recommended Celery worker replicas/concurrency/resources
- Redis topology (how many instances, why)
- queue strategy and sizing math
- monitoring/alerting with concrete thresholds
- a rollout/tuning plan to optimize safely

This is a **baseline**, not a fixed truth. You should tune with real queue age, p95 runtime, and failure metrics.

---

## 2) Workload Assumptions (for the numbers below)

- 100 active users, business hours traffic bursts
- ~5-15 file uploads/minute during peaks
- mixed file sizes (small text + medium/large PDFs)
- chat usage ongoing during indexing/deletes
- vector indexing enabled (OpenSearch/Vespa path active)
- Redis used as Celery broker (DB 15 queues, DB 16 results/metadata)

If your upload rate or document size is much larger, scale docprocessing and delete pools earlier.

---

## 3) Recommended Celery Worker Baseline (100 users)

## 3.1 Worker topology

- Keep queues isolated by task class (do not merge all into one worker).
- Keep dedicated delete capacity to avoid starvation.
- Keep beat single instance.

| Worker | Queues (example) | Replicas | Concurrency | CPU req/limit | Memory req/limit | Notes |
|---|---|---:|---:|---|---|---|
| `celery-beat` | scheduler | 1 | n/a | 300m / 1000m | 512Mi / 1Gi | single instance |
| `worker-primary` | `celery,periodic_tasks` | 2 | 4 | 500m / 2000m | 1Gi / 4Gi | orchestration tasks |
| `worker-light` | metadata/sync cleanup | 2 | 8 | 750m / 2000m | 1536Mi / 4Gi | short I/O tasks |
| `worker-heavy` | long heavy ops | 1 | 2 | 1000m / 2000m | 2Gi / 4Gi | long tasks, low concurrency |
| `worker-docprocessing` | `docprocessing` | 4 | 6 | 1500m / 3000m | 4Gi / 10Gi | indexing bottleneck pool |
| `worker-docfetching` | connector fetch | 2 | 2 | 500m / 2000m | 2Gi / 6Gi | external fetch |
| `worker-user-file-processing` | `user_file_processing,user_file_project_sync` | 3 | 4 | 750m / 2000m | 2Gi / 4Gi | upload pipeline |
| `worker-user-file-delete` | `user_file_delete` | 2 | 4 | 500m / 2000m | 1Gi / 4Gi | dedicated delete queue |
| `worker-monitoring` | monitoring | 1 | 2 | 250m / 1000m | 512Mi / 2Gi | metrics/report jobs |

## 3.2 Total worker reservation (approx)

- CPU requests: ~**15.6 cores**
- Memory requests: ~**43.5 GiB**

Plan cluster allocatable with headroom:

- target worker headroom: +25% to +35%
- recommended worker capacity budget: **~20 cores / ~58 GiB**

This is only Celery layer, not including API, web/nginx, Postgres, Redis, OpenSearch, model servers.

---

## 4) Why many medium workers over one very large worker

Even with same total CPU/memory:

- better failure isolation (smaller blast radius)
- smoother scheduling on Kubernetes/OpenShift
- less queue jitter under mixed long/short tasks
- better autoscaling granularity

For docprocessing especially, prefer:

- multiple medium pods (`3-5`) with moderate concurrency (`4-6`)

instead of:

- one giant pod with very high concurrency.

---

## 5) Redis Sizing and Instance Strategy

## 5.1 How many Redis instances?

For 100-user production, use one of these:

### Option A (minimum reliable)
- **1 Redis primary + 1 replica + Sentinel/HA control plane**
- Celery broker on DB 15, result/meta on DB 16

### Option B (better isolation, recommended)
- **Redis cluster for broker** (Celery queues only)
- **Separate Redis for cache/session** (if used)

Reason: queue stability should not compete with cache churn.

## 5.2 Redis memory baseline

Start with:

- broker Redis memory limit: **2-4 GiB**
- eviction for broker queues: avoid policies that can drop active queue keys/messages under pressure
- monitor `used_memory`, fragmentation, and connection counts continuously

If queue peaks are high (large payloads, retries), move to **4-8 GiB**.

---

## 6) Queue Strategy

## 6.1 Must-have queue isolation

- keep `docprocessing` separate from user-file delete
- keep delete queue dedicated
- avoid mixing heavy + latency-sensitive queues in one worker

## 6.2 Prefetch

For heavy and delete queues:

- use low prefetch (`prefetch_multiplier=1`) to reduce starvation and improve fairness.

---

## 7) Capacity math you can use in planning meetings

Approx formula:

`needed_slots ~= arrival_rate_tasks_per_sec * p95_task_seconds * headroom_factor`

Where:

- `headroom_factor` = 1.3 to 2.0

Example:

- docprocessing arrival 0.8 tasks/sec
- p95 runtime 12 sec
- headroom 1.5

`needed_slots ~= 0.8 * 12 * 1.5 = 14.4` -> target 15 slots

If concurrency is 5 per pod:

- pods needed ~= 15/5 = 3 pods (round up + safety -> 4 pods)

---

## 8) Monitoring: what to measure

Track these as first-class SLO metrics:

1. queue depth per queue key
2. oldest message/task age per queue
3. task runtime p50/p95/p99 by task name
4. retries and failures by exception type
5. worker restarts / OOM kills
6. Redis memory, connections, latency, evictions

Depth alone is not enough; **oldest task age** is the real pain indicator.

---

## 9) Monitoring commands (in-pod focused)

## 9.1 Redis queue lengths (DB 15)

```bash
redis-cli -a "$REDIS_PASSWORD" -n 15 --scan | while read key; do
  type=$(redis-cli -a "$REDIS_PASSWORD" -n 15 TYPE "$key" 2>/dev/null)
  if [ "$type" = "list" ]; then
    len=$(redis-cli -a "$REDIS_PASSWORD" -n 15 LLEN "$key" 2>/dev/null)
    echo "$len  $key"
  fi
done | sort -rn
```

Check critical queues explicitly:

```bash
redis-cli -a "$REDIS_PASSWORD" -n 15 LLEN user_file_delete:1
redis-cli -a "$REDIS_PASSWORD" -n 15 LLEN user_file_processing
redis-cli -a "$REDIS_PASSWORD" -n 15 LLEN docprocessing
```

Peek messages:

```bash
redis-cli -a "$REDIS_PASSWORD" -n 15 LRANGE user_file_delete:1 0 2
```

## 9.2 Continuous queue watch

```bash
while true; do
  date
  redis-cli -a "$REDIS_PASSWORD" -n 15 LLEN user_file_delete:1
  redis-cli -a "$REDIS_PASSWORD" -n 15 LLEN docprocessing
  sleep 5
done
```

## 9.3 Worker control-plane checks

From a worker container with Celery CLI available:

```bash
celery -A onyx.background.celery.versioned_apps.user_file_processing inspect active
celery -A onyx.background.celery.versioned_apps.user_file_processing inspect reserved
celery -A onyx.background.celery.versioned_apps.user_file_processing inspect stats
```

For docprocessing app:

```bash
celery -A onyx.background.celery.versioned_apps.docprocessing inspect active
```

---

## 10) Suggested alert thresholds (starting point)

- delete queue age > 5 min for 10 min -> warn
- delete queue age > 15 min -> critical
- docprocessing queue age > 15 min -> warn
- docprocessing queue age > 30 min -> critical
- worker restart count > 3 in 30 min -> critical
- Redis memory > 80% sustained 10 min -> warn
- Redis evictions > 0 on broker instance -> critical

Tune thresholds after 2-3 weeks of real traffic history.

---

## 11) Optimization playbook (safe tuning order)

When queue backlog grows:

1. scale replicas for the impacted worker pool first
2. if still saturated, increase per-pod CPU/memory
3. then increase concurrency gradually (+1 or +2 steps)
4. validate downstreams (OpenSearch/model/DB) are not bottlenecking

Avoid jumping directly to high concurrency; that often amplifies retries and jitter.

---

## 12) Red flags and immediate actions

### Symptom: queue depth rising, CPU low
Likely I/O wait/downstream problem (OpenSearch/DB/S3/LLM), not pure CPU shortage.

### Symptom: `DELETING` rows accumulating
Delete worker starvation or downstream delete failures. Scale dedicated delete worker and inspect queue age.

### Symptom: intermittent long delays
Queue jitter from mixed long/short tasks or high prefetch. Reduce prefetch and isolate workloads.

---

## 13) Final recommendation for your 100-user target

- keep dedicated delete worker pool
- keep docprocessing at 4 replicas baseline
- keep Redis broker in HA (primary+replica+sentinel) at minimum
- isolate broker from cache workloads when possible
- operate with queue-age SLOs and weekly tuning cycle

This gives better resilience, lower blast radius, and more predictable latency than one large mixed worker design.

