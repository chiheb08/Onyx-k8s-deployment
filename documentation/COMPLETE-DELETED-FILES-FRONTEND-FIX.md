# Complete Frontend Fix for Deleted Files Inconsistencies

## 🐛 Problems Identified

1. **Same Chat Session**: Deleted files still appear in search results within the same chat session
2. **File Dropdown Menu**: Deleted files appear in the file dropdown menu in new chat sessions
3. **Search Results Caching**: Search results are cached in chat state and not refreshed when files are deleted

---

## ✅ Solution Overview

We need to add **frontend filtering** at multiple points:

1. **Search Results Display**: Filter deleted files when rendering search results
2. **File Dropdown**: Ensure deleted files are filtered from `allRecentFiles`
3. **Context Refresh**: Refresh file list when files are deleted

---

## 📋 Implementation

### Fix 1: Filter Deleted Files in Search Results (SearchToolRenderer)

**File**: `onyx-repo/web/src/app/chat/message/messageComponents/renderers/SearchToolRenderer.tsx`

**Problem**: Search results from packets contain deleted files that are displayed in the chat session.

**Solution**: Add filtering to check file status before displaying results.

```typescript
// Add import
import { useProjectsContext } from "@/app/chat/projects/ProjectsContext";

// Modify constructCurrentSearchState function
const constructCurrentSearchState = (
  packets: SearchToolPacket[],
  validFileIds?: Set<string> // NEW: Set of valid (non-deleted) file IDs
): {
  queries: string[];
  results: OnyxDocument[];
  isSearching: boolean;
  isComplete: boolean;
  isInternetSearch: boolean;
} => {
  // ... existing code ...

  const seenDocIds = new Set<string>();
  const results = searchDeltas
    .flatMap((delta) => delta?.documents || [])
    .filter((doc) => {
      if (!doc || !doc.document_id) return false;
      if (seenDocIds.has(doc.document_id)) return false;
      
      // NEW: Filter out deleted user files
      if (validFileIds && doc.source_type === "user_file") {
        if (!validFileIds.has(doc.document_id)) {
          return false; // File is deleted, don't show
        }
      }
      
      seenDocIds.add(doc.document_id);
      return true;
    });

  // ... rest of existing code ...
};

// Modify SearchToolRenderer component
export const SearchToolRenderer: MessageRenderer<
  SearchToolPacket,
  { researchType?: string | null }
> = ({
  packets,
  state,
  onComplete,
  renderType,
  animate,
  stopPacketSeen,
  children,
}) => {
  // ... existing code ...
  
  // NEW: Get valid file IDs from context
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

  // NEW: Filter results using valid file IDs
  const { queries, results: rawResults, isSearching, isComplete, isInternetSearch } =
    constructCurrentSearchState(packets, validFileIds);
  
  // Additional filtering for user_file sources
  const results = useMemo(() => {
    return rawResults.filter((doc) => {
      if (doc.source_type === "user_file") {
        return validFileIds.has(doc.document_id);
      }
      return true; // Keep non-user-file documents
    });
  }, [rawResults, validFileIds]);

  // ... rest of component ...
};
```

---

### Fix 2: Ensure File Dropdown Filters Deleted Files

**File**: `onyx-repo/web/src/refresh-components/popovers/FilePickerPopover.tsx`

**Problem**: `allRecentFiles` might contain deleted files if context isn't refreshed.

**Solution**: Add status-based filtering in addition to `deletedFileIds`.

```typescript
// Modify the useEffect that sets recentFilesSnapshot
useEffect(() => {
  setRecentFilesSnapshot(
    allRecentFiles
      .slice()
      .filter((f) => {
        // Filter by deleted IDs
        if (deletedFileIds.includes(f.id)) return false;
        // Filter by status
        if (f.status === UserFileStatus.DELETING) return false;
        if (f.status === UserFileStatus.FAILED) return false;
        return true;
      })
  );
}, [allRecentFiles, deletedFileIds]);
```

---

### Fix 3: Refresh Recent Files When File is Deleted

**File**: `onyx-repo/web/src/app/chat/projects/ProjectsContext.tsx`

**Problem**: When a file is deleted, `allRecentFiles` isn't immediately refreshed.

**Solution**: Ensure `refreshRecentFiles` is called after successful deletion.

**Already implemented**, but verify it's being called:

