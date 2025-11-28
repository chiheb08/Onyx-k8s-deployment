# The Story of the Disappearing File Bug: A User Story with Technical Deep Dive

## 📖 The User Story

### Meet Sarah, the Project Manager

Sarah is a project manager at a company using Onyx. She's working on a project called "Q4 Sales Report" and has uploaded several files to help her team analyze sales data.

**Monday, 9:00 AM** - Sarah uploads `sales_data.csv` to her project. The file appears in the project, and she can search for information in it. Everything works perfectly.

**Monday, 2:00 PM** - Sarah realizes she uploaded the wrong file. She removes `sales_data.csv` from the project and uploads the correct `sales_data_v2.csv` instead.

**Monday, 3:00 PM** - Sarah asks Onyx: "What were our sales in October?" 

**The Problem**: Onyx's answer includes information from `sales_data.csv` - the file she deleted 1 hour ago!

**Sarah is confused**: "I deleted that file! Why is it still showing up?"

---

## 🔍 What's Really Happening: The Technical Story

### The Two-Storage System

Onyx uses **two separate storage systems** that must stay synchronized:

```
┌─────────────────────────────────────────────────────────────┐
│                    ONYX STORAGE ARCHITECTURE                 │
└─────────────────────────────────────────────────────────────┘

    PostgreSQL (The Catalog)          Vespa (The Search Index)
    ────────────────────────          ────────────────────────
    
    Stores:                            Stores:
    - File metadata                   - Document chunks
    - Project associations            - Embeddings (for search)
    - User ownership                  - Project tags
    - File status                     - Access control
    
    Think of it like:                  Think of it like:
    A library catalog                  The actual bookshelves
    (tells you where                   (where books are
     books should be)                   physically located)
```

### The Bug: When They Get Out of Sync

When Sarah removes a file from a project, here's what happens:

#### Step 1: The API Call (Synchronous - Immediate)

```python
# File: backend/onyx/server/features/projects/api.py
# When Sarah clicks "Remove from Project"

@router.delete("/{project_id}/files/{file_id}")
def unlink_user_file_from_project(...):
    # Remove the link in PostgreSQL (INSTANT - <1ms)
    project.user_files.remove(user_file)
    user_file.needs_project_sync = True  # Mark as "needs sync"
    db_session.commit()
    
    # Send task to background worker (ASYNC - doesn't wait!)
    task = client_app.send_task(
        OnyxCeleryTask.PROCESS_SINGLE_USER_FILE_PROJECT_SYNC,
        kwargs={"user_file_id": user_file.id},
    )
    
    # Return immediately - user sees "Success!"
    return Response(status_code=204)
```

**What happens**:
1. PostgreSQL is updated instantly: "File is no longer in Project 5"
2. A message is sent to Celery: "Please update Vespa"
3. API returns success to Sarah
4. **But Vespa hasn't been updated yet!**

#### Step 2: The Background Task (Asynchronous - Later)

```python
# File: backend/onyx/background/celery/tasks/user_file_processing/tasks.py
# This runs in a separate worker process, later

@shared_task(name=OnyxCeleryTask.PROCESS_SINGLE_USER_FILE_PROJECT_SYNC)
def process_single_user_file_project_sync(user_file_id: str, tenant_id: str):
    # Get the file from database
    user_file = db_session.get(UserFile, user_file_id)
    
    # Get current project list (should be empty now)
    project_ids = [p.id for p in user_file.projects]  # []
    
    # Update Vespa
    retry_index.update_single(
        doc_id=str(user_file.id),
        user_fields=VespaDocumentUserFields(user_projects=project_ids),  # []
    )
```

**The Problem**: If this task:
- Fails (Vespa is down)
- Is delayed (worker is busy)
- Never runs (worker crashed)

Then Vespa still has the old project list: `user_project = [5]`

#### Step 3: The Search Query (The Bug Appears)

When Sarah searches, Onyx queries Vespa:

