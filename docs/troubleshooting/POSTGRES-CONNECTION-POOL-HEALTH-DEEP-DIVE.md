# Postgres Connection Pool Health — Deep Dive

**Purpose:** Know whether your DB connection behavior is **healthy** or **unhealthy**, what to measure, and what your observed production snapshot indicates.

**Related:**

- [POSTGRES-CONNECTIONS-PER-INSTANCE.md](./POSTGRES-CONNECTIONS-PER-INSTANCE.md) — queries
- [5-USER-CONCURRENT-UPLOAD-TEST-SCENARIO.md](./5-USER-CONCURRENT-UPLOAD-TEST-SCENARIO.md) — load test
- [../reference/POSTGRES-POOL-REMEDIATION-RUNBOOK.md](../reference/POSTGRES-POOL-REMEDIATION-RUNBOOK.md) — exact fix steps

---

## Executive verdict on your observed case

**Status: UNHEALTHY (high confidence)**

Evidence from your investigation:

| Signal | Your value | Healthy range (3 API pods) | Verdict |
|--------|------------|----------------------------|---------|
| API pod A `total` connections | **320** | ~5–25 idle, ~10–30 under load | **Critical** |
| API pod B `total` | **108** | same | **Bad** |
| API pod C `total` | **40** | same | **Borderline / high** |
| `active` at snapshot | **0** on all | 0–10 bursts OK | Misleadingly “quiet” |
| Idle connection age | **~47 minutes** | seconds–few minutes typical | **Bad** (hoarding) |
| Last query on idle conns | `ROLLBACK` / `COMMIT` | normal in isolation | OK by itself |
| Traffic spread across API pods | **very uneven** | roughly balanced | **Unhealthy** |

**Bottom line:** This is not “Postgres is slow.” This is **too many idle connections held open by API pods**, especially one hot replica. That can exhaust `max_connections`, cause random timeouts, and make uploads/chat feel like crashes.

---

## Part 1 — What “healthy” means (simple)

A healthy system:

1. Opens **only as many** DB connections as needed
2. **Reuses** connections from a bounded pool
3. Releases pressure on Postgres when load drops
4. Spreads load **fairly** across API replicas (roughly)
5. Stays **below** Postgres `max_connections` with headroom

**Analogy:** A hotel with 100 keys (`max_connections`). Healthy = guests check in, use room, check out. Unhealthy = one group reserves 320 keys overnight while sleeping (`idle`).

---

## Part 2 — Architecture: who opens connections?

```text
┌─────────────────────────────────────────────────────────────┐
│                     PostgreSQL                              │
│              max_connections = N (e.g. 100)                 │
└────────────▲───────────────────────▲──────────────────────┘
             │                       │
    ┌────────┴────────┐     ┌────────┴────────┐
    │  API pod 1      │     │  Celery workers │
    │  SQLAlchemy pool│     │  own pools      │
    │  per process    │     │                 │
    └─────────────────┘     └─────────────────┘
```

Each **API replica** = separate process = **its own pool(s)**.

If env vars are missing, many apps default to something like:

- `POOL_SIZE = 40`
- `OVERFLOW = 10`
- max **50 per pool per engine**

If the app creates **multiple engines** (read/write, tenant, etc.), multiply:

```text
max connections per API pod ≈ num_engines × (POOL_SIZE + OVERFLOW)
```

That explains how one pod can reach **hundreds** without “heavy SQL.”

---

## Part 3 — Connection states explained

| `pg_stat_activity.state` | Meaning | Healthy? |
|--------------------------|---------|----------|
| `active` | Running SQL now | Normal during work |
| `idle` | Connected, waiting for next command | Normal **in small numbers** |
| `idle in transaction` | Transaction open, doing nothing | **Avoid** sustained counts |
| `idle in transaction (aborted)` | Failed txn not cleaned up | Investigate |

| `wait_event` (when idle) | Meaning |
|--------------------------|---------|
| `ClientRead` | Postgres waiting for app to send next query | Normal for pooled idle conn |

**Your `ROLLBACK` / `COMMIT` on idle rows:**  
Normal **last command** before returning to pool. **Not** the disease. The disease is **count** (320) and **age** (~47 min).

