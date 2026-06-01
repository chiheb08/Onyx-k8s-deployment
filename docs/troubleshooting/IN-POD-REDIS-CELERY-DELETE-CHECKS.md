# In-Pod Checks: Redis + Celery + Stuck `DELETING` Files

**For:** OpenShift/Kubernetes **pod terminal** only (no `kubectl` / `oc` on your laptop).

Open the terminal on the pod named in each section (UI: Workloads → Pod → Terminal).

---

## Which pod to open?

| Goal | Open terminal on pod |
|------|----------------------|
| Redis queue sizes | **redis** |
| Delete task / worker errors | **celery-worker-user-file-processing** (or **celery-worker-user-file-delete** if deployed) |
| DB: how many `DELETING` | **postgresql** |
| Env vars (Redis host, etc.) | **api-server** or any **celery-worker-*** |

---

## Part 1 — PostgreSQL (30 seconds)

**Pod:** `postgresql`

```bash
psql -U postgres -d postgres
```

```sql
-- How many stuck deletes?
SELECT COUNT(*) AS deleting_count
FROM public.user_file
WHERE status = 'DELETING';

-- Breakdown by status
SELECT status, COUNT(*)
FROM public.user_file
GROUP BY status
ORDER BY status;

-- Oldest stuck deletes
SELECT id, name, status, chunk_count, created_at
FROM public.user_file
WHERE status = 'DELETING'
ORDER BY created_at ASC
LIMIT 10;
```

```sql
\q
```

**Meaning:**

| `deleting_count` | Likely issue |
|------------------|--------------|
| 0 | Fixed (or deletes still in flight for seconds) |
| 100+ | Celery/Redis/Vespa not finishing deletes |

---

## Part 2 — Redis (easy, 2 minutes)

**Pod:** `redis`

Password is in the container environment:

```bash
echo "REDIS_PASSWORD is set: $([ -n \"$REDIS_PASSWORD\" ] && echo yes || echo no)"
```

### Option A — `redis-cli` (best)

```bash
redis-cli -a "$REDIS_PASSWORD" PING
```

Expected: `PONG`

**Queue lengths (most important):**

```bash
redis-cli -a "$REDIS_PASSWORD" LLEN user_file_delete
redis-cli -a "$REDIS_PASSWORD" LLEN user_file_processing
redis-cli -a "$REDIS_PASSWORD" LLEN user_file_project_sync
```

| Queue | What it means |
|-------|----------------|
| `user_file_delete` | Pending **delete** tasks |
| `user_file_processing` | Pending **upload/index** tasks (competes for same worker) |

**Quick read:**

| `user_file_delete` | Many `DELETING` in DB | Diagnosis |
|--------------------|------------------------|-----------|
| **> 0** (e.g. 50–110) | Yes | Worker too slow — need more delete capacity |
| **0** | Yes | Tasks missing or failing — check worker logs |
| Going **down** over time | Yes | Healthy — wait for drain |

**Memory / eviction (optional):**

```bash
redis-cli -a "$REDIS_PASSWORD" INFO memory | grep -E 'used_memory_human|maxmemory_human|evicted_keys'
```

If `evicted_keys` is large and growing, Redis may be dropping broker data.

### Option B — No `redis-cli` on your pod

Use **api-server** or **celery-worker-user-file-processing** pod instead (Part 2C).

---

## Part 2B — Redis from api-server / celery pod

**Pod:** `api-server` **or** `celery-worker-user-file-processing`

Check env:

```bash
echo "HOST=$REDIS_HOST PORT=$REDIS_PORT"
echo "PASSWORD set: $([ -n \"$REDIS_PASSWORD\" ] && echo yes || echo no)"
```

If `redis-cli` exists:

```bash
redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" LLEN user_file_delete
redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" LLEN user_file_processing
```

### Python (works on most Onyx backend pods)

