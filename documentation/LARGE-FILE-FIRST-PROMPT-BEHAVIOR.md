# Large File Uploads: Why the First Prompt Sometimes Misses

When you upload a big document and immediately ask a question, the very first prompt may not “see” the document. The second prompt usually works. Here’s the exact reason and how to handle it.

---

## 🔄 What Happens After Upload

1. **Upload starts a background job** (`process_single_user_file`).
   - The file status stays **PROCESSING** until the job finishes.
   - During this time the frontend shows a “Processing…” chip and keeps polling `/api/user/projects/file/statuses`.

2. **Indexing pipeline runs**:
   - Splits the document into chunks.
   - Generates embeddings and stores them in Vespa / Postgres.
   - Once done, the file status changes to **COMPLETED**.

3. **Prompt handling depends on file size** (`parse_user_files`):
   - Calculates the available document budget (`available_tokens`).
   - Sets `uploaded_context_cap = available_tokens * 0.5`.
   - If total file tokens ≤ cap → file is **inlined** directly in the prompt (doesn’t need the index).
   - If total file tokens > cap → Onyx expects to use **retrieval** via embeddings (needs the index).

### Inline vs Retrieval (Plain English)

| Term | What it means in Onyx | When it’s used |
|------|-----------------------|----------------|
| **Inline** | Drop the document text straight into the prompt sent to the LLM. | Small / medium files that fit the token budget. |
| **Retrieval** | Use embeddings to search for relevant snippets at question time. | Large files that would blow the prompt budget if inlined. |

### Diagram – Upload to Answer

```
Upload file
   │
   ├─ Optimistic UI (status = PROCESSING)
   │
   ├─ Background job finishes → status = COMPLETED
   │
   └─ Prompt time
       ├─ Inline path (small file) → prompt includes document text immediately
       └─ Retrieval path (large file) → needs embeddings
             └─ if embeddings missing ⇒ first prompt can’t find the info
```

---

## 🤔 Why the First Prompt Fails for Large Files

```
Upload (status = PROCESSING)
   │
   └─ First question → retrieval path → embeddings not ready → no result
               (background job still running)
   │
Background job finishes (status = COMPLETED)
   │
   └─ Second question → embeddings available → retrieval works → answer
```

- Big files exceed the inline threshold, so Onyx relies on retrieval.
- Immediately after upload the embeddings aren’t ready, so the retrieval step has nothing to return.
- By the second prompt the embeddings exist, so the LLM sees the document.

---

## ✅ How to Avoid It

1. **Wait for “Processing” to finish** before asking your first question.
2. If files are extremely large, consider splitting them so they can be inlined.
3. Readiness signals:
   - Frontend chip switches from “Processing…” to normal.
   - `/api/user/projects/file/statuses` returns `COMPLETED`.

---

## 🛠 Solutions (software, architecture, hardware)

| Type | Idea | Notes |
|------|------|-------|
| UX / Software | Disable the send button or show a banner while files are `PROCESSING`. | Avoids user confusion; ensures first prompt waits for indexing. |
| Backend (inline) | Raise `uploaded_context_cap` multiplier in `parse_user_files` so more content can be inlined. | Works if you accept larger prompts / higher token cost. |
| Backend (retrieval) | Speed up embedding jobs: add more Celery workers, increase worker CPU/RAM, or run embeddings with GPU acceleration. | Shrinks the processing window. |
| Architecture | Pre-split huge documents before upload or in ingestion pipelines. | Smaller docs index faster and can often be inlined. |
| Hardware | Use faster storage, more Redis/DB resources, and additional worker nodes. | Helps when many large uploads happen simultaneously. |
| Monitoring | Track indexing queue length and completion time; alert when lagging. | Lets you scale before users notice delays. |

With this context you know nothing is “wrong” with the LLM—the document just hasn’t finished its embedding job yet. Give it a moment after each large upload and the very next prompt will work normally.
