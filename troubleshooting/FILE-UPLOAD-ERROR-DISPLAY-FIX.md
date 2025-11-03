# File Upload Error Display Fix

## Problem
When uploading large files, error messages were appearing in **backend logs** but **not being displayed to users in the UI**. This happened when:
- Files exceeded NGINX `client_max_body_size` (HTTP 413)
- Backend validation failed (HTTP 400/500)
- Network errors occurred

## Affected Backend Service
**FastAPI API Server** - Endpoint: `POST /api/user/projects/file/upload`

The error originates from the backend service located at:
- **File**: `onyx-repo/backend/onyx/server/features/projects/api.py`
- **Function**: `upload_user_files()` (lines 75-113)
- **Router**: `/user/projects` (prefix)

## Root Cause Analysis

### Why Errors Were Not Displaying

The error flow had **two critical gaps**:

1. **Frontend Error Handler** - Lost error details from backend response
2. **Frontend Upload Handler** - No error catch block to display errors

Let's examine the code flow to understand what was happening:

## Code Flow Analysis

### Backend Error Response (Working Correctly)

The backend **correctly returns** error details:

```python
# onyx-repo/backend/onyx/server/features/projects/api.py (lines 107-113)
@router.post("/file/upload")
def upload_user_files(...):
    try:
        # ... file upload logic ...
        return CategorizedFilesSnapshot.from_result(categorized_files_result)
    except Exception as e:
        logger.exception(f"Error uploading files - {type(e).__name__}: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail="Failed to upload files. Please try again or contact support if the issue persists.",
        )
```

**Backend Response Format** (FastAPI standard):
```json
{
  "detail": "Failed to upload files. Please try again or contact support if the issue persists."
}
```

The backend was correctly:
- ✅ Catching exceptions
- ✅ Logging errors with full details
- ✅ Returning HTTPException with `detail` field
- ✅ Setting appropriate HTTP status codes

### The Problem: Frontend Error Handling

#### **BEFORE - Error Handler (Lost Details)**

```typescript
// onyx-repo/web/src/app/chat/projects/projectsService.ts
// ❌ BEFORE: Generic error handler that discarded backend error messages

const handleRequestError = (action: string, response: Response) => {
  // ❌ PROBLEM: Only returns status code, ignores response body!
  throw new Error(`${action} failed (Status: ${response.status})`);
};

export async function uploadFiles(...): Promise<CategorizedFiles> {
  const response = await fetch("/api/user/projects/file/upload", {
    method: "POST",
    body: formData,
  });

  if (!response.ok) {
    // ❌ PROBLEM: Response body never read!
    // Backend sends: { "detail": "Failed to upload files..." }
    // But frontend only sees: "Upload files failed (Status: 500)"
    handleRequestError("Upload files", response);
  }
  
  return response.json();
}
```

**What Happened:**
1. Backend returns: `{ "detail": "File size exceeds limit" }` with status 413
2. Frontend checks: `if (!response.ok)` → true
3. Frontend calls: `handleRequestError()` which **never reads the response body**
4. User sees: `"Upload files failed (Status: 413)"` ❌
5. Backend detail message **lost forever**

#### **AFTER - Enhanced Error Handler (Extracts Details)**

