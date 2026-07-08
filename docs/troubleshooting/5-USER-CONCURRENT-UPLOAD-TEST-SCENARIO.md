# 5-User Concurrent Upload Test — What to Watch

**Goal:** Run a controlled test with **5 people uploading at the same time** and know whether slowness is **Postgres pool**, **Celery backlog**, **indexing**, or **something else**.

**Duration:** ~30 minutes  
**Style:** In-pod terminals (no `kubectl` required on laptop if you use OpenShift UI pod shells)

**Related:** [POSTGRES-CONNECTIONS-PER-INSTANCE.md](./POSTGRES-CONNECTIONS-PER-INSTANCE.md)  
**Health deep dive:** [POSTGRES-CONNECTION-POOL-HEALTH-DEEP-DIVE.md](./POSTGRES-CONNECTION-POOL-HEALTH-DEEP-DIVE.md)

---

## Before you start

### Test files (use the same set for everyone)

| User | File | Why |
|------|------|-----|
| 1 | `test-1-small.txt` (~50 KB) | Baseline — should finish fast |
| 2 | `test-2-medium.pdf` (~2–5 MB) | Normal PDF |
| 3 | `test-3-medium.pdf` (~2–5 MB) | Duplicate size, different name |
| 4 | `test-4-large.pdf` (~10–20 MB) | Stress indexing |
| 5 | `test-5-small.txt` (~50 KB) | Second small file |

Avoid one user uploading a 200 MB monster for the first test — that tests a different bottleneck.

### Record baseline (5 minutes before test)

**Pod: Postgres**

```sql
SELECT status, COUNT(*) FROM user_file GROUP BY status ORDER BY status;
```

**Pod: Redis** (`-n 15` is typical for Celery broker — confirm in your env if needed)

```bash
redis-cli -a "$REDIS_PASSWORD" -n 15 LLEN user_file_processing
redis-cli -a "$REDIS_PASSWORD" -n 15 LLEN user_file_delete
```

Write down starting numbers.

### Optional: map pod IPs once

Note API pod IPs and worker IPs (`hostname -i` inside each pod, or `kubectl get pods -o wide`). You will match them to `client_addr` in Postgres.

---

## Test roles

| Role | Person | Job during test |
|------|--------|-----------------|
| **Uploaders** | Users 1–5 | Upload assigned file at the same time (see script below) |
| **Observer** | You (or 6th person) | Run Postgres + Redis queries every 30s, note errors |

Everyone uploads in the **same project** (or same flow you use in prod).

---

## Synchronized upload script (read to the team)

**T=0:** Observer says “Go.”

1. All 5 click upload within **10 seconds** of each other.
2. Wait until UI shows processing complete (or 15 min max).
3. Do **not** delete files during this test.
4. Do **not** start heavy chat during first 10 minutes (upload-only phase).

**T+10 min:** Optional phase 2 — all 5 ask one short chat question while files finish indexing.

---

## What to watch (4 layers)

```text
Layer 1  Browser/UI     → "uploading", "processing", errors
Layer 2  API + Postgres   → connections per pod, pool pressure
Layer 3  Redis + Celery  → queue backlog
Layer 4  Indexing        → user_file status, model/search health
```

---

## Layer 1 — UI (each uploader reports)

| Signal | Good | Bad |
|--------|------|-----|
| Upload HTTP completes | Within 1–3 min per file (size dependent) | Spinner >5 min, 413, 504, 502 |
| File appears in project | Yes | Missing or stuck "processing" |
| Status becomes usable | COMPLETED / ready | FAILED or forever PROCESSING |

---

## Layer 2 — Postgres connections (Observer, every 30s)

**Pod: Postgres**

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

```sql
SELECT
  COUNT(*) AS db_connections_used,
  (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') AS max_connections
FROM pg_stat_activity
WHERE datname = current_database();
```

### Example output (illustrative)

```text
 client_addr  | total_connections | active | idle | idle_in_tx
--------------+-------------------+--------+------+------------
 10.131.4.22  |                24 |      3 |   21 |          0
 10.131.4.18  |                22 |      2 |   20 |          0
 10.131.4.31  |                20 |      1 |   19 |          0
 10.130.8.44  |                 8 |      2 |    6 |          0
 10.130.8.51  |                 7 |      1 |    6 |          0
```

**How to read:**

