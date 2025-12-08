# File Deletion Process in Onyx - Complete Guide

## 📚 Overview

When you delete a file in Onyx, it's not as simple as clicking "Delete" and it's gone. Onyx stores file data in **multiple systems**, and all of them need to be cleaned up. This guide explains the entire process step-by-step.

---

## 🏗️ Architecture: Where Files Are Stored

Before understanding deletion, you need to know where files live:

```
┌─────────────────────────────────────────────────────────────┐
│                    USER UPLOADS FILE                         │
└──────────────────────┬───────────────────────────────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │  1. PostgreSQL Database       │  ← File metadata
        │     - user_file table         │     (name, status, owner)
        │     - project associations    │
        └──────────────┬───────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │  2. MinIO/S3 Storage          │  ← Actual file content
        │     - Original file bytes    │     (PDF, DOCX, etc.)
        │     - Plaintext version      │
        └──────────────┬───────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │  3. Vespa Vector Store        │  ← Search index
        │     - Document chunks        │     (text split into pieces)
        │     - Embedding vectors      │     (AI representations)
        │     - Metadata               │
        └──────────────────────────────┘
```

**Why Multiple Systems?**
- **PostgreSQL**: Fast metadata queries, relationships, access control
- **MinIO/S3**: Efficient file storage, large files
- **Vespa**: Fast semantic search, similarity matching

---

## 🔄 The Deletion Process: Step-by-Step

### Step 1: User Initiates Deletion

**What Happens:**
```
User clicks "Delete" button in UI
    ↓
Frontend calls: DELETE /api/user/projects/file/{file_id}
    ↓
API Server receives request
```

**Technical Details:**
- **Endpoint**: `DELETE /api/user/projects/file/{file_id}`
- **Location**: `backend/onyx/server/features/projects/api.py`
- **Authentication**: User must own the file

---

### Step 2: API Server Validates Request

**What Happens:**
```python
# Check if file exists and user owns it
user_file = db_session.query(UserFile).filter(
    UserFile.id == file_id,
    UserFile.user_id == user_id
).one_or_none()

if not user_file:
    return 404 "File not found"
```

**Technical Details:**
- Validates file exists in PostgreSQL
- Checks user ownership
- Returns 404 if file doesn't exist or user doesn't own it

---

### Step 3: Check for Associations

**What Happens:**
```python
# Check if file is linked to projects or assistants
project_names = [project.name for project in user_file.projects]
assistant_names = [assistant.name for assistant in user_file.assistants]

if project_names or assistant_names:
    # File is in use - return warning
    return {
        "has_associations": True,
        "project_names": project_names,
        "assistant_names": assistant_names
    }
```

**Why This Matters:**
- Files linked to projects/assistants can't be deleted immediately
- User must unlink them first
- Prevents breaking references

**If No Associations:**
- Proceed to deletion

---

### Step 4: Mark File as DELETING

**What Happens:**
```python
# Change status to DELETING (not deleted yet!)
user_file.status = UserFileStatus.DELETING
db_session.commit()
```

**Why Not Delete Immediately?**
- Deletion from Vespa takes time (can fail)
- Need to track deletion status
- Allows retry if deletion fails

**Status Flow:**
```
PROCESSING → COMPLETED → DELETING → (deleted from DB)
```

---

### Step 5: Enqueue Background Deletion Task

**What Happens:**
```python
# Send task to Celery worker (background job)
task = client_app.send_task(
    OnyxCeleryTask.DELETE_SINGLE_USER_FILE,
    kwargs={
        "user_file_id": str(user_file.id),
        "tenant_id": tenant_id
    },
    queue=OnyxCeleryQueues.USER_FILE_DELETE,
    priority=OnyxCeleryPriority.HIGH,
)
```

**Technical Details:**
- **Celery**: Python task queue system
- **Redis**: Stores task queue
- **Worker**: Background process that executes tasks
- **Async**: API returns immediately, deletion happens in background

**Why Background?**
- Deletion can take 5-30 seconds
- Don't want to block user's request
- Can retry if it fails

---

### Step 6: API Returns Success

**What Happens:**
```python
# API returns immediately (doesn't wait for deletion)
return {
    "has_associations": False,
    "project_names": [],
    "assistant_names": []
}
```

**User Experience:**
- UI shows "File deleted" message
- File disappears from UI
- But deletion is still in progress!

---

### Step 7: Celery Worker Picks Up Task

**What Happens:**
```
Redis Queue: [DELETE_SINGLE_USER_FILE: file_id=abc-123]
    ↓
Celery Worker (running in background)
    ↓
Worker picks up task from queue
    ↓
Executes: process_single_user_file_delete()
```

**Technical Details:**
- **Worker Process**: Separate Python process
- **Queue**: Redis list of pending tasks
- **Polling**: Worker checks queue every few seconds
- **Concurrency**: Multiple workers can run simultaneously

---

### Step 8: Acquire Lock (Prevent Duplicate Deletion)