```bash
python3 << 'PY'
import os
try:
    import redis
except ImportError:
    print("Install redis module not available - use redis pod terminal instead")
    raise SystemExit(1)

host = os.environ.get("REDIS_HOST", "redis")
port = int(os.environ.get("REDIS_PORT", "6379"))
password = os.environ.get("REDIS_PASSWORD")

r = redis.Redis(host=host, port=port, password=password, decode_responses=True)
print("PING:", r.ping())
for q in ["user_file_delete", "user_file_processing", "user_file_project_sync"]:
    print(f"LLEN {q}:", r.llen(q))
info = r.info("memory")
print("used_memory_human:", info.get("used_memory_human"))
print("evicted_keys:", info.get("evicted_keys"))
PY
```

---

## Part 3 — Celery workers (easy, 3 minutes)

**Pod:** `celery-worker-user-file-processing`  
(and **`celery-worker-user-file-delete`** if you deployed the dedicated delete worker)

### 3.1 See if delete tasks are running now

```bash
celery -A onyx.background.celery.versioned_apps.user_file_processing inspect active
```

Look for task names containing `delete` or `process_single_user_file_delete`.

```bash
celery -A onyx.background.celery.versioned_apps.user_file_processing inspect reserved
```

Reserved = waiting to run.

### 3.2 Worker stats (queues this process listens to)

```bash
celery -A onyx.background.celery.versioned_apps.user_file_processing inspect stats
```

Check which queues appear under the worker hostname.

### 3.3 Recent delete activity in **this** pod’s logs

The pod terminal often does not show old logs. In the UI, open **Logs** for the same pod and search for:

```text
process_single_user_file_delete
```

**Good signs:**

```text
process_single_user_file_delete - Starting id=...
process_single_user_file_delete - Completed id=...
```

**Bad signs:**

```text
429
Failed to delete from Vespa
Error
exception
lock
```

### 3.4 Dedicated delete worker (if deployed)

On pod **`celery-worker-user-file-delete`**:

```bash
celery -A onyx.background.celery.versioned_apps.user_file_processing inspect active
```

That pod should only consume `user_file_delete`.

---

## Part 4 — One-page decision tree

```text
                    ┌─────────────────────────┐
                    │ COUNT DELETING in DB  │
                    └───────────┬─────────────┘
                                │
              ┌─────────────────┴─────────────────┐
              │                                   │
         LLEN user_file_delete               LLEN user_file_delete
              > 0                                = 0
              │                                   │
              ▼                                   ▼
    Scale/delete worker busy              Tasks not queued or failed
    Vespa 429? check logs                 Check worker logs + beat
    Apply dedicated delete worker         Re-trigger delete (see runbook)
```

---

## Part 5 — Re-run one delete manually (inside celery pod)

**Pod:** `celery-worker-user-file-processing`  
Replace `<FILE_UUID>` with id from Postgres.

```bash
celery -A onyx.background.celery.versioned_apps.user_file_processing call \
  onyx.background.celery.tasks.user_file_processing.tasks.process_single_user_file_delete \
  --kwargs='{"user_file_id":"<FILE_UUID>","tenant_id":"public"}'
```

> Use your real tenant id if not single-tenant `public`.

Then in **postgresql** pod:

```sql
SELECT id, status FROM public.user_file WHERE id = '<FILE_UUID>';
```

Row should disappear when delete succeeds.

---

## Part 6 — Copy/paste checklist (fill in)

```text
DELETING count in DB:     ______
LLEN user_file_delete:    ______
LLEN user_file_processing: ______
redis PING:               ______
Worker active delete task: yes / no
Log error (one line):     ________________________
```

---

## Fixes (still from pod UI / admin, not laptop CLI)

| Problem | What to do |
|---------|------------|
| High `user_file_delete` + high `DELETING` | Ask ops to scale **celery-worker-user-file-delete** or apply manifests in repo |
| `user_file_delete` = 0, `DELETING` high | Restart beat + user-file workers from UI; re-run manual `celery call` above |
| Vespa 429 in logs | Reduce indexing load; fix Vespa resources first |
| SQL-only cleanup | **Avoid** — leaves Vespa/MinIO orphans |

Full remediation: [DELETING-FILES-STUCK-INVESTIGATION-AND-REMEDIATION.md](./DELETING-FILES-STUCK-INVESTIGATION-AND-REMEDIATION.md)

---

*Version 1.0 — in-pod only*
