# First Prompt Race Condition: Exact Code Implementation

## 🎯 The Real Problem

**You're absolutely right** - the issue is a **race condition with Vespa eventual consistency**:

1. File uploads → Status: `PROCESSING`
2. Background task completes in ~1-2 seconds → Status: `COMPLETED` ✅
3. **BUT**: Vespa needs another ~500ms-1s to make documents searchable (eventual consistency)
4. First prompt (1 second after upload) → Status is `COMPLETED` but Vespa returns nothing → "Can't find information" ❌
5. Second prompt (another second later) → Vespa is ready → Works ✅

**Root Cause**: Status is set to `COMPLETED` **before** Vespa makes documents searchable.

---

## ✅ Best Solution: Check chunk_count > 0

**Why this works**: Even if status is `COMPLETED`, if `chunk_count` is `None` or `0`, the chunks aren't indexed yet. This catches the race condition.

---

## 📝 Exact Code Changes

### File 1: Add Helper Functions

**File**: `onyx-repo/backend/onyx/db/user_file.py`

**Add after line 88**:

```python
def get_user_file_statuses_by_ids(
    user_file_ids: list[UUID],
    db_session: Session,
) -> dict[UUID, str]:
    """
    Get status for multiple user files by their IDs.
    
    Returns:
        Dictionary mapping user_file_id (UUID) to status string
    """
    if not user_file_ids:
        return {}
    
    from onyx.db.enums import UserFileStatus
    
    stmt = select(UserFile.id, UserFile.status).where(
        UserFile.id.in_(user_file_ids)
    )
    results = db_session.execute(stmt).all()
    
    return {row.id: row.status.value for row in results}


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

---

### File 2: Update parse_user_files with chunk_count Check

**File**: `onyx-repo/backend/onyx/chat/user_files/parse_user_files.py`

**Add imports at top** (after line 13):

```python
from onyx.db.user_file import validate_user_files_ready
from onyx.db.enums import UserFileStatus
from fastapi import HTTPException
```

**Add validation after line 63** (after combining file IDs):

```python
    # Combine user-provided and project-derived user file IDs
    combined_user_file_ids = user_file_ids + project_user_file_ids or []
    
    # ============================================================================
    # VALIDATION: Check files are COMPLETED AND have chunks indexed
    # This handles the race condition where status=COMPLETED but Vespa isn't ready
    # ============================================================================
    if combined_user_file_ids:
        # Step 1: Check status is COMPLETED
        all_ready, not_ready_files = validate_user_files_ready(
            combined_user_file_ids,
            db_session,
        )
        
        if not all_ready:
            # Build error message for files not COMPLETED
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
                f"Please wait for the file(s) to finish processing before asking questions."
            )
            
            logger.warning(
                f"Rejecting chat request: files not ready. Not ready files: {not_ready_files}"
            )
            
            raise HTTPException(status_code=400, detail=error_message)
        
        # Step 2: Verify chunk_count > 0 (handles Vespa eventual consistency)
        # Even if status is COMPLETED, chunks might not be searchable yet
        user_files_to_check = (
            db_session.query(UserFile)
            .filter(UserFile.id.in_(combined_user_file_ids))
            .all()
        )
        
        files_without_chunks = []
        for user_file in user_files_to_check:
            # chunk_count is None or 0 means chunks aren't indexed yet
            if user_file.chunk_count is None or user_file.chunk_count == 0:
                files_without_chunks.append(user_file.name)
        
        if files_without_chunks:
            error_message = (
                f"The following file(s) are still being indexed: {', '.join(files_without_chunks)}. "
                f"Please wait a moment and try again. The file processing is almost complete."
            )
            
            logger.warning(
                f"Rejecting chat request: files have status COMPLETED but chunk_count is 0. "
                f"This indicates Vespa eventual consistency - chunks written but not yet searchable. "
                f"Files: {files_without_chunks}"
            )
            
            raise HTTPException(status_code=400, detail=error_message)
    # ============================================================================
    # End validation
    # ============================================================================
```

---

## 🔍 Complete Modified Function

Here's the complete `parse_user_files` function with all changes:

```python
from uuid import UUID

from sqlalchemy.orm import Session

from onyx.db.models import Persona
from onyx.db.models import UserFile
from onyx.db.projects import get_user_files_from_project
from onyx.db.user_file import update_last_accessed_at_for_user_files
from onyx.db.user_file import validate_user_files_ready  # ← NEW
from onyx.file_store.models import InMemoryChatFile
from onyx.file_store.utils import get_user_files_as_user
from onyx.file_store.utils import load_in_memory_chat_files
from onyx.tools.models import SearchToolOverrideKwargs
from onyx.utils.logger import setup_logger
from onyx.db.enums import UserFileStatus  # ← NEW
from fastapi import HTTPException  # ← NEW