**What Happens:**
```python
# Use Redis lock to prevent multiple workers deleting same file
redis_client = get_redis_client(tenant_id=tenant_id)
file_lock = redis_client.lock(
    f"user_file_delete:{user_file_id}",
    timeout=300  # 5 minutes
)

if not file_lock.acquire(blocking=False):
    # Another worker is already deleting this file
    return None
```

**Why Lock?**
- Multiple workers might pick up same task
- Prevents duplicate deletion attempts
- Ensures atomic operation

---

### Step 9: Verify File Still Exists

**What Happens:**
```python
# Get file from database
user_file = db_session.get(UserFile, user_file_id)

if not user_file:
    # File already deleted by another process
    return None

# Verify it's still in DELETING status
if user_file.status != UserFileStatus.DELETING:
    # File status changed (maybe restored?)
    return None
```

**Why Check?**
- File might have been deleted already
- Status might have changed
- Prevents deleting wrong files

---

### Step 10: Delete from Vespa (Vector Store) - THE CRITICAL STEP

**What Happens:**
```python
# Get Vespa connection
document_index = get_default_document_index(...)
retry_index = RetryDocumentIndex(document_index)

# Count chunks to delete
chunk_count = user_file.chunk_count or 0
if chunk_count == 0:
    # Query Vespa to count chunks
    chunk_count = _get_document_chunk_count(...)

# Delete all chunks from Vespa
retry_index.delete_single(
    doc_id=user_file_id,
    tenant_id=tenant_id,
    chunk_count=chunk_count,
)
```

**What Gets Deleted from Vespa:**
```
Document ID: abc-123
├── Chunk 0: "Introduction to machine learning..." [embedding vector]
├── Chunk 1: "Neural networks are..." [embedding vector]
├── Chunk 2: "Deep learning uses..." [embedding vector]
└── ... (all chunks deleted)
```

**Technical Details:**
- **Vespa API**: HTTP DELETE request to Vespa
- **Chunk Count**: Need to know how many chunks to delete
- **Retry Logic**: If deletion fails, retry automatically
- **Time**: Takes 1-5 seconds depending on chunk count

**Why This Can Fail:**
- Vespa service down
- Network timeout
- Rate limiting (too many requests)
- Authentication error

---

### Step 11: Delete from File Storage (MinIO/S3)

**What Happens:**
```python
file_store = get_default_file_store()

# Delete original file
file_store.delete_file(user_file.file_id)
# Example: "files/abc-123/document.pdf"

# Delete plaintext version (if exists)
file_store.delete_file(
    user_file_id_to_plaintext_file_name(user_file.id)
)
# Example: "files/abc-123/plaintext.txt"
```

**What Gets Deleted:**
- Original uploaded file (PDF, DOCX, etc.)
- Plaintext extracted version (for faster retrieval)

**Technical Details:**
- **MinIO/S3 API**: DELETE object request
- **Two Files**: Original + plaintext version
- **Non-Critical**: If this fails, log warning but continue

**Why Non-Critical?**
- File storage deletion failure doesn't affect search
- Can be cleaned up later
- Main concern is Vespa deletion

---

### Step 12: Delete from PostgreSQL Database

**What Happens:**
```python
# Delete the database record
db_session.delete(user_file)
db_session.commit()
```

**What Gets Deleted:**
```sql
DELETE FROM user_file WHERE id = 'abc-123';
-- Also deletes:
-- - project associations (cascade)
-- - assistant associations (cascade)
```

**Technical Details:**
- **SQL DELETE**: Removes row from `user_file` table
- **Cascade**: Automatically removes related records
- **Commit**: Makes deletion permanent

**Why Last?**
- Only delete from DB after Vespa deletion succeeds
- If Vespa deletion fails, file stays in DB (can retry)
- DB record is the "source of truth"

---

### Step 13: Release Lock and Complete

**What Happens:**
```python
# Release Redis lock
if file_lock.owned():
    file_lock.release()

# Log success
task_logger.info(
    f"Successfully deleted file {user_file_id}"
)
```

**Result:**
- File completely removed from all systems
- Lock released (other operations can proceed)
- Task marked as complete

---

## 🔄 Retry Logic: What If Deletion Fails?

### Automatic Retry

**Configuration:**
```python
@shared_task(
    autoretry_for=(Exception,),
    retry_kwargs={
        'max_retries': 3,      # Try 3 times
        'countdown': 60        # Wait 60 seconds between retries
    }
)
```

**Retry Flow:**
```
Attempt 1: Delete from Vespa → FAILS (timeout)
    ↓ (wait 60 seconds)
Attempt 2: Delete from Vespa → FAILS (service down)
    ↓ (wait 60 seconds)
Attempt 3: Delete from Vespa → SUCCESS ✓
    ↓
Continue with file storage and database deletion
```

**Why Retry?**
- Network issues are temporary
- Vespa might be temporarily unavailable
- Increases chance of successful deletion

