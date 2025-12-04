# Disable Input While Files Processing - Step-by-Step Implementation

## ✅ Implementation Complete

This document provides the exact code changes to disable text input while files are uploading or processing.

---

## 📝 Changes Made

### **File:** `onyx-repo/web/src/app/chat/components/input/ChatInputBar.tsx`

### **Change 1: Add `hasProcessingFiles` Check**

**Location:** After `currentIndexingFiles` definition (around line 140)

**Code Added:**
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

**What it does:**
- Checks if ANY file is in `UPLOADING` or `PROCESSING` state
- Returns `true` if files are not ready
- Memoized for performance

---

### **Change 2: Add Status Message Above Textarea**

**Location:** Before `<textarea>` element (around line 412)

**Code Added:**
```typescript
{hasProcessingFiles && (
  <div className="px-3 pt-2 pb-1 text-xs text-text-03 flex items-center gap-2">
    <SvgHourglass className="h-4 w-4 animate-spin" />
    <span>
      {currentMessageFiles.filter(
        (f) => f.status === UserFileStatus.UPLOADING
      ).length > 0
        ? `Uploading ${currentMessageFiles.filter((f) => f.status === UserFileStatus.UPLOADING).length} file(s)...`
        : `Processing ${currentIndexingFiles.length} file(s)... Please wait before sending a message.`}
    </span>
  </div>
)}
```

**What it does:**
- Shows a message when files are processing
- Displays different messages for "Uploading" vs "Processing"
- Shows count of files being processed
- Includes spinning hourglass icon for visual feedback

---

### **Change 3: Disable Textarea When Files Processing**

**Location:** In `<textarea>` element (around line 412)

**Changes:**
1. **Add `disabled` attribute:**
   ```typescript
   disabled={hasProcessingFiles}
   ```

2. **Update `className` to show disabled state:**
   ```typescript
   className={cn(
     // ... existing classes ...
     hasProcessingFiles && "opacity-50 cursor-not-allowed"
   )}
   ```

3. **Update `autoFocus` to prevent focus when disabled:**
   ```typescript
   autoFocus={!hasProcessingFiles}
   ```

4. **Update `placeholder` to show processing message:**
   ```typescript
   placeholder={
     hasProcessingFiles
       ? "Please wait for files to finish processing..."
       : selectedAssistant.id === 0
       ? `How can ${
           combinedSettings?.enterpriseSettings?.application_name ||
           "Onyx"
         } help you today`
       : `How can ${selectedAssistant.name} help you today`
   }
   ```

5. **Update `onKeyDown` to prevent Enter key when processing:**
   ```typescript
   onKeyDown={(event) => {
     if (
       event.key === "Enter" &&
       !showPrompts &&
       !event.shiftKey &&
       !(event.nativeEvent as any).isComposing &&
       !hasProcessingFiles  // ← ADD THIS CHECK
     ) {
       event.preventDefault();
       if (message) {
         onSubmit();
       }
     }
   }}
   ```

**What it does:**
- Disables textarea when files are processing
- Shows visual feedback (opacity + cursor change)
- Prevents typing
- Prevents Enter key submission
- Shows helpful placeholder message

---

### **Change 4: Disable Send Button When Files Processing**

**Location:** In `<IconButton>` for send button (around line 594)

**Changes:**
1. **Update `disabled` condition:**
   ```typescript
   disabled={
     (chatState === "input" && !message) ||
     (chatState === "input" && hasProcessingFiles)  // ← ADD THIS
   }
   ```

2. **Add `tooltip` for disabled state:**
   ```typescript
   tooltip={
     hasProcessingFiles
       ? "Please wait for files to finish processing"
       : undefined
   }
   ```

3. **Update `onClick` to check processing state:**
   ```typescript
   onClick={() => {
     if (chatState == "streaming") {
       stopGenerating();
     } else if (message && !hasProcessingFiles) {  // ← ADD CHECK
       onSubmit();
     }
   }}
   ```

**What it does:**
- Disables send button when files are processing
- Shows tooltip explaining why it's disabled
- Prevents accidental submission

---

## 🎯 User Experience Flow

