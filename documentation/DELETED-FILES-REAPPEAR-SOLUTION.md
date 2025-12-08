# Solution: Deleted Files Reappear in Internal Search

## 🐛 Problem Statement

**GitHub Issues:**
- [#69 - deleted files reappear in internal search](https://github.rzn.bayern.testa-de.net/BAI/CustomOnyxFrontend/issues/69)
- Comment from franziska-rubenbauer: Backend deletion implementation unclear

**Symptoms:**
- Files deleted via the UI still appear in search results
- Deletion seems to be only partial
- Users see files they've already deleted

---

## 🔍 Root Cause Analysis

### The Problem Flow

```
1. User deletes file via UI
   ↓
2. API marks file as DELETING in PostgreSQL
   ↓
3. API enqueues Celery task DELETE_SINGLE_USER_FILE
   ↓
4. Celery task should:
   - Delete from Vespa (search index) ✓
   - Delete from MinIO (file storage) ✓
   - Delete from PostgreSQL ✓
   ↓
5. IF Vespa deletion FAILS or is DELAYED:
   - Vespa still has chunks in index ✗
   - PostgreSQL record may be deleted ✓
   ↓
6. User searches
   ↓
7. Vespa returns chunks from deleted file
   ↓
8. Search code doesn't validate file exists
   ↓
9. User sees deleted file in results ✗ BUG!
```

### Root Causes

#### Cause 1: No Database Validation in Search Flow

**Location**: `backend/onyx/context/search/retrieval/search_runner.py`

**Problem**: The `doc_index_retrieval()` function returns chunks from Vespa without validating that the corresponding `user_file` still exists in PostgreSQL or is not in `DELETING` status.

**Current Code**:
```python
def doc_index_retrieval(...) -> list[InferenceChunk]:
    # ... Vespa query ...
    top_chunks = document_index.hybrid_retrieval(...)
    # ... processing ...
    return cleanup_chunks(deduped_chunks)  # ❌ No validation!
```

#### Cause 2: Async Deletion Task May Fail

**Location**: `backend/onyx/background/celery/tasks/user_file_processing/tasks.py`

**Problem**: The `process_single_user_file_delete()` task may fail silently or timeout, leaving chunks in Vespa.

**Failure Scenarios**:
- Vespa service unreachable
- Network timeout
- Vespa returns 429 (rate limit)
- Task queue full
- Celery worker down

#### Cause 3: No Retry Logic for Vespa Deletion

**Problem**: If Vespa deletion fails, there's no automatic retry mechanism.

---

## ✅ Solution: Multi-Layer Defense

### Solution 1: Validate User Files in Search Flow (Primary Fix)

**Location**: `backend/onyx/context/search/retrieval/search_runner.py`

**Problem**: Search returns chunks from deleted files because there's no validation.

---

#### Change 1: Add New Validation Function

**OLD CODE** (doesn't exist):
```python
# No validation function exists
```

**NEW CODE** (add this function):
```python
def _filter_deleted_user_files(
    chunks: list[InferenceChunkUncleaned],
    db_session: Session,
) -> list[InferenceChunkUncleaned]:
    """
    Filter out chunks from deleted user files.
    
    This is a defense-in-depth measure to prevent deleted files
    from appearing in search results if Vespa deletion failed or was delayed.
    """
    from onyx.db.models import UserFile
    from onyx.db.enums import UserFileStatus
    
    # Identify chunks that might be from user files
    # User files use UUID as document_id, connector documents use strings
    user_file_chunks: list[tuple[InferenceChunkUncleaned, UUID]] = []
    other_chunks: list[InferenceChunkUncleaned] = []
    
    for chunk in chunks:
        # Try to parse document_id as UUID
        try:
            user_file_id = UUID(chunk.document_id)
            user_file_chunks.append((chunk, user_file_id))
        except (ValueError, TypeError):
            # Not a UUID, so not a user file - keep it
            other_chunks.append(chunk)
    
    # If no potential user file chunks, return all chunks
    if not user_file_chunks:
        return chunks
    
    # Batch query for all user files to check their status
    user_file_ids = [uf_id for _, uf_id in user_file_chunks]
    valid_user_files = (
        db_session.query(UserFile.id)
        .filter(
            UserFile.id.in_(user_file_ids),
            UserFile.status != UserFileStatus.DELETING,
        )
        .all()
    )
    valid_user_file_ids = {str(uf.id) for uf in valid_user_files}
    
    # Filter chunks: keep only those from valid (non-deleted) user files
    filtered_chunks = other_chunks.copy()
    filtered_count = 0
    for chunk, user_file_id in user_file_chunks:
        if str(user_file_id) in valid_user_file_ids:
            filtered_chunks.append(chunk)
        else:
            filtered_count += 1
            logger.debug(
                f"Filtered out chunk from deleted user_file: {user_file_id} "
                f"(document_id: {chunk.document_id})"
            )
    
    if filtered_count > 0:
        logger.info(
            f"Filtered out {filtered_count} chunk(s) from deleted user files"
        )
    
    return filtered_chunks
```

---

#### Change 2: Add Imports

**OLD CODE**:
```python
from onyx.utils.timing import log_function_time
from shared_configs.model_server_models import Embedding

logger = setup_logger()
```

**NEW CODE**:
```python
from onyx.utils.timing import log_function_time
from shared_configs.model_server_models import Embedding
from onyx.db.models import UserFile
from onyx.db.enums import UserFileStatus

logger = setup_logger()
```

---

#### Change 3: Update `doc_index_retrieval()` - Path 1 (with large chunks)

**OLD CODE**:
```python
    # Deduplicate the chunks
    deduped_chunks = list(unique_chunks.values())
    deduped_chunks.sort(key=lambda chunk: chunk.score or 0, reverse=True)
    return cleanup_chunks(deduped_chunks)
```

**NEW CODE**:
```python
    # Deduplicate the chunks
    deduped_chunks = list(unique_chunks.values())
    deduped_chunks.sort(key=lambda chunk: chunk.score or 0, reverse=True)
    
    # Filter out chunks from deleted user files (defense in depth)
    deduped_chunks = _filter_deleted_user_files(deduped_chunks, db_session)
    
    return cleanup_chunks(deduped_chunks)
```

---

#### Change 4: Update `doc_index_retrieval()` - Path 2 (no large chunks)

**OLD CODE**:
```python
    # If there are no large chunks, just return the normal chunks
    if not retrieval_requests:
        return cleanup_chunks(normal_chunks)
```

**NEW CODE**:
```python
    # If there are no large chunks, filter and return the normal chunks
    if not retrieval_requests:
        filtered_chunks = _filter_deleted_user_files(normal_chunks, db_session)
        return cleanup_chunks(filtered_chunks)
```

---

### Solution 2: Add Retry Logic to Deletion Task

**Location**: `backend/onyx/background/celery/tasks/user_file_processing/tasks.py`

**Problem**: If Vespa deletion fails, the task fails permanently with no retry.

---

#### Change 1: Add Retry Configuration to Task Decorator

**OLD CODE**:
```python
@shared_task(
    name=OnyxCeleryTask.DELETE_SINGLE_USER_FILE,
    bind=True,
    ignore_result=True,
)
def process_single_user_file_delete(
    self: Task, *, user_file_id: str, tenant_id: str
) -> None:
    """Process a single user file delete."""
```

**NEW CODE**:
```python
@shared_task(
    name=OnyxCeleryTask.DELETE_SINGLE_USER_FILE,
    bind=True,
    ignore_result=True,
    autoretry_for=(Exception,),  # ← NEW: Retry on any exception
    retry_kwargs={'max_retries': 3, 'countdown': 60},  # ← NEW: Retry 3 times, wait 60s between
)
def process_single_user_file_delete(
    self: Task, *, user_file_id: str, tenant_id: str
) -> None:
    """Process a single user file delete with retry logic."""  # ← Updated docstring
```

---

#### Change 2: Add Status Check Before Deletion

**OLD CODE**:
```python
            user_file = db_session.get(UserFile, _as_uuid(user_file_id))
            if not user_file:
                task_logger.info(
                    f"process_single_user_file_delete - User file not found id={user_file_id}"
                )
                return None

            # 1) Delete Vespa chunks for the document
```

**NEW CODE**:
```python
            user_file = db_session.get(UserFile, _as_uuid(user_file_id))
            if not user_file:
                task_logger.info(
                    f"process_single_user_file_delete - User file not found id={user_file_id}"
                )
                return None
            
            # ← NEW: Check if file is still in DELETING status
            if user_file.status != UserFileStatus.DELETING:
                task_logger.warning(
                    f"process_single_user_file_delete - File {user_file_id} is not in DELETING status, "
                    f"current status: {user_file.status}. Skipping deletion."
                )
                return None

            # 1) Delete Vespa chunks for the document
```

---

#### Change 3: Add Error Handling for Vespa Deletion

**OLD CODE**:
```python
            retry_index.delete_single(
                doc_id=user_file_id,
                tenant_id=tenant_id,
                chunk_count=chunk_count,
            )

            # 2) Delete the user-uploaded file content from filestore (blob + metadata)
```

**NEW CODE**:
```python
            # ← NEW: Wrap in try/except to catch Vespa errors
            try:
                retry_index.delete_single(
                    doc_id=user_file_id,
                    tenant_id=tenant_id,
                    chunk_count=chunk_count,
                )
                # ← NEW: Log success
                task_logger.info(
                    f"process_single_user_file_delete - Deleted {chunk_count} chunks from Vespa for {user_file_id}"
                )
            except Exception as vespa_error:
                # ← NEW: Log error and re-raise to trigger retry
                task_logger.error(
                    f"process_single_user_file_delete - Failed to delete from Vespa for {user_file_id}: {vespa_error}"
                )
                raise  # ← NEW: Re-raise to trigger Celery retry

            # 2) Delete the user-uploaded file content from filestore (blob + metadata)
```

---

#### Change 4: Improve File Store Error Handling

**OLD CODE**:
```python
            except Exception as e:
                # This block executed only if the file is not found in the filestore
                task_logger.exception(
                    f"process_single_user_file_delete - Error deleting file id={user_file.id} - {e.__class__.__name__}"
                )

            # 3) Finally, delete the UserFile row
```

**NEW CODE**:
```python
            except Exception as e:
                # ← UPDATED: Better error message and use warning instead of exception
                task_logger.warning(
                    f"process_single_user_file_delete - Error deleting from file store for {user_file_id}: {e.__class__.__name__}"
                )
                # ← NEW: Don't fail the whole task if file store deletion fails
                # The file may have already been deleted or not exist

            # 3) Finally, delete the UserFile row
```

---

#### Change 5: Re-raise Exceptions to Trigger Retry

**OLD CODE**:
```python
    except Exception as e:
        task_logger.exception(
            f"process_single_user_file_delete - Error processing file id={user_file_id} - {e.__class__.__name__}"
        )
        return None  # ← OLD: Returns None, no retry
```

**NEW CODE**:
```python
    except Exception as e:
        task_logger.exception(
            f"process_single_user_file_delete - Error processing file id={user_file_id} - {e.__class__.__name__}"
        )
        raise  # ← NEW: Re-raise to trigger Celery retry
```

---

### Solution 3: Add Monitoring and Alerting

**Location**: Add to monitoring setup

**Approach**: Monitor deletion task failures and alert when files remain in DELETING status too long.

**Implementation**:

```python
# Add to monitoring/alerting system
# Alert if user_file has been in DELETING status for > 1 hour
SELECT id, name, status, created_at
FROM user_file
WHERE status = 'DELETING'
AND created_at < NOW() - INTERVAL '1 hour';
```

---

## 📋 Implementation Steps

### Step 1: Add Validation Function to Search Flow

**File**: `onyx-repo/backend/onyx/context/search/retrieval/search_runner.py`

1. **Add imports** (see Change 2 above)
2. **Add `_filter_deleted_user_files()` function** (see Change 1 above)
3. **Update `doc_index_retrieval()` function** (see Changes 3 & 4 above)

**Quick Copy-Paste**:
- Copy the entire `_filter_deleted_user_files()` function from Change 1
- Add the two filter calls in `doc_index_retrieval()` from Changes 3 & 4

### Step 2: Update Deletion Task with Retry Logic

**File**: `onyx-repo/backend/onyx/background/celery/tasks/user_file_processing/tasks.py`

1. **Update task decorator** (see Change 1 above)
2. **Add status check** (see Change 2 above)
3. **Add Vespa error handling** (see Change 3 above)
4. **Update file store error handling** (see Change 4 above)
5. **Re-raise exceptions** (see Change 5 above)

**Quick Copy-Paste**:
- Update the `@shared_task` decorator
- Add the status check after getting `user_file`
- Wrap `retry_index.delete_single()` in try/except
- Change exception handler to re-raise

### Step 3: Test the Fix

1. Upload a test file
2. Wait for indexing to complete
3. Search for the file → File appears ✓
4. Delete the file via UI
5. Wait 30 seconds
6. Search for the file → File does NOT appear ✓
7. Check Celery logs for deletion task status
8. Verify Vespa chunks are deleted

### Step 4: Monitor

1. Set up alerting for files stuck in DELETING status
2. Monitor deletion task failure rate
3. Track search results for deleted files

---

## 🧪 Testing

### Test Case 1: Normal Deletion

```
1. Upload file "test.pdf"
2. Wait for indexing to complete
3. Search for "test" → File appears ✓
4. Delete "test.pdf" via UI
5. Wait 30 seconds
6. Search for "test" → File does NOT appear ✓
```

### Test Case 2: Vespa Deletion Failure

```
1. Upload file "test.pdf"
2. Stop Vespa service (simulate failure)
3. Delete "test.pdf" via UI
4. Search for "test" → File does NOT appear (filtered by validation) ✓
5. Restart Vespa
6. Verify deletion task retries and completes
```

### Test Case 3: Multiple Files

```
1. Upload 5 files
2. Delete 3 files
3. Search → Only 2 files appear ✓
```

---

## 📊 Expected Impact

### Before Fix
- ❌ Deleted files appear in search results
- ❌ No validation of file existence
- ❌ No retry on deletion failure
- ❌ Users confused by stale results

### After Fix
- ✅ Deleted files filtered from search results
- ✅ Database validation prevents stale results
- ✅ Automatic retry on deletion failure
- ✅ Better user experience

---

## 🔗 Related Files

- `onyx-repo/backend/onyx/context/search/retrieval/search_runner.py` - Search retrieval
- `onyx-repo/backend/onyx/background/celery/tasks/user_file_processing/tasks.py` - Deletion task
- `onyx-repo/backend/onyx/server/features/projects/api.py` - Delete API endpoint
- `onyx-repo/backend/onyx/db/models.py` - UserFile model
- `onyx-repo/backend/onyx/db/enums.py` - UserFileStatus enum

---

## 📝 Notes

- **Performance**: The validation adds a database query per search, but it's batched for efficiency
- **Backward Compatibility**: This change is backward compatible - existing searches will work, but deleted files will be filtered
- **Edge Cases**: Files in DELETING status are filtered, even if deletion task hasn't run yet

---

**Last Updated**: 2024  
**Author**: Onyx Deployment Team  
**Version**: 1.0

