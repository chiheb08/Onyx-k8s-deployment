# Frontend Context Limits in Onyx

This note explains how the web client currently reduces the document context budget before calling the backend, what code paths are involved, and how to change the behavior.

---

## 1. High-Level Summary

1. **Backend API** `/api/chat/max-selected-document-tokens` returns the safe number of document tokens for a persona. It already subtracts system prompts, estimated user message, reserved output tokens, and a buffer.
2. **Frontend (ChatPage.tsx)** immediately halves that number: `availableContextTokens = maxTokens * 0.5`. This conservative guard exists purely in the UI.
3. **Document selector** (`DocumentResults.tsx`) uses the persona’s `maxTokens` to disable the “select” button when `selectedDocumentTokens > maxTokens - 75`. There is still a TODO to wire in the real token count.
4. **File upload bar** (`ChatInputBar.tsx`) reuses the halved value to hide the “processing” banner when attached files stay within the context cap.

**Result:** Users can only select roughly half of the backend allowance because of the `* 0.5` multiplier on the frontend.

---

## 2. Relevant Code Locations

| File | Key Snippet | Effect |
|------|-------------|--------|
| `backend/onyx/server/query_and_chat/chat_backend.py` | `get_max_document_tokens()` → `compute_max_document_tokens_for_persona()` | Computes safe doc tokens per persona. No additional cap. |
| `backend/onyx/chat/prompt_builder/citations_prompt.py` | `compute_max_document_tokens()` | Calculates tokens = context − prompts − user message − reserved output − 40 buffer. |
| `web/src/app/chat/hooks/useChatController.ts` | Fetches `/api/chat/max-selected-document-tokens` and sets `_maxTokens`. | Fetches backend number. |
| `web/src/app/chat/components/ChatPage.tsx` | `availableContextTokens = (maxTokens ?? DEFAULT_CONTEXT_TOKENS) * 0.5` | **Halves** the backend budget for UI. |
| `web/src/app/chat/components/documentSidebar/DocumentResults.tsx` | `tokenLimitReached = selectedDocumentTokens > maxTokens - 75` | Disables doc selection when close to cap. Currently `selectedDocumentTokens` still TODO. |
| `web/src/app/chat/components/input/ChatInputBar.tsx` | Calculates `totalTokens` and compares to `availableContextTokens`. | Controls processing banner & prevents overshoot during uploads. |

---

## 3. How to Restore Full Context

1. **Remove or change the 50% cap**:
   - Edit `ChatPage.tsx`, replace `* 0.5` with `* 1` or a different factor for both new and existing sessions.
2. **Optional safety margin**:
   - Keep the UI buffer in `DocumentResults.tsx` (current `maxTokens - 75`). Adjust if you want more headroom.
3. **Wire real token counts (optional)**:
   - Replace `selectedDocumentTokens={0}` with the actual total of currently selected documents to make the guard precise.
4. **Rebuild the web app** after changes (`pnpm build` or your deployment pipeline).

---

## 4. Why the Cap Exists

- Adds a UI safety net on top of server-side calculations to avoid hitting the LLM’s hard context limit.
- Useful when document token counts are estimated or when high latency models make retries expensive.
- You can relax it once you trust the backend buffers and document token measurement.

---

## 5. Recommended Adjustments

| Goal | Suggested Change |
|------|------------------|
| Allow full backend context | Remove `* 0.5` multiplier. |
| Keep guard but less aggressive | Use `* 0.8` or similar. |
| Keep slower/safer behavior | Leave as-is, but document the behavior for users. |
| Provide UI feedback on actual tokens | Implement TODOs to calculate `selectedDocumentTokens` so the selector shows precise limits. |

---

With this information you can tune the frontend’s context usage without altering backend safeguards. After adjusting the multiplier, redeploy the web client so users can immediately select the larger context window.
