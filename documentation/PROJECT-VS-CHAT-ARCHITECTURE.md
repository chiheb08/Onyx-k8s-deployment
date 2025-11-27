# Project vs Chat Architecture in Onyx

## Understanding the Issue

**GitHub Issue #69: "deleted files reappear in internal search"**

Users report:
1. Deleted files (CSV, HTML) still appear in internal search after being removed from projects
2. Different behavior within a **Project** vs in a **Chat**
3. Files deleted from projects are still being found by the model
4. Question: "Maybe different databases for Project vs Chat are in contact somewhere?"

---

## What is a Project vs a Chat?

### Chat (Regular Conversation)

A **Chat** is a standalone conversation session with the AI assistant.

| Aspect | Description |
|--------|-------------|
| **Purpose** | One-off Q&A, general questions |
| **Files** | Files attached to individual messages, temporary |
| **Persistence** | Files are attached to specific messages only |
| **Context** | Only files in the current message are used |
| **Database Table** | `chat_session` (no `project_id`) |

### Project

A **Project** is a persistent workspace that groups multiple chats and files together.

| Aspect | Description |
|--------|-------------|
| **Purpose** | Ongoing work on a specific topic/task |
| **Files** | Files are linked to the project, persistent |
| **Persistence** | Files remain available across all chats in the project |
| **Context** | All project files are available in every chat |
| **Database Table** | `user_project` + `project__user_file` (many-to-many) |

---

## Database Architecture

### Key Tables

```
+-------------------+       +-------------------+       +-------------------+
|      user         |       |   user_project    |       |    user_file      |
+-------------------+       +-------------------+       +-------------------+
| id (UUID)         |<----->| id (int)          |       | id (UUID)         |
| email             |       | user_id (FK)      |       | user_id (FK)      |
| ...               |       | name              |       | name              |
+-------------------+       | description       |       | file_id           |
                            | instructions      |       | document_id       |
                            +-------------------+       | status            |
                                    |                   | token_count       |
                                    |                   | chunk_count       |
                                    v                   +-------------------+
                            +-------------------+               |
                            | project__user_file|<--------------+
                            +-------------------+
                            | project_id (FK)   |
                            | user_file_id (FK) |
                            +-------------------+
                                    
+-------------------+
|   chat_session    |
+-------------------+
| id (UUID)         |
| user_id (FK)      |
| persona_id (FK)   |
| project_id (FK)   |<---- Links chat to project (nullable)
| description       |
| ...               |
+-------------------+
```

### Key Relationships

1. **User** owns multiple **Projects**
2. **User** owns multiple **Files**
3. **Project** contains multiple **Files** (via `project__user_file` many-to-many table)
4. **ChatSession** can belong to a **Project** (via `project_id` foreign key)
5. **File** can belong to multiple **Projects**

---

## How Search Works: The Two-Layer System

### Layer 1: PostgreSQL (Metadata)

Stores:
- File metadata (name, owner, status)
- Project-file relationships (`project__user_file`)
- Chat sessions and messages

### Layer 2: Vespa (Search Index)

Stores:
- Document chunks (text content)
- Embeddings (for semantic search)
- **`user_project` field** (array of project IDs)

```yaml
# Vespa Schema (danswer_chunk.sd.jinja)
field user_project type array<int> {
    indexing: summary | attribute
    rank: filter
    attribute: fast-search
}
```

---

## The Bug: Why Deleted Files Reappear

### The Problem Flow

```
1. User uploads file.csv to Project A
   - PostgreSQL: Creates UserFile record
   - PostgreSQL: Creates project__user_file link
   - Vespa: Indexes chunks with user_project = [project_A_id]

2. User removes file.csv from Project A (unlink, not delete)
   - PostgreSQL: Removes project__user_file link
   - Celery Task: Updates Vespa user_project = []
   
3. User searches in Project A
   - Query includes: user_project contains "project_A_id"
   - EXPECTED: File not found (user_project is empty)
   - ACTUAL: File sometimes still found!
```