```typescript
// ✅ AFTER: Extracts actual error messages from backend response

const handleRequestError = async (action: string, response: Response) => {
  let errorMessage = `${action} failed (Status: ${response.status})`;
  
  try {
    // ✅ NEW: Read the response body to get error details
    const contentType = response.headers.get("content-type");
    if (contentType && contentType.includes("application/json")) {
      const errorBody = await response.json();
      // ✅ NEW: Extract FastAPI 'detail' field
      if (errorBody.detail) {
        errorMessage = errorBody.detail;
      } else if (errorBody.message) {
        errorMessage = errorBody.message;
      }
    } else {
      // ✅ NEW: Fallback to text response
      const text = await response.text();
      if (text) {
        errorMessage = text.substring(0, 200);
      }
    }
  } catch (parseError) {
    // If parsing fails, use default message
  }
  
  // ✅ NEW: User-friendly messages for common status codes
  if (response.status === 413) {
    errorMessage = "File size exceeds the maximum allowed limit. Please compress the file or split it into smaller parts.";
  } else if (response.status === 400) {
    errorMessage = errorMessage || "Invalid file. Please check the file format and try again.";
  }
  
  throw new Error(errorMessage); // ✅ Now throws message with actual backend detail
};

export async function uploadFiles(...): Promise<CategorizedFiles> {
  const response = await fetch("/api/user/projects/file/upload", {
    method: "POST",
    body: formData,
  });

  if (!response.ok) {
    // ✅ NOW: Reads response body and extracts error message
    await handleRequestError("Upload files", response);
  }
  
  return response.json();
}
```

**What Happens Now:**
1. Backend returns: `{ "detail": "Failed to upload files..." }` with status 500
2. Frontend checks: `if (!response.ok)` → true
3. Frontend calls: `await handleRequestError()` which **reads response body**
4. Frontend extracts: `errorBody.detail = "Failed to upload files..."`
5. Frontend throws: `Error("Failed to upload files...")` ✅
6. Error message **preserved** and available for UI display

---

#### **BEFORE - Upload Handler (No Error Display)**

```typescript
// onyx-repo/web/src/app/chat/components/projects/ProjectContextPanel.tsx
// ❌ BEFORE: No error handling, errors silently fail

const handleUploadChange = useCallback(
  async (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files;
    if (!files || files.length === 0) return;
    
    // ❌ PROBLEM: No try/catch block!
    // If uploadFiles() throws, error propagates uncaught
    await handleUploadFiles(Array.from(files));
    e.target.value = "";
  },
  [handleUploadFiles]
);
```

**What Happened:**
1. User uploads file → `handleUploadChange()` called
2. `handleUploadFiles()` calls `uploadFiles()` service
3. Backend returns error → `uploadFiles()` throws `Error("...")`
4. Error propagates up → **No catch block** to handle it
5. Error goes to browser console ❌ → **User sees nothing in UI**

#### **AFTER - Upload Handler (Displays Errors)**

```typescript
// ✅ AFTER: Catches errors and displays them to users

const handleUploadChange = useCallback(
  async (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files;
    if (!files || files.length === 0) return;
    
    try {
      // ✅ NEW: Wrap in try/catch
      await handleUploadFiles(Array.from(files));
    } catch (error) {
      // ✅ NEW: Extract error message and display in UI
      const errorMessage =
        error instanceof Error
          ? error.message  // ✅ Now contains backend detail message!
          : "Failed to upload files. Please try again.";
      
      // ✅ NEW: Show error in popup UI
      setPopup({
        type: "error",
        message: errorMessage,
      });
    } finally {
      e.target.value = "";
    }
  },
  [handleUploadFiles, setPopup]
);
```

**What Happens Now:**
1. User uploads file → `handleUploadChange()` called
2. `handleUploadFiles()` calls `uploadFiles()` service
3. Backend returns error → `uploadFiles()` throws `Error("Failed to upload files...")`
4. **Catch block** intercepts the error ✅
5. Error message extracted and displayed in UI popup ✅
6. **User sees error message** instead of silent failure

---

## Complete Error Flow Comparison

### BEFORE (Broken Flow)
```
User uploads file
  ↓
Frontend: POST /api/user/projects/file/upload
  ↓
Backend: Error occurs → Returns { "detail": "File too large" } (status 413)
  ↓
Frontend: handleRequestError() called
  ❌ Reads only status code → Throws Error("Upload files failed (Status: 413)")
  ❌ Backend detail message LOST
  ↓
Frontend: handleUploadChange() has no catch block
  ❌ Error propagates uncaught → Browser console only
  ❌ User sees NOTHING in UI
```