- Rows with **~20–30** connections and mostly **idle** → likely **3 API pods** each holding pool connections (normal if `POOL_SIZE=20`).
- Rows with **lower** counts (5–10) → often **Celery workers**.
- **`active` always high** on one IP → that pod is DB-bound or slow queries.
- **`idle_in_tx` > 0** and growing → possible connection leak or long transactions — investigate.
- Sum of `total_connections` near **`max_connections`** → Postgres limit hit; pool tuning alone won’t fix it.

**If pool is too small:** API logs show pool wait / timeout while Postgres still has free `max_connections`.

**If pool is OK but slow:** total connections moderate, but Redis queue grows (Layer 3).

---

## Layer 3 — Redis queues (Observer, every 30s)

**Pod: Redis**

```bash
echo "user_file_processing=$(redis-cli -a "$REDIS_PASSWORD" -n 15 LLEN user_file_processing)"
echo "user_file_delete=$(redis-cli -a "$REDIS_PASSWORD" -n 15 LLEN user_file_delete)"
echo "docprocessing=$(redis-cli -a "$REDIS_PASSWORD" -n 15 LLEN docprocessing)"
```

| Pattern | Meaning |
|---------|---------|
| `user_file_processing` 0→5→0 | Healthy — burst then drain |
| Stays at 5+ for many minutes | **Worker/indexing bottleneck** |
| Grows without draining | Scale workers or fix downstream (model, search) |
| `user_file_delete` high during upload test | Wrong worker mix — delete starving upload |

---

## Layer 4 — File pipeline (Observer, every 1–2 min)

**Pod: Postgres**

```sql
SELECT status, COUNT(*) AS cnt
FROM user_file
GROUP BY status
ORDER BY status;
```

```sql
SELECT name, status, chunk_count, created_at
FROM user_file
ORDER BY created_at DESC
LIMIT 10;
```

| Status | Good during test | Bad |
|--------|------------------|-----|
| `PROCESSING` | Few, then drops | Many stuck 10+ min |
| `COMPLETED` | Grows after uploads | Stays 0 |
| `FAILED` | 0 | Any — check worker/indexing logs |
| `DELETING` | 0 (no deletes in test) | Should not appear |

---

## Timeline checklist (print this)

| Time | Observer action | Uploaders |
|------|-----------------|-----------|
| T−5 min | Baseline SQL + Redis | Prepare files |
| T=0 | Start 30s timer loop | All upload within 10s |
| T+2 min | Postgres + Redis snapshot | Report UI state |
| T+5 min | Postgres + Redis + `user_file` status | Report UI state |
| T+10 min | Same + note max `total_connections` per IP | Optional: one chat each |
| T+15 min | Final snapshot | Confirm all done or failed |
| T+20 min | Write summary (table below) | — |

---

## Results scorecard (fill after test)

| Metric | Value | OK? |
|--------|-------|-----|
| All 5 uploads accepted (no 5xx) | yes/no | |
| Time to UI "upload done" (small files) | ___ min | < 3 |
| Time to `COMPLETED` (small files) | ___ min | < 5 |
| Peak `user_file_processing` queue | ___ | returns to 0 |
| Peak DB connections used / max | ___ / ___ | < 80% max |
| Max connections on one API IP | ___ | < pool_size+overflow |
| `FAILED` count | ___ | 0 |
| `idle_in_tx` | ___ | 0 |
| Subjective "app crashed" | yes/no | no |

---

## Decision tree after the test

```text
Upload 5xx / timeout at gateway?
  → nginx/route timeouts, body size — not Postgres pool first

Upload OK but PROCESSING forever + Redis queue high?
  → Celery workers / indexing-model / OpenSearch

Postgres max connections near limit?
  → reduce per-pod pool OR raise max_connections OR fewer replicas

One API IP at pool max + pool timeout errors?
  → increase POOL_SIZE slightly OR add API replica

Low DB connections + slow anyway?
  → not a pool problem — indexing GPU/model/search

Many FAILED + indexing-model HF/offline errors?
  → embedding model cache — fix before scaling workers
```

---

## API pool env check (after test)

**Pod: any API server**

```bash
printenv | grep POSTGRES_API_SERVER_POOL
```

Confirm values match what you intended before comparing connection counts.

---

## One-paragraph report template (for your team)

> We ran 5 concurrent uploads (2 small txt, 3 PDF). Peak `user_file_processing` queue was X (drained in Y min). Postgres peaked at Z/M connections; API pods peaked at A/B/C per IP. Final status: N COMPLETED, F FAILED. Bottleneck appears to be **[pool / workers / indexing / gateway]**. Next action: **[specific change]**.

---

*Keep test files for repeat runs so you can compare before/after pool or worker changes.*
