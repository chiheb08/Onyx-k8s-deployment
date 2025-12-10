# All Changes Required - Old vs New Code

## 📋 Complete List of All Changes

This document shows **exactly** what to change in each file, with **old code** vs **new code** for every modification.

---

## 🔧 Backend Changes (2 files)

### File 1: projects/api.py

**File Path**: `onyx-repo/backend/onyx/server/features/projects/api.py`

---

#### Change 1.1: Fix `get_files_in_project` Function

**Location**: Around line 133-147

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
        .filter(UserFile.status != UserFileStatus.FAILED)
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
        .filter(UserFile.status != UserFileStatus.DELETING)  # ✅ ADD THIS LINE
        .order_by(UserFile.created_at.desc())
        .all()
    )
    return [UserFileSnapshot.from_model(user_file) for user_file in user_files]
```

**What Changed**: Added `.filter(UserFile.status != UserFileStatus.DELETING)` on line 144

---

#### Change 1.2: Fix `get_chat_session_project_files` Function

**Location**: Around line 561-597

**OLD CODE**:
```python
    user_files = (
        db_session.query(UserFile)
        .filter(
            UserFile.projects.any(id=chat_session.project_id),
            UserFile.user_id == user_id,
            UserFile.status != UserFileStatus.FAILED,
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
            UserFile.status != UserFileStatus.DELETING,  # ✅ ADD THIS LINE
        )
        .order_by(UserFile.created_at.desc())
        .all()
    )
```

**What Changed**: Added `UserFile.status != UserFileStatus.DELETING,` in the filter on line 591

---

## 🎨 Frontend Changes (3 files)

### File 2: SearchToolRenderer.tsx

**File Path**: `onyx-repo/web/src/app/chat/message/messageComponents/renderers/SearchToolRenderer.tsx`

---

#### Change 2.1: Add Import

**Location**: Top of file, with other imports (around line 18)

**OLD CODE**:
```typescript
import { SearchToolRendererV2 } from "./SearchToolRendererV2";
import { usePostHog } from "posthog-js/react";
import { ResearchType } from "@/app/chat/interfaces";
```

**NEW CODE**:
```typescript
import { SearchToolRendererV2 } from "./SearchToolRendererV2";
import { usePostHog } from "posthog-js/react";
import { ResearchType } from "@/app/chat/interfaces";
import { useProjectsContext } from "@/app/chat/projects/ProjectsContext";  // ✅ ADD THIS LINE
```

---

#### Change 2.2: Add File Filtering Logic

**Location**: Inside `SearchToolRenderer` component, after `isDeepResearch` variable (around line 87-91)

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

**What Changed**: 
- Added `useProjectsContext` hook call
- Added `validFileIds` memoized set
- Changed `results` to `rawResults` in `constructCurrentSearchState`
- Added `results` memoized filter

---

### File 3: SearchToolRendererV2.tsx

**File Path**: `onyx-repo/web/src/app/chat/message/messageComponents/renderers/SearchToolRendererV2.tsx`

---

#### Change 3.1: Add Import

**Location**: Top of file, with other imports (around line 15)

**OLD CODE**:
```typescript
import { OnyxDocument } from "@/lib/search/interfaces";
import { ResultIcon } from "@/components/chat/sources/SourceCard";
```

**NEW CODE**:
```typescript
import { OnyxDocument } from "@/lib/search/interfaces";
import { ResultIcon } from "@/components/chat/sources/SourceCard";
import { useProjectsContext } from "@/app/chat/projects/ProjectsContext";  // ✅ ADD THIS LINE
```

---

#### Change 3.2: Add File Filtering Logic

**Location**: Inside `SearchToolRendererV2` component, at the start (around line 71-78)

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

**What Changed**: 
- Added `useProjectsContext` hook call
- Added `validFileIds` memoized set
- Changed `results` to `rawResults` in `constructCurrentSearchState`
- Added `results` memoized filter

---

### File 4: FilePickerPopover.tsx

**File Path**: `onyx-repo/web/src/refresh-components/popovers/FilePickerPopover.tsx`

---

#### Change 4.1: Enhance File Filtering in useEffect

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
  }, [allRecentFiles, deletedFileIds]);  // ✅ ADD deletedFileIds to dependencies
```

**What Changed**: 
- Enhanced filter to check both `deletedFileIds` and file status
- Added status checks for `DELETING` and `FAILED`
- Added `deletedFileIds` to dependency array

---

## 📊 Quick Reference Table

| File | Line | Change Type | What to Add |
|------|------|-------------|-------------|
| `projects/api.py` | ~144 | Backend | `.filter(UserFile.status != UserFileStatus.DELETING)` |
| `projects/api.py` | ~591 | Backend | `UserFile.status != UserFileStatus.DELETING,` in filter |
| `SearchToolRenderer.tsx` | ~18 | Frontend | Import `useProjectsContext` |
| `SearchToolRenderer.tsx` | ~87-91 | Frontend | Add filtering logic (see Change 2.2) |
| `SearchToolRendererV2.tsx` | ~15 | Frontend | Import `useProjectsContext` |
| `SearchToolRendererV2.tsx` | ~71-78 | Frontend | Add filtering logic (see Change 3.2) |
| `FilePickerPopover.tsx` | ~201-205 | Frontend | Enhance filter (see Change 4.1) |

---

## ✅ Step-by-Step Application

### Step 1: Backend Changes

1. Open `onyx-repo/backend/onyx/server/features/projects/api.py`
2. Find `get_files_in_project` function (line ~133)
3. Add `.filter(UserFile.status != UserFileStatus.DELETING)` after line 143
4. Find `get_chat_session_project_files` function (line ~561)
5. Add `UserFile.status != UserFileStatus.DELETING,` in the filter (line ~591)
6. Save file

### Step 2: Frontend Changes

1. Open `onyx-repo/web/src/app/chat/message/messageComponents/renderers/SearchToolRenderer.tsx`
2. Add import at top (line ~18)
3. Add filtering logic after `isDeepResearch` (line ~87)
4. Save file

5. Open `onyx-repo/web/src/app/chat/message/messageComponents/renderers/SearchToolRendererV2.tsx`
6. Add import at top (line ~15)
7. Add filtering logic at start of component (line ~71)
8. Save file

9. Open `onyx-repo/web/src/refresh-components/popovers/FilePickerPopover.tsx`
10. Find `useEffect` hook (line ~201)
11. Replace filter logic with enhanced version
12. Save file

### Step 3: Verify

```bash
# Backend
cd onyx-repo/backend
python -m py_compile onyx/server/features/projects/api.py

# Frontend
cd onyx-repo/web
npm run type-check  # or your type checking command
```

---

## 🎯 What This Fixes

**Before**:
- ❌ Deleted files appear in project file lists
- ❌ Deleted files appear in search results (same session)
- ❌ Deleted files appear in file dropdown (new sessions)
- ❌ Inconsistent behavior across endpoints

**After**:
- ✅ Deleted files filtered from all backend endpoints
- ✅ Deleted files filtered from all frontend displays
- ✅ Consistent behavior everywhere
- ✅ Files disappear immediately when deleted

---

**Last Updated**: 2024  
**Version**: 1.0

