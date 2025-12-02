# Complete Fix: First Prompt "Can't Find Information" Issue

## 🎯 Problem Summary

**Symptom**: When you upload a file and immediately ask a question, Onyx says "I can't find any information related to your question." But when you ask a second time, it works fine.

**Root Cause**: 
- Files are processed asynchronously (background Celery task)
- File status starts as `PROCESSING` and changes to `COMPLETED` when embeddings are ready
- The first prompt happens before embeddings are ready
- For large files, Onyx uses **retrieval** (search via embeddings) instead of **inline** (direct text in prompt)
- Since embeddings aren't ready, retrieval returns nothing → LLM says "can't find information"
- By the second prompt, embeddings are ready → retrieval works → answer is correct

**Impact**: Poor user experience, users think the system is broken

---

## 🔍 Technical Deep Dive

### Current Flow (Broken)

```
1. User uploads file
   └─ Status: PROCESSING
   └─ Celery task enqueued: process_single_user_file

2. User immediately asks question
   └─ parse_user_files() called
   └─ Checks: total_tokens > uploaded_context_cap?
   └─ YES → Uses retrieval (search via embeddings)
   └─ Retrieval fails: embeddings not ready yet
   └─ LLM receives: "No relevant documents found"
   └─ LLM responds: "I can't find any information"

3. Background task completes
   └─ Status: COMPLETED
   └─ Embeddings stored in Vespa

4. User asks second question
   └─ parse_user_files() called
   └─ Uses retrieval (search via embeddings)
   └─ Retrieval succeeds: embeddings are ready
   └─ LLM receives: relevant document chunks
   └─ LLM responds: correct answer ✅
```

### Problem Location

**File**: `backend/onyx/chat/user_files/parse_user_files.py`

**Issue**: No validation that files are `COMPLETED` before using them for retrieval.

