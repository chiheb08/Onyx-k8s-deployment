# First Prompt Fix: Exact Code Changes

## File 1: Add Helper Functions to `user_file.py`

**File**: `onyx-repo/backend/onyx/db/user_file.py`

**Add after line 88** (after `get_file_id_by_user_file_id` function):

```python
def get_user_file_statuses_by_ids(
    user_file_ids: list[UUID],
    db_session: Session,
) -> dict[UUID, str]:
    """
    Get status for multiple user files by their IDs.
    
    Args:
        user_file_ids: List of user file UUIDs to check
        db_session: Database session
        
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
    
    Args:
        user_file_ids: List of user file UUIDs to validate
        db_session: Database session
        
    Returns:
        Tuple of:
            - all_ready (bool): True if all files are COMPLETED
            - not_ready_files (list): List of (file_id, status) tuples for files not ready
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

## File 2: Update `parse_user_files.py` to Validate Status

**File**: `onyx-repo/backend/onyx/chat/user_files/parse_user_files.py`

### Step 1: Add Imports

**Add after line 13**:

```python
from onyx.db.user_file import validate_user_files_ready
from onyx.db.enums import UserFileStatus
from fastapi import HTTPException
```

### Step 2: Add Validation in Function

**Find this section** (around lines 48-63):

```python
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
```

**Replace with**:

```python
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
        all_ready, not_ready_files = validate_user_files_ready(
            combined_user_file_ids,
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
```

---

## Complete Modified `parse_user_files.py` Function

Here's the complete function with all changes:

```python
from uuid import UUID

from sqlalchemy.orm import Session

from onyx.db.models import Persona
from onyx.db.models import UserFile
from onyx.db.projects import get_user_files_from_project
from onyx.db.user_file import update_last_accessed_at_for_user_files
from onyx.db.user_file import validate_user_files_ready  # ← NEW IMPORT
from onyx.file_store.models import InMemoryChatFile
from onyx.file_store.utils import get_user_files_as_user
from onyx.file_store.utils import load_in_memory_chat_files
from onyx.tools.models import SearchToolOverrideKwargs
from onyx.utils.logger import setup_logger
from onyx.db.enums import UserFileStatus  # ← NEW IMPORT
from fastapi import HTTPException  # ← NEW IMPORT


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
    # VALIDATION: Check that all files are COMPLETED before processing
    # ============================================================================
    if combined_user_file_ids:
        all_ready, not_ready_files = validate_user_files_ready(
            combined_user_file_ids,
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

## Testing the Fix

### Test 1: File Still Processing

```python
# Upload a file
# Immediately try to ask a question
# Expected: HTTP 400 error with message:
# "The following file(s) are not ready yet: 'document.pdf' (still processing). 
#  Please wait for the file(s) to finish processing before asking questions."
```

### Test 2: File Completed

```python
# Upload a file
# Wait for status to be COMPLETED
# Ask a question
# Expected: Works normally, returns answer
```

### Test 3: Multiple Files, Some Not Ready

```python
# Upload 3 files
# File 1: COMPLETED
# File 2: PROCESSING
# File 3: COMPLETED
# Try to ask question with all 3 files
# Expected: HTTP 400 error listing File 2 as "still processing"
```

---

## Deployment Checklist

- [ ] Add helper functions to `user_file.py`
- [ ] Update `parse_user_files.py` with validation
- [ ] Test locally with files in PROCESSING status
- [ ] Test with files in COMPLETED status
- [ ] Build Docker image
- [ ] Deploy to staging
- [ ] Test in staging environment
- [ ] Deploy to production
- [ ] Monitor logs for validation messages

---

## Expected Error Message Format

**Single file not ready**:
```
The following file(s) are not ready yet: "document.pdf" (still processing). Please wait for the file(s) to finish processing before asking questions. You can check the file status in the file list.
```

**Multiple files not ready**:
```
The following file(s) are not ready yet: "document1.pdf" (still processing), "document2.docx" (still processing). Please wait for the file(s) to finish processing before asking questions. You can check the file status in the file list.
```

**File failed**:
```
The following file(s) are not ready yet: "document.pdf" (failed to process). Please wait for the file(s) to finish processing before asking questions. You can check the file status in the file list.
```

