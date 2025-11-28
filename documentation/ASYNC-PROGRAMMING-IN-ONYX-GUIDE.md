# Async Programming in Onyx: A Beginner's Guide

## Table of Contents

1. [What is Async Programming?](#1-what-is-async-programming)
2. [Why Onyx Uses Async](#2-why-onyx-uses-async)
3. [Two Types of Async in Onyx](#3-two-types-of-async-in-onyx)
4. [Use Case 1: File Upload](#4-use-case-1-file-upload)
5. [Use Case 2: File Deletion](#5-use-case-2-file-deletion)
6. [Use Case 3: Document Indexing](#6-use-case-3-document-indexing)
7. [Understanding Celery Tasks](#7-understanding-celery-tasks)
8. [The Hardest Parts Explained](#8-the-hardest-parts-explained)
9. [Common Patterns](#9-common-patterns)

---

## 1. What is Async Programming?

### Simple Explanation

**Synchronous (Sync)**: Do one thing at a time, wait for it to finish, then do the next thing.

**Asynchronous (Async)**: Start multiple things, don't wait for them to finish, do other work while they run.

### Real-World Analogy

**Synchronous (Like a Restaurant with One Waiter)**:
```
Waiter: Takes order from Table 1 → Waits for kitchen → Serves Table 1
        Takes order from Table 2 → Waits for kitchen → Serves Table 2
        Takes order from Table 3 → Waits for kitchen → Serves Table 3
```
**Problem**: Table 2 and 3 wait even though the waiter could be doing other things!

**Asynchronous (Like a Restaurant with Multiple Waiters)**:
```
Waiter 1: Takes order from Table 1 → Gives to kitchen → Moves to Table 2
Waiter 2: Takes order from Table 3 → Gives to kitchen → Moves to Table 4
Kitchen:  Cooking all orders in parallel
Waiters:  Pick up food when ready, serve customers
```
**Benefit**: More customers served at the same time!

---

## 2. Why Onyx Uses Async

### The Problem: Slow Operations

Some operations in Onyx take a LONG time:

| Operation | Time | Why It's Slow |
|-----------|------|---------------|
| Upload a 100MB file | 10-30 seconds | Network transfer |
| Extract text from PDF | 5-15 seconds | File parsing |
| Generate embeddings | 20-60 seconds | AI model processing |
| Index to Vespa | 10-30 seconds | Database writes |

### The Solution: Don't Make Users Wait!

Instead of:
```
User uploads file → Wait 60 seconds → "Done!"
```

We do:
```
User uploads file → "Uploaded! Processing in background..." → User can continue working
                    ↓
              Background worker processes file
```

---

## 3. Two Types of Async in Onyx

### Type 1: Python `async/await` (FastAPI)

**Used for**: HTTP requests, database queries, API calls

**Example**:
```python
# File: backend/onyx/server/middleware/latency_logging.py

@app.middleware("http")
async def log_latency(
    request: Request, 
    call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    start_time = time.monotonic()
    response = await call_next(request)  # <-- "await" = wait for this
    process_time = time.monotonic() - start_time
    logger.debug(f"Time: {process_time:.4f} secs")
    return response
```

**What `await` means**: "Pause here, let other code run, come back when this is done"

### Type 2: Celery Tasks (Background Workers)

**Used for**: Long-running jobs (file processing, indexing, deletion)

**Example**:
```python
# File: backend/onyx/db/projects.py

# API endpoint (runs immediately)
def upload_user_files(...):
    # Save file metadata to database
    user_file = create_user_file(...)
    db_session.commit()
    
    # Send task to background worker (doesn't wait!)
    task = client_app.send_task(
        OnyxCeleryTask.PROCESS_SINGLE_USER_FILE,
        kwargs={"user_file_id": user_file.id},
    )
    
    # Return immediately - user doesn't wait!
    return {"status": "uploaded", "file_id": user_file.id}
```

**What `send_task` means**: "Put this job in a queue, a worker will handle it later"

---

## 4. Use Case 1: File Upload

### The Complete Flow

```
Step 1: User uploads file
        |
        v
Step 2: API receives file (synchronous)
        - Validates file
        - Saves to MinIO (file storage)
        - Creates database record
        - Returns "success" to user
        |
        v
Step 3: Send task to Celery (asynchronous)
        - Doesn't wait!
        - Returns immediately
        |
        v
Step 4: Celery worker picks up task (background)
        - Extracts text
        - Chunks document
        - Generates embeddings
        - Indexes to Vespa
        - Updates database status
```

### Code Example: Upload Endpoint

```python
# File: backend/onyx/server/features/projects/api.py, line 75-113

@router.post("/file/upload")
def upload_user_files(
    files: list[UploadFile] = File(...),
    project_id: int | None = Form(None),
    user: User | None = Depends(current_user),
    db_session: Session = Depends(get_session),
) -> CategorizedFilesSnapshot:
    """
    This function handles file uploads.
    It's SYNCHRONOUS - it does the work immediately.
    """
    try:
        # Step 1: Save files to database and storage
        categorized_files_result = upload_files_to_user_files_with_indexing(
            files=files,
            project_id=project_id,
            user=user,
            db_session=db_session,
        )
        
        # Step 2: Return immediately (file processing happens in background)
        return CategorizedFilesSnapshot.from_result(categorized_files_result)
        
    except Exception as e:
        logger.exception(f"Error uploading files: {e}")
        raise HTTPException(status_code=500, detail="Failed to upload files")
```

### Code Example: Triggering Background Task

```python
# File: backend/onyx/db/projects.py, line 104-151

def upload_files_to_user_files_with_indexing(
    files: List[UploadFile],
    project_id: int | None,
    user: User | None,
    db_session: Session,
) -> CategorizedFilesResult:
    """
    This function:
    1. Saves file metadata (SYNC - immediate)
    2. Triggers background processing (ASYNC - later)
    """
    
    # STEP 1: Save file metadata to database (SYNCHRONOUS)
    categorized_files_result = create_user_files(
        files=files,
        project_id=project_id,
        user=user,
        db_session=db_session,
    )
    
    # STEP 2: For each file, trigger background processing (ASYNCHRONOUS)
    tenant_id = get_current_tenant_id()
    for user_file in categorized_files_result.user_files:
        # This doesn't wait! It just puts a job in a queue
        task = client_app.send_task(
            OnyxCeleryTask.PROCESS_SINGLE_USER_FILE,  # Task name
            kwargs={
                "user_file_id": user_file.id,  # Which file to process
                "tenant_id": tenant_id
            },
            queue=OnyxCeleryQueues.USER_FILE_PROCESSING,  # Which worker queue
            priority=OnyxCeleryPriority.HIGH,  # How important
        )
        logger.info(f"Triggered indexing for file {user_file.id}")
    
    # Return immediately - processing happens in background!
    return categorized_files_result
```

### Code Example: Background Worker Task

```python
# File: backend/onyx/background/celery/tasks/user_file_processing/tasks.py, line 178-330

@shared_task(
    name=OnyxCeleryTask.PROCESS_SINGLE_USER_FILE,
    bind=True,
    ignore_result=True,
)
def process_single_user_file(
    self: Task, 
    *, 
    user_file_id: str, 
    tenant_id: str
) -> None:
    """
    This function runs in a BACKGROUND WORKER.
    It processes the file: extracts text, chunks, embeds, indexes.
    
    This takes 30-60 seconds, but the user doesn't wait!
    """
    task_logger.info(f"Starting to process file {user_file_id}")
    
    # Get a lock (prevent multiple workers from processing same file)
    redis_client = get_redis_client(tenant_id=tenant_id)
    file_lock = redis_client.lock(
        f"user_file_lock_{user_file_id}",
        timeout=300,  # Lock expires after 5 minutes
    )
    
    if not file_lock.acquire(blocking=False):
        # Another worker is already processing this file
        return None
    
    try:
        with get_session_with_current_tenant() as db_session:
            # Get the file from database
            user_file = db_session.get(UserFile, _as_uuid(user_file_id))
            if not user_file:
                return None
            
            # Load the file from storage
            connector = LocalFileConnector(
                file_locations=[user_file.file_id],
                file_names=[user_file.name],
            )
            
            # Extract documents from file
            documents = []
            for batch in connector.load_from_state():
                documents.extend(batch)
            
            # Set up embedding model
            embedding_model = DefaultIndexingEmbedder.from_db_search_settings(...)
            
            # Run the indexing pipeline (THIS IS THE SLOW PART!)
            index_pipeline_result = run_indexing_pipeline(
                embedder=embedding_model,
                document_index=document_index,
                document_batch=documents,
                db_session=db_session,
                tenant_id=tenant_id,
            )
            
            # Update file status to COMPLETED
            user_file.status = UserFileStatus.COMPLETED
            user_file.chunk_count = index_pipeline_result.total_chunks
            db_session.commit()
            
            task_logger.info(f"Successfully processed file {user_file_id}")
            
    except Exception as e:
        task_logger.exception(f"Error processing file: {e}")
        # Mark file as FAILED
        user_file.status = UserFileStatus.FAILED
        db_session.commit()
    finally:
        file_lock.release()  # Release the lock
```

### Visual Timeline

```
Time →

User Action:     [Upload file]─────────────────────────────────────────────>
API Server:      [Save metadata] [Return success]──────────────────────────>
Celery Worker:                    [Pick up task] [Process file]─────────────>
Database:        [Create record]                    [Update status: COMPLETED]
User sees:       [File uploaded!]                    [File ready to use!]
```

---

## 5. Use Case 2: File Deletion

### Why Deletion is Async

Deleting a file involves:
1. Delete from Vespa (search index) - 5-10 seconds
2. Delete from MinIO (file storage) - 2-5 seconds
3. Delete from PostgreSQL (metadata) - <1 second

**Total**: 7-16 seconds. Too long to make the user wait!

### Code Example: Delete Endpoint

```python
# File: backend/onyx/server/features/projects/api.py, line 387-433

@router.delete("/file/{file_id}")
def delete_user_file(
    file_id: UUID,
    user: User | None = Depends(current_user),
    db_session: Session = Depends(get_session),
) -> UserFileDeleteResult:
    """
    Delete a user file.
    
    Steps:
    1. Check if file exists (SYNC)
    2. Check if file is used elsewhere (SYNC)
    3. Mark as DELETING (SYNC)
    4. Trigger background deletion (ASYNC)
    5. Return immediately (SYNC)
    """
    
    # STEP 1: Get the file (SYNCHRONOUS)
    user_file = db_session.query(UserFile).filter(
        UserFile.id == file_id,
        UserFile.user_id == user.id
    ).one_or_none()
    
    if user_file is None:
        raise HTTPException(status_code=404, detail="File not found")
    
    # STEP 2: Check if file is used in projects or assistants (SYNCHRONOUS)
    project_names = [project.name for project in user_file.projects]
    assistant_names = [assistant.name for assistant in user_file.assistants]
    
    if len(project_names) > 0 or len(assistant_names) > 0:
        # File is in use - don't delete!
        return UserFileDeleteResult(
            has_associations=True,
            project_names=project_names,
            assistant_names=assistant_names,
        )
    
    # STEP 3: Mark as DELETING (SYNCHRONOUS)
    user_file.status = UserFileStatus.DELETING
    db_session.commit()
    
    # STEP 4: Trigger background deletion (ASYNCHRONOUS - doesn't wait!)
    tenant_id = get_current_tenant_id()
    task = client_app.send_task(
        OnyxCeleryTask.DELETE_SINGLE_USER_FILE,
        kwargs={
            "user_file_id": str(user_file.id),
            "tenant_id": tenant_id
        },
        queue=OnyxCeleryQueues.USER_FILE_DELETE,
        priority=OnyxCeleryPriority.HIGH,
    )
    
    # STEP 5: Return immediately (SYNCHRONOUS)
    return UserFileDeleteResult(
        has_associations=False,
        project_names=[],
        assistant_names=[],
    )
```

### Code Example: Background Deletion Task

```python
# File: backend/onyx/background/celery/tasks/user_file_processing/tasks.py, line 402-493

@shared_task(
    name=OnyxCeleryTask.DELETE_SINGLE_USER_FILE,
    bind=True,
    ignore_result=True,
)
def process_single_user_file_delete(
    self: Task,
    *,
    user_file_id: str,
    tenant_id: str
) -> None:
    """
    This runs in a BACKGROUND WORKER.
    It actually deletes the file from all storage systems.
    """
    task_logger.info(f"Starting deletion for file {user_file_id}")
    
    try:
        with get_session_with_current_tenant() as db_session:
            # Get file from database
            user_file = db_session.get(UserFile, _as_uuid(user_file_id))
            if not user_file:
                return None
            
            # STEP 1: Delete from Vespa (search index)
            document_index = get_default_document_index(...)
            retry_index = RetryDocumentIndex(document_index)
            
            chunk_count = user_file.chunk_count or 0
            retry_index.delete_single(
                doc_id=user_file_id,
                tenant_id=tenant_id,
                chunk_count=chunk_count,
            )
            task_logger.info(f"Deleted {chunk_count} chunks from Vespa")
            
            # STEP 2: Delete from MinIO (file storage)
            file_store = get_default_file_store()
            try:
                file_store.delete_file(user_file.file_id)
                file_store.delete_file(user_file_id_to_plaintext_file_name(user_file.id))
            except Exception as e:
                task_logger.warning(f"Error deleting from storage: {e}")
            
            # STEP 3: Delete from PostgreSQL (database)
            db_session.delete(user_file)
            db_session.commit()
            
            task_logger.info(f"Successfully deleted file {user_file_id}")
            
    except Exception as e:
        task_logger.exception(f"Error deleting file: {e}")
```

---

## 6. Use Case 3: Document Indexing

### What is Document Indexing?

When you connect a data source (Google Drive, Confluence, etc.), Onyx needs to:
1. **Fetch** documents from the source
2. **Process** them (chunk, embed, index)

This can take **hours** for large sources!

### The Two-Task Pipeline

```
Task 1: Docfetching (Fetch documents)
        ↓
Task 2: Docprocessing (Process documents)
```

### Code Example: Starting Indexing

```python
# File: backend/onyx/background/celery/tasks/docprocessing/utils.py, line 303-384

def try_creating_docfetching_task(
    celery_app: Celery,
    cc_pair: ConnectorCredentialPair,
    search_settings: SearchSettings,
    reindex: bool,
    db_session: Session,
    tenant_id: str,
) -> int | None:
    """
    This function starts the indexing pipeline.
    
    It creates a "docfetching" task that will:
    1. Fetch documents from the source
    2. Create "docprocessing" tasks for each batch
    """
    
    # Check if indexing is already running
    index_attempt_id = IndexingCoordination.try_create_index_attempt(
        db_session=db_session,
        cc_pair_id=cc_pair.id,
        search_settings_id=search_settings.id,
    )
    
    if index_attempt_id is None:
        # Already running!
        return None
    
    # Determine which queue to use
    queue = (
        OnyxCeleryQueues.USER_FILES_INDEXING
        if cc_pair.is_user_file
        else OnyxCeleryQueues.CONNECTOR_DOC_FETCHING
    )
    
    # Send the task (ASYNC - doesn't wait!)
    result = celery_app.send_task(
        OnyxCeleryTask.CONNECTOR_DOC_FETCHING_TASK,
        kwargs={
            "index_attempt_id": index_attempt_id,
            "cc_pair_id": cc_pair.id,
            "search_settings_id": search_settings.id,
            "tenant_id": tenant_id,
        },
        queue=queue,
        priority=OnyxCeleryPriority.MEDIUM,
    )
    
    return index_attempt_id
```

### Code Example: Docfetching Task

```python
# File: backend/onyx/background/celery/tasks/docfetching/tasks.py, line 307-385

@shared_task(
    name=OnyxCeleryTask.CONNECTOR_DOC_FETCHING_TASK,
    bind=True,
    acks_late=False,
    track_started=True,
)
def docfetching_proxy_task(
    self: Task,
    index_attempt_id: int,
    cc_pair_id: int,
    search_settings_id: int,
    tenant_id: str,
) -> None:
    """
    This task:
    1. Fetches documents from the source (Google Drive, Confluence, etc.)
    2. For each batch of documents, creates a "docprocessing" task
    3. The docprocessing tasks run in parallel!
    """
    
    # Get connector (Google Drive, Confluence, etc.)
    connector = get_connector_from_cc_pair(cc_pair_id, db_session)
    
    # Fetch documents in batches
    for batch_num, document_batch in enumerate(connector.load_from_state()):
        # Store batch in file store
        batch_id = store_document_batch(document_batch, index_attempt_id)
        
        # Create a docprocessing task for this batch (ASYNC!)
        celery_app.send_task(
            OnyxCeleryTask.DOCPROCESSING_TASK,
            kwargs={
                "index_attempt_id": index_attempt_id,
                "cc_pair_id": cc_pair_id,
                "tenant_id": tenant_id,
                "batch_num": batch_num,
            },
            queue=OnyxCeleryQueues.DOCPROCESSING,
        )
        
        # Continue fetching next batch while processing happens in background!
```

### Code Example: Docprocessing Task

```python
# File: backend/onyx/background/celery/tasks/docprocessing/tasks.py, line 1241-1274

@shared_task(
    name=OnyxCeleryTask.DOCPROCESSING_TASK,
    bind=True,
)
def docprocessing_task(
    self: Task,
    index_attempt_id: int,
    cc_pair_id: int,
    tenant_id: str,
    batch_num: int,
) -> None:
    """
    This task processes ONE batch of documents:
    1. Load batch from file store
    2. Chunk documents
    3. Generate embeddings
    4. Index to Vespa
    5. Update database
    """
    
    # Load document batch
    document_batch = load_document_batch(index_attempt_id, batch_num)
    
    # Chunk documents
    chunks = chunk_documents(document_batch)
    
    # Generate embeddings (SLOW - calls AI model)
    embeddings = embedding_model.embed_chunks(chunks)
    
    # Index to Vespa (SLOW - database writes)
    document_index.index_chunks(chunks, embeddings)
    
    # Update database
    mark_batch_as_processed(index_attempt_id, batch_num)
```

---

## 7. Understanding Celery Tasks

### What is Celery?

**Celery** is a task queue system. Think of it like a **job board**:

```
┌─────────────────┐
│   Job Board     │  ← Redis (stores tasks)
│  (Task Queue)   │
┌─────────────────┐
│ 1. Process File │
│ 2. Delete File  │
│ 3. Index Docs   │
└─────────────────┘
        │
        │ Workers pick up jobs
        ↓
┌─────────────────┐
│   Workers       │  ← Celery Workers (do the work)
│  (Background)   │
└─────────────────┘
```

### Key Concepts

#### 1. `@shared_task` Decorator

```python
@shared_task(
    name=OnyxCeleryTask.PROCESS_SINGLE_USER_FILE,
    bind=True,
    ignore_result=True,
)
def process_single_user_file(self: Task, *, user_file_id: str) -> None:
    # This function becomes a Celery task
    pass
```

**What it does**:
- `@shared_task`: Makes this function a Celery task
- `name=...`: Unique name for the task
- `bind=True`: Task can access itself (`self`)
- `ignore_result=True`: Don't store the result (saves memory)

#### 2. `send_task()` - Sending Tasks

```python
task = client_app.send_task(
    OnyxCeleryTask.PROCESS_SINGLE_USER_FILE,  # Which task to run
    kwargs={"user_file_id": "abc-123"},        # Arguments
    queue=OnyxCeleryQueues.USER_FILE_PROCESSING,  # Which queue
    priority=OnyxCeleryPriority.HIGH,         # How important
)
```

**What happens**:
1. Task is added to Redis queue
2. Function returns immediately (doesn't wait!)
3. Worker picks up task later
4. Worker executes the function

#### 3. Queues - Organizing Tasks

```python
# Different queues for different types of work
OnyxCeleryQueues.USER_FILE_PROCESSING    # User file uploads
OnyxCeleryQueues.DOCPROCESSING           # Document indexing
OnyxCeleryQueues.USER_FILE_DELETE        # File deletions
OnyxCeleryQueues.CONNECTOR_DOC_FETCHING  # Fetching from sources
```

**Why queues?**: Different workers handle different queues. This allows:
- Scaling: More workers for heavy queues
- Priority: Important tasks get processed first
- Isolation: One slow task doesn't block others

#### 4. Priority - Ordering Tasks

```python
OnyxCeleryPriority.HIGHEST  # Most important (user actions)
OnyxCeleryPriority.HIGH     # Important (file operations)
OnyxCeleryPriority.MEDIUM   # Normal (indexing)
OnyxCeleryPriority.LOW      # Less urgent (cleanup)
```

---

## 8. The Hardest Parts Explained

### Part 1: Understanding `await`

**The Confusion**: When do you use `await`? When don't you?

**Simple Rule**: 
- Use `await` for **async functions** (functions defined with `async def`)
- Don't use `await` for **regular functions** (functions defined with `def`)

**Example**:
```python
# This is an ASYNC function
async def fetch_data():
    response = await http_client.get("/api/data")  # ← Need await
    return response.json()

# This is a REGULAR function
def process_data():
    result = calculate_sum(1, 2)  # ← No await needed
    return result
```

**In Onyx**:
- FastAPI endpoints can be `async def` → use `await` for database/HTTP calls
- Celery tasks are `def` → no `await` (they run in separate processes)

### Part 2: Celery vs Async/Await

**The Confusion**: Why use Celery if Python has `async/await`?

**Answer**: They solve different problems!

| Feature | `async/await` | Celery |
|---------|---------------|--------|
| **Use case** | Fast operations (<1 second) | Slow operations (>10 seconds) |
| **Runs in** | Same process | Separate worker process |
| **Scaling** | Limited by CPU | Can run on different machines |
| **Example** | Database query, API call | File processing, indexing |

**In Onyx**:
- FastAPI uses `async/await` for HTTP requests
- Celery handles long-running background jobs

### Part 3: Task Locks (Preventing Duplicates)

**The Problem**: What if two workers try to process the same file?

**The Solution**: Redis locks!

```python
# File: backend/onyx/background/celery/tasks/user_file_processing/tasks.py

def process_single_user_file(self: Task, *, user_file_id: str) -> None:
    # Get a lock for this file
    redis_client = get_redis_client(tenant_id=tenant_id)
    file_lock = redis_client.lock(
        f"user_file_lock_{user_file_id}",
        timeout=300,  # Lock expires after 5 minutes
    )
    
    # Try to acquire the lock
    if not file_lock.acquire(blocking=False):
        # Another worker is already processing this file!
        task_logger.info("Lock held, skipping")
        return None
    
    try:
        # Do the work (only one worker can be here at a time)
        process_file(user_file_id)
    finally:
        # Always release the lock when done
        file_lock.release()
```

**How it works**:
1. Worker 1 gets lock → processes file
2. Worker 2 tries to get lock → fails → skips
3. Worker 1 finishes → releases lock

### Part 4: Task Status Tracking

**The Problem**: How do we know if a task succeeded or failed?

**The Solution**: Database status fields!

```python
# When task starts
user_file.status = UserFileStatus.PROCESSING
db_session.commit()

# When task succeeds
user_file.status = UserFileStatus.COMPLETED
user_file.chunk_count = 100
db_session.commit()

# When task fails
user_file.status = UserFileStatus.FAILED
db_session.commit()
```

**Frontend checks status**:
```typescript
// Frontend polls the API
const status = await fetch(`/api/user/files/${fileId}/status`);
if (status === "COMPLETED") {
    // File is ready!
}
```

### Part 5: Error Handling in Tasks

**The Problem**: What if a task crashes?

**The Solution**: Try/except blocks!

```python
@shared_task(...)
def process_single_user_file(self: Task, *, user_file_id: str) -> None:
    try:
        # Do the work
        process_file(user_file_id)
        task_logger.info("Success!")
    except Exception as e:
        # Log the error
        task_logger.exception(f"Error: {e}")
        
        # Update status to FAILED
        user_file.status = UserFileStatus.FAILED
        db_session.commit()
        
        # Re-raise to mark task as failed in Celery
        raise
```

**What happens**:
- Task fails → Celery logs it
- Status updated to FAILED
- User sees error in UI
- Admin can retry manually

---

## 9. Common Patterns

### Pattern 1: Fire and Forget

**When**: You don't need to know when the task finishes

```python
# Send task, don't wait for result
client_app.send_task(
    OnyxCeleryTask.PROCESS_SINGLE_USER_FILE,
    kwargs={"user_file_id": file_id},
    ignore_result=True,  # Don't store result
)
```

### Pattern 2: Status Polling

**When**: You need to know when the task finishes

```python
# API endpoint
@router.get("/file/{file_id}/status")
def get_file_status(file_id: UUID) -> dict:
    user_file = db_session.get(UserFile, file_id)
    return {
        "status": user_file.status,  # PROCESSING, COMPLETED, FAILED
        "chunk_count": user_file.chunk_count,
    }

# Frontend polls this endpoint
setInterval(async () => {
    const status = await fetch(`/api/file/${fileId}/status`);
    if (status.status === "COMPLETED") {
        // Done!
    }
}, 2000);  // Check every 2 seconds
```

### Pattern 3: Chained Tasks

**When**: One task needs to trigger another

```python
# Task 1: Fetch documents
@shared_task(name="fetch_documents")
def fetch_documents(source_id: int):
    documents = fetch_from_source(source_id)
    
    # For each batch, trigger processing task
    for batch in split_into_batches(documents):
        client_app.send_task(
            "process_batch",
            kwargs={"batch_id": batch.id},
        )

# Task 2: Process batch
@shared_task(name="process_batch")
def process_batch(batch_id: int):
    # Process the batch
    pass
```

### Pattern 4: Retry on Failure

**When**: Task might fail temporarily (network issues, etc.)

```python
@shared_task(
    name=OnyxCeleryTask.PROCESS_SINGLE_USER_FILE,
    autoretry_for=(Exception,),  # Retry on any error
    retry_backoff=True,          # Wait longer each time
    max_retries=5,              # Try 5 times
)
def process_single_user_file(...):
    # If this fails, Celery will retry automatically
    pass
```

---

## Summary

### Key Takeaways

1. **Async = Don't wait**: Start work, do other things, check back later
2. **Celery = Background workers**: Long jobs run separately, don't block users
3. **Locks = Prevent duplicates**: Only one worker processes each file
4. **Status = Track progress**: Database fields show what's happening
5. **Errors = Handle gracefully**: Try/except + status updates

### When to Use What

| Situation | Solution |
|-----------|----------|
| Fast operation (<1s) | `async/await` in FastAPI |
| Slow operation (>10s) | Celery task |
| Need immediate response | Fire and forget |
| Need to know when done | Status polling |
| Prevent duplicates | Redis locks |
| Handle failures | Try/except + retry |

### Next Steps

1. **Read the code**: Look at real examples in `backend/onyx/background/celery/tasks/`
2. **Add logging**: Use `task_logger.info()` to see what's happening
3. **Test locally**: Run Celery worker locally to see tasks execute
4. **Monitor in production**: Check Celery flower or logs to see task status

Good luck! 🚀

