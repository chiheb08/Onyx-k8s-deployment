# OpenSearch / Vector DB Fix Report

**Date:** 2026-06-05  
**Issue:** User file uploads ending in `FAILED` status — vector DB writes to OpenSearch failing  
**Status:** **RESOLVED** — both test files now `COMPLETED` with chunks indexed in OpenSearch

---

## 1. Problem Summary

User files were consistently reaching `FAILED` status after upload. Background worker logs showed:

```
Failed to write document chunks for '<user_file_id>' to vector db
ConnectionError: HTTPSConnection(host='opensearch', port=9200): Failed to resolve 'opensearch'
  OR
Connection refused [Errno 111]
```

This was **not** an application bug, misconfigured `OPENSEARCH_HOST`, or wrong credentials. The root cause was **OpenSearch repeatedly OOM-killed by Docker**, leaving the container down or restarting whenever the background worker tried to write chunks.

---

## 2. Investigation Steps

### 2.1 Confirmed OpenSearch was crash-looping

```bash
docker compose ps opensearch
# STATUS: Restarting (137)  — exit 137 = SIGKILL, typically OOM

docker inspect onyx-opensearch-1 --format 'OOMKilled={{.State.OOMKilled}}'
# OOMKilled=true
```

### 2.2 Measured Docker memory budget

```bash
docker stats --no-stream
```

| Container | Memory |
|-----------|--------|
| Total Docker allocation | **7.654 GiB** |
| `onyx-background-1` | ~2.35 GiB |
| `onyx-api_server-1` | ~608 MiB |
| Other services | ~700 MiB combined |

OpenSearch was configured with **2 GB JVM heap** (`-Xms2g -Xmx2g`) plus off-heap memory for Lucene, security plugins, and the OS. On an ~8 GB Docker Desktop VM, that exceeds available RAM once background workers and embedding run concurrently.

### 2.3 Confirmed OOM events in Docker event stream

```bash
docker events --filter container=onyx-opensearch-1
```

Multiple `container oom` events were logged, including during our re-indexing attempts at 15:55:07 and 15:56:21 local time. Each OOM caused:
1. OpenSearch process killed
2. DNS name `opensearch` temporarily unresolvable or connection refused
3. Celery `process_single_user_file` task fails → Postgres `status=FAILED`

### 2.4 Ruled out other causes

| Checked | Result |
|---------|--------|
| `OPENSEARCH_HOST` env in api/background | Correct: `opensearch` |
| Network connectivity (when OS healthy) | `HTTP 200` from `https://opensearch:9200` |
| Credentials | `admin` / `StrongPassword123!` works |
| Index name | `danswer_chunk_nomic_ai_nomic_embed_text_v1` exists |
| Code path | Standard `process_single_user_file` → `_process_user_file_with_indexing` |

---

## 3. Root Cause

**OpenSearch OOM (Out Of Memory) kills** due to JVM heap set too high for the local Docker environment.

The default `docker-compose.yml` used:

```yaml
bootstrap.memory_lock=true
OPENSEARCH_JAVA_OPTS=-Xms2g -Xmx2g
```

On Docker Desktop with ~8 GB RAM and a 2.3 GB background worker, OpenSearch could not sustain 2 GB heap + native memory. The container was killed mid-indexing, which surfaced as vector DB write failures and `FAILED` user files.

---

## 4. Fix Applied

### 4.1 Changes to `docker-compose.yml` (opensearch service)

| Setting | Before | After | Why |
|---------|--------|-------|-----|
| `bootstrap.memory_lock` | `true` | `false` | Memory lock + low RAM worsens OOM on Docker Desktop |
| `OPENSEARCH_JAVA_OPTS` | hardcoded `-Xms2g -Xmx2g` | `${OPENSEARCH_JAVA_OPTS:--Xms256m -Xmx256m}` | Configurable; 256m fits local dev |
| `deploy.resources.limits.memory` | none | `768m` | Hard cap prevents runaway memory from killing other containers |
| `healthcheck` | none | curl `/_cluster/health` green/yellow | Detect when OS is actually ready |

### 4.2 Changes to `.env`

```env
OPENSEARCH_JAVA_OPTS=-Xms256m -Xmx256m
```

### 4.3 Recreated OpenSearch container

```bash
cd onyx/deployment/docker_compose
docker compose up -d opensearch --force-recreate
```

After ~50 seconds: `health=healthy`, memory `656 MiB / 768 MiB`, no OOM.

---

