# Complete Backend + Frontend Fixes for Deleted Files

## 🎯 Summary

This document lists **ALL** code changes needed to fix deleted files inconsistencies, including both **backend** and **frontend** changes.

---

## 📋 Backend Changes

### File 1: projects/api.py

**File Path**: `onyx-repo/backend/onyx/server/features/projects/api.py`

#### Change 1.1: Fix `get_files_in_project` Endpoint

**Location**: Function `get_files_in_project` (around line 133-147)

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
        .filter(UserFile.status != UserFileStatus.FAILED)  # ❌ Missing DELETING filter
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

#### Change 1.2: Fix `get_chat_session_project_files` Endpoint

**Location**: Function `get_chat_session_project_files` (around line 561-596)

**OLD CODE**:
```python
    user_files = (
        db_session.query(UserFile)
        .filter(
            UserFile.projects.any(id=chat_session.project_id),
            UserFile.user_id == user_id,
            UserFile.status != UserFileStatus.FAILED,  # ❌ Missing DELETING filter
        )
        .order_by(UserFile.created_at.desc())
        .all()
    )
```

**NEW CODE**:
```python
    user_files = (
        db_session.query(UserFile)
        .filter(
            UserFile.projects.any(id=chat_session.project_id),
            UserFile.user_id == user_id,
            UserFile.status != UserFileStatus.FAILED,
            UserFile.status != UserFileStatus.DELETING,  # ✅ NEW: Filter DELETING files
        )
        .order_by(UserFile.created_at.desc())
        .all()
    )
```

---

## 📋 Frontend Changes

### File 2: SearchToolRenderer.tsx

**File Path**: `onyx-repo/web/src/app/chat/message/messageComponents/renderers/SearchToolRenderer.tsx`

#### Change 2.1: Add Import

**Location**: Top of file, with other imports

**OLD CODE**:
```typescript
import { usePostHog } from "posthog-js/react";
import { ResearchType } from "@/app/chat/interfaces";
```

**NEW CODE**:
```typescript
import { usePostHog } from "posthog-js/react";
import { ResearchType } from "@/app/chat/interfaces";
import { useProjectsContext } from "@/app/chat/projects/ProjectsContext";  // NEW
```

---

#### Change 2.2: Add File Filtering Logic

**Location**: Inside `SearchToolRenderer` component, after `isDeepResearch` variable

**OLD CODE**:
```typescript
  // Check if this message has a research_type, which indicates it's using the simple agent framework
  const isDeepResearch = state.researchType === ResearchType.Deep;

  // Initialize all hooks at the top level (before any conditional returns)
  const { queries, results, isSearching, isComplete, isInternetSearch } =
    constructCurrentSearchState(packets);
```

**NEW CODE**:
```typescript
  // Check if this message has a research_type, which indicates it's using the simple agent framework
  const isDeepResearch = state.researchType === ResearchType.Deep;

  // Get valid file IDs from context to filter deleted files
  const { allRecentFiles } = useProjectsContext();
  const validFileIds = useMemo(() => {
    const valid = new Set<string>();
    allRecentFiles.forEach((file) => {
      if (file.status !== "DELETING" && file.status !== "FAILED") {
        valid.add(file.id);
      }
    });
    return valid;
  }, [allRecentFiles]);

  // Initialize all hooks at the top level (before any conditional returns)
  const { queries, results: rawResults, isSearching, isComplete, isInternetSearch } =
    constructCurrentSearchState(packets);

  // Filter out deleted user files from search results
  const results = useMemo(() => {
    return rawResults.filter((doc) => {
      // Only filter user_file sources
      if (doc.source_type === "user_file") {
        return validFileIds.has(doc.document_id);
      }
      // Keep all non-user-file documents
      return true;
    });
  }, [rawResults, validFileIds]);
```

---

### File 3: SearchToolRendererV2.tsx

**File Path**: `onyx-repo/web/src/app/chat/message/messageComponents/renderers/SearchToolRendererV2.tsx`

#### Change 3.1: Add Import

**Location**: Top of file, with other imports

**OLD CODE**:
```typescript
import { OnyxDocument } from "@/lib/search/interfaces";
import { ResultIcon } from "@/components/chat/sources/SourceCard";
```

**NEW CODE**:
```typescript
import { OnyxDocument } from "@/lib/search/interfaces";
import { ResultIcon } from "@/components/chat/sources/SourceCard";
import { useProjectsContext } from "@/app/chat/projects/ProjectsContext";  // NEW
```

---

#### Change 3.2: Add File Filtering Logic

**Location**: Inside `SearchToolRendererV2` component, at the start

**OLD CODE**:
```typescript
export const SearchToolRendererV2: MessageRenderer<SearchToolPacket, {}> = ({
  packets,
  onComplete,
  animate,
  children,
}) => {
  const { queries, results, isSearching, isComplete, isInternetSearch } =
    constructCurrentSearchState(packets);
```