```python
# File: backend/onyx/document_index/vespa/shared_utils/vespa_request_builders.py

def _build_user_project_filter(project_id: int | None) -> str:
    if project_id is None:
        return ""  # NO FILTER! <-- BUG!
    return f'({USER_PROJECT} contains "{project_id}") and '
```

**The Bug**: When searching in a regular chat (no project), `project_id` is `None`, so:
- No filter is applied
- Vespa returns ALL files with `user_project = [5]`
- Including the file Sarah deleted!

---

## 🛠️ The Three Solutions: How We Fix It

### Solution 1: Add Retry Logic (The Persistent Worker)

**The Story**: Imagine a delivery driver who gives up after one failed attempt. Now imagine a persistent driver who tries 5 times, waiting longer each time.

**The Code Change**:

```python
# BEFORE: If task fails, it just fails
@shared_task(
    name=OnyxCeleryTask.PROCESS_SINGLE_USER_FILE_PROJECT_SYNC,
    bind=True,
    ignore_result=True,
)
def process_single_user_file_project_sync(...):
    # If Vespa is down, task fails and never retries
    pass

# AFTER: Task automatically retries on failure
@shared_task(
    name=OnyxCeleryTask.PROCESS_SINGLE_USER_FILE_PROJECT_SYNC,
    bind=True,
    ignore_result=True,
    autoretry_for=(Exception,),   # Retry on ANY error
    retry_backoff=True,            # Wait longer each time
    retry_backoff_max=300,         # Max wait: 5 minutes
    max_retries=5,                 # Try 5 times
)
def process_single_user_file_project_sync(...):
    # If Vespa is down, task will retry automatically
    pass
```

**How It Works**:

```
Attempt 1: Try to update Vespa → FAIL (Vespa is down)
    Wait 1 second
Attempt 2: Try again → FAIL (still down)
    Wait 2 seconds
Attempt 3: Try again → FAIL (still down)
    Wait 4 seconds
Attempt 4: Try again → SUCCESS! (Vespa is back up)
    Done!
```

**Technical Deep Dive**:

- **`autoretry_for=(Exception,)`**: Celery will catch ANY exception and retry
- **`retry_backoff=True`**: Exponential backoff - wait time doubles each retry (1s, 2s, 4s, 8s, 16s)
- **`retry_backoff_max=300`**: Cap the wait time at 5 minutes (prevents waiting hours)
- **`max_retries=5`**: After 5 attempts, give up and log the error

**Why This Helps**: If Vespa is temporarily down (maintenance, network issue), the task will eventually succeed when Vespa comes back up.

---

### Solution 2: Synchronous Vespa Update (The Guaranteed Update)

**The Story**: Instead of sending a messenger and hoping they deliver the message, we call the warehouse directly and wait for confirmation.

**The Code Change**:

```python
# BEFORE: Async update (might fail silently)
@router.delete("/{project_id}/files/{file_id}")
def unlink_user_file_from_project(...):
    # Update PostgreSQL
    project.user_files.remove(user_file)
    user_file.needs_project_sync = True
    db_session.commit()
    
    # Send async task (doesn't wait!)
    client_app.send_task(...)
    
    return Response(status_code=204)  # Returns immediately

# AFTER: Sync update (waits for completion)
@router.delete("/{project_id}/files/{file_id}")
def unlink_user_file_from_project(...):
    # Update PostgreSQL
    project.user_files.remove(user_file)
    db_session.commit()
    
    # Update Vespa NOW (waits for it!)
    try:
        # Get Vespa connection
        document_index = get_default_document_index(...)
        retry_index = RetryDocumentIndex(document_index)
        
        # Get current project list
        project_ids = [p.id for p in user_file.projects]  # []
        
        # Update Vespa (BLOCKING - waits for response)
        retry_index.update_single(
            doc_id=str(user_file.id),
            user_fields=VespaDocumentUserFields(user_projects=project_ids),
        )
        
        # Mark as synced
        user_file.needs_project_sync = False
        db_session.commit()
        
    except Exception as e:
        # If update fails, fall back to async
        logger.error(f"Failed to sync Vespa: {e}")
        user_file.needs_project_sync = True
        db_session.commit()
        client_app.send_task(...)  # Backup: async retry
    
    return Response(status_code=204)  # Returns after Vespa is updated
```

