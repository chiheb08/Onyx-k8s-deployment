# Postgres Connections per Instance — Monitoring Query

Use this to see **how many DB connections each client (pod/IP) is using** after changing API pool settings (`POSTGRES_API_SERVER_POOL_SIZE`, `POSTGRES_API_SERVER_POOL_OVERFLOW`).

**Where to run:** Postgres pod terminal (`psql`).

**Load test playbook:** [5-USER-CONCURRENT-UPLOAD-TEST-SCENARIO.md](./5-USER-CONCURRENT-UPLOAD-TEST-SCENARIO.md)

---

## Connect

```bash
PGPASSWORD=$POSTGRES_PASSWORD psql -h localhost -U $POSTGRES_USER -d $POSTGRES_DB
```

(Adjust host/user/db if your secret names differ.)

---

## Main query — connections per client

```sql
SELECT
  client_addr,
  COUNT(*) AS total_connections,
  COUNT(*) FILTER (WHERE state = 'active') AS active,
  COUNT(*) FILTER (WHERE state = 'idle') AS idle,
  COUNT(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_tx
FROM pg_stat_activity
WHERE datname = current_database()
  AND pid <> pg_backend_pid()
GROUP BY client_addr
ORDER BY total_connections DESC;
```

---

## Understanding the output (detailed)

### What each column means

| Column | Plain English |
|--------|----------------|
| `client_addr` | IP address of the pod that opened the connection (API, worker, etc.) |
| `total_connections` | How many DB connections that one client holds right now |
| `active` | Connections **running a query this second** |
| `idle` | Connections **open but waiting** (typical for connection pools) |
| `idle_in_tx` | Connection started a transaction but **has not committed** — often a warning sign if it grows |

`total_connections` = `active` + `idle` + `idle_in_tx` (for that row).

We exclude your own `psql` session with `pid <> pg_backend_pid()` so you don't count yourself.

---

### Example 1 — Healthy API pool under load

```text
 client_addr  | total | active | idle | idle_in_tx
--------------+-------+--------+------+------------
 10.131.4.22  |    22 |      2 |   20 |          0
 10.131.4.18  |    21 |      3 |   18 |          0
 10.131.4.31  |    19 |      1 |   18 |          0
 10.130.8.44  |     6 |      1 |    5 |          0
```

**How to read:**

- Three rows with ~19–22 connections → likely **3 API replicas**, each keeping a warm pool (`idle` high is **normal**).
- `active` only 1–3 → DB is not melting; pools are ready for bursts.
- Smaller row (`10.130.8.44`) → probably a **Celery worker** pod.
- `idle_in_tx = 0` → good.

**Analogy:** Three reception desks (API pods). Each has staff at the desk (`idle`) and only a few helping customers right now (`active`).

---

### Example 2 — Pool too small (app waits, DB looks fine)

```text
 client_addr  | total | active | idle | idle_in_tx
--------------+-------+--------+------+------------
 10.131.4.22  |    30 |     28 |    2 |          0
 10.131.4.18  |    30 |     27 |    3 |          0
 10.131.4.31  |    30 |     29 |    1 |          0
```

Global query still shows e.g. `45 / 100` max connections — **plenty of room**.

But API logs show `TimeoutError waiting for connection` or `QueuePool limit`.

**How to read:**

- Each API pod at **max pool** (e.g. 20+10=30) with almost all **active** → every connection busy; new requests **queue inside the app**.
- Fix: slightly increase `POOL_SIZE` or add API replica — not only Postgres `max_connections`.

---

### Example 3 — Postgres global limit hit

```sql
 db_connections_used | max_connections
---------------------+-----------------
                  98 |             100
```

**How to read:**

- Database is full. New connections fail with `too many clients already`.
- Fix: lower per-pod pools, reduce worker concurrency, or raise `max_connections` (with care).

Per-client query might show many pods each using 10–20 connections — problem is **sum**, not one pod.

---

### Example 4 — `idle in transaction` warning

```text
 client_addr  | total | active | idle | idle_in_tx
--------------+-------+--------+------+------------
 10.131.4.22  |    25 |      0 |   20 |          5
```

**How to read:**

- 5 connections stuck mid-transaction → possible bug, long request, or leak.
- Investigate API/worker logs; look for hung endpoints.

---

### Map `client_addr` → pod name

Inside each suspect pod:

```bash
hostname -i
```

Match IP to the query row. Typical mapping:

| Connection count | Likely pod type |
|------------------|-----------------|
| ~15–30 per IP (with your pool settings) | API server replica |
| ~5–15 per IP | Celery worker |
| `null` or unix socket | local/admin tools |

---

### Relate numbers to your pool config

If you set:

```text
POOL_SIZE=20, OVERFLOW=10  →  max 30 per API pod
3 API replicas             →  max ~90 from API tier alone
```

During a 5-user upload test, you might see **only 5–15 per API pod** — that's fine. You are measuring **headroom**, not trying to hit 30.

| Peak per API IP | Interpretation |
|-----------------|----------------|
| < 50% of max | Pool sized with room |
| 80–100% of max + errors | Pool too small for this traffic |
| Low usage + slow app | Bottleneck is **not** Postgres pool (check Redis/indexing) |

---

## Global usage vs limit

```sql
SELECT
  COUNT(*) AS db_connections_used,
  (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') AS max_connections
FROM pg_stat_activity
WHERE datname = current_database();
```

| `used / max` | Risk |
|--------------|------|
| < 60% | Comfortable |
| 60–80% | Watch during peaks |
| > 85% | Danger zone — scale or reduce pools |

---

## See what each connection is doing (debug one IP)

Replace the IP with a row from your results:

```sql
SELECT
  pid,
  client_addr,
  state,
  wait_event_type,
  wait_event,
  LEFT(query, 80) AS query_preview,
  NOW() - state_change AS time_in_state
FROM pg_stat_activity
WHERE datname = current_database()
  AND client_addr = '10.131.4.22'
ORDER BY state, time_in_state DESC;
```

Useful when `active` is high and you need to know **which queries** hold connections.

---

## Repeat during test (every 30s)

```sql
SELECT
  now() AS ts,
  client_addr,
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE state = 'active') AS active
FROM pg_stat_activity
WHERE datname = current_database()
  AND pid <> pg_backend_pid()
GROUP BY client_addr
ORDER BY total DESC;
```

Log `ts`, max `total` per API IP, and global `used/max` — compare before and after pool changes.

---

## Per API replica math (reminder)

With 3 API replicas and e.g. `POOL_SIZE=20`, `OVERFLOW=10`:

- Max per API pod ≈ **30**
- Max from API tier ≈ **90** (3 × 30), plus Celery/worker connections

Run the main query **during load** — see [5-USER-CONCURRENT-UPLOAD-TEST-SCENARIO.md](./5-USER-CONCURRENT-UPLOAD-TEST-SCENARIO.md).
