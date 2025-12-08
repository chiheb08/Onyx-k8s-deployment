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

**Approach**: After retrieving chunks from Vespa, validate that user_file chunks correspond to existing, non-deleted files.

**Implementation**:

```python
# Add this function to search_runner.py
def _filter_deleted_user_files(
    chunks: list[InferenceChunkUncleaned],
    db_session: Session,
) -> list[InferenceChunkUncleaned]:
    """
    Filter out chunks from deleted user files.
    
    This is a defense-in-depth measure to prevent deleted files
    from appearing in search results if Vespa deletion failed.
    """
    from onyx.db.models import UserFile
    from onyx.db.enums import UserFileStatus
    from onyx.configs.constants import DocumentSource
    
    # Identify chunks from user files
    user_file_chunks: list[InferenceChunkUncleaned] = []
    other_chunks: list[InferenceChunkUncleaned] = []
    
    for chunk in chunks:
        # Check if chunk is from a user file
        # document_id for user files is the user_file.id (UUID)
        try:
            from uuid import UUID
            # Try to parse as UUID - user files use UUID as document_id
            user_file_id = UUID(chunk.document_id)
            user_file_chunks.append((chunk, user_file_id))
        except (ValueError, TypeError):
            # Not a UUID, so not a user file
            other_chunks.append(chunk)
    
    if not user_file_chunks:
        return chunks
    
    # Batch query for all user files
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
    
    # Filter chunks: keep only those from valid user files
    filtered_chunks = other_chunks.copy()
    for chunk, user_file_id in user_file_chunks:
        if str(user_file_id) in valid_user_file_ids:
            filtered_chunks.append(chunk)
        else:
            logger.debug(
                f"Filtered out chunk from deleted user_file: {user_file_id}"
            )
    
    return filtered_chunks
```

**Update `doc_index_retrieval()` function**:

```python
def doc_index_retrieval(
    query: SearchQuery,
    document_index: DocumentIndex,
    db_session: Session,
) -> list[InferenceChunk]:
    # ... existing code ...
    
    # After getting top_chunks from Vespa, before cleanup_chunks:
    top_chunks = _dedupe_chunks(top_base_chunks_standard_ranking)
    
    # NEW: Filter out chunks from deleted user files
    top_chunks = _filter_deleted_user_files(top_chunks, db_session)
    
    # ... rest of existing code ...
    return cleanup_chunks(deduped_chunks)
```

---

### Solution 2: Add Retry Logic to Deletion Task

**Location**: `backend/onyx/background/celery/tasks/user_file_processing/tasks.py`

**Approach**: Add retry logic with exponential backoff for Vespa deletion failures.

**Implementation**:

```python
@shared_task(
    name=OnyxCeleryTask.DELETE_SINGLE_USER_FILE,
    bind=True,
    ignore_result=True,
    autoretry_for=(Exception,),
    retry_kwargs={'max_retries': 3, 'countdown': 60},  # Retry 3 times, wait 60s between
)
def process_single_user_file_delete(
    self: Task, *, user_file_id: str, tenant_id: str
) -> None:
    """Process a single user file delete with retry logic."""
    task_logger.info(f"process_single_user_file_delete - Starting id={user_file_id}")
    
    # ... existing lock code ...
    
    try:
        with get_session_with_current_tenant() as db_session:
            # ... existing Vespa setup code ...
            
            user_file = db_session.get(UserFile, _as_uuid(user_file_id))
            if not user_file:
                task_logger.info(
                    f"process_single_user_file_delete - User file not found id={user_file_id}"
                )
                return None
            
            # Check if file is still in DELETING status
            if user_file.status != UserFileStatus.DELETING:
                task_logger.warning(
                    f"process_single_user_file_delete - File {user_file_id} is not in DELETING status, "
                    f"current status: {user_file.status}. Skipping deletion."
                )
                return None
            
            # 1) Delete Vespa chunks with retry
            chunk_count = user_file.chunk_count or 0
            if chunk_count == 0:
                chunk_count = _get_document_chunk_count(
                    index_name=index_name,
                    selection=selection,
                )
            
            try:
                retry_index.delete_single(
                    doc_id=user_file_id,
                    tenant_id=tenant_id,
                    chunk_count=chunk_count,
                )
                task_logger.info(
                    f"process_single_user_file_delete - Deleted {chunk_count} chunks from Vespa for {user_file_id}"
                )
            except Exception as vespa_error:
                task_logger.error(
                    f"process_single_user_file_delete - Failed to delete from Vespa for {user_file_id}: {vespa_error}"
                )
                # Re-raise to trigger Celery retry
                raise
            
            # 2) Delete from file store
            file_store = get_default_file_store()
            try:
                file_store.delete_file(user_file.file_id)
                file_store.delete_file(
                    user_file_id_to_plaintext_file_name(user_file.id)
                )
            except Exception as e:
                task_logger.warning(
                    f"process_single_user_file_delete - Error deleting from file store for {user_file_id}: {e}"
                )
                # Don't fail the whole task if file store deletion fails
            
            # 3) Delete from PostgreSQL
            db_session.delete(user_file)
            db_session.commit()
            task_logger.info(
                f"process_single_user_file_delete - Completed id={user_file_id}"
            )
            
    except Exception as e:
        task_logger.exception(
            f"process_single_user_file_delete - Error processing file id={user_file_id}: {e.__class__.__name__}"
        )
        # Re-raise to trigger Celery retry
        raise
    finally:
        if file_lock.owned():
            file_lock.release()
    return None
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

### Step 1: Add Validation Function

1. Open `onyx-repo/backend/onyx/context/search/retrieval/search_runner.py`
2. Add `_filter_deleted_user_files()` function (see Solution 1)
3. Update `doc_index_retrieval()` to call the filter function

### Step 2: Update Deletion Task

1. Open `onyx-repo/backend/onyx/background/celery/tasks/user_file_processing/tasks.py`
2. Update `process_single_user_file_delete()` with retry logic (see Solution 2)
3. Add status check before deletion

### Step 3: Test the Fix

1. Upload a test file
2. Delete the file via UI
3. Verify file doesn't appear in search
4. Check Celery logs for deletion task status
5. Verify Vespa chunks are deleted

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