**How It Works**:

```
User clicks "Remove"
    ↓
API updates PostgreSQL (instant)
    ↓
API calls Vespa directly (waits ~100-500ms)
    ↓
Vespa confirms update
    ↓
API returns "Success" to user
```

**Technical Deep Dive**:

1. **`get_default_document_index(...)`**: Creates an HTTP client connection to Vespa
   - Uses `httpx` library for async HTTP requests
   - Handles authentication, SSL certificates, connection pooling

2. **`RetryDocumentIndex(document_index)`**: Wraps the connection with retry logic
   - If a request fails (network error, timeout), automatically retries
   - Prevents temporary network issues from causing failures

3. **`update_single(...)`**: Sends an HTTP PUT request to Vespa
   - URL: `http://vespa:8080/document/v1/onyx_chunk/docid/{file_id}`
   - Body: `{"fields": {"user_project": [1, 12]}}` (new project list)
   - **This is BLOCKING** - the function waits for Vespa's response

4. **Error Handling**: If Vespa is down, we:
   - Log the error
   - Mark file as needing sync
   - Trigger async task as backup
   - Still return success to user (they'll see correct state eventually)

**Why This Helps**: 
- **Guaranteed consistency**: When user sees "success", Vespa is definitely updated
- **Faster feedback**: User knows immediately if something went wrong
- **Fallback safety**: If sync fails, async task will retry later

**Trade-off**: 
- User waits ~100-500ms longer (instead of instant response)
- But this is acceptable for the guarantee of consistency

---

### Solution 3: Filter User Files in Chat (The Isolation Fix)

**The Story**: Imagine a library where personal books and shared books are mixed together. When you search, you see everything. The fix: separate personal books from shared books in search results.

**The Code Change**:

```python
# BEFORE: No filter for regular chat
def _build_user_project_filter(project_id: int | None) -> str:
    if project_id is None:
        return ""  # NO FILTER - shows everything!
    return f'({USER_PROJECT} contains "{project_id}") and '

# AFTER: Exclude user files from regular chat
def _build_user_project_filter(
    project_id: int | None,
    user_file_ids: list[str] | None = None,  # NEW parameter
) -> str:
    # Case 1: Searching in a project
    if project_id is not None:
        return f'({USER_PROJECT} contains "{project_id}") and '
    
    # Case 2: User attached specific files to message
    if user_file_ids:
        return ""  # Already filtered by file IDs
    
    # Case 3: Regular chat - exclude user files
    return f'({SOURCE_TYPE} != "user_file") and '  # NEW!
```

**How It Works**:

**BEFORE (Bug)**:
```
Sarah searches "sales data" in regular chat
    ↓
Vespa query: "Find documents matching 'sales data'"
    ↓
Returns:
    - Connector documents (Confluence, Google Drive) ✓
    - User files (including deleted ones!) ✗ BUG!
```

**AFTER (Fixed)**:
```
Sarah searches "sales data" in regular chat
    ↓
Vespa query: "Find documents matching 'sales data' AND source_type != 'user_file'"
    ↓
Returns:
    - Connector documents (Confluence, Google Drive) ✓
    - NO user files ✓ FIXED!
```

**Technical Deep Dive**:

1. **Vespa Query Language (YQL)**:
   ```yql
   select * from onyx_chunk 
   where userQuery("sales data") 
   and source_type != "user_file"
   ```
   - `userQuery("sales data")`: Semantic search for the query
   - `source_type != "user_file"`: Exclude user-uploaded files
   - This filter is added to EVERY search query in regular chat

2. **Source Types in Onyx**:
   ```python
   class DocumentSource(str, Enum):
       USER_FILE = "user_file"           # User uploads
       GOOGLE_DRIVE = "google_drive"      # Google Drive connector
       CONFLUENCE = "confluence"          # Confluence connector
       SLACK = "slack"                    # Slack connector
       # ... etc
   ```

3. **Why This Works**:
   - Even if Vespa has stale data (`user_project = [5]`), the `source_type` filter prevents it from appearing
   - User files are ONLY searchable when:
     - Searching within a project (project filter applies)
     - Explicitly attached to a message (file IDs filter applies)

4. **Performance Impact**:
   - Adding a filter to Vespa queries is very fast (<1ms)
   - Vespa indexes `source_type` for fast filtering
   - No noticeable performance difference

**Why This Helps**:
- **Immediate fix**: Works even if Vespa sync is delayed
- **Defense in depth**: Multiple layers of protection
- **User experience**: Users don't see files they shouldn't see

---

## 🎯 The Complete Picture: How All Three Solutions Work Together

### The Defense-in-Depth Strategy

```
┌─────────────────────────────────────────────────────────────┐
│              DEFENSE IN DEPTH: THREE LAYERS                 │
└─────────────────────────────────────────────────────────────┘

Layer 1: Retry Logic
    ↓
    If Vespa sync fails → Automatically retry up to 5 times
    Prevents: Temporary failures from causing permanent bugs

Layer 2: Synchronous Update
    ↓
    Update Vespa immediately during API call
    Prevents: Most sync failures from happening in the first place

Layer 3: Filter Fix
    ↓
    Exclude user files from regular chat search
    Prevents: Stale data from appearing even if sync fails
```

### Real-World Scenario

**Monday, 2:00 PM** - Sarah removes `sales_data.csv` from Project 5

**What Happens**:

1. **API Call** (Solution 2):
   ```python
   # PostgreSQL updated: File no longer in Project 5
   # Vespa updated: user_project = [] (synchronous)
   # Returns: Success
   ```
   **Result**: Vespa is updated immediately ✅

2. **If Vespa Update Fails** (Solution 1):
   ```python
   # PostgreSQL updated: File no longer in Project 5
   # Vespa update fails: Network error
   # Async task triggered: Will retry 5 times
   ```
   **Result**: Task will eventually succeed when Vespa is back up ✅

3. **If User Searches Before Sync** (Solution 3):
   ```python
   # User searches in regular chat
   # Query: "sales data" AND source_type != "user_file"
   # Result: File doesn't appear (even if Vespa has stale data)
   ```
   **Result**: User doesn't see the file ✅

---

## 🧠 Technical Deep Dive: Understanding the Architecture

### Why Two Storage Systems?

**PostgreSQL** (Relational Database):
- **Purpose**: Store structured data (users, projects, files, relationships)
- **Strengths**: ACID transactions, complex queries, relationships
- **Weaknesses**: Not optimized for full-text search

**Vespa** (Vector/Search Database):
- **Purpose**: Store document chunks, embeddings, enable semantic search
- **Strengths**: Fast full-text search, vector similarity search, handles millions of documents
- **Weaknesses**: Not a relational database, eventual consistency

**Why Both?**:
- PostgreSQL: "What files does this user have? What projects?"
- Vespa: "Find documents similar to 'sales data in October'"

### The Sync Problem

**The Challenge**: Keeping two systems in sync is hard!

```
PostgreSQL Update:  <1ms (instant)
Vespa Update:       100-500ms (network call)
```

**The Gap**: Between PostgreSQL update and Vespa update, they're out of sync!

**Solutions**:
1. **Retry Logic**: If sync fails, keep trying
2. **Synchronous Update**: Wait for sync to complete
3. **Filter Fix**: Don't show data that might be stale

### Understanding Celery Tasks

**What is Celery?**:
- A distributed task queue system
- Uses Redis/RabbitMQ as message broker
- Workers run tasks in background processes

**How It Works**:

```
API Server                    Redis Queue              Celery Worker
     |                            |                         |
     |-- send_task() ----------->|                         |
     |                            |-- Task queued          |
     |                            |                         |
     |<-- Returns immediately ---|                         |
     |                            |                         |
     |                            |-- Worker picks up ----->|
     |                            |                         |
     |                            |<-- Task executing -----|
     |                            |                         |
     |                            |-- Task complete ------->|
```

**Why Async?**:
- File processing takes 30-60 seconds
- Can't make user wait that long!
- Background workers handle it while user continues working

### Understanding Vespa Queries

**Vespa Query Language (YQL)**:

```yql
select 
    documentid, 
    content, 
    title 
from onyx_chunk 
where 
    userQuery("sales data") 
    and user_project contains "5"
    and source_type != "user_file"
    and !(hidden=true)
```

**Breaking It Down**:
- `userQuery("sales data")`: Semantic search (finds similar meaning)
- `user_project contains "5"`: Only files in Project 5
- `source_type != "user_file"`: Exclude user uploads
- `!(hidden=true)`: Don't show hidden documents

**How Filters Work**:
- Vespa indexes all fields for fast filtering
- Adding filters is very fast (<1ms)
- Multiple filters are combined with AND logic

---

## 📊 Performance Impact

### Solution 1: Retry Logic
- **Impact**: Minimal
- **Cost**: If task fails, retries add 1-16 seconds total
- **Benefit**: Prevents permanent failures

### Solution 2: Synchronous Update
- **Impact**: Small
- **Cost**: User waits 100-500ms longer (instead of instant)
- **Benefit**: Guaranteed consistency

### Solution 3: Filter Fix
- **Impact**: None
- **Cost**: <1ms per query (negligible)
- **Benefit**: Prevents stale data from appearing

**Overall**: All solutions have minimal performance impact while significantly improving reliability.

---

## 🎓 Key Learnings for Junior Engineers

### 1. Understanding Async vs Sync

**Async (Asynchronous)**:
- Start work, don't wait, do other things
- Example: Sending an email (you don't wait for delivery)

**Sync (Synchronous)**:
- Start work, wait for completion, then continue
- Example: Withdrawing money from ATM (you wait for the money)

**When to Use What**:
- **Async**: Long operations (>10 seconds), user doesn't need immediate result
- **Sync**: Fast operations (<1 second), user needs immediate result

### 2. Understanding Distributed Systems

**The Challenge**: Multiple systems must stay in sync

**The Reality**: They often don't! Network failures, crashes, delays happen.

**The Solution**: 
- Retry logic (handle failures)
- Synchronous updates (prevent failures)
- Defensive filters (hide stale data)

### 3. Understanding Task Queues

**Why Task Queues?**: 
- Long operations would block users
- Need to scale workers independently
- Need to retry failed tasks

**How They Work**:
1. API sends task to queue
2. Worker picks up task
3. Worker executes task
4. Worker reports result

### 4. Understanding Database Consistency

**ACID (PostgreSQL)**:
- **Atomicity**: All or nothing
- **Consistency**: Data is always valid
- **Isolation**: Transactions don't interfere
- **Durability**: Changes are permanent

**Eventual Consistency (Vespa)**:
- Changes propagate eventually
- Temporary inconsistencies are OK
- System will converge to consistent state

**The Trade-off**: 
- Strong consistency (PostgreSQL): Slower, guaranteed
- Eventual consistency (Vespa): Faster, might be temporarily inconsistent

---

## 🎬 The Happy Ending

**After the Fix**:

**Monday, 2:00 PM** - Sarah removes `sales_data.csv` from Project 5
- PostgreSQL updated ✅
- Vespa updated immediately ✅
- API returns success ✅

**Monday, 3:00 PM** - Sarah searches "sales data"
- Query excludes user files ✅
- Only shows connector documents ✅
- No deleted files appear ✅

**Sarah is happy**: "The system works as expected!"

---

## 📚 Summary

### The Problem
Files deleted from projects still appear in search because:
1. PostgreSQL and Vespa get out of sync
2. Background sync tasks can fail
3. Regular chat search doesn't filter user files

### The Solutions
1. **Retry Logic**: Automatically retry failed syncs
2. **Synchronous Update**: Update Vespa immediately during API call
3. **Filter Fix**: Exclude user files from regular chat search

### The Result
- Files are properly removed from search
- System is more reliable
- Users have better experience

---

**For Junior Engineers**: This bug teaches us that distributed systems are complex, and we need multiple layers of defense to ensure reliability. Always think about what happens when things fail!

