# Onyx Internal Search Explained & Deleted Files Reappearing - Troubleshooting Guide

This document explains how Onyx's internal search works and provides step-by-step solutions for when deleted files reappear in search results.

---

## Table of Contents

1. [How Onyx Internal Search Works](#how-onyx-internal-search-works)
2. [The Search Flow (Step-by-Step)](#the-search-flow-step-by-step)
3. [Why Deleted Files Reappear](#why-deleted-files-reappear)
4. [Step-by-Step Troubleshooting](#step-by-step-troubleshooting)
5. [Solutions](#solutions)
6. [Prevention](#prevention)

---

## How Onyx Internal Search Works

### Simple Explanation

Onyx uses **semantic search** to find relevant documents. Think of it like this:

1. **You ask a question** → "What is the company vacation policy?"
2. **Onyx converts your question to numbers** (an embedding vector)
3. **Onyx searches its database** (Vespa) for documents with similar number patterns
4. **Onyx returns the most relevant chunks** that match your question

### The Components

```
┌─────────────────────────────────────────────────────────┐
│                    USER QUESTION                         │
│  "What is the vacation policy?"                          │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
        ┌───────────────────────────────┐
        │   EMBEDDING MODEL              │
        │  (Converts question to        │
        │   numerical vector)            │
        └──────────┬────────────────────┘
                   │
                   ▼
        ┌───────────────────────────────┐
        │   VESPA (Vector Search)       │
        │  (Finds similar embeddings)   │
        │                               │
        │  Searches through all         │
        │  document chunks stored       │
        │  in the index                 │
        └──────────┬────────────────────┘
                   │
                   ▼
        ┌───────────────────────────────┐
        │   POSTGRESQL DATABASE          │
        │  (Stores document metadata)   │
        │                               │
        │  - document table             │
        │  - search_doc table           │
        │  - user_file table            │
        └──────────┬────────────────────┘
                   │
                   ▼
        ┌───────────────────────────────┐
        │   ACCESS CONTROL FILTERS       │
        │  (Checks user permissions)    │
        └──────────┬────────────────────┘
                   │
                   ▼
        ┌───────────────────────────────┐
        │   RERANKING                   │
        │  (Sorts by relevance)         │
        └──────────┬────────────────────┘
                   │
                   ▼
        ┌───────────────────────────────┐
        │   SEARCH RESULTS               │
        │  (Top relevant chunks)         │
        └───────────────────────────────┘
```

---

## The Search Flow (Step-by-Step)

### Step 1: User Initiates Search

**What happens:**
- User types a question in the chat interface
- Frontend sends request to `/api/document-search` or `/api/chat`
- Backend receives the search query

**Code location:**
- `backend/ee/onyx/server/query_and_chat/query_backend.py` → `handle_search_request()`

### Step 2: Query Processing

**What happens:**
- Onyx creates a `SearchPipeline` object
- The query is analyzed and potentially rewritten
- Filters are applied (user permissions, document sets, tags, etc.)

**Code location:**
- `backend/onyx/context/search/pipeline.py` → `SearchPipeline` class

### Step 3: Embedding Generation

**What happens:**
- The user's question is converted to an embedding vector
- This vector represents the "meaning" of the question

**Example:**
```
Question: "What is the vacation policy?"
Embedding: [0.23, -0.45, 0.67, 0.12, ..., 0.89] (384 or 512 numbers)
```

### Step 4: Vector Search in Vespa

**What happens:**
- Onyx sends the embedding to Vespa
- Vespa searches its index for document chunks with similar embeddings
- Vespa returns the top N most relevant chunks

**Code location:**
- `backend/onyx/document_index/vespa/index.py` → `id_based_retrieval()` or similar methods

**Important:** Vespa only searches what's in its index. If a document was deleted from the database but **not** from Vespa, it will still appear in search results!

### Step 5: Database Lookup

**What happens:**
- For each chunk returned by Vespa, Onyx looks up metadata in PostgreSQL
- Checks if the document exists in the `document` or `user_file` table
- Verifies user has access to the document

**Code location:**
- `backend/onyx/context/search/retrieval/search_runner.py` → `doc_index_retrieval()`

### Step 6: Access Control Filtering

**What happens:**
- Onyx checks if the user has permission to see each document
- Filters out documents the user shouldn't access
- Applies document set filters, tag filters, etc.

**Code location:**
- `backend/onyx/context/search/preprocessing/access_filters.py` → `build_access_filters_for_user()`

### Step 7: Reranking

**What happens:**
- Results are sorted by relevance score
- Cross-encoder model may be used for better ranking
- Duplicates are removed

**Code location:**
- `backend/onyx/context/search/postprocessing/postprocessing.py`

### Step 8: Return Results

**What happens:**
- Final list of document chunks is returned to the user
- Results are displayed in the UI

---

## Why Deleted Files Reappear

### The Problem: Two Separate Systems

Onyx uses **two separate storage systems**:

1. **PostgreSQL Database** - Stores document metadata, user files, relationships
2. **Vespa Index** - Stores document chunks and embeddings for fast search

**The Issue:**
When you delete a file, Onyx needs to delete it from **BOTH** systems. If deletion fails in Vespa (or is delayed), the document will still appear in search results even though it's deleted from the database.

### Common Scenarios

#### Scenario 1: Vespa Deletion Failed

**What happens:**
```
1. User deletes file → Database record deleted ✓
2. Celery task tries to delete from Vespa → FAILS ✗
3. Vespa still has the chunks in its index
4. Search queries Vespa → Finds deleted document chunks
5. User sees deleted file in search results
```

**Why it fails:**
- Vespa service is down or unreachable
- Network timeout
- Vespa returns 429 (too many requests)
- Authentication/authorization error

#### Scenario 2: Deletion Task Not Executed

**What happens:**
```
1. User deletes file → Database record deleted ✓
2. Celery task is queued but never runs
3. Vespa still has the chunks
4. Search finds them
```

**Why it doesn't run:**
- Celery worker is down
- Task queue is full
- Task failed and exhausted retries
- Redis connection issue

#### Scenario 3: Secondary Index Not Updated

**What happens:**
```
1. User deletes file → Primary Vespa index updated ✓
2. Secondary index (if configured) not updated ✗
3. Search uses secondary index → Finds deleted document
```

**Why it happens:**
- Secondary index deletion code path not executed
- Configuration issue with multiple indexes

#### Scenario 4: Cache/Stale Data

**What happens:**
```
1. File deleted from both DB and Vespa ✓
2. Search results cached in Redis
3. User sees cached (stale) results
```

**Why it happens:**
- Redis cache not invalidated
- Cache TTL too long
- Search results cached before deletion

---

## Step-by-Step Troubleshooting

### Step 1: Verify the File is Actually Deleted from Database

**Check PostgreSQL:**

```sql
-- Check if user_file record exists
SELECT id, name, status, deleted_at 
FROM user_file 
WHERE id = '<file_id>'::uuid;

-- Check if document record exists
SELECT id, name 
FROM document 
WHERE id = '<document_id>';

-- Check search_doc table
SELECT id, document_id 
FROM search_doc 
WHERE document_id = '<document_id>';
```

**Expected result:** All queries should return 0 rows (file is deleted)

**If rows exist:** The deletion didn't complete. Check Celery task logs.

---

### Step 2: Check if File Still Exists in Vespa

**Query Vespa directly:**

```bash
# Get Vespa endpoint
kubectl get svc vespa -n <namespace>

# Query Vespa for the document
curl -X POST "http://<vespa-endpoint>:8080/search/" \
  -H "Content-Type: application/json" \
  -d '{
    "yql": "select * from sources * where document_id = \"<file_id>\"",
    "hits": 10
  }'
```

**Expected result:** `"hits": []` (no results)

**If hits exist:** The document is still in Vespa. Proceed to Step 3.

---

### Step 3: Check Celery Task Status

**Check if deletion task ran:**

```bash
# Check Celery worker logs
kubectl logs -f deployment/celery-worker-user-file-processing -n <namespace> | grep "process_single_user_file_delete"

# Check for errors
kubectl logs deployment/celery-worker-user-file-processing -n <namespace> | grep -i "error\|exception\|failed"
```

**Look for:**
- `process_single_user_file_delete - Starting id=<file_id>`
- `process_single_user_file_delete - Completed id=<file_id>`
- Any error messages

**If task didn't run:** Check Redis, Celery worker status, task queue

**If task failed:** Check the error message and fix the root cause

---

### Step 4: Check Vespa Service Health

**Verify Vespa is running and accessible:**

```bash
# Check Vespa pod status
kubectl get pods -n <namespace> | grep vespa

# Check Vespa logs for errors
kubectl logs <vespa-pod-name> -n <namespace> | tail -100

# Test Vespa connectivity from API server
kubectl exec -it deployment/api-server -n <namespace> -- curl http://vespa:8080/ApplicationStatus
```

**Expected result:** Vespa pod is `Running` and responds to requests

**If Vespa is down:** Restart the pod or check resource limits

---

### Step 5: Check for Secondary Index

**If you have a secondary Vespa index configured:**

```bash
# Check Vespa configuration
kubectl get configmap vespa-config -n <namespace> -o yaml

# Query secondary index
curl -X POST "http://<vespa-endpoint>:8080/search/" \
  -H "Content-Type: application/json" \
  -d '{
    "yql": "select * from sources <secondary_index_name> where document_id = \"<file_id>\"",
    "hits": 10
  }'
```

**If secondary index has the document:** The deletion code may not be handling secondary indexes correctly.

---

### Step 6: Check Redis Cache

**If search results are cached:**

```bash
# Connect to Redis
kubectl exec -it deployment/redis -n <namespace> -- redis-cli

# Search for cached search results (pattern depends on your cache keys)
KEYS *search*<file_id>*
KEYS *document*<file_id>*

# Delete cache entries if found
DEL <cache-key>
```

**Note:** Onyx may not cache search results, but it's worth checking.

---

## Solutions

### Solution 1: Manually Delete from Vespa

**If the file is deleted from DB but still in Vespa:**

```python
# Run this in a Python shell or script
from onyx.document_index.document_index_utils import get_default_document_index
from onyx.db.search_settings import get_active_search_settings
from onyx.db.session import get_session

with get_session() as db_session:
    search_settings = get_active_search_settings(db_session)
    document_index = get_default_document_index(
        search_settings.primary,
        search_settings.secondary,
    )
    
    # Delete the document
    document_index.delete_single(
        doc_id="<file_id>",
        tenant_id="<tenant_id>",
        chunk_count=None,  # Will query Vespa to get count
    )
```

**Or use Vespa API directly:**

```bash
# Delete all chunks for a document
curl -X DELETE "http://<vespa-endpoint>:8080/document/v1/<index_name>/docid/<file_id>"
```

---

### Solution 2: Re-run Deletion Task

**If the Celery task failed, manually trigger it:**

```python
# In Python shell or script
from onyx.background.celery.tasks.user_file_processing.tasks import process_single_user_file_delete

# Trigger the task
process_single_user_file_delete.delay(
    user_file_id="<file_id>",
    tenant_id="<tenant_id>"
)
```

**Or via Celery CLI:**

```bash
# Connect to Celery worker pod
kubectl exec -it deployment/celery-worker-user-file-processing -n <namespace> -- bash

# Trigger task (if you have celery CLI installed)
celery -A onyx.background.celery.app call onyx.background.celery.tasks.user_file_processing.tasks.process_single_user_file_delete \
  --kwargs '{"user_file_id": "<file_id>", "tenant_id": "<tenant_id>"}'
```

---

### Solution 3: Fix Vespa Connection Issues

**If Vespa is unreachable:**

1. **Check network connectivity:**
   ```bash
   # From API server pod
   kubectl exec -it deployment/api-server -n <namespace> -- curl -v http://vespa:8080/ApplicationStatus
   ```

2. **Check Vespa service:**
   ```bash
   kubectl get svc vespa -n <namespace>
   kubectl describe svc vespa -n <namespace>
   ```

3. **Check DNS resolution:**
   ```bash
   kubectl exec -it deployment/api-server -n <namespace> -- nslookup vespa
   ```

4. **Restart Vespa if needed:**
   ```bash
   kubectl rollout restart statefulset/vespa -n <namespace>
   ```

---

### Solution 4: Handle Secondary Index

**If you have a secondary index, ensure deletion code handles it:**

Check the deletion code in:
- `backend/onyx/background/celery/tasks/user_file_processing/tasks.py` → `process_single_user_file_delete()`

It should delete from both primary and secondary indexes. If not, you may need to update the code.

---

### Solution 5: Increase Retry Logic

**If deletions fail due to transient errors, increase retries:**

Check Celery task configuration:
- `backend/onyx/background/celery/tasks/user_file_processing/tasks.py`

Look for:
```python
@shared_task(
    name=OnyxCeleryTask.DELETE_SINGLE_USER_FILE,
    max_retries=3,  # Increase this
    retry_backoff=True,  # Enable exponential backoff
)
```

---

## Prevention

### Best Practices

1. **Monitor Deletion Tasks**
   - Set up alerts for failed Celery tasks
   - Monitor Vespa deletion success rate
   - Log all deletion operations

2. **Health Checks**
   - Ensure Vespa is always accessible
   - Monitor Vespa service health
   - Set up automatic restarts if Vespa fails

3. **Retry Logic**
   - Implement robust retry logic for Vespa deletions
   - Use exponential backoff
   - Log retry attempts

4. **Verification**
   - After deletion, verify document is removed from both DB and Vespa
   - Run periodic cleanup jobs to find orphaned documents
   - Compare DB and Vespa document counts

5. **Error Handling**
   - Catch and log all deletion errors
   - Notify admins of persistent failures
   - Implement fallback deletion mechanisms

---

## Quick Diagnostic Checklist

Use this checklist when investigating deleted files reappearing:

- [ ] File deleted from PostgreSQL `user_file` table?
- [ ] File deleted from PostgreSQL `document` table?
- [ ] File deleted from PostgreSQL `search_doc` table?
- [ ] File deleted from Vespa primary index?
- [ ] File deleted from Vespa secondary index (if configured)?
- [ ] Celery deletion task executed successfully?
- [ ] No errors in Celery worker logs?
- [ ] Vespa service is healthy and accessible?
- [ ] No cached search results in Redis?
- [ ] Deletion happened more than 5 minutes ago (to account for delays)?

---

## Summary

**The Root Cause:**
Deleted files reappear because Onyx uses two separate systems (PostgreSQL and Vespa), and deletion must succeed in both. If Vespa deletion fails or is delayed, search will still find the document.

**The Solution:**
1. Verify deletion in both systems
2. Check Celery task logs for failures
3. Manually delete from Vespa if needed
4. Fix underlying issues (Vespa connectivity, task queue, etc.)
5. Implement monitoring and retry logic

**Prevention:**
- Monitor deletion tasks
- Ensure Vespa is always healthy
- Implement robust error handling and retries
- Run periodic cleanup jobs

---

This guide should help you diagnose and fix the issue of deleted files reappearing in search. If problems persist, check the specific error messages in Celery logs and Vespa logs to identify the root cause.

