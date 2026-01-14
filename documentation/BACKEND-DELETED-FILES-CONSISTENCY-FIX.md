# Backend Consistency Fix for Deleted Files

## 🐛 Problems Identified

1. **Inconsistent Filtering**: Some endpoints filter `DELETING` files, others don't
2. **Project Files Endpoint**: `get_files_in_project` doesn't filter `DELETING` files
3. **Chat Session Project Files Endpoint**: `get_chat_session_project_files` doesn't filter `DELETING` files
4. **Deletion Timing**: Files marked as `DELETING` may still appear briefly if any list endpoint still returns them
5. **No Immediate Feedback**: User doesn't know deletion is in progress

---

## ✅ Solution: Consistent Backend Filtering

### Problem 1: Project Files Endpoint Missing DELETING Filter

**File**: `onyx-repo/backend/onyx/server/features/projects/api.py`

**Location**: `get_files_in_project` function (around line 133-147)

**OLD CODE**:
```python
@router.get("/files/{project_id}")
def get_files_in_project(
    project_id: int,
    user: User | None = Depends(current_user),
    db_session: Session = Depends(get_session),
) -> list[UserFileSnapshot]:
    user_id = user.id if user is not None else None
    user_files = (
        db_session.query(UserFile)
        .filter(UserFile.projects.any(id=project_id), UserFile.user_id == user_id)
        .filter(UserFile.status != UserFileStatus.FAILED)  # ❌ Missing DELETING filter!
        .order_by(UserFile.created_at.desc())
        .all()
    )
    return [UserFileSnapshot.from_model(user_file) for user_file in user_files]
```

**NEW CODE**:
```python
@router.get("/files/{project_id}")
def get_files_in_project(
    project_id: int,
    user: User | None = Depends(current_user),
    db_session: Session = Depends(get_session),
) -> list[UserFileSnapshot]:
    user_id = user.id if user is not None else None
    user_files = (
        db_session.query(UserFile)
        .filter(UserFile.projects.any(id=project_id), UserFile.user_id == user_id)
        .filter(UserFile.status != UserFileStatus.FAILED)
        .filter(UserFile.status != UserFileStatus.DELETING)  # ✅ NEW: Filter DELETING files
        .order_by(UserFile.created_at.desc())
        .all()
    )
    return [UserFileSnapshot.from_model(user_file) for user_file in user_files]
```

---

### Problem 2: Chat Session Project Files Endpoint Missing DELETING Filter

**File**: `onyx-repo/backend/onyx/server/features/projects/api.py`

**Location**: `get_chat_session_project_files` (near the bottom of the file)

**Why it matters**: the UI often loads project files for an active chat session; if this endpoint doesn't filter `DELETING`, a deleted file can “come back” in the project/chat file list until the background delete finishes.

**Change**: add `.filter(UserFile.status != UserFileStatus.DELETING)` alongside the existing FAILED filter.

---

### Problem 3: Improve Deletion Task Reliability

**File**: `onyx-repo/backend/onyx/background/celery/tasks/user_file_processing/tasks.py`

**Current**: Task has retry logic, but we should ensure it completes faster.

**Enhancement**: Add immediate Vespa deletion attempt before enqueueing background task.

**File**: `onyx-repo/backend/onyx/server/features/projects/api.py`

**Location**: `delete_user_file` function (around line 387-433)

**OLD CODE**:
```python
    # No associations found; mark as DELETING and enqueue delete task
    user_file.status = UserFileStatus.DELETING
    db_session.commit()

    tenant_id = get_current_tenant_id()
    task = client_app.send_task(
        OnyxCeleryTask.DELETE_SINGLE_USER_FILE,
        kwargs={"user_file_id": str(user_file.id), "tenant_id": tenant_id},
        queue=OnyxCeleryQueues.USER_FILE_DELETE,
        priority=OnyxCeleryPriority.HIGH,
    )
    logger.info(
        f"Triggered delete for user_file_id={user_file.id} with task_id={task.id}"
    )
    return UserFileDeleteResult(
        has_associations=False, project_names=[], assistant_names=[]
    )
```