## 5. Recovery Actions (Post-Fix)

### 5.1 Re-queued failed files

The beat task `check_for_user_file_processing` only picks up `PROCESSING` status — not `FAILED`. Manually reset:

```sql
UPDATE user_file SET status='PROCESSING'
WHERE id='5b7f468f-01c6-4ae3-970d-c0149e34f88d';
```

The stuck `DELETING` test file from the earlier trace (`a4e30ebe-...`) was automatically deleted once OpenSearch came back healthy (beat retried `delete_single_user_file` successfully).

### 5.2 Uploaded verification file

```
POST /api/user/projects/file/upload
File: test-upload-report.txt
New ID: 4eec7606-bbbd-493f-b067-b9bf1053ce47
```

### 5.3 Verified end-to-end success

| File | Final Status | Chunks (Postgres) | Chunks (OpenSearch) | Processing Time |
|------|-------------|-------------------|---------------------|-----------------|
| `ML-IhebMejri.pdf` | **COMPLETED** | 2 | 2 | 5.39s |
| `test-upload-report.txt` | **COMPLETED** | 1 | 1 | 8.08s |

Worker logs (success):

```
_process_user_file_with_indexing - Indexing pipeline completed
  new_docs=1 total_docs=1 total_chunks=2 failures=[]
process_user_file_impl - Finished id=5b7f468f-... elapsed=5.39s

_process_user_file_with_indexing - Indexing pipeline completed
  new_docs=1 total_docs=1 total_chunks=1 failures=[]
process_user_file_impl - Finished id=4eec7606-... elapsed=8.08s
```

OpenSearch remained **healthy** for 2+ minutes of monitoring with no further OOM events.

---

## 6. Current System State

```
user_file status:
  ML-IhebMejri.pdf       → COMPLETED (2 chunks, 806 tokens)
  test-upload-report.txt → COMPLETED (1 chunk, 116 tokens)

opensearch:
  Status: running
  Health: healthy
  Memory: ~656 MiB / 768 MiB limit
  OOMKilled: false
```

---

## 7. How to Prevent `FAILED` Status Going Forward

### Immediate (already done)
- Keep `OPENSEARCH_JAVA_OPTS=-Xms256m -Xmx256m` in `.env` for this machine
- OpenSearch healthcheck ensures you can spot instability early

### If you still see OOM / FAILED

1. **Increase Docker Desktop memory** (Settings → Resources → Memory → 12 GB+), then you can raise heap:
   ```env
   OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m
   ```

2. **Monitor OpenSearch health:**
   ```bash
   docker inspect onyx-opensearch-1 --format 'health={{.State.Health.Status}} oom={{.State.OOMKilled}}'
   docker events --filter container=onyx-opensearch-1 --filter event=oom
   ```

3. **Re-process a stuck FAILED file:**
   ```sql
   UPDATE user_file SET status='PROCESSING' WHERE status='FAILED';
   ```
   Beat will enqueue `process_single_user_file` within ~20 seconds.

4. **Check worker logs:**
   ```bash
   docker logs onyx-background-1 --tail 50 | grep -iE "vector db|Indexing pipeline|FAILED"
   ```

### Production note

The 256m heap is appropriate for **local dev on 8 GB Docker**. Production deployments with more RAM should use larger heap (512m–2g) matching available memory. Never set heap to more than ~50% of the container memory limit.

---

## 8. Files Modified

| File | Change |
|------|--------|
| `docker-compose.yml` | OpenSearch heap, memory_lock, memory limit, healthcheck |
| `.env` | `OPENSEARCH_JAVA_OPTS=-Xms256m -Xmx256m` |

No application code changes were required — this was purely an infrastructure/memory configuration issue.

---

## 9. Timeline

| Time (UTC) | Event |
|------------|-------|
| 12:40 | `ML-IhebMejri.pdf` uploaded → FAILED (OpenSearch OOM) |
| 12:59 | Test upload trace → FAILED (OpenSearch down) |
| 13:00 | Delete attempted → stuck DELETING (OpenSearch down) |
| 13:53 | Investigation started — confirmed `OOMKilled=true` |
| 13:53 | First fix: heap 512m — still OOM under indexing load |
| 13:57 | Second fix: heap 256m, memory_lock=false, 768m limit, healthcheck |
| 13:57 | OpenSearch healthy |
| 13:57 | Re-upload + re-process → both files **COMPLETED** |
| 13:59 | Verified chunks in OpenSearch, stable for 2+ minutes |