**Current Code** (lines 19-130):
- Loads files without checking status
- Decides inline vs retrieval based on token count
- For retrieval, assumes embeddings are ready (they're not!)

---

## ✅ Complete Solution

### Solution 1: Backend Validation (Primary Fix)

**Add file status validation before processing**

#### Step 1: Create Helper Function

**File**: `backend/onyx/db/user_file.py`

**Add this function** (after line 88):

```python
def get_user_file_statuses_by_ids(
    user_file_ids: list[UUID],
    db_session: Session,
) -> dict[UUID, str]:
    """
    Get status for multiple user files by their IDs.
    
    Returns:
        Dictionary mapping user_file_id to status string
    """
    if not user_file_ids:
        return {}
    
    from onyx.db.models import UserFile
    from onyx.db.enums import UserFileStatus
    
    user_files = (
        db_session.query(UserFile)
        .filter(UserFile.id.in_(user_file_ids))
        .all()
    )
    
    return {uf.id: uf.status.value for uf in user_files}


def validate_user_files_ready(
    user_file_ids: list[UUID],
    db_session: Session,
) -> tuple[bool, list[tuple[UUID, str]]]:
    """
    Validate that all user files are COMPLETED and ready for use.
    
    Returns:
        Tuple of (all_ready: bool, not_ready_files: list[(file_id, status)])
    """
    if not user_file_ids:
        return True, []
    
    from onyx.db.enums import UserFileStatus
    
    statuses = get_user_file_statuses_by_ids(user_file_ids, db_session)
    not_ready = []
    
    for file_id in user_file_ids:
        status = statuses.get(file_id)
        if status != UserFileStatus.COMPLETED.value:
            not_ready.append((file_id, status or "NOT_FOUND"))
    
    return len(not_ready) == 0, not_ready
```

#### Step 2: Update `parse_user_files` to Validate Status

**File**: `backend/onyx/chat/user_files/parse_user_files.py`

**Add import at top** (after line 13):

```python
from onyx.db.user_file import validate_user_files_ready
from onyx.db.enums import UserFileStatus
from fastapi import HTTPException
```

**Add validation at the start of function** (after line 50, before loading files):

```python
def parse_user_files(
    user_file_ids: list[UUID],
    db_session: Session,
    persona: Persona,
    actual_user_input: str,
    project_id: int | None,
    # should only be None if auth is disabled
    user_id: UUID | None,
) -> tuple[list[InMemoryChatFile], list[UserFile], SearchToolOverrideKwargs | None]:
    """
    Parse user files and project into in-memory chat files and create search tool override kwargs.
    Only creates SearchToolOverrideKwargs if token overflow occurs.
    """
    # Return empty results if no files or project specified
    if not user_file_ids and not project_id:
        return [], [], None

    project_user_file_ids = []

    if project_id:
        project_user_file_ids.extend(
            [
                file.id
                for file in get_user_files_from_project(project_id, user_id, db_session)
            ]
        )

    # Combine user-provided and project-derived user file IDs
    combined_user_file_ids = user_file_ids + project_user_file_ids or []
    
    # ============================================================================
    # VALIDATION: Check that all files are COMPLETED before processing
    # ============================================================================
    if combined_user_file_ids:
        from onyx.db.user_file import validate_user_files_ready
        
        all_ready, not_ready_files = validate_user_files_ready(
            combined_user_file_ids,
            db_session,
        )
        
        if not all_ready:
            # Build user-friendly error message
            from onyx.db.models import UserFile
            
            file_names = []
            for file_id, status in not_ready_files:
                user_file = db_session.get(UserFile, file_id)
                file_name = user_file.name if user_file else f"File {file_id}"
                status_display = {
                    UserFileStatus.PROCESSING.value: "still processing",
                    UserFileStatus.FAILED.value: "failed to process",
                    UserFileStatus.CANCELED.value: "was canceled",
                    UserFileStatus.DELETING.value: "is being deleted",
                }.get(status, f"has status: {status}")
                
                file_names.append(f'"{file_name}" ({status_display})')
            
            error_message = (
                f"The following file(s) are not ready yet: {', '.join(file_names)}. "
                f"Please wait for the file(s) to finish processing before asking questions. "
                f"You can check the file status in the file list."
            )
            
            logger.warning(
                f"Rejecting chat request: files not ready. "
                f"Not ready files: {not_ready_files}"
            )
            
            raise HTTPException(
                status_code=400,
                detail=error_message,
            )
    # ============================================================================
    # End validation
    # ============================================================================

    # Load user files from the database into memory
    user_files = load_in_memory_chat_files(
        combined_user_file_ids,
        db_session,
    )

    # ... rest of function remains the same ...
```

#### Step 3: Update `stream_chat_message_objects` (Alternative Location)

**File**: `backend/onyx/chat/process_message.py`

**Alternative approach**: Validate in `stream_chat_message_objects` before calling `parse_user_files`.

**Add validation** (around line 539, before calling `parse_user_files`):

```python
        # Validate that all user files are ready before processing
        if user_file_ids:
            from onyx.db.user_file import validate_user_files_ready
            from onyx.db.models import UserFile
            from onyx.db.enums import UserFileStatus
            
            all_ready, not_ready_files = validate_user_files_ready(
                user_file_ids,
                db_session,
            )
            
            if not all_ready:
                # Build user-friendly error message
                file_names = []
                for file_id, status in not_ready_files:
                    user_file = db_session.get(UserFile, file_id)
                    file_name = user_file.name if user_file else f"File {file_id}"
                    status_display = {
                        UserFileStatus.PROCESSING.value: "still processing",
                        UserFileStatus.FAILED.value: "failed to process",
                        UserFileStatus.CANCELED.value: "was canceled",
                    }.get(status, f"has status: {status}")
                    
                    file_names.append(f'"{file_name}" ({status_display})')
                
                error_message = (
                    f"The following file(s) are not ready yet: {', '.join(file_names)}. "
                    f"Please wait for the file(s) to finish processing. "
                    f"You can see the processing status next to each file."
                )
                
                from fastapi import HTTPException
                raise HTTPException(
                    status_code=400,
                    detail=error_message,
                )

        # Load in user files into memory and create search tool override kwargs if needed
        (
            in_memory_user_files,
            user_file_models,
            search_tool_override_kwargs_for_user_files,
        ) = parse_user_files(
            user_file_ids=user_file_ids or [],
            project_id=chat_session.project_id,
            db_session=db_session,
            persona=persona,
            actual_user_input=message_text,
            user_id=user_id,
        )
```

---

### Solution 2: Frontend Enhancement (Secondary Fix)

**File**: `onyx-repo/web/src/app/chat/components/input/ChatInputBar.tsx`

**Already documented in**: `PENDING-FILE-UPLOAD-BUG-FIX.md`

**Summary**: Disable send button and Enter key when files are `PROCESSING` or `UPLOADING`.

---

## 📋 Complete Implementation Checklist

### Backend Changes

- [ ] **Step 1**: Add `get_user_file_statuses_by_ids()` to `backend/onyx/db/user_file.py`
- [ ] **Step 2**: Add `validate_user_files_ready()` to `backend/onyx/db/user_file.py`
- [ ] **Step 3**: Add validation in `parse_user_files()` OR `stream_chat_message_objects()`
- [ ] **Step 4**: Test with files in PROCESSING status (should reject)
- [ ] **Step 5**: Test with files in COMPLETED status (should work)
- [ ] **Step 6**: Test with mixed status files (should reject with clear message)

### Frontend Changes (Optional but Recommended)

- [ ] **Step 7**: Disable send button when files are PROCESSING (already documented)
- [ ] **Step 8**: Show tooltip explaining why send is disabled
- [ ] **Step 9**: Display file processing status in UI

### Testing

- [ ] **Test 1**: Upload large file, immediately ask question → Should get 400 error with clear message
- [ ] **Test 2**: Upload large file, wait for COMPLETED, ask question → Should work
- [ ] **Test 3**: Upload small file (inline), immediately ask question → Should work (inline doesn't need embeddings)
- [ ] **Test 4**: Upload multiple files, some PROCESSING, some COMPLETED → Should reject with list of not-ready files

---

## 🔧 Code Changes Summary

### File 1: `backend/onyx/db/user_file.py`

**Add two new functions**:
1. `get_user_file_statuses_by_ids()` - Get statuses for multiple files
2. `validate_user_files_ready()` - Validate all files are COMPLETED

### File 2: `backend/onyx/chat/user_files/parse_user_files.py`

**Add validation** at the start of `parse_user_files()` function:
- Check all files are COMPLETED
- Raise HTTPException with user-friendly message if not ready

**OR**

### File 2 Alternative: `backend/onyx/chat/process_message.py`

**Add validation** in `stream_chat_message_objects()` before calling `parse_user_files()`:
- Same validation logic
- Rejects request early with clear error

---

## 🎯 Recommended Approach

**Use Solution 1 (Backend Validation in `parse_user_files`)**

**Why**:
- Centralized validation logic
- Works for all code paths that use `parse_user_files`
- Clear error messages
- Prevents the issue at the source

**Implementation Priority**:
1. ✅ **HIGH**: Add validation in `parse_user_files()` (prevents the bug)
2. ✅ **MEDIUM**: Enhance frontend to disable send button (better UX)
3. ✅ **LOW**: Add monitoring/alerting for processing times

---

## 📊 Expected Behavior After Fix

### Before Fix
```
User: Uploads file → Immediately asks question
System: "I can't find any information related to your question."
User: Asks again
System: [Correct answer] ✅
```

### After Fix
```
User: Uploads file → Immediately asks question
System: HTTP 400 Error: "The following file(s) are not ready yet: 'document.pdf' (still processing). Please wait for the file(s) to finish processing before asking questions."
User: Waits for file to show "Completed" → Asks question
System: [Correct answer] ✅
```

---

## 🚀 Deployment Steps

1. **Apply backend code changes**
   ```bash
   cd onyx-repo/backend
   # Make code changes
   # Build and push Docker image
   ```

2. **Update deployment**
   ```bash
   oc set image deployment/api-server api-server=your-registry/onyx-backend:new-tag
   oc rollout restart deployment/api-server
   ```

3. **Verify**
   ```bash
   # Check logs
   oc logs -f deployment/api-server | grep -i "files not ready"
   
   # Test: Upload file, immediately ask question
   # Should get 400 error with clear message
   ```

---

## 📚 Related Documentation

- `LARGE-FILE-FIRST-PROMPT-BEHAVIOR.md` - Explains the root cause
- `PENDING-FILE-UPLOAD-BUG-FIX.md` - Frontend fixes
- `COMPLETE-FILE-UPLOAD-FIX.md` - Performance optimizations

---

## ✅ Summary

**Problem**: First prompt fails because files aren't indexed yet.

**Solution**: Validate file status before processing. Reject requests with clear error if files are still PROCESSING.

**Impact**: 
- ✅ Prevents confusing "can't find information" messages
- ✅ Clear error messages guide users to wait
- ✅ Better user experience
- ✅ Prevents wasted LLM API calls

**Priority**: **CRITICAL** - This is a major UX issue that confuses users.

