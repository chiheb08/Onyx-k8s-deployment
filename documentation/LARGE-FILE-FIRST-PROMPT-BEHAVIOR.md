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
   - If total file tokens ≤ cap → file is inlined directly in the prompt (doesn’t need the index).
   - If total file tokens > cap → Onyx expects to retrieve chunks via embeddings (needs the index).

---

## 🤔 Why the First Prompt Fails for Large Files

- For big files the inline option is off (too many tokens), so Onyx relies on embeddings.
- Immediately after upload the embeddings aren’t ready (still **PROCESSING**).
- The first prompt therefore has nothing to retrieve, so the answer looks empty.
- By the time you ask again, indexing is done and the second prompt succeeds.

---

## ✅ How to Avoid It

1. **Wait for “Processing” to finish** before asking your first question.
2. If files are extremely large, consider splitting them so they can be inlined.
3. Readiness signals:
   - Frontend chip switches from “Processing…” to normal.
   - `/api/user/projects/file/statuses` returns `COMPLETED`.

---

## 🛠 Optional Improvements (if you want to change behavior)

- **Disable send button** while any attachment is still `PROCESSING` (frontend change).
- **Increase upload headroom** in `parse_user_files` if you prefer inlining over retrieval.
- **Show a banner**: “Still indexing your file; answers may be incomplete.”

With this context you know nothing is “wrong” with the LLM—the document just hasn’t finished its embedding job yet. Give it a moment after each large upload and the very next prompt will work normally.