### **Before Fix:**
```
1. User uploads file
2. File shows "Processing..." badge
3. User can still type in textarea ✅
4. User can click send button ✅
5. Message sent but file not ready ❌
6. User gets confusing error or no results ❌
```

### **After Fix:**
```
1. User uploads file
2. File shows "Processing..." badge
3. Status message appears: "Processing 1 file(s)... Please wait"
4. Textarea is disabled (grayed out) ❌
5. Send button is disabled with tooltip ❌
6. User cannot type or send until file is ready ✅
7. Once file is "COMPLETED", input re-enables automatically ✅
8. User can now type and send ✅
```

---

## 🧪 Testing Checklist

After implementing, test these scenarios:

1. ✅ **Upload single file**
   - Textarea should disable immediately
   - Status message should appear
   - Send button should disable
   - Once file is "COMPLETED", everything should re-enable

2. ✅ **Upload multiple files**
   - Should show count: "Processing 3 file(s)..."
   - All files must be "COMPLETED" before input enables
   - Status message should update as files complete

3. ✅ **Upload large file (takes time)**
   - Should show "Processing..." for extended period
   - Input should remain disabled throughout
   - No way to bypass the check

4. ✅ **Upload file that fails**
   - File should show "Failed" status
   - Input should re-enable (failed files don't block)
   - User can remove failed file and try again

5. ✅ **Mix of uploading and processing**
   - Should show "Uploading X file(s)..." if any are uploading
   - Should show "Processing X file(s)..." if all are processing
   - Input should remain disabled until all are "COMPLETED"

6. ✅ **Keyboard shortcuts**
   - Enter key should not work when disabled
   - Shift+Enter (new line) should not work when disabled
   - Tab navigation should skip disabled textarea

---

## 🐛 Troubleshooting

### **Issue: Textarea not disabling**

**Check:**
1. Is `hasProcessingFiles` returning `true`?
   - Add `console.log(hasProcessingFiles)` to debug
2. Are file statuses correct?
   - Check `currentMessageFiles` in React DevTools
3. Is the `disabled` prop being applied?
   - Inspect textarea element in browser DevTools

### **Issue: Send button not disabling**

**Check:**
1. Is the `disabled` condition correct?
   - Should be: `(chatState === "input" && !message) || (chatState === "input" && hasProcessingFiles)`
2. Is `hasProcessingFiles` being checked?
   - Verify it's in the dependency array if needed

### **Issue: Status message not showing**

**Check:**
1. Is `SvgHourglass` imported?
   - Should be: `import SvgHourglass from "@/icons/hourglass";`
2. Is the condition `hasProcessingFiles` true?
   - Check React DevTools for state

---

## 📊 Performance Impact

**Minimal Impact:**
- `hasProcessingFiles` is memoized (only recalculates when `currentMessageFiles` changes)
- No additional API calls
- No additional re-renders (uses existing state)
- Simple boolean check (O(n) where n = number of files, typically < 10)

**Benefits:**
- Prevents user errors (sending before files ready)
- Better UX (clear feedback)
- Reduces support tickets
- Prevents race conditions

---

## 🚀 Next Steps (Future Improvements)

After this fix is deployed, consider:

1. **Adaptive Polling** (Phase 2)
   - Reduce polling frequency over time
   - Stop polling when all files complete

2. **SSE/WebSocket Status Updates** (Phase 3)
   - Real-time updates instead of polling
   - Better performance and UX

3. **Progress Indicators** (Phase 4)
   - Show percentage complete
   - Estimated time remaining

See `FILE-UPLOAD-UX-PERFORMANCE-RESEARCH.md` for detailed recommendations.

---

## ✅ Summary

**What was changed:**
- ✅ Added `hasProcessingFiles` check
- ✅ Disabled textarea when files processing
- ✅ Disabled send button when files processing
- ✅ Added status message above textarea
- ✅ Updated placeholder text
- ✅ Prevented Enter key submission

**Result:**
- ✅ Users cannot type while files are processing
- ✅ Users cannot send messages while files are processing
- ✅ Clear visual feedback about processing state
- ✅ Automatic re-enable when files are ready

**Files Modified:**
- `onyx-repo/web/src/app/chat/components/input/ChatInputBar.tsx`

**No Backend Changes Required** - This is a frontend-only fix.