---

## Part 4 — Healthy numbers (rules of thumb)

Assumptions: **3 API replicas**, explicit pool cap `POOL_SIZE=15`, `OVERFLOW=5` (recommended starting point).

### A) Idle system (no user load)

| Metric | Healthy | Warning | Critical |
|--------|---------|---------|----------|
| Per API pod `total` | 2–15 | 16–30 | **> 30** |
| Sum all API pods | 6–45 | 46–90 | **> 90** |
| `idle_in_tx` | 0 | 1–2 brief | **> 5** or growing |
| Global `used / max_connections` | < 40% | 40–70% | **> 80%** |

### B) During 5-user upload test (peak)

| Metric | Healthy | Warning | Critical |
|--------|---------|---------|----------|
| Per API pod `total` | 10–25 | 26–40 | **> 40** |
| Per API pod `active` | 1–8 | 9–15 | **most rows active** |
| Global `used / max` | < 60% | 60–80% | **> 85%** |
| After test ends (10 min) | returns toward idle baseline | flat high | **keeps climbing** |

### C) Balance across API replicas

| Pattern | Healthy | Unhealthy |
|---------|---------|-----------|
| 3 API totals | within ~2× of each other | one pod 3–10× others |
| Example | 18, 22, 15 | **320, 108, 40** |

Your case: **320 vs 40** → severe imbalance + absolute count too high.

---

## Part 5 — Your snapshot decoded (deep dive)

### Query 1 — per client summary

```text
10.129.33.6   total=320  active=0
10.130.65.99  total=108  active=0
10.130.34.99  total=40   active=0
```

**Interpretation:**

1. **~468 connections** from API tier alone (before counting workers)
2. At snapshot, **no query running** → not CPU/query tuning issue
3. Connections are **reserved but unused** → pool hoarding or leak
4. Hottest pod took most traffic **or** leaks faster under load

### Query 2 — detail on `10.129.33.6`

Observed:

- dozens+ rows, all `idle`
- `wait_event = ClientRead`
- `query_preview = ROLLBACK` or `COMMIT`
- `time_in_state ≈ 00:46:48`

**Interpretation:**

- Connections opened over time and **never closed to Postgres**
- Sitting in app pool (or leak) for **47 minutes**
- Classic pattern before `too many clients` errors appear under next traffic spike

### Why users feel “crash” with `active=0`

Because Postgres enforces a **hard connection limit**. Idle connections **count**:

```text
used_connections = active + idle + idle_in_tx
```

When `used ≈ max_connections`:

- new login fails
- uploads hang
- API returns 500/timeout
- Celery jobs stall

System looks “idle” in your query but is **full**.

---

## Part 6 — Healthy vs your case (side by side)

```text
HEALTHY (3 API, pool 15+5)          YOUR CASE (observed)
────────────────────────────          ─────────────────────
API pods: 12, 14, 10 total            API pods: 320, 108, 40
active: 2, 1, 3 during load           active: 0 at snapshot
idle_in_tx: 0                         idle_in_tx: (check; should be 0)
global: 45/100 used                   global: likely 80–100+/100
after restart: low counts             long idle age ~47 min
```

---

## Part 7 — Root cause hypotheses (ranked)

| # | Hypothesis | Likelihood | How to confirm |
|---|------------|------------|----------------|
| 1 | `POSTGRES_API_SERVER_POOL_*` not set; defaults too high × multiple engines | **High** | `printenv` on API pods |
| 2 | Connection leak in app under load | **Medium** | counts rise after restart without traffic |
| 3 | No pooler; every pod/engine hits Postgres directly | **High** | architecture review |
| 4 | Load balancer sticky / uneven routing | **Medium** | compare per-pod request metrics |
| 5 | Postgres `max_connections` too low for unchecked pools | **Medium** | `SHOW max_connections` + used |

---

## Part 8 — What to do (ordered)

See full runbook: [POSTGRES-POOL-REMEDIATION-RUNBOOK.md](../reference/POSTGRES-POOL-REMEDIATION-RUNBOOK.md)

**Short version:**

