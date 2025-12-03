# Disable Send Button Until Files Are Fully Loaded - Implementation Guide

## Overview

This document provides a comprehensive guide on how to implement the feature that disables the send button until all uploaded files are fully loaded or their status is `COMPLETED`. This prevents users from sending messages before file processing is complete, ensuring that embeddings and file data are available when the message is sent.

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Solution Overview](#solution-overview)
3. [Implementation Steps](#implementation-steps)
4. [Code Changes Explained](#code-changes-explained)
5. [File Status Flow](#file-status-flow)
6. [Testing Guide](#testing-guide)
7. [Troubleshooting](#troubleshooting)
8. [Future Enhancements](#future-enhancements)

---

## Problem Statement

### The Issue

When users upload files and immediately press "Send", the chat request can execute before the file embeddings are ready. This causes:
- The first response to miss the newly uploaded document
- Poor user experience with incomplete results
- Potential confusion about why the AI didn't use the uploaded file

### User Flow Problem

```
User uploads file → Immediately clicks Send → LLM request runs → 
File still processing → Response doesn't include file content ❌
```

### Desired Behavior

```
User uploads file → File shows "Processing..." → Send button disabled → 
File status becomes COMPLETED → Send button enabled → User can send ✅
```

---

## Solution Overview

### Architecture

The solution tracks file upload and processing status in real-time and disables the send button (and Enter key) until all files are ready.

```
┌─────────────────────────────────────────────────────────────┐
│                    File Upload Flow                         │
└─────────────────────────────────────────────────────────────┘

User uploads file
    │
    ├─► File added to currentMessageFiles (status = UPLOADING)
    │
    ├─► API /upload endpoint stores file + returns temp IDs
    │
    ├─► Frontend shows file chip with "Processing..." status
    │
    ├─► Celery task process_single_user_file
    │      └─ chunks + embeddings → sets status COMPLETED/FAILED
    │
    └─► Frontend polls /file/statuses
             ↓
        hasProcessingFiles?
        │          │
        │ yes      │ no
        ▼          ▼
  Disable send   Enable send
  & block Enter  & allow prompt
```

### Key Components

1. **File Status Tracking**: `ProjectsContext` polls file statuses and updates `currentMessageFiles`
2. **Processing Check**: `hasProcessingFiles` memoized check detects UPLOADING/PROCESSING files
3. **UI Disable Logic**: Send button and Enter key respect the processing state
4. **User Feedback**: Tooltip explains why button is disabled

---

## Implementation Steps

### Step 1: Add Tooltip Component Imports

**Location**: `web/src/app/chat/components/input/ChatInputBar.tsx`

Add the Tooltip imports at the top of the file with other imports:

```typescript
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
```

**Why**: We need these components to show a helpful message when the button is disabled.

---

### Step 2: Create `hasProcessingFiles` Check

**Location**: After the `currentIndexingFiles` useMemo (around line 149)

Add this code:

```typescript
// Check if any files are still uploading or processing
const hasProcessingFiles = useMemo(() => {
  return currentMessageFiles.some(
    (file) =>
      file.status === UserFileStatus.UPLOADING ||
      file.status === UserFileStatus.PROCESSING
  );
}, [currentMessageFiles]);
```

**What it does**:
- Uses `useMemo` for performance (only recalculates when `currentMessageFiles` changes)
- Checks if ANY file has status `UPLOADING` or `PROCESSING`
- Returns `true` if files are not ready, `false` when all files are `COMPLETED` or `FAILED`

**Why `useMemo`**: Prevents unnecessary recalculations on every render, improving performance.

---

### Step 3: Update Send Button Disabled State

**Location**: In the `IconButton` component for the send button (around line 586)

**Before**:
```typescript
<IconButton
  id="onyx-chat-input-send-button"
  icon={chatState === "input" ? SvgArrowUp : SvgStop}
  disabled={chatState === "input" && !message}
  onClick={() => {
    if (chatState == "streaming") {
      stopGenerating();
    } else if (message) {
      onSubmit();
    }
  }}
/>
```

**After**:
```typescript
<IconButton
  id="onyx-chat-input-send-button"
  icon={chatState === "input" ? SvgArrowUp : SvgStop}
  disabled={
    (chatState === "input" && !message) ||
    (chatState === "input" && hasProcessingFiles)
  }
  onClick={() => {
    if (chatState == "streaming") {
      stopGenerating();
    } else if (message && !hasProcessingFiles) {
      onSubmit();
    }
  }}
/>
```

**Changes**:
1. Added `hasProcessingFiles` to the `disabled` condition
2. Added `!hasProcessingFiles` check in the `onClick` handler

**Why both checks**: 
- `disabled` prop prevents the button from being clickable
- `onClick` check provides an extra safety layer in case the button somehow gets clicked

---

### Step 4: Update Enter Key Handler

**Location**: In the `textarea` `onKeyDown` handler (around line 446)

**Before**:
```typescript
onKeyDown={(event) => {
  if (
    event.key === "Enter" &&
    !showPrompts &&
    !event.shiftKey &&
    !(event.nativeEvent as any).isComposing
  ) {
    event.preventDefault();
    if (message) {
      onSubmit();
    }
  }
}}
```

**After**:
```typescript
onKeyDown={(event) => {
  if (
    event.key === "Enter" &&
    !showPrompts &&
    !event.shiftKey &&
    !(event.nativeEvent as any).isComposing
  ) {
    event.preventDefault();
    if (message && !hasProcessingFiles) {
      onSubmit();
    }
  }
}}
```

**Change**: Added `!hasProcessingFiles` check before calling `onSubmit()`

**Why**: Users might try to press Enter even when the button is disabled. This prevents that.

---

### Step 5: Add Tooltip for User Feedback

**Location**: Wrap the send `IconButton` with Tooltip components (around line 579)

**Before**:
```typescript
<IconButton
  id="onyx-chat-input-send-button"
  ...
/>
```

**After**:
```typescript
<TooltipProvider>
  <Tooltip>
    <TooltipTrigger asChild>
      <div>
        <IconButton
          id="onyx-chat-input-send-button"
          icon={chatState === "input" ? SvgArrowUp : SvgStop}
          disabled={
            (chatState === "input" && !message) ||
            (chatState === "input" && hasProcessingFiles)
          }
          onClick={() => {
            if (chatState == "streaming") {
              stopGenerating();
            } else if (message && !hasProcessingFiles) {
              onSubmit();
            }
          }}
        />
      </div>
    </TooltipTrigger>
    {hasProcessingFiles && (
      <TooltipContent side="top" align="center">
        Files are still processing. Please wait before sending.
      </TooltipContent>
    )}
  </Tooltip>
</TooltipProvider>
```

**What it does**:
- Wraps the button in a Tooltip component
- Shows a helpful message when `hasProcessingFiles` is true
- Only displays the tooltip when files are processing (conditional rendering)

**Why wrap in `<div>`**: The `TooltipTrigger` with `asChild` requires a single child element, and `IconButton` might not forward refs correctly, so we wrap it.

---

## Code Changes Explained

### Complete Code Block Reference

Here's the complete section with all changes:

```typescript
// 1. Add imports at top of file
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";

// 2. Add hasProcessingFiles check (after currentIndexingFiles)
const hasProcessingFiles = useMemo(() => {
  return currentMessageFiles.some(
    (file) =>
      file.status === UserFileStatus.UPLOADING ||
      file.status === UserFileStatus.PROCESSING
  );
}, [currentMessageFiles]);

// 3. Update Enter key handler in textarea
onKeyDown={(event) => {
  if (
    event.key === "Enter" &&
    !showPrompts &&
    !event.shiftKey &&
    !(event.nativeEvent as any).isComposing
  ) {
    event.preventDefault();
    if (message && !hasProcessingFiles) {
      onSubmit();
    }
  }
}}

// 4. Update send button with tooltip
<TooltipProvider>
  <Tooltip>
    <TooltipTrigger asChild>
      <div>
        <IconButton
          id="onyx-chat-input-send-button"
          icon={chatState === "input" ? SvgArrowUp : SvgStop}
          disabled={
            (chatState === "input" && !message) ||
            (chatState === "input" && hasProcessingFiles)
          }
          onClick={() => {
            if (chatState == "streaming") {
              stopGenerating();
            } else if (message && !hasProcessingFiles) {
              onSubmit();
            }
          }}
        />
      </div>
    </TooltipTrigger>
    {hasProcessingFiles && (
      <TooltipContent side="top" align="center">
        Files are still processing. Please wait before sending.
      </TooltipContent>
    )}
  </Tooltip>
</TooltipProvider>
```

---

## File Status Flow

### File Status Enum

Files can have the following statuses (defined in `projectsService.ts`):

```typescript
export enum UserFileStatus {
  UPLOADING = "UPLOADING",    // UI only - file is being uploaded
  PROCESSING = "PROCESSING",  // File is being indexed/embedded
  COMPLETED = "COMPLETED",    // File is ready to use
  FAILED = "FAILED",          // File processing failed
  CANCELED = "CANCELED",      // File upload was canceled
}
```

### Status Transition Flow

```
┌─────────────┐
│  UPLOADING  │  ← User selects file
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ PROCESSING  │  ← File uploaded, being indexed
└──────┬──────┘
       │
       ├──► ┌──────────┐
       │    │COMPLETED │  ← Success! File ready
       │    └──────────┘
       │
       └──► ┌────────┐
            │ FAILED │  ← Error occurred
            └────────┘
```

### When Send Button is Disabled

The send button is disabled when:
- `hasProcessingFiles === true` (any file is UPLOADING or PROCESSING)
- AND `chatState === "input"` (not streaming)

The send button is enabled when:
- All files have status `COMPLETED` or `FAILED`
- OR `hasProcessingFiles === false`
- AND there's a message to send

---

## Testing Guide

### Manual Testing Steps

#### Test Case 1: Single File Upload

1. **Setup**: Open the chat interface
2. **Action**: Upload a single file (PDF, TXT, etc.)
3. **Expected Behavior**:
   - File chip appears with "Processing..." status
   - Send button becomes disabled (grayed out)
   - Hovering over send button shows tooltip: "Files are still processing. Please wait before sending."
   - Pressing Enter does nothing
4. **Wait**: Wait for file to finish processing
5. **Expected Result**:
   - File chip shows "Completed" or checkmark
   - Send button becomes enabled
   - Tooltip no longer appears
   - Can now send message

#### Test Case 2: Multiple File Upload

1. **Setup**: Open the chat interface
2. **Action**: Upload 3 files simultaneously
3. **Expected Behavior**:
   - All 3 file chips appear
   - Send button disabled while ANY file is processing
   - Tooltip appears
4. **Wait**: Wait for all files to complete
5. **Expected Result**:
   - Send button enabled only when ALL files are COMPLETED
   - Can send message

#### Test Case 3: Mixed Status Files

1. **Setup**: Have some files already completed
2. **Action**: Upload a new file
3. **Expected Behavior**:
   - Send button disabled (because new file is processing)
   - Even though other files are ready
4. **Wait**: New file completes
5. **Expected Result**:
   - Send button enabled

#### Test Case 4: Failed File

1. **Setup**: Upload a file that will fail (corrupted, unsupported format, etc.)
2. **Action**: Wait for processing
3. **Expected Behavior**:
   - File status becomes `FAILED`
   - Send button becomes enabled (failed files don't block sending)
   - User can send message

#### Test Case 5: Enter Key Prevention

1. **Setup**: Upload a file
2. **Action**: Type a message and press Enter
3. **Expected Behavior**:
   - Message does NOT send
   - Send button remains disabled
4. **Wait**: File completes
5. **Action**: Press Enter again
6. **Expected Result**:
   - Message sends successfully

#### Test Case 6: Streaming State

1. **Setup**: Send a message (no files uploading)
2. **Action**: While streaming, upload a file
3. **Expected Behavior**:
   - Send button shows "Stop" icon (not disabled)
   - Can still stop generation
   - File upload doesn't interfere with streaming

### Automated Testing (Future)

Consider adding unit tests:

```typescript
describe('ChatInputBar - File Processing', () => {
  it('disables send button when files are uploading', () => {
    // Test implementation
  });
  
  it('disables send button when files are processing', () => {
    // Test implementation
  });
  
  it('enables send button when all files are completed', () => {
    // Test implementation
  });
  
  it('prevents Enter key submission when files are processing', () => {
    // Test implementation
  });
});
```

---

## Troubleshooting

### Issue: Send Button Not Disabling

**Symptoms**: Button remains enabled even when files are processing

**Possible Causes**:
1. `hasProcessingFiles` not updating
2. File status not being polled correctly
3. `currentMessageFiles` not updating

**Debug Steps**:
1. Add console.log to check `hasProcessingFiles`:
   ```typescript
   console.log('hasProcessingFiles:', hasProcessingFiles);
   console.log('currentMessageFiles:', currentMessageFiles);
   ```
2. Check `ProjectsContext` polling is working
3. Verify file statuses in network tab (`/api/user/projects/file/statuses`)

**Solution**: Ensure `ProjectsContext` is properly polling and updating `currentMessageFiles`

---

### Issue: Tooltip Not Showing

**Symptoms**: Button is disabled but no tooltip appears

**Possible Causes**:
1. Tooltip components not imported correctly
2. Conditional rendering issue
3. CSS z-index problem

**Debug Steps**:
1. Check browser console for errors
2. Verify Tooltip imports are correct
3. Check if `hasProcessingFiles` is actually `true`

**Solution**: Ensure TooltipProvider wraps the Tooltip, and conditional rendering is correct

---

### Issue: Enter Key Still Works

**Symptoms**: Can still submit with Enter when files are processing

**Possible Causes**:
1. `onKeyDown` handler not updated
2. Event not being prevented
3. Handler not being called

**Debug Steps**:
1. Add console.log in `onKeyDown` handler
2. Check if `hasProcessingFiles` is being checked
3. Verify event.preventDefault() is called

**Solution**: Ensure the `!hasProcessingFiles` check is in the Enter key handler

---

### Issue: Button Disabled Forever

**Symptoms**: Button never enables even after files complete

**Possible Causes**:
1. File status not updating to COMPLETED
2. Polling stopped
3. `currentMessageFiles` not updating

**Debug Steps**:
1. Check file statuses in browser DevTools
2. Verify polling is still active
3. Check if files actually completed (check backend logs)

**Solution**: Ensure `ProjectsContext` polling continues until all files are COMPLETED or FAILED

---

## Future Enhancements

### 1. Progress Indicators

Show more detailed progress:
- "Processing file 2 of 5..."
- Estimated time remaining
- Percentage complete

### 2. Adaptive Polling

Optimize polling frequency:
- Start with 2-second intervals
- Increase to 5 seconds after 30 seconds
- Increase to 10 seconds after 2 minutes

### 3. Server-Side Validation

Add backend check to reject messages with processing files:
```python
# In chat endpoint
if any(file.status == "PROCESSING" for file in current_message_files):
    return JSONResponse(
        status_code=409,
        content={"error": "Files still indexing. Please wait."}
    )
```

### 4. Visual Feedback

Enhance UI with:
- Animated spinner on disabled button
- Progress bar for file processing
- File-by-file status indicators

### 5. WebSocket/SSE Updates

Replace polling with real-time updates:
- Use WebSocket or Server-Sent Events
- Instant status updates
- Better performance

---

## Git Workflow

### Committing Changes

The changes have been committed locally with this message:

```
feat: disable send button until files are fully loaded or status is completed

- Add hasProcessingFiles check to detect UPLOADING or PROCESSING file status
- Disable send button when files are still processing
- Prevent Enter key submission while files are processing
- Add tooltip to explain why button is disabled
- Ensure user cannot send messages until all files are ready
```

### Pushing to GitHub

**Note**: The commit is ready locally. To push:

1. **If you have write access**:
   ```bash
   cd onyx
   git push origin main
   ```

2. **If you need to create a Pull Request**:
   ```bash
   # Create a new branch
   git checkout -b feature/disable-send-button-until-files-ready
   
   # Push the branch
   git push origin feature/disable-send-button-until-files-ready
   
   # Then create a PR on GitHub
   ```

3. **If your branch is behind** (as shown in git status):
   ```bash
   # Pull latest changes first
   git pull origin main
   
   # Resolve any conflicts if needed
   # Then push
   git push origin main
   ```

---

## Summary

This implementation ensures a better user experience by preventing premature message submission while files are processing. The key changes are:

1. ✅ **File Status Tracking**: Uses existing `currentMessageFiles` from `ProjectsContext`
2. ✅ **Processing Detection**: `hasProcessingFiles` memoized check
3. ✅ **UI Disable**: Send button and Enter key respect processing state
4. ✅ **User Feedback**: Tooltip explains why button is disabled
5. ✅ **Performance**: Uses `useMemo` to optimize re-renders

The solution is minimal, performant, and integrates seamlessly with the existing codebase.

---

## Related Files

- **Main Implementation**: `web/src/app/chat/components/input/ChatInputBar.tsx`
- **File Status Types**: `web/src/app/chat/projects/projectsService.ts`
- **File Context**: `web/src/app/chat/projects/ProjectsContext.tsx`
- **Tooltip Component**: `web/src/components/ui/tooltip.tsx`

---

## Questions or Issues?

If you encounter any issues or have questions about this implementation, please:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review the code changes in `ChatInputBar.tsx`
3. Verify file status polling is working in `ProjectsContext`
4. Check browser console for any errors

---

**Last Updated**: 2024
**Version**: 1.0
**Author**: Implementation Guide

