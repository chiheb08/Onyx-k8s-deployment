# File Upload Error Display Fix

## Problem
When uploading large files, error messages were appearing in backend logs but not being displayed to users in the UI. This happened when:
- Files exceeded NGINX `client_max_body_size` (HTTP 413)
- Backend validation failed (HTTP 400/500)
- Network errors occurred

## Root Cause
1. **Error Handler**: The `handleRequestError` function in `projectsService.ts` only returned a generic status code message, not the actual error details from the backend response.
2. **Missing Error Handling**: The `ProjectContextPanel.tsx` upload handler had no `catch` block to display errors to users.

## Solution

### 1. Enhanced Error Handler (`projectsService.ts`)
- Extracts error messages from backend response body (supports FastAPI `detail` field)
- Provides user-friendly messages for common HTTP status codes:
  - **413**: "File size exceeds the maximum allowed limit..."
  - **400**: "Invalid file. Please check the file format..."
  - **500**: "Server error. Please try again..."
- Falls back to response text if JSON parsing fails
- All `handleRequestError` calls now properly use `await` to handle async error extraction

### 2. Frontend Error Display (`ProjectContextPanel.tsx`)
- Added `catch` block to `handleUploadChange` to catch upload errors
- Displays error messages in the existing popup system (with `type: "error"`)
- Shows the actual backend error message to users

## Files Modified
1. `onyx-repo/web/src/app/chat/projects/projectsService.ts`
   - Enhanced `handleRequestError` to extract backend error details
   - Updated all error handler calls to use `await`

2. `onyx-repo/web/src/app/chat/components/projects/ProjectContextPanel.tsx`
   - Added `catch` block to display upload errors in UI

## Testing
To verify the fix works:
1. Upload a file larger than `client_max_body_size` (check NGINX config)
2. Upload an invalid file type (if restrictions exist)
3. Check that error messages appear in the UI popup instead of just backend logs

## Notes
- Error messages are extracted from FastAPI's standard `detail` field in error responses
- NGINX errors (413) will also be caught if they reach the backend, but may be rejected earlier by NGINX
- The popup system already exists in the component, so no new UI components were needed

