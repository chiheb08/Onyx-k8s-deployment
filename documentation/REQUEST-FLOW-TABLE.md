# Prompt-to-Answer Request Flow

This table lists the key steps and API calls involved from the moment a user submits a prompt until the LLM answer is returned. It combines frontend actions, backend endpoints, and background jobs.

| Step | Component | What Happens | API / Endpoint | Notes |
|------|-----------|--------------|----------------|-------|
| 1 | Browser | User types question, attaches files. | – | Attachments appear in chat input bar. |
| 2 | Browser → API | Large file upload. | `POST /api/user/projects/file/upload` | Returns upload ID(s). UI marks file as “Processing…”. |
| 3 | Backend (background) | Celery task `process_single_user_file` chunks file, generates embeddings, stores in Vespa/Postgres. | – | Upon completion file status becomes `COMPLETED`. |
| 4 | Browser polling | Check file status. | `POST /api/user/projects/file/statuses` | Runs until `COMPLETED`; status shown in UI. |
| 5 | Browser → API | Prompt submission (user message). | `POST /api/chat` | Body includes message, selected document IDs, and file descriptors for uploaded files. |
| 6 | Backend (FastAPI) | Build chat chain, store user message in DB. | – | Writes a row into `chat_message` (`message_type=user`). |
| 7 | Backend → Storage | Load file contents for current message + persona files. | – | `parse_user_files` decides inline vs retrieval. |
| 8 | Backend → Search | If retrieval needed, call vector search. | `POST /api/internal/search` (internal call) | Retrieves top document chunks via embeddings. |
| 9 | Backend | Build prompt (system prompt + history + docs). | – | Enforces token budgets via `compute_max_document_tokens_for_persona`. |
|10 | Backend → LLM | Send prompt to LLM (vLLM/OpenAI/etc.). | `POST /api/chat/stream` ↴<br>`→ /internal/llm` provider call | Streams tokens via SSE/WebSocket back to client. |
|11 | Backend | Write assistant message to DB as it streams. | – | Final assistant message stored in `chat_message` (`message_type=assistant`). |
|12 | Browser ← Backend | SSE/WebSocket delivers tokens to UI. | `/api/chat/stream` | UI shows typing indicator, then renders answer with citations. |
|13 | Backend | Update token usage, feedback hooks, optional tracing. | – | Token counts saved in DB, Langfuse/Braintrust called if configured. |
|14 | Browser | Prompt input resets, user can ask follow-up. | – | Conversation state persists in chat session. |

**Notes:**
- Steps 2–4 only occur when new files are uploaded. Existing documents skip to step 5.
- Retrieval vs inline depends on token thresholds; if inline, step 8 is skipped.
- Background jobs (step 3) run on Celery workers; monitoring `/metrics` or log outputs helps confirm progress.

