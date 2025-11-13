# Prevent Chat Submission While Files Are Still Processing

When a user uploads a large document and immediately presses “Send”, the LLM request can run before embeddings are ready. This causes the first answer to miss the new document. Below is a detailed plan to block chat submission until all attached files have finished processing.

---

## 1. Desired Behavior

1. User uploads files → UI shows a “Processing…” chip per file.
2. While any attachment has status `PROCESSING` or `UPLOADING`:
   - The chat input’s **send button is disabled** (and Enter key is ignored).
   - A tooltip/banner explains “Please wait until files finish indexing.”
3. Once every file status flips to `COMPLETED` (or `FAILED`), the user can send the prompt.

This ensures the first prompt runs only after embeddings are available.

### Architecture Flow (ASCII Diagram)
```
User uploads file
    │
    ├─► UI adds file to currentMessageFiles (status = UPLOADING)
    │
    ├─► API /upload endpoint stores file + returns temp IDs
    │
    ├─► Frontend shows chip “Processing…”
    │
    ├─► Celery task process_single_user_file
    │      └─ chunks + embeddings → sets status COMPLETED/FAILED
    │
    └─► Frontend poll /file/statuses
             ↓
        hasProcessingFiles?
        │          │
        │ yes      │ no
        ▼          ▼
  Disable send   Enable send
  & block Enter  & allow prompt
```

---

## 2. Frontend changes (Next.js app)

### 2.1 Track file states
`ProjectsContext.tsx` already polls `/api/user/projects/file/statuses` and keeps `currentMessageFiles` updated with `status` (enum `UserFileStatus`). Keep using these values.

### 2.2 Disable send button & Enter key (in one place)

**File to edit:** `web/src/app/chat/components/input/ChatInputBar.tsx`

Locate the section at the bottom of the component where the send icon button is rendered (search for `id="onyx-chat-input-send-button"`). Replace that block with:

```tsx
const hasProcessingFiles = currentMessageFiles.some((file) =>
  [UserFileStatus.PROCESSING, UserFileStatus.UPLOADING].includes(
    file.status as UserFileStatus
  )
);

...

{hasProcessingFiles && (
  <div className="text-xs text-action-warning-05 px-3 pb-2">
    Files are still indexing. Please wait…
  </div>
)}

<TooltipProvider>
  <Tooltip>
    <TooltipTrigger asChild>
      <IconButton
        id="onyx-chat-input-send-button"
        icon={chatState === "input" ? SvgArrowUp : SvgStop}
        disabled={
          (chatState === "input" && !message) ||
          (chatState === "input" && hasProcessingFiles)
        }
        onClick={() => {
          if (chatState === "streaming") {
            stopGenerating();
          } else if (message && !hasProcessingFiles) {
            onSubmit();
          }
        }}
      />
    </TooltipTrigger>
    {hasProcessingFiles && (
      <TooltipContent side="top" align="center">
        Attached files are still processing. Try again shortly.
      </TooltipContent>
    )}
  </Tooltip>
</TooltipProvider>
```

Also extend the keyboard handler so it respects the same flag. Inside the textarea’s `onKeyDown`, replace the submit block with:

```tsx
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
```

### 2.3 Tooltip on send button
Wrap the icon button with a tooltip to explain why it’s disabled:

```tsx
<TooltipProvider>
  <Tooltip>
    <TooltipTrigger asChild>
      <IconButton ... disabled={disabledFlag} />
    </TooltipTrigger>
    {hasProcessingFiles && (
      <TooltipContent side="top" align="center">
        Attached files are still processing. Try again shortly.
      </TooltipContent>
    )}
  </Tooltip>
</TooltipProvider>
```

### 2.4 Hide spinner when uploads finish
No change necessary—`ProjectsContext` already updates the UI once statuses flip to `COMPLETED` or `FAILED`.

---

## 3. Backend considerations

No backend change is strictly required. The API already returns correct status values. The frontend simply needs to respect them. However, you may optionally:

- Enforce the rule server-side by rejecting `/api/chat` requests that include `current_message_files` with `PROCESSING` status. (Return 409 Conflict with message “Files still indexing.”)
- Emit audit logs when a prompt is rejected for this reason.

---

## 4. Testing

1. Upload a large PDF (watch the chip show “Processing…”).
2. Ensure the send button and Enter key are disabled while processing.
3. Wait until status shows “Completed”.
4. Verify the first prompt now succeeds (LLM references the document).
5. Regression-test other scenarios (no attachments, small files, multi-file uploads, failed uploads).

---

## 5. Deployment

1. Apply the frontend changes in `onyx-repo`.
2. Build and redeploy the web UI.
3. (Optional) add backend guard if you choose to enforce it server-side.

Once implemented, users can’t accidentally fire off the first prompt before their documents are indexed, eliminating the “second prompt works better” confusion.