```typescript
// In deleteUserFile function, ensure refreshRecentFiles is called
deleteUserFile: async (fileId: string) => {
  const result = await svcDeleteUserFile(fileId);
  
  // Remove from local state
  setAllRecentFiles((prev) => prev.filter((f) => f.id !== fileId));
  setRecentFiles((prev) => prev.filter((f) => f.id !== fileId));
  
  // Refresh from server to ensure consistency
  await refreshRecentFiles();
  
  return result;
},
```

---

### Fix 4: Add Real-time File Status Check for Search Results

**File**: `onyx-repo/web/src/app/chat/message/messageComponents/renderers/SearchToolRenderer.tsx`

**Problem**: Search results might contain files that were deleted after the search was performed.

**Solution**: Add a hook to periodically check file statuses for displayed results.

```typescript
// Add new hook to check file statuses
const useFileStatusCheck = (results: OnyxDocument[]) => {
  const { getUserFileStatuses } = useProjectsContext();
  const [validFileIds, setValidFileIds] = useState<Set<string>>(new Set());

  useEffect(() => {
    // Extract user file IDs from results
    const userFileIds = results
      .filter((doc) => doc.source_type === "user_file")
      .map((doc) => doc.document_id);

    if (userFileIds.length === 0) {
      setValidFileIds(new Set());
      return;
    }

    // Check file statuses
    getUserFileStatuses(userFileIds)
      .then((files) => {
        const valid = new Set<string>();
        files.forEach((file) => {
          if (file.status !== "DELETING" && file.status !== "FAILED") {
            valid.add(file.id);
          }
        });
        setValidFileIds(valid);
      })
      .catch((error) => {
        console.error("Failed to check file statuses:", error);
        // On error, assume all files are valid (fail open)
        setValidFileIds(new Set(userFileIds));
      });
  }, [results, getUserFileStatuses]);

  return validFileIds;
};

// Use in SearchToolRenderer
const validFileIds = useFileStatusCheck(results);
const filteredResults = useMemo(() => {
  return results.filter((doc) => {
    if (doc.source_type === "user_file") {
      return validFileIds.has(doc.document_id);
    }
    return true;
  });
}, [results, validFileIds]);
```

---

## 🎯 Complete Code Changes

### Change 1: SearchToolRenderer.tsx

**Location**: `onyx-repo/web/src/app/chat/message/messageComponents/renderers/SearchToolRenderer.tsx`

**Changes**:
1. Import `useProjectsContext`
2. Add `validFileIds` parameter to `constructCurrentSearchState`
3. Filter results by valid file IDs
4. Add `useFileStatusCheck` hook for real-time status checking

---

### Change 2: FilePickerPopover.tsx

**Location**: `onyx-repo/web/src/refresh-components/popovers/FilePickerPopover.tsx`

**Changes**:
1. Add status-based filtering in `useEffect` for `recentFilesSnapshot`
2. Filter by both `deletedFileIds` and file status

---

### Change 3: ProjectsContext.tsx

**Location**: `onyx-repo/web/src/app/chat/projects/ProjectsContext.tsx`

**Changes**:
1. Ensure `refreshRecentFiles` is called after file deletion
2. Verify `allRecentFiles` is updated immediately

---

## 🔍 Testing

### Test Case 1: Same Chat Session

1. Upload file A
2. Ask a question → File A appears in search results ✓
3. Delete file A
4. Ask another question in same session → File A should NOT appear ✗ → ✓ (after fix)

### Test Case 2: File Dropdown

1. Upload file B
2. Delete file B
3. Open new chat session
4. Click file dropdown → File B should NOT appear ✗ → ✓ (after fix)

### Test Case 3: Search Results Refresh

1. Upload file C
2. Ask question → File C appears ✓
3. Delete file C
4. Refresh page
5. View previous search results → File C should NOT appear ✗ → ✓ (after fix)

---

## 📝 Summary

**Root Causes**:
1. Search results are cached in chat state and not filtered for deleted files
2. File dropdown uses stale `allRecentFiles` data
3. No real-time status checking for displayed search results

**Solutions**:
1. ✅ Filter deleted files when displaying search results
2. ✅ Add status-based filtering in file dropdown
3. ✅ Add real-time file status checking hook
4. ✅ Ensure context refreshes after deletion

---

**Last Updated**: 2024  
**Version**: 1.0