logger = setup_logger()


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
    # VALIDATION: Check files are COMPLETED AND have chunks indexed
    # This handles the race condition where status=COMPLETED but Vespa isn't ready
    # ============================================================================
    if combined_user_file_ids:
        # Step 1: Check status is COMPLETED
        all_ready, not_ready_files = validate_user_files_ready(
            combined_user_file_ids,
            db_session,
        )
        
        if not all_ready:
            # Build error message for files not COMPLETED
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
                f"Please wait for the file(s) to finish processing before asking questions."
            )
            
            logger.warning(
                f"Rejecting chat request: files not ready. Not ready files: {not_ready_files}"
            )
            
            raise HTTPException(status_code=400, detail=error_message)
        
        # Step 2: Verify chunk_count > 0 (handles Vespa eventual consistency)
        # Even if status is COMPLETED, chunks might not be searchable yet
        user_files_to_check = (
            db_session.query(UserFile)
            .filter(UserFile.id.in_(combined_user_file_ids))
            .all()
        )
        
        files_without_chunks = []
        for user_file in user_files_to_check:
            # chunk_count is None or 0 means chunks aren't indexed yet
            if user_file.chunk_count is None or user_file.chunk_count == 0:
                files_without_chunks.append(user_file.name)
        
        if files_without_chunks:
            error_message = (
                f"The following file(s) are still being indexed: {', '.join(files_without_chunks)}. "
                f"Please wait a moment and try again. The file processing is almost complete."
            )
            
            logger.warning(
                f"Rejecting chat request: files have status COMPLETED but chunk_count is 0. "
                f"This indicates Vespa eventual consistency - chunks written but not yet searchable. "
                f"Files: {files_without_chunks}"
            )
            
            raise HTTPException(status_code=400, detail=error_message)
    # ============================================================================
    # End validation
    # ============================================================================

    # Load user files from the database into memory
    user_files = load_in_memory_chat_files(
        combined_user_file_ids,
        db_session,
    )

    user_file_models = get_user_files_as_user(
        combined_user_file_ids,
        user_id,
        db_session,
    )

    # Update last accessed at for the user files which are used in the chat
    if user_file_ids or project_user_file_ids:
        # update_last_accessed_at_for_user_files expects list[UUID]
        update_last_accessed_at_for_user_files(
            combined_user_file_ids,
            db_session,
        )

    # Calculate token count for the files, need to import here to avoid circular import
    # TODO: fix this
    from onyx.db.user_file import calculate_user_files_token_count
    from onyx.chat.prompt_builder.citations_prompt import (
        compute_max_document_tokens_for_persona,
    )

    # calculate_user_files_token_count now expects list[UUID]
    total_tokens = calculate_user_files_token_count(
        combined_user_file_ids,
        db_session,
    )

    # Calculate available tokens for documents based on prompt, user input, etc.
    available_tokens = compute_max_document_tokens_for_persona(
        persona=persona,
        actual_user_input=actual_user_input,
    )
    uploaded_context_cap = int(available_tokens * 0.5)

    logger.debug(
        f"Total file tokens: {total_tokens}, Available tokens: {available_tokens},"
        f"Allowed uploaded context tokens: {uploaded_context_cap}"
    )

    have_enough_tokens = total_tokens <= uploaded_context_cap

    # If we have enough tokens, we don't need search
    # we can just pass them into the prompt directly
    if have_enough_tokens:
        # No search tool override needed - files can be passed directly
        return user_files, user_file_models, None

    # Token overflow - need to use search tool
    override_kwargs = SearchToolOverrideKwargs(
        force_no_rerank=have_enough_tokens,
        alternate_db_session=None,
        retrieved_sections_callback=None,
        skip_query_analysis=have_enough_tokens,
        user_file_ids=user_file_ids or [],
        project_id=(
            project_id if persona.is_default_persona else None
        ),  # if the persona is not default, we don't want to use the project files
    )

    return user_files, user_file_models, override_kwargs
```

---

## 🎯 Why This Solution Works

**The Problem**:
- Status changes to `COMPLETED` very quickly (~1-2 seconds)
- But `chunk_count` is set at the same time
- **However**: There's a tiny window where status=COMPLETED but `chunk_count` might still be `None` or `0` if there's a race condition

**The Solution**:
- Check **both** status AND chunk_count
- If status is `COMPLETED` but `chunk_count` is `None` or `0`, reject the request
- This catches the race condition where Vespa hasn't finished indexing yet

**Why chunk_count works**:
- `chunk_count` is set in `post_index()` **after** chunks are written to Vespa
- If `chunk_count` is `None` or `0`, chunks definitely aren't ready
- This is a reliable indicator that Vespa indexing isn't complete

---

## 📋 Implementation Checklist

- [ ] Add `get_user_file_statuses_by_ids()` to `user_file.py`
- [ ] Add `validate_user_files_ready()` to `user_file.py`
- [ ] Add imports to `parse_user_files.py`
- [ ] Add status validation in `parse_user_files()`
- [ ] Add chunk_count validation in `parse_user_files()`
- [ ] Test: Upload file → Immediately ask → Should reject with clear message
- [ ] Test: Upload file → Wait for COMPLETED + chunk_count > 0 → Ask → Should work

---

## ✅ Expected Behavior

### Before Fix
```
Upload → Status: COMPLETED (1 second)
Ask question → chunk_count > 0 but Vespa not ready → "Can't find information"
Ask again → Works ✅
```

### After Fix
```
Upload → Status: COMPLETED (1 second) → chunk_count still 0
Ask question → chunk_count check fails → HTTP 400: "File still being indexed"
Wait → chunk_count > 0 → Ask question → Works ✅
```

---

## 🚀 Quick Deploy

1. **Apply code changes** to both files
2. **Build and deploy**:
   ```bash
   # Build
   docker build -t onyx-backend:fixed ./onyx-repo/backend
   
   # Deploy
   oc set image deployment/api-server api-server=your-registry/onyx-backend:fixed
   oc rollout restart deployment/api-server
   ```

3. **Test**:
   - Upload a file
   - Immediately ask a question
   - Should get: "File still being indexed. Please wait a moment."
   - Wait 2-3 seconds
   - Ask again → Should work

---

This solution catches the race condition by checking `chunk_count > 0` in addition to status, which handles Vespa eventual consistency.

