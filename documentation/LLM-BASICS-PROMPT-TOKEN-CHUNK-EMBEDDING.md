# LLM Building Blocks – Prompt, Token, Chunk, Embedding (Onyx Edition)

This guide explains the essential pieces of an LLM workflow the way I’d explain it to someone who is just starting out. We’ll use a simple end‑to‑end story and diagrams to show where each concept fits.

---

## 🧱 The Four Pieces

| Term | Plain-English Definition | Why Onyx Cares |
|------|---------------------------|---------------|
| **Prompt** | The instructions + text we send to the LLM. Think of it as the question sheet. | Onyx builds prompts by combining system instructions, chat history, and documents. |
| **Token** | A tiny slice of text (≈3–4 characters). LLMs count everything in tokens. | Tokens determine cost, speed, and whether the prompt fits in the model’s memory. |
| **Chunk** | A small segment of a document. We chop long files into chunks so they fit. | Onyx indexes documents chunk-by-chunk and only sends relevant chunks to the LLM. |
| **Embedding** | A numeric fingerprint of text (vector). Similar text ≈ similar vectors. | Onyx uses embeddings to search and match the best document chunks for each question. |

---

## 🖼️ High-Level Diagram

```
User Question
    │
    ▼
Prompt Builder ──► Prompt (instructions + question + top chunks)
                           │
                           ▼
                        LLM (e.g., vLLM)
                           │
                           ▼
                   Answer (streamed back to user)

Document Flow (background work)
    ┌───────────────┐
    │  Original doc │
    └──────┬────────┘
           │ split into
           ▼
      Chunks (512 tokens each)
           │ for each chunk
           ▼
    Embedding (vector)
           │ stored in
           ▼
  Vector Search (Vespa / PGvector)
           │ retrieves top chunks
           └──────────────────────────────┘
```

---

## 🔁 Step-by-Step Story

We’ll follow what happens when Alice uploads a PDF and later asks a question about it.

### 1. Uploading the Document (Indexing Pipeline)

1. **Alice uploads `HR_Policy.pdf`.**
2. Onyx **splits the PDF into chunks**: each is around 512 tokens (≈250–300 words).  
   - If the PDF is 20 pages, we might get 50 chunks.
3. For each chunk, Onyx **creates an embedding** (a vector of numbers).  
   - These embeddings go into Vespa (vector search engine).  
   - We also store chunk text + metadata in the database.
4. Now the document is ready for retrieval.

### 2. Asking a Question (Retrieval + Prompt Building)

1. **Alice asks:** “What’s the parental leave policy?”
2. Onyx turns her question into an embedding and **searches for similar chunk embeddings**.  
   - Suppose chunks #12 and #13 are the best matches.
3. Onyx builds a **prompt**:
   - System instructions (persona)  
   - Conversation history  
   - Alice’s question  
   - Top chunks (#12 and #13)  
   - All these pieces add up to X tokens.
4. Before sending, Onyx checks `<model context limit>` − `<prompt tokens>` − `<reserved output>` − `<buffer>` to ensure the prompt fits.

### 3. Getting the Answer

1. Onyx sends the prompt to the LLM (vLLM or external API).
2. The LLM generates output tokens (the answer) and streams them back.
3. Onyx attaches citations pointing to chunks #12 and #13.
4. Alice sees the answer in the chat with clickable references.

---

## 🧮 Concrete Mini Example

- **LLM context window:** 4,000 tokens
- **Reserved output tokens:** 512 (room for the answer)
- **Prompt pieces:**
  - System instructions: 150 tokens
  - Chat history: 200 tokens
  - Alice’s question: 40 tokens
  - Chunk #12: 300 tokens
  - Chunk #13: 320 tokens

**Token math**:
```
150 + 200 + 40 + 300 + 320 = 1,010 prompt tokens
Reserve 512 for output
Add 40 token buffer
Total = 1,562 tokens used
```
We’re safely under 4,000, so the request is good to go.

---

## 🔧 Where to Adjust Things

| Want to change… | What to tweak |
|------------------|---------------|
| Chunk size while indexing | `DOC_EMBEDDING_CONTEXT_SIZE` (default 512). |
| Prompt space reserved for answers | `GEN_AI_NUM_RESERVED_OUTPUT_TOKENS`. |
| Strict chunking vs. flexible chunking | `STRICT_CHUNK_TOKEN_LIMIT`. |
| Total context window (if provider doesn’t report it) | `GEN_AI_MAX_TOKENS` / `GEN_AI_MODEL_FALLBACK_MAX_TOKENS`. |
| Frontend guard (currently halves backend allowance) | `ChatPage.tsx` multiplier (`* 0.5`). |

---

## 📝 Quick Recap for Juniors

1. **Prompt** = what we send to the LLM (instructions + history + question + chosen chunks).
2. **Token** = how text is measured; everything must stay within the model’s token limit.
3. **Chunk** = a manageable slice of a document; easier to store, search, and insert into prompts.
4. **Embedding** = numerical fingerprint that lets us find the best chunks quickly.
5. Onyx’s workflow: upload → chunk & embed → store → retrieve top chunks → build prompt → LLM → answer with citations.

Keep these mental models handy and you’ll understand how Onyx bridges long documents with LLM answers without overwhelming the model’s memory.
