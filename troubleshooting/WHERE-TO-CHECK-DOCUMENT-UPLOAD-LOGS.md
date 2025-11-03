# Where to Check Logs for Large Document Upload Errors

Based on the Onyx architecture, when you upload a large document, here's where errors can occur and which service logs to check:

## Document Upload Flow (Step-by-Step)

```
1. User uploads file → NGINX → API Server
2. API Server validates → Stores in MinIO
3. API Server creates task → Redis queue
4. Background Workers process → Index document
```

## Services to Check (In Order of Likelihood)

### 1. 🔴 **API Server** (Most Critical - Check First)

**Service Name (Kubernetes):** `api-server` or `onyx-api-server`

**When to check:**
- File size validation errors
- File format validation errors
- Initial upload failures
- MinIO connection errors
- Database connection errors during metadata creation

**How to check logs:**
```bash
# Kubernetes
kubectl logs -f deployment/api-server -n onyx

# Docker Compose
docker compose logs -f api_server

# Search for your file
kubectl logs deployment/api-server -n onyx | grep -i "upload\|error\|failed\|<your-filename>"
```

**What to look for:**
- `Error uploading files`
- `File size exceeds`
- `Failed to upload files`
- `HTTPException` with status 413 (File too large)
- Connection errors to MinIO or PostgreSQL

**Error Location in Code:**
- `onyx-repo/backend/onyx/server/features/projects/api.py` → `upload_user_files()`

---

### 2. 🟠 **Background Workers** (Very Important - Check Second)

**Service Name (Kubernetes):** `background-workers` or `onyx-background-workers`

**Worker Types Involved:**
- **User File Processing Worker** - Processes uploaded user files
- **Docprocessing Worker** - Chunks and indexes documents
- **Docfetching Worker** - Fetches files from MinIO

**When to check:**
- Document processing errors
- Chunking failures
- Text extraction errors
- Indexing pipeline failures
- Task timeouts

**How to check logs:**
```bash
# Kubernetes
kubectl logs -f deployment/background-workers -n onyx

# Docker Compose
docker compose logs -f background

# Search for specific worker or file
kubectl logs deployment/background-workers -n onyx | grep -i "user_file\|docprocessing\|<your-filename>"
```

**What to look for:**
- `process_single_user_file - Error processing file`
- `Indexing pipeline failed`
- `Error processing file id=`
- `FAILED` status updates
- Timeout errors
- Memory errors (OOM - Out of Memory)

**Error Location in Code:**
- `onyx-repo/backend/onyx/background/celery/tasks/user_file_processing/tasks.py` → `process_single_user_file()`
- `onyx-repo/backend/onyx/background/celery/tasks/docprocessing/tasks.py` → `_docprocessing_task()`

**Log File Paths (if using file logs):**
- `/var/log/celery_worker_user_file_processing.log`
- `/var/log/celery_worker_docprocessing.log`
- `/var/log/celery_worker_background.log`

---

### 3. 🟡 **Indexing Model Server** (Important - For Embedding Errors)

**Service Name (Kubernetes):** `indexing-model-server` or `onyx-indexing-model-server`

**When to check:**
- Embedding generation failures
- Model server timeouts
- Memory issues during embedding
- Model loading errors

**How to check logs:**
```bash
# Kubernetes
kubectl logs -f deployment/indexing-model-server -n onyx

# Docker Compose
docker compose logs -f indexing_model_server

# Search for errors
kubectl logs deployment/indexing-model-server -n onyx | grep -i "error\|failed\|timeout\|oom"
```

**What to look for:**
- `Failed to generate embedding`
- `Timeout waiting for model server`
- `CUDA out of memory` (if using GPU)
- `Out of Memory` errors
- Model loading failures

---

### 4. 🟢 **MinIO** (Storage Errors)

**Service Name (Kubernetes):** `minio` or `onyx-minio`

**When to check:**
- File storage failures
- Disk space errors
- Permission errors
- Upload timeouts

**How to check logs:**
```bash
# Kubernetes
kubectl logs -f deployment/minio -n onyx

# Docker Compose
docker compose logs -f minio

# Check disk space
kubectl exec deployment/minio -n onyx -- df -h
```

**What to look for:**
- `No space left on device`
- `Permission denied`
- `Failed to upload`
- Storage quota errors

---

### 5. 🔵 **PostgreSQL** (Metadata Errors)

**Service Name (Kubernetes):** `postgresql` or `onyx-postgresql`

**When to check:**
- Database connection errors
- Transaction failures
- Metadata insertion errors

**How to check logs:**
```bash
# Kubernetes
kubectl logs -f statefulset/postgresql -n onyx

# Docker Compose
docker compose logs -f relational_db

# Search for errors
kubectl logs statefulset/postgresql -n onyx | grep -i "error\|failed\|timeout"
```