**NEW CODE**:
```typescript
export const SearchToolRendererV2: MessageRenderer<SearchToolPacket, {}> = ({
  packets,
  onComplete,
  animate,
  children,
}) => {
  // Get valid file IDs from context to filter deleted files
  const { allRecentFiles } = useProjectsContext();
  const validFileIds = useMemo(() => {
    const valid = new Set<string>();
    allRecentFiles.forEach((file) => {
      if (file.status !== "DELETING" && file.status !== "FAILED") {
        valid.add(file.id);
      }
    });
    return valid;
  }, [allRecentFiles]);

  const { queries, results: rawResults, isSearching, isComplete, isInternetSearch } =
    constructCurrentSearchState(packets);

  // Filter out deleted user files from search results
  const results = useMemo(() => {
    return rawResults.filter((doc) => {
      // Only filter user_file sources
      if (doc.source_type === "user_file") {
        return validFileIds.has(doc.document_id);
      }
      // Keep all non-user-file documents
      return true;
    });
  }, [rawResults, validFileIds]);
```

---

### File 4: FilePickerPopover.tsx

**File Path**: `onyx-repo/web/src/refresh-components/popovers/FilePickerPopover.tsx`

#### Change 4.1: Enhance File Filtering

**Location**: Find the `useEffect` hook that sets `recentFilesSnapshot` (around line 201-205)

**OLD CODE**:
```typescript
  useEffect(() => {
    setRecentFilesSnapshot(
      allRecentFiles.slice().filter((f) => !deletedFileIds.includes(f.id))
    );
  }, [allRecentFiles]);
```

**NEW CODE**:
```typescript
  useEffect(() => {
    setRecentFilesSnapshot(
      allRecentFiles.slice().filter((f) => {
        // Filter by deleted IDs
        if (deletedFileIds.includes(f.id)) return false;
        // Filter by status - don't show DELETING or FAILED files
        if (f.status === UserFileStatus.DELETING) return false;
        if (f.status === UserFileStatus.FAILED) return false;
        return true;
      })
    );
  }, [allRecentFiles, deletedFileIds]);
```

---

## 📊 Summary Table

| File | Change | Type | Status |
|------|--------|------|--------|
| `projects/api.py` | Add DELETING filter to `get_files_in_project` | Backend | ✅ Applied |
| `projects/api.py` | Add DELETING filter to `get_chat_session_project_files` | Backend | ✅ Applied |
| `SearchToolRenderer.tsx` | Add import + filtering logic | Frontend | ✅ Applied |
| `SearchToolRendererV2.tsx` | Add import + filtering logic | Frontend | ✅ Applied |
| `FilePickerPopover.tsx` | Enhance filtering in useEffect | Frontend | ✅ Applied |

---

## 🎯 Expected Behavior After All Fixes

### Normal Deletion Flow

1. **User clicks delete** → File status set to `DELETING` immediately
2. **Backend filters** → All endpoints exclude `DELETING` files
3. **Frontend filters** → All UI components exclude `DELETING` files
4. **File disappears immediately** → From all lists, dropdowns, search results
5. **Background task runs** → Deletes from Vespa, file store, then DB
6. **File completely removed** → No traces left

### Consistency Points

- ✅ File disappears immediately from all lists (recent files, project files, dropdown)
- ✅ File doesn't appear in search results (backend + frontend filtering)
- ✅ File doesn't appear in same chat session
- ✅ File doesn't appear in new chat sessions
- ✅ File doesn't appear in file dropdown

---

## ✅ Verification Checklist

After applying all changes:

**Backend**:
- [ ] `get_files_in_project` filters DELETING files
- [ ] `get_chat_session_project_files` filters DELETING files
- [ ] No Python syntax errors
- [ ] Backend starts successfully

**Frontend**:
- [ ] `SearchToolRenderer.tsx` - Import added
- [ ] `SearchToolRenderer.tsx` - Filtering logic added
- [ ] `SearchToolRendererV2.tsx` - Import added
- [ ] `SearchToolRendererV2.tsx` - Filtering logic added
- [ ] `FilePickerPopover.tsx` - Enhanced filtering
- [ ] No TypeScript errors
- [ ] No linting errors
- [ ] Code compiles successfully

---

## 🚀 Testing

### Test 1: Same Chat Session
1. Upload file A
2. Ask question → File A appears ✓
3. Delete file A
4. Ask another question in same session → File A should NOT appear ✓

### Test 2: File Dropdown
1. Upload file B
2. Delete file B
3. Open new chat session
4. Click file dropdown → File B should NOT appear ✓

### Test 3: Project Files
1. Upload file C to project
2. Delete file C
3. View project files → File C should NOT appear ✓

### Test 4: Search Results
1. Upload file D
2. Ask question → File D appears ✓
3. Delete file D
4. View previous search results → File D should NOT appear ✓

---

**Last Updated**: 2024  
**Version**: 1.0