### Root Causes

#### Cause 1: Vespa Sync Delay/Failure

When unlinking a file from a project, a Celery task is triggered:

```python
# backend/onyx/server/features/projects/api.py (line 150-196)
@router.delete("/{project_id}/files/{file_id}")
def unlink_user_file_from_project(...):
    # Remove PostgreSQL association
    project.user_files.remove(user_file)
    user_file.needs_project_sync = True
    db_session.commit()

    # Trigger async Vespa update
    task = client_app.send_task(
        OnyxCeleryTask.PROCESS_SINGLE_USER_FILE_PROJECT_SYNC,
        kwargs={"user_file_id": user_file.id, "tenant_id": tenant_id},
        ...
    )
```

The Celery task updates Vespa:

```python
# backend/onyx/background/celery/tasks/user_file_processing/tasks.py (line 548-620)
def process_single_user_file_project_sync(...):
    project_ids = [project.id for project in user_file.projects]
    retry_index.update_single(
        doc_id=str(user_file.id),
        ...
        user_fields=VespaDocumentUserFields(user_projects=project_ids),
    )
```

**Problem**: If this task fails, is delayed, or never runs, Vespa still has the old `user_project` array.

#### Cause 2: Internal Search Without Project Filter

When searching in a **Chat** (not a Project), the search might not filter by `user_project`:

```python
# backend/onyx/document_index/vespa/shared_utils/vespa_request_builders.py (line 140-150)
def _build_user_project_filter(project_id: int | None) -> str:
    if project_id is None:
        return ""  # NO FILTER APPLIED!
    return f'({USER_PROJECT} contains "{pid}") and '
```

**Problem**: If `project_id` is `None` (regular chat), ALL user files are searchable, including those unlinked from projects.

#### Cause 3: File Type Filtering Gap

The issue mentions CSV and HTML files:
- These might fail validation during upload
- But if they were indexed before validation, they remain in Vespa
- The error message ("Die Datei konnte nicht hochgeladen werden") appears, but the file is already indexed

---

## Diagrams

### Architecture: Project vs Chat Data Flow

```
                    +-----------------+
                    |     User        |
                    +-----------------+
                           |
           +---------------+---------------+
           |                               |
           v                               v
    +--------------+               +--------------+
    |   Project    |               |    Chat      |
    | (Persistent) |               | (Temporary)  |
    +--------------+               +--------------+
           |                               |
           | project_id                    | (no project_id)
           v                               v
    +--------------+               +--------------+
    | Chat Session |               | Chat Session |
    | (in project) |               | (standalone) |
    +--------------+               +--------------+
           |                               |
           v                               v
    +--------------+               +--------------+
    | Project Files|               | Message Files|
    | (persistent) |               | (per-message)|
    +--------------+               +--------------+
           |                               |
           +---------------+---------------+
                           |
                           v
                    +--------------+
                    |    Vespa     |
                    | (Search)     |
                    | user_project |
                    | field        |
                    +--------------+
```

### Search Query Flow

```
User Query in Project
        |
        v
+-------------------+
| Build Search      |
| Filters           |
+-------------------+
        |
        | project_id = 5
        v
+-------------------+
| Vespa Query:      |
| user_project      |
| contains "5"      |
+-------------------+
        |
        v
+-------------------+
| Return Results    |
| (Only project 5   |
|  files)           |
+-------------------+


User Query in Chat (No Project)
        |
        v
+-------------------+
| Build Search      |
| Filters           |
+-------------------+
        |
        | project_id = None
        v
+-------------------+
| Vespa Query:      |
| NO user_project   |
| filter!           |
+-------------------+
        |
        v
+-------------------+
| Return Results    |
| (ALL user files!) | <-- BUG: Includes unlinked files
+-------------------+
```

---

## Solutions

### Solution 1: Ensure Vespa Sync Completes (Recommended)

**Problem**: Celery task might fail silently.

**Fix**: Add retry logic and monitoring.

