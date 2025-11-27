# Code Changes Explained: Fixing the "Deleted Files Reappear" Bug

This document explains each code change in simple terms, as if explaining to a junior IT professional.

---

## Table of Contents

1. [Understanding the Problem First](#1-understanding-the-problem-first)
2. [Solution 1: Add Retry Logic](#2-solution-1-add-retry-logic)
3. [Solution 2: Synchronous Vespa Update](#3-solution-2-synchronous-vespa-update)
4. [Solution 3: Filter User Files in Chat](#4-solution-3-filter-user-files-in-chat)
5. [How to Apply These Changes](#5-how-to-apply-these-changes)

---

## 1. Understanding the Problem First

### What Happens When You Remove a File from a Project?

Think of it like a library system:

```
PostgreSQL = The library's catalog (list of books and where they belong)
Vespa = The actual bookshelves (where books are physically located)
```

When you remove a book from a section:
1. **Catalog update** (PostgreSQL): "This book is no longer in the Science section" - **INSTANT**
2. **Physical move** (Vespa): Actually moving the book - **TAKES TIME (async)**

**The Bug**: Sometimes step 2 never happens, so the book is still on the Science shelf even though the catalog says it's not there!

---

## 2. Solution 1: Add Retry Logic

### What We're Changing

**File**: `backend/onyx/background/celery/tasks/user_file_processing/tasks.py`

### The Original Code (Before)

```python
@shared_task(
    name=OnyxCeleryTask.PROCESS_SINGLE_USER_FILE_PROJECT_SYNC,
    bind=True,
    ignore_result=True,
)
def process_single_user_file_project_sync(self: Task, *, user_file_id: str, tenant_id: str):
    # ... task code ...
```

### What This Code Does (Simple Explanation)

```
@shared_task(...)  <-- This is a "decorator". It tells Python:
                       "Hey, this function is a Celery task that can run in the background"

name=...           <-- The name of the task (like a label)
bind=True          <-- Allows the task to access itself (self)
ignore_result=True <-- Don't save the result (we don't need it)
```

### The Problem

If this task fails (e.g., Vespa is temporarily down), it just... fails. No retry. The file stays in the wrong state forever.

### The New Code (After)

```python
@shared_task(
    name=OnyxCeleryTask.PROCESS_SINGLE_USER_FILE_PROJECT_SYNC,
    bind=True,
    ignore_result=True,
    # NEW LINES BELOW:
    autoretry_for=(Exception,),   # <-- NEW
    retry_backoff=True,            # <-- NEW
    retry_backoff_max=300,         # <-- NEW
    max_retries=5,                 # <-- NEW
)
def process_single_user_file_project_sync(self: Task, *, user_file_id: str, tenant_id: str):
    # ... task code (unchanged) ...
```

### What Each New Line Does

```python
autoretry_for=(Exception,)
```
**Meaning**: "If ANY error happens, automatically try again"

**Analogy**: Like telling a delivery driver: "If you can't deliver the package, try again later"

---

```python
retry_backoff=True
```
**Meaning**: "Wait longer between each retry"

**Analogy**: 
- 1st retry: Wait 1 second
- 2nd retry: Wait 2 seconds
- 3rd retry: Wait 4 seconds
- ...and so on (doubles each time)

This prevents hammering a server that might be overloaded.

---

```python
retry_backoff_max=300
```
**Meaning**: "Never wait more than 300 seconds (5 minutes) between retries"

**Analogy**: "Even if the math says wait 10 minutes, cap it at 5 minutes"

---

```python
max_retries=5
```
**Meaning**: "Try up to 5 times, then give up"

**Analogy**: "If you can't deliver after 5 attempts, mark it as failed"

---

### Visual: How Retries Work

```
Task starts
    |
    v
[Try 1] --> Success? --> Done!
    |
    No (error)
    |
    Wait 1 second
    |
    v
[Try 2] --> Success? --> Done!
    |
    No (error)
    |
    Wait 2 seconds
    |
    v
[Try 3] --> Success? --> Done!
    |
    No (error)
    |
    Wait 4 seconds
    |
    v
[Try 4] --> Success? --> Done!
    |
    No (error)
    |
    Wait 8 seconds
    |
    v
[Try 5] --> Success? --> Done!
    |
    No (error)
    |
    v
Give up (log error)
```

---

## 3. Solution 2: Synchronous Vespa Update

### What We're Changing

**File**: `backend/onyx/server/features/projects/api.py`

### The Original Code (Before)

```python
@router.delete("/{project_id}/files/{file_id}")
def unlink_user_file_from_project(
    project_id: int,
    file_id: UUID,
    user: User | None = Depends(current_user),
    db_session: Session = Depends(get_session),
) -> Response:
    """Unlink an existing user file from a specific project."""
    
    # ... validation code ...
    
    # Step 1: Remove from PostgreSQL
    project.user_files.remove(user_file)
    user_file.needs_project_sync = True
    db_session.commit()

    # Step 2: Trigger async Vespa update
    task = client_app.send_task(
        OnyxCeleryTask.PROCESS_SINGLE_USER_FILE_PROJECT_SYNC,
        kwargs={"user_file_id": user_file.id, "tenant_id": tenant_id},
        queue=OnyxCeleryQueues.USER_FILE_PROJECT_SYNC,
        priority=OnyxCeleryPriority.HIGHEST,
    )
    
    return Response(status_code=204)
```

### What This Code Does (Line by Line)

```python
@router.delete("/{project_id}/files/{file_id}")
```
**Meaning**: "This function handles DELETE requests to `/projects/5/files/abc-123`"

**Analogy**: Like a receptionist who handles "remove file" requests

---

```python
def unlink_user_file_from_project(
    project_id: int,
    file_id: UUID,
    user: User | None = Depends(current_user),
    db_session: Session = Depends(get_session),
) -> Response:
```
**Meaning**: 
- `project_id`: Which project (e.g., 5)
- `file_id`: Which file (e.g., abc-123)
- `user`: Who is making the request (automatically detected)
- `db_session`: Database connection (automatically provided)
- `-> Response`: This function returns an HTTP response

---

```python
project.user_files.remove(user_file)
user_file.needs_project_sync = True
db_session.commit()
```
**Meaning**:
1. Remove the link between project and file (in memory)
2. Mark the file as "needs to be synced to Vespa"
3. Save changes to PostgreSQL

**Analogy**: 
1. Erase the book from the section's list
2. Put a sticky note: "Move this book!"
3. Save the updated list

---

```python
task = client_app.send_task(
    OnyxCeleryTask.PROCESS_SINGLE_USER_FILE_PROJECT_SYNC,
    kwargs={"user_file_id": user_file.id, "tenant_id": tenant_id},
    ...
)
```
**Meaning**: "Send a message to a background worker: Please update Vespa"

**Problem**: This is ASYNC (asynchronous). The function returns immediately without waiting for Vespa to be updated!

---

### The New Code (After)

```python
@router.delete("/{project_id}/files/{file_id}")
def unlink_user_file_from_project(
    project_id: int,
    file_id: UUID,
    user: User | None = Depends(current_user),
    db_session: Session = Depends(get_session),
) -> Response:
    """Unlink an existing user file from a specific project."""
    
    # ... validation code (same as before) ...
    
    # Step 1: Remove from PostgreSQL
    project.user_files.remove(user_file)
    db_session.commit()  # Note: removed needs_project_sync=True here
    
    # Step 2: Update Vespa SYNCHRONOUSLY (wait for it to complete)
    try:
        # Get the search settings
        active_search_settings = get_active_search_settings(db_session)
        
        # Create a connection to Vespa
        document_index = get_default_document_index(
            search_settings=active_search_settings.primary,
            secondary_search_settings=active_search_settings.secondary,
        )
        retry_index = RetryDocumentIndex(document_index)
        
        # Get the list of projects this file STILL belongs to
        project_ids = [p.id for p in user_file.projects]
        
        # Update Vespa with the new project list
        retry_index.update_single(
            doc_id=str(user_file.id),
            tenant_id=get_current_tenant_id(),
            chunk_count=user_file.chunk_count,
            fields=None,
            user_fields=VespaDocumentUserFields(user_projects=project_ids),
        )
        
        # Mark as synced (no longer needs sync)
        user_file.needs_project_sync = False
        db_session.commit()
        
    except Exception as e:
        # If Vespa update fails, mark for async retry
        logger.error(f"Failed to sync Vespa: {e}")
        user_file.needs_project_sync = True
        db_session.commit()
        
        # Trigger async task as backup
        client_app.send_task(
            OnyxCeleryTask.PROCESS_SINGLE_USER_FILE_PROJECT_SYNC,
            kwargs={"user_file_id": user_file.id, "tenant_id": tenant_id},
        )
    
    return Response(status_code=204)
```

### What Each New Part Does

```python
active_search_settings = get_active_search_settings(db_session)
```
**Meaning**: "Get the current search configuration (which Vespa index to use, etc.)"

**Analogy**: "Check which warehouse we're using today"

---

```python
document_index = get_default_document_index(
    search_settings=active_search_settings.primary,
    secondary_search_settings=active_search_settings.secondary,
)
```
**Meaning**: "Create a connection to Vespa"

**Analogy**: "Open a phone line to the warehouse"

---

```python
retry_index = RetryDocumentIndex(document_index)
```
**Meaning**: "Wrap the connection with automatic retry logic"

**Analogy**: "If the call drops, automatically redial"

---

```python
project_ids = [p.id for p in user_file.projects]
```
**Meaning**: "Get a list of project IDs this file STILL belongs to"

**Example**: 
- Before: File was in projects [1, 5, 12]
- User removed from project 5
- After: `project_ids = [1, 12]`

---

```python
retry_index.update_single(
    doc_id=str(user_file.id),           # Which file to update
    tenant_id=get_current_tenant_id(),  # Which tenant (for multi-tenant)
    chunk_count=user_file.chunk_count,  # How many chunks the file has
    fields=None,                         # Don't update other fields
    user_fields=VespaDocumentUserFields(user_projects=project_ids),  # Update project list
)
```
**Meaning**: "Tell Vespa: This file now belongs to projects [1, 12] instead of [1, 5, 12]"

**Analogy**: "Tell the warehouse: Move this book from sections 1, 5, 12 to just sections 1, 12"

---

```python
except Exception as e:
    logger.error(f"Failed to sync Vespa: {e}")
    user_file.needs_project_sync = True
    db_session.commit()
    
    client_app.send_task(...)
```
**Meaning**: "If Vespa update fails, mark for retry and trigger async task as backup"

**Analogy**: "If the warehouse call fails, leave a note and send a messenger"

---

### Visual: Before vs After

**BEFORE (Async)**:
```
User clicks "Remove" --> API updates PostgreSQL --> API returns "Success" --> (Later) Celery updates Vespa
                                                         |
                                                         |-- User sees success immediately
                                                         |-- But Vespa might not be updated!
```

**AFTER (Sync)**:
```
User clicks "Remove" --> API updates PostgreSQL --> API updates Vespa --> API returns "Success"
                                                         |
                                                         |-- User waits ~100-500ms longer
                                                         |-- But Vespa is DEFINITELY updated!
```

---

## 4. Solution 3: Filter User Files in Chat

### What We're Changing

**File**: `backend/onyx/document_index/vespa/shared_utils/vespa_request_builders.py`

### The Original Code (Before)

```python
def _build_user_project_filter(
    project_id: int | None,
) -> str:
    if project_id is None:
        return ""  # <-- PROBLEM: No filter at all!
    try:
        pid = int(project_id)
    except Exception:
        return ""
    return f'({USER_PROJECT} contains "{pid}") and '
```

### What This Code Does

This function builds a **filter** for Vespa queries. Think of it like a search filter on Amazon:

```
Amazon: "Show me only Electronics in the $50-$100 range"
Vespa:  "Show me only files in Project 5"
```

### The Problem

```python
if project_id is None:
    return ""  # Returns empty string = NO FILTER
```

When you search in a regular chat (no project), `project_id` is `None`, so:
- No filter is applied
- ALL user files are searchable
- Including files you removed from projects!

**Analogy**: It's like searching Amazon without any filters - you see EVERYTHING, including items you removed from your wishlist.

---

### The New Code (After)

```python
def _build_user_project_filter(
    project_id: int | None,
    user_file_ids: list[str] | None = None,  # <-- NEW parameter
) -> str:
    # Case 1: Searching within a specific project
    if project_id is not None:
        try:
            pid = int(project_id)
        except Exception:
            return ""
        return f'({USER_PROJECT} contains "{pid}") and '
    
    # Case 2: Searching with specific files attached to message
    if user_file_ids:
        # Already filtered by user_file_ids elsewhere, no extra filter needed
        return ""
    
    # Case 3: Regular chat without specific files
    # Exclude user-uploaded files, only search connector documents
    return f'({SOURCE_TYPE} != "user_file") and '  # <-- NEW
```

### What Each Part Does

```python
user_file_ids: list[str] | None = None
```
**Meaning**: "Optionally accept a list of specific file IDs"

**Analogy**: "Are there specific books the user wants to search?"

---

```python
if project_id is not None:
    return f'({USER_PROJECT} contains "{pid}") and '
```
**Meaning**: "If searching in a project, only show files in that project"

**Analogy**: "If user is in the Science section, only show Science books"

---

```python
if user_file_ids:
    return ""
```
**Meaning**: "If user attached specific files to their message, don't add extra filters (they're already filtered elsewhere)"

**Analogy**: "If user is holding specific books, just search those"

---

```python
return f'({SOURCE_TYPE} != "user_file") and '
```
**Meaning**: "If no project and no specific files, EXCLUDE all user-uploaded files"

**Analogy**: "If user is just browsing, don't show personal files - only show shared library books"

---

### Visual: How Filtering Works

**BEFORE**:
```
User searches "sales data" in regular chat
    |
    v
Build Vespa query:
    - No project filter (project_id is None)
    - No source filter
    |
    v
Vespa returns:
    - Connector documents (Confluence, Google Drive, etc.)
    - User files (including ones removed from projects!) <-- BUG!
```

**AFTER**:
```
User searches "sales data" in regular chat
    |
    v
Build Vespa query:
    - No project filter (project_id is None)
    - Source filter: source_type != "user_file"  <-- NEW!
    |
    v
Vespa returns:
    - Connector documents (Confluence, Google Drive, etc.)
    - NO user files <-- FIXED!
```

---

## 5. How to Apply These Changes

### Step 1: Locate the Files

```bash
# From your onyx-repo directory
cd backend/onyx

# The files to modify:
# 1. background/celery/tasks/user_file_processing/tasks.py
# 2. server/features/projects/api.py
# 3. document_index/vespa/shared_utils/vespa_request_builders.py
```

### Step 2: Make a Backup

```bash
# Always backup before editing!
cp background/celery/tasks/user_file_processing/tasks.py tasks.py.backup
cp server/features/projects/api.py api.py.backup
cp document_index/vespa/shared_utils/vespa_request_builders.py vespa_request_builders.py.backup
```

### Step 3: Apply Changes

Open each file in your editor and make the changes described above.

### Step 4: Test Locally

```bash
# Run the tests
pytest tests/

# Or run specific tests
pytest tests/unit/test_user_file_processing.py
```

### Step 5: Deploy

```bash
# Build new Docker image
docker build -t your-registry/onyx-backend:fixed .

# Push to registry
docker push your-registry/onyx-backend:fixed

# Update Kubernetes deployment
kubectl set image deployment/api-server api-server=your-registry/onyx-backend:fixed
kubectl set image deployment/celery-worker celery-worker=your-registry/onyx-backend:fixed
```

---

## Summary: What We Fixed

| Solution | What It Does | Why It Helps |
|----------|--------------|--------------|
| **Retry Logic** | Automatically retries failed Vespa updates | If Vespa is temporarily down, it will eventually succeed |
| **Sync Update** | Updates Vespa immediately during API call | Guarantees consistency - user sees correct state |
| **Filter Fix** | Excludes user files from regular chat search | Prevents seeing files you don't have access to |

---

## Glossary

| Term | Simple Explanation |
|------|-------------------|
| **Async** | "Do it later in the background" - doesn't wait for completion |
| **Sync** | "Do it now and wait" - waits for completion |
| **Celery** | A system for running background tasks |
| **Decorator** | `@something` - adds extra behavior to a function |
| **Vespa** | A search engine that stores and searches documents |
| **PostgreSQL** | A database that stores structured data (tables) |
| **Retry backoff** | Waiting longer between each retry attempt |
| **Filter** | A condition that limits search results |

---

## Need Help?

If you're stuck:

1. **Read the error message** - it usually tells you what's wrong
2. **Check the logs** - `kubectl logs deployment/api-server`
3. **Test one change at a time** - easier to find what broke
4. **Ask for help** - it's okay to not know everything!

Good luck!