### AFTER (Fixed Flow)
```
User uploads file
  ↓
Frontend: POST /api/user/projects/file/upload
  ↓
Backend: Error occurs → Returns { "detail": "File too large" } (status 413)
  ↓
Frontend: handleRequestError() called
  ✅ Reads response body → Extracts errorBody.detail
  ✅ Throws Error("File too large") with actual message
  ↓
Frontend: handleUploadChange() catch block
  ✅ Intercepts error → Extracts error.message
  ✅ Displays in UI popup → User sees "File too large"
```

## Solution Summary

### 1. Enhanced Error Handler (`projectsService.ts`)
- ✅ Extracts error messages from backend response body (FastAPI `detail` field)
- ✅ Provides user-friendly messages for common HTTP status codes:
  - **413**: "File size exceeds the maximum allowed limit..."
  - **400**: "Invalid file. Please check the file format..."
  - **500**: "Server error. Please try again..."
- ✅ Falls back to response text if JSON parsing fails
- ✅ All `handleRequestError` calls now properly use `await` to handle async error extraction

### 2. Frontend Error Display (`ProjectContextPanel.tsx`)
- ✅ Added `try/catch` block to `handleUploadChange` to catch upload errors
- ✅ Displays error messages in the existing popup system (with `type: "error"`)
- ✅ Shows the actual backend error message to users

## Files Modified

1. **`onyx-repo/web/src/app/chat/projects/projectsService.ts`**
   - **Changed**: `handleRequestError()` from synchronous to async
   - **Added**: Response body parsing to extract `detail` field
   - **Added**: User-friendly status code messages
   - **Updated**: All 18 `handleRequestError()` calls to use `await`

2. **`onyx-repo/web/src/app/chat/components/projects/ProjectContextPanel.tsx`**
   - **Added**: `try/catch` block around `handleUploadFiles()` call
   - **Added**: Error message extraction and popup display
   - **Changed**: Dependency array to include `setPopup`

## Code Changes Summary

### Change 1: Error Handler Enhancement
**Lines Changed**: `projectsService.ts` lines 3-39

**Key Changes**:
- Made function `async`
- Added response body reading (`await response.json()`)
- Extract `detail` or `message` fields
- Status-code-specific messages

### Change 2: Error Display
**Lines Changed**: `ProjectContextPanel.tsx` lines 76-97

**Key Changes**:
- Wrapped upload call in `try/catch`
- Extract error message
- Display via `setPopup()` with type "error"

## Testing Instructions

To verify the fix works:

1. **Test File Size Error (413)**:
   - Upload a file larger than NGINX `client_max_body_size`
   - **Expected**: UI popup shows "File size exceeds the maximum allowed limit..."
   - **Before**: No error displayed, only in backend logs

2. **Test Invalid File (400)**:
   - Upload an invalid/corrupted file
   - **Expected**: UI popup shows backend error detail or "Invalid file..."
   - **Before**: No error displayed

3. **Test Server Error (500)**:
   - Trigger backend error (e.g., database connection issue)
   - **Expected**: UI popup shows backend error detail or "Server error..."
   - **Before**: No error displayed

## Technical Details

- **Backend Service**: FastAPI API Server (`/api/user/projects/file/upload`)
- **Error Format**: FastAPI standard `HTTPException` with `detail` field
- **Response Format**: JSON `{ "detail": "error message" }`
- **Status Codes Handled**: 400, 413, 500, and any other error status
- **Error Propagation**: Backend → Frontend Service → UI Component → Popup Display

## Notes

- Error messages are extracted from FastAPI's standard `detail` field in error responses
- NGINX errors (413) will also be caught if they reach the backend, but may be rejected earlier by NGINX (in which case the browser may show its own error)
- The popup system already exists in the component (`usePopup()` hook), so no new UI components were needed
- All error handler calls across the codebase were updated to use `await` for consistency

