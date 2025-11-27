# Complete Guide: Deleted Files Reappear in Internal Search

## Issue Summary (GitHub Issue #69)

**Problem**: When users delete or unlink files from projects, those files still appear in search results.

**User Reports**:
1. CSV files deleted from projects are still found by the model
2. Different behavior in Project vs Chat
3. HTML files show upload error but still appear in search
4. Once a PDF is added, the model finds files that weren't officially added

---

## Table of Contents

1. [Understanding the Architecture](#1-understanding-the-architecture)
2. [The Data Flow: Step by Step](#2-the-data-flow-step-by-step)
3. [Root Cause Analysis](#3-root-cause-analysis)
4. [Debugging: How to Investigate](#4-debugging-how-to-investigate)
5. [Solutions: Step by Step](#5-solutions-step-by-step)
6. [Best Practices](#6-best-practices)
7. [Quick Reference](#7-quick-reference)

---

## 1. Understanding the Architecture

### 1.1 What is a Project?

A **Project** is a persistent workspace where:
- Files are stored permanently
- Multiple chat sessions share the same files
- Files remain available across sessions

**Example**: You create a project called "Q4 Reports" and add 5 PDF files. Every chat in this project can access all 5 files.

### 1.2 What is a Chat?

A **Chat** is a single conversation where:
- Files are attached to individual messages
- Files are temporary (per-message)
- No persistence across sessions

**Example**: You start a new chat and attach a PDF. That PDF is only available in that specific message.

### 1.3 The Two Storage Layers

Onyx uses **two separate storage systems** that must stay synchronized:

```
+---------------------------+     +---------------------------+
|      PostgreSQL           |     |         Vespa             |
|      (Metadata)           |     |      (Search Index)       |
+---------------------------+     +---------------------------+
|                           |     |                           |
| - user_file table         |     | - Document chunks         |
| - project__user_file      |     | - Embeddings              |
| - File ownership          |     | - user_project field      |
| - Project associations    |     | - Access control          |
|                           |     |                           |
+---------------------------+     +---------------------------+
           |                                   |
           |     MUST BE SYNCHRONIZED          |
           +-----------------------------------+
```

### 1.4 Key Database Tables

```sql
-- User's uploaded files
CREATE TABLE user_file (
    id UUID PRIMARY KEY,
    user_id UUID,
    name VARCHAR,
    status VARCHAR,           -- PROCESSING, COMPLETED, DELETING
    needs_project_sync BOOL,  -- Flag for pending Vespa updates
    chunk_count INT           -- Number of chunks in Vespa
);

-- Link between projects and files (many-to-many)
CREATE TABLE project__user_file (
    project_id INT,
    user_file_id UUID
);

-- Projects
CREATE TABLE user_project (
    id INT PRIMARY KEY,
    user_id UUID,
    name VARCHAR
);
```

### 1.5 Vespa Document Structure

Each document chunk in Vespa has:

```yaml
document_id: "abc-123-def"      # Same as user_file.id
chunk_id: 0                      # Chunk number (0, 1, 2...)
content: "The actual text..."
user_project: [1, 5, 12]        # Array of project IDs this file belongs to
access_control_list: [...]       # Who can access this file
hidden: false
```

**Key Point**: The `user_project` field in Vespa determines which projects can "see" this file in search.

---

## 2. The Data Flow: Step by Step

### 2.1 When You Upload a File to a Project

```
Step 1: User uploads file.csv to Project "Sales Data"
        |
        v
Step 2: API Server receives file
        |
        +---> PostgreSQL: INSERT INTO user_file (id='abc', name='file.csv', status='PROCESSING')
        +---> PostgreSQL: INSERT INTO project__user_file (project_id=5, user_file_id='abc')
        +---> MinIO: Store the actual file bytes
        |
        v
Step 3: Celery Worker picks up the indexing task
        |
        +---> Extract text from file
        +---> Split into chunks
        +---> Generate embeddings
        +---> Vespa: INSERT chunks with user_project=[5]
        |
        v
Step 4: PostgreSQL: UPDATE user_file SET status='COMPLETED', chunk_count=10
```

### 2.2 When You UNLINK a File from a Project

This is where the bug can occur:

```
Step 1: User clicks "Remove from Project" for file.csv
        |
        v
Step 2: API Server handles DELETE /projects/5/files/abc
        |
        +---> PostgreSQL: DELETE FROM project__user_file WHERE project_id=5 AND user_file_id='abc'
        +---> PostgreSQL: UPDATE user_file SET needs_project_sync=TRUE
        +---> Celery: ENQUEUE task PROCESS_SINGLE_USER_FILE_PROJECT_SYNC
        |
        v
Step 3: Celery Worker (ASYNC) processes the sync task
        |
        +---> Read current projects: user_file.projects = []  (empty now)
        +---> Vespa: UPDATE chunks SET user_project=[]
        +---> PostgreSQL: UPDATE user_file SET needs_project_sync=FALSE
```

**THE PROBLEM**: Step 3 happens **asynchronously**. If it fails, is delayed, or never runs, Vespa still has `user_project=[5]`.

### 2.3 When You Search in a Project

```
Step 1: User types "sales data" in Project 5
        |
        v
Step 2: Build Vespa Query
        |
        +---> Filter: user_project contains "5"
        +---> Filter: access_control_list contains user_id
        +---> Query: semantic search for "sales data"
        |
        v
Step 3: Vespa returns matching chunks
        |
        +---> If Vespa still has user_project=[5] for file.csv (sync failed)
        +---> file.csv chunks are returned!
        |
        v
Step 4: User sees file.csv in results (BUG!)
```

---

## 3. Root Cause Analysis

### 3.1 Root Cause #1: Async Vespa Sync Failure

**Location**: `backend/onyx/server/features/projects/api.py` (lines 150-196)

```python
@router.delete("/{project_id}/files/{file_id}")
def unlink_user_file_from_project(...):
    # Step 1: Remove from PostgreSQL (SYNC - immediate)
    project.user_files.remove(user_file)
    user_file.needs_project_sync = True
    db_session.commit()

    # Step 2: Trigger Vespa update (ASYNC - might fail!)
    task = client_app.send_task(
        OnyxCeleryTask.PROCESS_SINGLE_USER_FILE_PROJECT_SYNC,
        kwargs={"user_file_id": user_file.id, "tenant_id": tenant_id},
    )
```

**Problem**: The API returns success (204) immediately after PostgreSQL update, but before Vespa is updated.

### 3.2 Root Cause #2: No Project Filter in Regular Chat

**Location**: `backend/onyx/document_index/vespa/shared_utils/vespa_request_builders.py` (lines 140-150)

```python
def _build_user_project_filter(project_id: int | None) -> str:
    if project_id is None:
        return ""  # NO FILTER! All user files are searchable!
    return f'({USER_PROJECT} contains "{pid}") and '
```

**Problem**: When searching in a regular chat (no project), there's no filter on `user_project`. All user files are searchable.

### 3.3 Root Cause #3: Failed Upload Still Indexed

**Location**: `backend/onyx/background/celery/tasks/user_file_processing/tasks.py`

**Scenario**:
1. User uploads file.csv
2. File is indexed in Vespa
3. Validation fails (wrong file type)
4. Error shown to user
5. File remains in Vespa!

---

## 4. Debugging: How to Investigate

### 4.1 Check PostgreSQL State

```bash
# Connect to PostgreSQL pod
kubectl exec -it <postgres-pod> -- psql -U postgres -d postgres
```

```sql
-- Check if file is linked to any project
SELECT 
    uf.id,
    uf.name,
    uf.status,
    uf.needs_project_sync,
    uf.last_project_sync_at,
    puf.project_id
FROM user_file uf
LEFT JOIN project__user_file puf ON uf.id = puf.user_file_id
WHERE uf.name LIKE '%your_file_name%';

-- Example output showing the BUG:
-- id       | name     | status    | needs_project_sync | project_id
-- abc-123  | file.csv | COMPLETED | TRUE               | NULL
--                                   ^^^^                  ^^^^
--                                   Sync pending!         Not linked!
```

```sql
-- Check for files with pending sync
SELECT id, name, needs_project_sync, last_project_sync_at
FROM user_file
WHERE needs_project_sync = TRUE;

-- If you see files here, Vespa is out of sync!
```

### 4.2 Check Vespa State

```bash
# Port-forward to Vespa
kubectl port-forward svc/vespa 8080:8080

# Query Vespa directly
curl -X POST "http://localhost:8080/search/" \
  -H "Content-Type: application/json" \
  -d '{
    "yql": "select documentid, document_id, user_project from onyx_chunk where document_id contains \"abc-123\" limit 10"
  }'
```

**Expected response if properly unlinked**:
```json
{
  "root": {
    "children": [
      {
        "fields": {
          "document_id": "abc-123",
          "user_project": []  // Empty! Good!
        }
      }
    ]
  }
}
```

**Response showing the BUG**:
```json
{
  "root": {
    "children": [
      {
        "fields": {
          "document_id": "abc-123",
          "user_project": [5]  // Still has project 5! BAD!
        }
      }
    ]
  }
}
```

### 4.3 Check Celery Task Status

```bash
# Check Redis for pending tasks
kubectl exec -it <redis-pod> -- redis-cli

# List pending tasks
LRANGE celery 0 -1

# Check for failed tasks (if using result backend)
KEYS celery-task-meta-*
```

### 4.4 Check Celery Worker Logs

```bash
# Check user file processing worker logs
kubectl logs -f deployment/celery-worker-user-file-processing

# Look for:
# - "process_single_user_file_project_sync - Starting"
# - "process_single_user_file_project_sync - Completed"
# - Any exceptions or errors
```

---

## 5. Solutions: Step by Step

### Solution 1: Fix Pending Syncs (Immediate Fix)

**What it does**: Manually trigger sync for all files with `needs_project_sync=TRUE`

**Step 1**: Create a script to find and fix pending syncs

```python
# fix_pending_syncs.py
from sqlalchemy import create_engine, text
from celery import Celery

# Configure these
DATABASE_URL = "postgresql://user:pass@postgres:5432/onyx"
REDIS_URL = "redis://redis:6379/0"

engine = create_engine(DATABASE_URL)
celery_app = Celery(broker=REDIS_URL)

with engine.connect() as conn:
    # Find all files needing sync
    result = conn.execute(text("""
        SELECT id, name FROM user_file 
        WHERE needs_project_sync = TRUE 
        AND status = 'COMPLETED'
    """))
    
    for row in result:
        file_id, name = row
        print(f"Triggering sync for: {name} ({file_id})")
        
        # Trigger the sync task
        celery_app.send_task(
            "check_for_user_file_project_sync",
            kwargs={"user_file_id": str(file_id), "tenant_id": "public"}
        )
```

**Step 2**: Run the script

```bash
kubectl exec -it <api-server-pod> -- python fix_pending_syncs.py
```

### Solution 2: Add Retry Logic (Code Fix)

**What it does**: Ensure Vespa sync retries on failure

**File**: `backend/onyx/background/celery/tasks/user_file_processing/tasks.py`

**Change**: Add retry decorator to the sync task

```python
# BEFORE
@shared_task(
    name=OnyxCeleryTask.PROCESS_SINGLE_USER_FILE_PROJECT_SYNC,
    bind=True,
    ignore_result=True,
)
def process_single_user_file_project_sync(self: Task, *, user_file_id: str, tenant_id: str):
    ...

# AFTER
@shared_task(
    name=OnyxCeleryTask.PROCESS_SINGLE_USER_FILE_PROJECT_SYNC,
    bind=True,
    ignore_result=True,
    autoretry_for=(Exception,),  # Retry on any exception
    retry_backoff=True,           # Exponential backoff
    retry_backoff_max=300,        # Max 5 minutes between retries
    max_retries=5,                # Try up to 5 times
)
def process_single_user_file_project_sync(self: Task, *, user_file_id: str, tenant_id: str):
    ...
```

### Solution 3: Add Periodic Sync Check (Best Practice)

**What it does**: Periodically check for and fix out-of-sync files

**File**: `backend/onyx/background/celery/celery_app.py`

**Add to beat schedule**:

```python
# Add this to CELERY_BEAT_SCHEDULE
"check-user-file-project-sync": {
    "task": OnyxCeleryTask.CHECK_FOR_USER_FILE_PROJECT_SYNC,
    "schedule": crontab(minute="*/5"),  # Every 5 minutes
    "kwargs": {"tenant_id": "public"},
},
```

**Note**: This task already exists! Check if it's running:

```bash
kubectl logs -f deployment/celery-beat | grep "user_file_project_sync"
```

### Solution 4: Synchronous Vespa Update (Most Reliable)

**What it does**: Update Vespa immediately during the API call (blocking)

**File**: `backend/onyx/server/features/projects/api.py`

```python
# BEFORE (async)
@router.delete("/{project_id}/files/{file_id}")
def unlink_user_file_from_project(...):
    project.user_files.remove(user_file)
    user_file.needs_project_sync = True
    db_session.commit()
    
    # Async task (might fail)
    task = client_app.send_task(...)
    return Response(status_code=204)

# AFTER (sync)
@router.delete("/{project_id}/files/{file_id}")
def unlink_user_file_from_project(...):
    project.user_files.remove(user_file)
    db_session.commit()
    
    # Sync update to Vespa (blocking)
    try:
        active_search_settings = get_active_search_settings(db_session)
        document_index = get_default_document_index(
            search_settings=active_search_settings.primary,
            secondary_search_settings=active_search_settings.secondary,
        )
        retry_index = RetryDocumentIndex(document_index)
        
        project_ids = [p.id for p in user_file.projects]
        retry_index.update_single(
            doc_id=str(user_file.id),
            tenant_id=get_current_tenant_id(),
            chunk_count=user_file.chunk_count,
            fields=None,
            user_fields=VespaDocumentUserFields(user_projects=project_ids),
        )
        
        user_file.needs_project_sync = False
        db_session.commit()
    except Exception as e:
        logger.error(f"Failed to sync Vespa: {e}")
        user_file.needs_project_sync = True
        db_session.commit()
        # Still trigger async task as backup
        client_app.send_task(...)
    
    return Response(status_code=204)
```

**Trade-off**: Slower API response (~100-500ms) but guaranteed consistency.

### Solution 5: Filter User Files in Chat (Isolation Fix)

**What it does**: Prevent unlinked files from appearing in regular chat search

**File**: `backend/onyx/document_index/vespa/shared_utils/vespa_request_builders.py`

```python
# BEFORE
def _build_user_project_filter(project_id: int | None) -> str:
    if project_id is None:
        return ""  # No filter!
    return f'({USER_PROJECT} contains "{pid}") and '

# AFTER
def _build_user_project_filter(
    project_id: int | None,
    user_file_ids: list[str] | None = None,
) -> str:
    if project_id is not None:
        # Project search: only files in this project
        return f'({USER_PROJECT} contains "{project_id}") and '
    
    if user_file_ids:
        # Chat with specific files: only those files
        return ""  # Already filtered by user_file_ids
    
    # Regular chat without specific files: exclude user files entirely
    # Only search connector-ingested documents
    return f'({SOURCE_TYPE} != "user_file") and '
```

---

## 6. Best Practices

### 6.1 Monitoring

Add these monitoring checks:

```yaml
# Prometheus/Grafana alert
- alert: PendingVespaSyncs
  expr: count(user_file_needs_project_sync == 1) > 10
  for: 15m
  labels:
    severity: warning
  annotations:
    summary: "{{ $value }} files pending Vespa sync for >15 minutes"
```

### 6.2 Logging

Ensure these logs are captured:

```python
# In process_single_user_file_project_sync
logger.info(f"Starting project sync for file {user_file_id}")
logger.info(f"Updating Vespa with projects: {project_ids}")
logger.info(f"Completed project sync for file {user_file_id}, chunks affected: {chunks_affected}")
```

### 6.3 Health Check Endpoint

Add an endpoint to check sync status:

```python
@router.get("/health/vespa-sync")
def check_vespa_sync_health(db_session: Session = Depends(get_session)):
    pending_count = db_session.query(UserFile).filter(
        UserFile.needs_project_sync == True
    ).count()
    
    stale_count = db_session.query(UserFile).filter(
        UserFile.needs_project_sync == True,
        UserFile.last_project_sync_at < datetime.now() - timedelta(minutes=10)
    ).count()
    
    return {
        "pending_syncs": pending_count,
        "stale_syncs": stale_count,  # Pending for >10 minutes
        "healthy": stale_count == 0
    }
```

### 6.4 Data Consistency Check Script

Run periodically to verify consistency:

```python
# check_consistency.py
def check_postgres_vespa_consistency():
    with get_session() as db_session:
        # Get all completed user files
        user_files = db_session.query(UserFile).filter(
            UserFile.status == UserFileStatus.COMPLETED
        ).all()
        
        inconsistencies = []
        
        for uf in user_files:
            # Get expected projects from PostgreSQL
            pg_projects = set(p.id for p in uf.projects)
            
            # Get actual projects from Vespa
            vespa_response = query_vespa(f"document_id contains '{uf.id}'")
            vespa_projects = set(vespa_response.get("user_project", []))
            
            if pg_projects != vespa_projects:
                inconsistencies.append({
                    "file_id": str(uf.id),
                    "file_name": uf.name,
                    "postgres_projects": list(pg_projects),
                    "vespa_projects": list(vespa_projects),
                })
        
        return inconsistencies
```

---

## 7. Quick Reference

### 7.1 Summary Table

| Problem | Root Cause | Solution | Effort |
|---------|------------|----------|--------|
| Files reappear after unlink | Async Vespa sync fails | Add retry logic | Low |
| Sync never completes | Celery task not running | Check beat schedule | Low |
| Files visible in all chats | No project filter in chat | Add source filter | Medium |
| Failed uploads still indexed | Index before validation | Validate before index | Medium |

### 7.2 Key Files to Check

| File | Purpose |
|------|---------|
| `backend/onyx/server/features/projects/api.py` | Unlink/delete endpoints |
| `backend/onyx/background/celery/tasks/user_file_processing/tasks.py` | Sync tasks |
| `backend/onyx/document_index/vespa/shared_utils/vespa_request_builders.py` | Vespa filters |
| `backend/onyx/chat/user_files/parse_user_files.py` | File loading for chat |

### 7.3 Key Database Queries

```sql
-- Files pending sync
SELECT * FROM user_file WHERE needs_project_sync = TRUE;

-- Files not linked to any project
SELECT uf.* FROM user_file uf
LEFT JOIN project__user_file puf ON uf.id = puf.user_file_id
WHERE puf.project_id IS NULL AND uf.status = 'COMPLETED';

-- Projects with their files
SELECT up.name, uf.name, uf.status
FROM user_project up
JOIN project__user_file puf ON up.id = puf.project_id
JOIN user_file uf ON puf.user_file_id = uf.id
WHERE up.user_id = 'your-user-id';
```

### 7.4 Recommended Fix Priority

1. **Immediate**: Run fix script for pending syncs
2. **Short-term**: Add retry logic to sync task
3. **Medium-term**: Add synchronous Vespa update option
4. **Long-term**: Add monitoring and consistency checks

---

## Appendix: Mermaid Diagrams

### Data Flow Diagram

```mermaid
graph TD
    subgraph "User Action"
        A[User Uploads File] --> B[API Server]
        C[User Removes File from Project] --> D[API Server]
    end
    
    subgraph "Storage Layer"
        B --> E[(PostgreSQL)]
        B --> F[(MinIO)]
        D --> E
    end
    
    subgraph "Async Processing"
        B --> G[Celery Task: Index]
        D --> H[Celery Task: Sync]
        G --> I[(Vespa)]
        H --> I
    end
    
    subgraph "Search"
        J[User Searches] --> K[API Server]
        K --> L{Has Project ID?}
        L -->|Yes| M[Filter: user_project contains project_id]
        L -->|No| N[No Filter - BUG!]
        M --> I
        N --> I
        I --> O[Results]
    end
    
    style H fill:#ff6b6b,stroke:#333
    style N fill:#ff6b6b,stroke:#333
```

### Sync State Diagram

```mermaid
stateDiagram-v2
    [*] --> Uploading: User uploads file
    Uploading --> Processing: File received
    Processing --> Completed: Indexing done
    Completed --> NeedsSync: User unlinks from project
    NeedsSync --> Syncing: Celery picks up task
    Syncing --> Completed: Vespa updated
    Syncing --> NeedsSync: Task fails (retry)
    NeedsSync --> Stale: Task never runs (BUG)
    
    note right of Stale
        This is the bug state!
        PostgreSQL and Vespa are out of sync.
    end note
```

---

This guide should provide everything needed to understand, debug, and fix the "deleted files reappear" issue. Start with the debugging steps to confirm the root cause, then apply the appropriate solution based on your deployment constraints.