**What to look for:**
- `Connection refused`
- `Transaction rollback`
- `Deadlock detected`
- Database lock errors

---

### 6. 🟣 **Redis** (Queue Errors)

**Service Name (Kubernetes):** `redis` or `onyx-redis`

**When to check:**
- Task queue failures
- Redis connection errors
- Task not being picked up

**How to check logs:**
```bash
# Kubernetes
kubectl logs -f deployment/redis -n onyx

# Docker Compose
docker compose logs -f cache

# Check queue status
kubectl exec deployment/redis -n onyx -- redis-cli LLEN user_file_processing
```

**What to look for:**
- Connection errors
- Queue overflow
- Task not dequeued

---

### 7. ⚪ **Vespa** (Indexing Errors - If Document Reaches This Stage)

**Service Name (Kubernetes):** `vespa` or `onyx-vespa`

**When to check:**
- Vector indexing failures
- Vespa connection errors
- Index write errors

**How to check logs:**
```bash
# Kubernetes
kubectl logs -f statefulset/vespa -n onyx

# Docker Compose
docker compose logs -f index

# Search for errors
kubectl logs statefulset/vespa -n onyx | grep -i "error\|failed\|rejected"
```

**What to look for:**
- `Failed to index document`
- `Connection refused`
- Index quota errors

---

## Quick Diagnostic Commands

### Check All Services at Once
```bash
# Kubernetes - All services
kubectl get pods -n onyx | grep -E "api-server|background|indexing-model-server|minio"

# Check logs for specific time period
kubectl logs deployment/api-server -n onyx --since=10m
kubectl logs deployment/background-workers -n onyx --since=10m
```

### Search for Your Specific File
```bash
# Replace <filename> with your actual file name
kubectl logs -l app=api-server -n onyx | grep -i "<filename>"
kubectl logs -l app=background-workers -n onyx | grep -i "<filename>"
```

### Check for Common Error Patterns
```bash
# Search across all pods
kubectl logs -l app=api-server -n onyx | grep -E "ERROR|FAILED|Exception|Traceback"
kubectl logs -l app=background-workers -n onyx | grep -E "ERROR|FAILED|Exception|Traceback"
```

---

## Error Scenarios and Where to Check

### Scenario 1: File Too Large (413 Error)
**Check:** API Server logs
```bash
kubectl logs deployment/api-server -n onyx | grep -i "413\|client_max_body_size\|too large"
```

### Scenario 2: Document Processing Failed
**Check:** Background Workers logs
```bash
kubectl logs deployment/background-workers -n onyx | grep -i "process_single_user_file\|Indexing pipeline failed"
```

### Scenario 3: Out of Memory
**Check:** Background Workers + Indexing Model Server
```bash
kubectl logs deployment/background-workers -n onyx | grep -i "oom\|out of memory"
kubectl logs deployment/indexing-model-server -n onyx | grep -i "oom\|out of memory"
```

### Scenario 4: Storage Full
**Check:** MinIO logs
```bash
kubectl logs deployment/minio -n onyx | grep -i "no space\|disk full"
```

### Scenario 5: Task Stuck in Queue
**Check:** Redis + Background Workers
```bash
# Check queue length
kubectl exec deployment/redis -n onyx -- redis-cli LLEN user_file_processing

# Check worker status
kubectl logs deployment/background-workers -n onyx | tail -100
```

---

## Log File Locations (Inside Pods)

If you need to check log files directly inside containers:

**API Server:**
- Container logs: `stdout/stderr` (captured by kubectl logs)
- Application logs: `/var/log/onyx/` (if configured)

**Background Workers:**
- `/var/log/celery_worker_background.log`
- `/var/log/celery_worker_user_file_processing.log`
- `/var/log/celery_worker_docprocessing.log`

**Access inside pod:**
```bash
# Enter pod
kubectl exec -it deployment/background-workers -n onyx -- /bin/bash

# View logs
tail -f /var/log/celery_worker_user_file_processing.log
```

---

## Summary: Check Order for Large Document Upload

1. **First:** API Server logs (upload validation, initial errors)
2. **Second:** Background Workers logs (processing errors, indexing failures)
3. **Third:** Indexing Model Server logs (embedding generation errors)
4. **Fourth:** MinIO logs (storage errors)
5. **Fifth:** PostgreSQL logs (database errors)
6. **Sixth:** Redis logs (queue errors)
7. **Last:** Vespa logs (final indexing errors)

**Most Common Issues:**
- Large files → Check API Server (size limits) + Background Workers (memory/timeout)
- Processing failures → Check Background Workers
- Memory issues → Check Background Workers + Indexing Model Server

---

## Related Documentation

- `FILE-UPLOAD-ERROR-DISPLAY-FIX.md` - How to fix error display in UI
- `CONNECTORS-FILE-TROUBLESHOOTING.md` - File connector stuck issues
- Architecture Diagram - Complete service overview