---

## 🐛 Common Problems and Solutions

### Problem 1: File Still Appears in Search

**Cause:**
- Vespa deletion failed or was delayed
- Chunks still in Vespa index

**Solution:**
- Search validation filters deleted files (defense in depth)
- Retry logic attempts deletion again
- Manual cleanup script can remove orphaned chunks

### Problem 2: File Stuck in DELETING Status

**Cause:**
- Deletion task failed all retries
- Celery worker crashed
- Redis queue issue

**Solution:**
- Check Celery logs for errors
- Manually trigger deletion task
- Cleanup script to remove stuck files

### Problem 3: Partial Deletion

**Cause:**
- Vespa deleted but file storage failed
- Database deleted but Vespa still has chunks

**Solution:**
- Retry logic handles this
- Cleanup scripts can fix inconsistencies
- Search validation prevents showing deleted files

---

## 📊 Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ 1. USER CLICKS DELETE                                        │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. API SERVER                                                │
│    - Validate request                                        │
│    - Check associations                                      │
│    - Mark status = DELETING                                 │
│    - Enqueue Celery task                                    │
│    - Return success to user                                 │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. REDIS QUEUE                                               │
│    [DELETE_SINGLE_USER_FILE: file_id=abc-123]              │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. CELERY WORKER                                             │
│    - Pick up task from queue                                │
│    - Acquire Redis lock                                     │
│    - Verify file exists                                     │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. DELETE FROM VESPA (Vector Store)                          │
│    - Connect to Vespa                                        │
│    - Count chunks                                            │
│    - Delete all chunks                                      │
│    - Delete embedding vectors                               │
│    ⚠️  IF FAILS: Retry up to 3 times                        │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ 6. DELETE FROM MINIO/S3 (File Storage)                       │
│    - Delete original file                                   │
│    - Delete plaintext version                               │
│    ⚠️  If fails: Log warning, continue                       │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ 7. DELETE FROM POSTGRESQL (Database)                         │
│    - Delete user_file record                                │
│    - Cascade delete associations                            │
│    - Commit transaction                                     │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ 8. RELEASE LOCK & COMPLETE                                   │
│    - Release Redis lock                                     │
│    - Log success                                            │
│    - Task marked complete                                   │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔧 Technical Requirements

### Systems Involved

1. **PostgreSQL Database**
   - Stores file metadata
   - Tracks deletion status
   - Manages relationships

2. **Vespa Vector Store**
   - Stores document chunks
   - Stores embedding vectors
   - Provides search API

3. **MinIO/S3 Storage**
   - Stores original files
   - Stores plaintext versions
   - Object storage API

4. **Redis**
   - Task queue storage
   - Lock management
   - Task coordination

5. **Celery Workers**
   - Background task execution
   - Retry logic
   - Error handling

### API Endpoints

- `DELETE /api/user/projects/file/{file_id}` - Initiate deletion

### Celery Tasks

- `DELETE_SINGLE_USER_FILE` - Execute deletion

### Database Tables

- `user_file` - File metadata
- `project__user_file` - Project associations
- `persona__user_file` - Assistant associations

---

## ⏱️ Timing: How Long Does Deletion Take?

### Typical Timeline

```
0s:    User clicks delete
0.1s:  API marks file as DELETING
0.2s:  API returns success to user
0.5s:  Celery worker picks up task
1s:    Lock acquired, verification done
2-5s:  Delete from Vespa (depends on chunk count)
6s:    Delete from MinIO/S3
7s:    Delete from PostgreSQL
7.1s:  Lock released, task complete
```

**Total Time**: ~7 seconds (mostly Vespa deletion)

### Factors Affecting Speed

- **Chunk Count**: More chunks = longer Vespa deletion
- **Network Latency**: Slower if Vespa is remote
- **Vespa Load**: Busy Vespa = slower response
- **File Size**: Larger files = more chunks

---

## 🎯 Key Takeaways

1. **Deletion is Async**: API returns immediately, deletion happens in background
2. **Multiple Systems**: Must delete from PostgreSQL, Vespa, and MinIO/S3
3. **Vespa is Critical**: If Vespa deletion fails, file still appears in search
4. **Retry Logic**: Automatic retries handle temporary failures
5. **Defense in Depth**: Search validation filters deleted files even if Vespa deletion failed
6. **Status Tracking**: Files marked as DELETING during process
7. **Locking**: Prevents duplicate deletion attempts

---

## 📝 Summary

**Simple Version:**
1. User clicks delete → API marks file as "deleting"
2. Background worker deletes from Vespa (search index)
3. Background worker deletes from file storage
4. Background worker deletes from database
5. File completely removed from all systems

**Why It's Complex:**
- Three separate systems need cleanup
- Vespa deletion can fail (needs retry)
- Must prevent duplicate deletions
- Must handle errors gracefully

---

**Last Updated**: 2024  
**Author**: Onyx Deployment Team  
**Version**: 1.0