**NEW CODE** (Optional - for faster deletion):
```python
    # No associations found; mark as DELETING and enqueue delete task
    user_file.status = UserFileStatus.DELETING
    db_session.commit()

    tenant_id = get_current_tenant_id()
    
    # Try immediate deletion (non-blocking, doesn't wait for completion)
    # This makes deletion feel faster to the user
    try:
        task = client_app.send_task(
            OnyxCeleryTask.DELETE_SINGLE_USER_FILE,
            kwargs={"user_file_id": str(user_file.id), "tenant_id": tenant_id},
            queue=OnyxCeleryQueues.USER_FILE_DELETE,
            priority=OnyxCeleryPriority.HIGH,
        )
        logger.info(
            f"Triggered delete for user_file_id={user_file.id} with task_id={task.id}"
        )
    except Exception as e:
        # If enqueueing fails, log but don't fail the request
        # The check_for_user_file_delete beat task will pick it up
        logger.error(
            f"Failed to enqueue delete task for user_file_id={user_file.id}: {e}"
        )
    
    return UserFileDeleteResult(
        has_associations=False, project_names=[], assistant_names=[]
    )
```

**Note**: The current code is actually fine - the try/except is optional for better error handling.

---

## 📋 Complete List of Backend Changes

### Change 1: Fix Project Files Endpoint (`get_files_in_project`)

**File**: `onyx-repo/backend/onyx/server/features/projects/api.py`
**Function**: `get_files_in_project`
**Line**: ~143

**Change**: Add `.filter(UserFile.status != UserFileStatus.DELETING)`

---

### Change 2: Fix Chat Session Project Files Endpoint (`get_chat_session_project_files`)

**File**: `onyx-repo/backend/onyx/server/features/projects/api.py`
**Function**: `get_chat_session_project_files`

**Change**: Add `.filter(UserFile.status != UserFileStatus.DELETING)` (same as Change 1)

---

### Change 3: Verify Other Endpoints (Usually No Code Changes Needed)

In the official `onyx-dot-app/onyx` repo, these are already filtering `DELETING`:

1. ✅ `get_user_file` (in `projects/api.py`) - filters `DELETING`
2. ✅ `get_user_file_statuses` (in `projects/api.py`) - filters `DELETING` (so it will **NOT** return deleting files)

---

## 🔍 Additional Consistency Checks

### Check 1: Search Filtering

**File**: `onyx-repo/backend/onyx/context/search/retrieval/search_runner.py`

**Status**: ✅ Already implemented - `_filter_deleted_user_files` filters DELETING files

---

### Check 2: Display Filtering

**File**: `onyx-repo/backend/onyx/agents/agent_search/dr/utils.py`

**Status**: ✅ Already implemented - `convert_inference_sections_to_search_docs` filters DELETING files

---

### Check 3: Deletion Task

**File**: `onyx-repo/backend/onyx/background/celery/tasks/user_file_processing/tasks.py`

**Status**: ✅ Already has retry logic and status checking

---

## 🎯 Expected Behavior After Fix

### Normal Deletion Flow

1. **User clicks delete** → File status set to `DELETING` immediately
2. **File disappears from UI** → All endpoints filter `DELETING` files
3. **Background task runs** → Deletes from Vespa, file store, then DB
4. **File completely removed** → No traces left

### Consistency Points

- ✅ File disappears immediately from all lists (recent files, project files, dropdown)
- ✅ File doesn't appear in search results (backend + frontend filtering)
- ✅ File doesn't appear in new chat sessions
- ✅ File doesn't appear in file dropdown

---

## 📝 Summary

**2 backend changes needed**:

1. **Add DELETING filter to `get_files_in_project`**
2. **Add DELETING filter to `get_chat_session_project_files`**

**Most other endpoints are already correct in the official repo.**

---

**Last Updated**: 2024  
**Version**: 1.0