1. Rolling restart API pods (immediate relief)
2. Set explicit pool env vars on API
3. Restart API again; verify `printenv`
4. Re-run monitoring queries
5. Run 5-user upload test; compare to thresholds in Part 4
6. If one pod still climbs above 40 idle → treat as leak + vendor ticket

**Recommended starting env (3 API replicas):**

```yaml
POSTGRES_API_SERVER_POOL_SIZE: "15"
POSTGRES_API_SERVER_POOL_OVERFLOW: "5"
POSTGRES_API_SERVER_READ_ONLY_POOL_SIZE: "8"
POSTGRES_API_SERVER_READ_ONLY_POOL_OVERFLOW: "2"
```

---

## Part 9 — Monitoring pack (copy/paste)

### Dashboard query — health summary

```sql
SELECT
  now() AS ts,
  COUNT(*) AS total_used,
  (SELECT setting::int FROM pg_settings WHERE name='max_connections') AS max_conn,
  ROUND(100.0 * COUNT(*) /
    (SELECT setting::int FROM pg_settings WHERE name='max_connections'), 1) AS pct_used,
  COUNT(*) FILTER (WHERE state='active') AS active,
  COUNT(*) FILTER (WHERE state='idle') AS idle,
  COUNT(*) FILTER (WHERE state='idle in transaction') AS idle_in_tx
FROM pg_stat_activity
WHERE datname = current_database();
```

### Per-client health

```sql
SELECT
  client_addr,
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE state='active') AS active,
  COUNT(*) FILTER (WHERE state='idle in transaction') AS idle_in_tx,
  MAX(now() - state_change) AS oldest_state_age
FROM pg_stat_activity
WHERE datname = current_database()
  AND pid <> pg_backend_pid()
GROUP BY client_addr
ORDER BY total DESC;
```

### Alert thresholds (suggested)

| Alert | Condition |
|-------|-----------|
| Warning | `pct_used > 70%` for 5 min |
| Critical | `pct_used > 85%` for 2 min |
| Warning | any API pod `total > 30` |
| Critical | any API pod `total > 50` |
| Warning | `idle_in_tx > 5` |
| Critical | `idle_in_tx` growing over 10 min |

---

## Part 10 — Healthy timeline (what “good” looks like)

```text
T0  restart API
    → per-pod total drops to ~2–10

T1  light browsing
    → per-pod total ~5–15, active 0–2

T2  5 users upload
    → per-pod total ~10–25, active bursts 2–8

T3  10 min after test
    → totals drift down toward idle baseline

T4  30 min stable
    → no pod climbing monotonically
    → global used < 60% max_conn
```

**Your case at T?** looked like **T4 but with T2-level connection counts** — stale hoarding.

---

## Part 11 — FAQ

### “Is idle bad?”

No. **Idle is normal** for connection pooling.  
**Too much idle** (hundreds per pod) is bad.

### “Is ROLLBACK bad?”

Usually no. It often means a transaction ended and the connection returned to pool.

### “Should active be high?”

Only during real work. Constant high `active` everywhere = overload.  
Your `active=0` with `total=320` = **reservation problem**, not compute problem.

### “Is 40 OK on one API pod?”

Borderline if pool max is 20. **Not OK** as steady idle if target pool is 15+5.  
**320 is never OK.**

### “Do I only increase max_connections?”

No. That is a band-aid. **Cap app pools first**, then adjust `max_connections` if needed.

---

## Part 12 — Pass/fail card (print)

```text
HEALTHY if ALL true:
  [ ] No API pod > 30 connections at idle
  [ ] No API pod > 40 connections during 5-user test peak
  [ ] idle_in_tx = 0 (or tiny, not growing)
  [ ] global used/max < 70% during test
  [ ] API pod totals within 2× of each other
  [ ] after test, counts stabilize (no endless climb)

YOUR CASE (before fix):
  [x] API pod 320 — FAIL
  [x] imbalance 320/108/40 — FAIL
  [x] idle age ~47 min — FAIL
  [ ] pool env explicitly capped — likely FAIL (verify)
```

---

## Summary one-liner

**Healthy** = bounded, reused, balanced DB connections with headroom.  
**Your case** = unbounded idle hoarding on one API replica — **unhealthy** — fix pool limits and restart, then re-test.

---

*Last updated: July 2026*
