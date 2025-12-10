# Exact Code Changes for Deleted Files Frontend Fixes

## 📋 Overview

This document shows **exactly** what code changes you need to make in each file, with **old code** vs **new code** comparisons.

---

## File 1: SearchToolRenderer.tsx

**File Path**: `onyx-repo/web/src/app/chat/message/messageComponents/renderers/SearchToolRenderer.tsx`

### Change 1.1: Add Import

**Location**: Top of file, with other imports

**OLD CODE**:
```typescript
import React, { useEffect, useState, useRef, useMemo } from "react";
import { FiSearch, FiGlobe } from "react-icons/fi";
import {
  PacketType,
  SearchToolPacket,
  SearchToolStart,
  SearchToolDelta,
  SectionEnd,
} from "../../../services/streamingModels";
import { MessageRenderer } from "../interfaces";
import { ResultIcon } from "@/components/chat/sources/SourceCard";
import { OnyxDocument } from "@/lib/search/interfaces";
import { SourceChip2 } from "@/app/chat/components/SourceChip2";
import { BlinkingDot } from "../../BlinkingDot";
import Text from "@/refresh-components/texts/Text";
import { SearchToolRendererV2 } from "./SearchToolRendererV2";
import { usePostHog } from "posthog-js/react";
import { ResearchType } from "@/app/chat/interfaces";
```

**NEW CODE**:
```typescript
import React, { useEffect, useState, useRef, useMemo } from "react";
import { FiSearch, FiGlobe } from "react-icons/fi";
import {
  PacketType,
  SearchToolPacket,
  SearchToolStart,
  SearchToolDelta,
  SectionEnd,
} from "../../../services/streamingModels";
import { MessageRenderer } from "../interfaces";
import { ResultIcon } from "@/components/chat/sources/SourceCard";
import { OnyxDocument } from "@/lib/search/interfaces";
import { SourceChip2 } from "@/app/chat/components/SourceChip2";
import { BlinkingDot } from "../../BlinkingDot";
import Text from "@/refresh-components/texts/Text";
import { SearchToolRendererV2 } from "./SearchToolRendererV2";
import { usePostHog } from "posthog-js/react";
import { ResearchType } from "@/app/chat/interfaces";
import { useProjectsContext } from "@/app/chat/projects/ProjectsContext";  // NEW LINE
```

---

### Change 1.2: Add File Filtering Logic

**Location**: Inside the `SearchToolRenderer` component, right after the `isDeepResearch` variable and before `constructCurrentSearchState` call

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

## File 2: SearchToolRendererV2.tsx

**File Path**: `onyx-repo/web/src/app/chat/message/messageComponents/renderers/SearchToolRendererV2.tsx`

### Change 2.1: Add Import

**Location**: Top of file, with other imports

**OLD CODE**:
```typescript
import React, { useEffect, useState, useRef, useMemo } from "react";
import { FiSearch, FiGlobe } from "react-icons/fi";
import {
  PacketType,
  SearchToolPacket,
  SearchToolStart,
  SearchToolDelta,
  SectionEnd,
} from "../../../services/streamingModels";
import { MessageRenderer } from "../interfaces";
import { truncateString } from "@/lib/utils";
import { SourceChip2 } from "@/app/chat/components/SourceChip2";
import { BlinkingDot } from "../../BlinkingDot";
import { OnyxDocument } from "@/lib/search/interfaces";
import { ResultIcon } from "@/components/chat/sources/SourceCard";
```

**NEW CODE**:
```typescript
import React, { useEffect, useState, useRef, useMemo } from "react";
import { FiSearch, FiGlobe } from "react-icons/fi";
import {
  PacketType,
  SearchToolPacket,
  SearchToolStart,
  SearchToolDelta,
  SectionEnd,
} from "../../../services/streamingModels";
import { MessageRenderer } from "../interfaces";
import { truncateString } from "@/lib/utils";
import { SourceChip2 } from "@/app/chat/components/SourceChip2";
import { BlinkingDot } from "../../BlinkingDot";
import { OnyxDocument } from "@/lib/search/interfaces";
import { ResultIcon } from "@/components/chat/sources/SourceCard";
import { useProjectsContext } from "@/app/chat/projects/ProjectsContext";  // NEW LINE
```

---

### Change 2.2: Add File Filtering Logic

**Location**: Inside the `SearchToolRendererV2` component, right at the beginning after the function signature

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

## File 3: FilePickerPopover.tsx

**File Path**: `onyx-repo/web/src/refresh-components/popovers/FilePickerPopover.tsx`

### Change 3.1: Enhance File Filtering in useEffect

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

## 📝 Summary of Changes

### File 1: SearchToolRenderer.tsx
- ✅ Add 1 import line
- ✅ Add file filtering logic (2 `useMemo` hooks)

### File 2: SearchToolRendererV2.tsx
- ✅ Add 1 import line
- ✅ Add file filtering logic (2 `useMemo` hooks)

### File 3: FilePickerPopover.tsx
- ✅ Enhance 1 `useEffect` hook to filter by status

---

## 🔍 How to Apply Changes

### Step 1: Open Each File

```bash
# File 1
code onyx-repo/web/src/app/chat/message/messageComponents/renderers/SearchToolRenderer.tsx

# File 2
code onyx-repo/web/src/app/chat/message/messageComponents/renderers/SearchToolRendererV2.tsx

# File 3
code onyx-repo/web/src/refresh-components/popovers/FilePickerPopover.tsx
```

### Step 2: Apply Changes

For each file:
1. Find the **OLD CODE** section
2. Replace it with the **NEW CODE** section
3. Save the file

### Step 3: Verify

After making changes, verify:
- No TypeScript errors
- No linting errors
- Files compile successfully

---

## ✅ Verification Checklist

After applying all changes:

- [ ] `SearchToolRenderer.tsx` - Import added
- [ ] `SearchToolRenderer.tsx` - Filtering logic added
- [ ] `SearchToolRendererV2.tsx` - Import added
- [ ] `SearchToolRendererV2.tsx` - Filtering logic added
- [ ] `FilePickerPopover.tsx` - Enhanced filtering
- [ ] No TypeScript errors
- [ ] No linting errors
- [ ] Code compiles successfully

---

## 🎯 What Each Change Does

### SearchToolRenderer.tsx & SearchToolRendererV2.tsx

**Purpose**: Filter deleted files from search results displayed in chat

**How it works**:
1. Gets `allRecentFiles` from context
2. Creates a `Set` of valid (non-deleted) file IDs
3. Filters search results to only show documents from valid files
4. Updates automatically when files are deleted

### FilePickerPopover.tsx

**Purpose**: Filter deleted files from file dropdown menu

**How it works**:
1. Filters by `deletedFileIds` (local tracking)
2. Also filters by file status (`DELETING`, `FAILED`)
3. Updates when `allRecentFiles` or `deletedFileIds` changes

---

## 🚀 Testing After Changes

1. **Test Same Chat Session**:
   - Upload file → Ask question → File appears ✓
   - Delete file → Ask another question → File should NOT appear ✓

2. **Test File Dropdown**:
   - Upload file → Delete file → Open new chat → Click dropdown → File should NOT appear ✓

3. **Test Search Results**:
   - Upload file → Ask question → Delete file → View results → File should NOT appear ✓

---

**Last Updated**: 2024  
**Version**: 1.0