```python
# Check for failed syncs periodically
def check_pending_project_syncs(db_session: Session):
    pending_files = db_session.query(UserFile).filter(
        UserFile.needs_project_sync == True,
        UserFile.last_project_sync_at < datetime.now() - timedelta(minutes=5)
    ).all()
    
    for file in pending_files:
        # Re-trigger sync task
        client_app.send_task(
            OnyxCeleryTask.PROCESS_SINGLE_USER_FILE_PROJECT_SYNC,
            kwargs={"user_file_id": file.id, "tenant_id": tenant_id},
        )
```

### Solution 2: Synchronous Vespa Update on Unlink

**Problem**: Async task might not complete.

**Fix**: Update Vespa synchronously during the API call.

```python
# backend/onyx/server/features/projects/api.py
@router.delete("/{project_id}/files/{file_id}")
def unlink_user_file_from_project(...):
    # Remove PostgreSQL association
    project.user_files.remove(user_file)
    db_session.commit()

    # SYNC update to Vespa (blocking)
    project_ids = [p.id for p in user_file.projects]
    document_index.update_single(
        doc_id=str(user_file.id),
        user_fields=VespaDocumentUserFields(user_projects=project_ids),
    )
```

**Downside**: Slower API response, but more reliable.

### Solution 3: Filter by User Files in Chat

**Problem**: Chat searches return all user files.

**Fix**: When searching in a chat, only include files explicitly attached to the message.

```python
# backend/onyx/document_index/vespa/shared_utils/vespa_request_builders.py
def build_vespa_filters(filters: IndexFilters, ...):
    # If no project_id AND no explicit user_file_ids, exclude all user files
    if filters.project_id is None and not filters.user_file_ids:
        # Add filter to exclude user-uploaded files from general search
        filter_str += f"!({SOURCE_TYPE} = 'user_file') and "
```

### Solution 4: Verify File Status Before Indexing

**Problem**: Files with validation errors still get indexed.

**Fix**: Only index files with `status = COMPLETED`.

```python
# During search, verify file status in PostgreSQL
def filter_valid_user_files(file_ids: list[UUID], db_session: Session):
    valid_files = db_session.query(UserFile).filter(
        UserFile.id.in_(file_ids),
        UserFile.status == UserFileStatus.COMPLETED
    ).all()
    return [f.id for f in valid_files]
```

---

## Debugging Steps

### 1. Check PostgreSQL State

```sql
-- Check if file is linked to project
SELECT uf.id, uf.name, puf.project_id
FROM user_file uf
LEFT JOIN project__user_file puf ON uf.id = puf.user_file_id
WHERE uf.name LIKE '%your_file%';

-- Check if file needs sync
SELECT id, name, needs_project_sync, last_project_sync_at
FROM user_file
WHERE needs_project_sync = true;
```

### 2. Check Vespa State

```bash
# Query Vespa directly to see user_project field
curl -X POST "http://vespa:8080/search/" \
  -H "Content-Type: application/json" \
  -d '{
    "yql": "select documentid, user_project from onyx_chunk where document_id contains \"<file_id>\""
  }'
```

### 3. Check Celery Task Status

```bash
# Check Redis for pending tasks
redis-cli LRANGE celery 0 -1 | grep PROJECT_SYNC
```

---

## Summary

| Aspect | Project | Chat |
|--------|---------|------|
| **File Storage** | Persistent, linked via `project__user_file` | Attached to messages only |
| **Vespa Field** | `user_project = [project_ids]` | `user_project = []` or not set |
| **Search Filter** | `user_project contains "project_id"` | No project filter (bug!) |
| **Unlink Behavior** | Updates Vespa async | N/A |
| **Root Cause** | Vespa sync failure/delay | No isolation between chat and project files |

**The core issue**: When files are unlinked from projects, the Vespa index update happens asynchronously and can fail. Additionally, chats without a project don't filter out unlinked user files.

**Best Fix**: Implement Solution 1 (monitoring) + Solution 3 (filter user files in chat) for complete isolation.

