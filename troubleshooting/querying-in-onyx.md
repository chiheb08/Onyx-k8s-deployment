# Querying in Onyx — How Retrieval and Answering Actually Work

This document explains how Onyx answers questions: what happens from the moment you hit Send, how documents are retrieved, and the critical difference between **direct context injection** and **RAG (Retrieval-Augmented Generation)**.

Written for Onyx v4.x local Docker deployments, but the concepts apply generally.

> **New to these concepts?** See the beginner-friendly guide with glossary and simple diagrams:  
> [INTERNAL-SEARCH-AND-RAG-EXPLAINED-SIMPLE.md](../docs/reference/INTERNAL-SEARCH-AND-RAG-EXPLAINED-SIMPLE.md)

---

## Table of Contents

1. [The Big Picture](#the-big-picture)
2. [Two Ways Onyx Gets Document Content](#two-ways-onyx-gets-document-content)
3. [Direct Context Injection (Not RAG)](#direct-context-injection-not-rag)
4. [RAG in Onyx (The `internal_search` Path)](#rag-in-onyx-the-internal_search-path)
5. [Side-by-Side Comparison](#side-by-side-comparison)
6. [End-to-End: What Happens When You Send a Chat Message](#end-to-end-what-happens-when-you-send-a-chat-message)
7. [Indexing: How Documents Get Into the Search Index](#indexing-how-documents-get-into-the-search-index)
8. [User-Uploaded Files vs Connector Documents](#user-uploaded-files-vs-connector-documents)
9. [The LLM Agent Loop (Tools + Multiple Rounds)](#the-llm-agent-loop-tools--multiple-rounds)
10. [Storage Layers Involved](#storage-layers-involved)
11. [Real Example From This Deployment](#real-example-from-this-deployment)
12. [When Each Path Is Used (Decision Logic)](#when-each-path-is-used-decision-logic)
13. [Common Misconceptions](#common-misconceptions)

---

## The Big Picture

When you ask Onyx a question, it does **not** simply send your text to an LLM. The backend runs a multi-step pipeline:

```
Your message
    │
    ├─► Load chat history
    ├─► Attach files? → Direct injection OR flag for search
    ├─► Build system prompt + tools list
    │
    └─► LLM Agent Loop (up to 6 cycles)
            │
            ├─► LLM decides: answer directly OR call a tool
            │
            ├─► Tool: internal_search  → RAG over OpenSearch
            ├─► Tool: web_search       → External web
            ├─► Tool: read_file        → Read attached file by offset
            ├─► Tool: open_url         → Fetch URL content
            ├─► Tool: python           → Code interpreter
            │
            └─► Final answer streamed to UI
```

**Key insight:** "Querying" in Onyx can mean three different things depending on context:

| What people say | What Onyx actually does |
|-----------------|-------------------------|
| "I attached a PDF and asked about it" | **Direct context injection** (full text in prompt) |
| "Search my company docs" | **RAG** via `internal_search` tool |
| "What is machine learning?" (no docs) | **Pure LLM** (no retrieval) |

---

## Two Ways Onyx Gets Document Content

Onyx uses two fundamentally different strategies to give the LLM access to documents:

### Path A — Direct Context Injection
> "Here is the entire document. Read it and answer."

The full text (or a large portion) is **copied into the LLM prompt** before the first token is generated. No vector search. No embeddings at query time.

### Path B — RAG (Retrieval-Augmented Generation)
> "Search the index for relevant chunks, then answer using only what was found."

At query time, Onyx:
1. Embeds your question
2. Searches **OpenSearch** (hybrid semantic + keyword)
3. Retrieves the top matching **chunks**
4. Feeds only those chunks to the LLM

These are **not interchangeable**. They solve different problems.

---

## Direct Context Injection (Not RAG)

### When it happens

- You **attach a file** to a chat message (paperclip icon)
- Files belong to a **Project** and are small enough to fit in context
- Persona-attached user files that fit the token budget

### How it works (step by step)

1. **Upload** — File is stored in **Minio** (S3-compatible object storage)
2. **Token count** — Background worker parses the file and records `token_count` in `user_file` table
3. **Fit check** — Before chat, `extract_context_files()` asks:
   > "Do all project/attached files fit in ≤ 60% of the LLM context window?"
4. **If YES (files fit)** — `load_chat_file()` reads the file from Minio, extracts text (PDF → plain text), and builds `file_texts[]`
5. **Prompt injection** — `_build_project_message()` adds a synthetic message to the prompt containing the full file text
6. **LLM answers** — Model sees the document as if you pasted it into the chat

### Code path (simplified)

```
process_message.py
  └─► extract_context_files()      # fit check + load text
        └─► load_in_memory_chat_files()
              └─► load_chat_file()
                    └─► Minio read → extract_file_text() → content_text

llm_loop.py
  └─► _build_project_message()     # inject file_texts into message history
  └─► run_llm_loop()               # LLM sees full document in prompt
```

### Important properties

| Property | Value |
|----------|-------|
| Requires OpenSearch indexing? | **No** |
| Requires `user_file.status = COMPLETED`? | **No** (only needs raw file in Minio + token_count) |
| Retrieval method | Full document text in prompt |
| Best for | Small/medium files, single-doc Q&A |
| Limitation | Bounded by LLM context window (~60% reserved for files) |

### Why your PDF worked even with `FAILED` status

Your `ML-IhebMejri.pdf` had:
- `token_count = 806` (fits easily in context)
- Raw file in Minio (upload succeeded)
- `status = FAILED` (only the **OpenSearch indexing** step failed)

Direct injection reads from **Minio**, not OpenSearch. Indexing failure does not block chat with an attached file.

Log proof:
```
Cache miss for file with id=5b7f468f-01c6-4ae3-970d-c0149e34f88d
load_chat_file took 0.181 seconds
```

---

## RAG in Onyx (The `internal_search` Path)

### When it happens

- Default Assistant has **`internal_search` tool** enabled (when tools are configured)
- User asks about **indexed connector documents** (Google Drive, Confluence, Slack, etc.)
- Project files are **too large** to fit in context → `use_as_search_filter = true`
- LLM autonomously decides to search (tool choice = AUTO)

### How it works (step by step)

Onyx's `SearchTool` implements a **5-stage RAG pipeline** (documented in `search_tool.py`):

#### Stage 1 — Query Generation
Multiple search queries are generated:
- LLM-generated queries from chat history (broad, can split complex questions)
- A semantic-tuned query optimized for embedding search
- Keyword-emphasized queries for exact terminology

Example: *"Compare sales at Company X vs Company Y"* becomes:
- `"sales process Company X"`
- `"sales process Company Y"`

#### Stage 2 — Hybrid Retrieval (RRF)
Each query hits **OpenSearch** with hybrid search:
- **Semantic**: query embedding vs chunk embeddings (vector similarity)
- **Keyword**: BM25-style keyword matching
- Results combined via **Weighted Reciprocal Rank Fusion (RRF)**
- Adjacent chunks merged for continuity

```python
# retrieval/search_runner.py (simplified)
query_embedding = embed(query)
chunks = document_index.hybrid_retrieval(
    query=query,
    query_embedding=query_embedding,
    query_type=SEMANTIC or KEYWORD,
    filters=acl_filters,
)
```

#### Stage 3 — LLM Selection
Retrieved chunks (truncated set) are shown to the LLM. The LLM **selects** which chunks are most relevant — reducing noise before the final read.

#### Stage 4 — Expansion
For selected chunks, Onyx fetches **surrounding context** (chunks above/below) so the LLM gets coherent passages, not isolated fragments.

#### Stage 5 — Prompt Building
Selected + expanded chunks are formatted as JSON tool results and returned to the LLM. The LLM uses this as grounding context for its answer. Citations (`[[1]]`, `[[2]]`) link back to source documents in the UI.

### Code path (simplified)

```
llm_loop.py
  └─► run_llm_loop()
        └─► LLM emits tool_call: internal_search
              └─► SearchTool.run()
                    ├─► generate queries
                    ├─► search_pipeline() → OpenSearch hybrid retrieval
                    ├─► LLM chunk selection
                    ├─► chunk expansion
                    └─► return chunks as tool result → back to LLM
```

### Important properties

| Property | Value |
|----------|-------|
| Requires OpenSearch? | **Yes** |
| Requires prior indexing? | **Yes** (chunks + embeddings must exist) |
| Retrieval method | Semantic + keyword search over chunks |
| Best for | Large corpora, many documents, connector data |
| Limitation | Depends on chunk quality, embedding model, index health |

### Embedding model

In your deployment, embeddings use the **inference model server** container (`onyx-inference_model_server-1`), typically running a model like `nomic-embed-text` or similar configured in Admin → Index Settings.

---

## Side-by-Side Comparison

| Dimension | Direct Context Injection | RAG (`internal_search`) |
|-----------|--------------------------|-------------------------|
| **What it is** | Paste document into prompt | Search index, retrieve relevant chunks |
| **When** | File attached & fits in context | Indexed docs, or files too large for context |
| **Data source at query time** | Minio (raw file) | OpenSearch (chunk embeddings) |
| **Needs indexing first?** | No | Yes |
| **Needs OpenSearch up?** | No | Yes |
| **Query-time embedding?** | No | Yes (embed the user's question) |
| **LLM sees** | Full document(s) | Only top-K relevant chunks |
| **Citations** | Optional (project file citations) | Yes (`[[n]]` linked to sources) |
| **Scales to** | ~60% of context window | Entire indexed corpus |
| **Failure if index down** | Still works (if file in Minio) | **Fails** — no retrieval |
| **Typical latency** | Fast (one LLM call) | Slower (search + selection + expansion + answer) |

### Analogy

| Approach | Real-world analogy |
|----------|-------------------|
| **Direct injection** | Handing the LLM a printed copy of the document and saying "read this, then answer" |
| **RAG** | Giving the LLM a library card, it searches the catalog, pulls 5 relevant pages, then answers |

---

## End-to-End: What Happens When You Send a Chat Message

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. REQUEST ARRIVES (api_server)                                 │
│    POST /chat/send-chat-message                                 │
│    Body: message, chat_session_id, file_ids, model, etc.        │
└────────────────────────────┬────────────────────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. BUILD CHAT TURN (process_message.py)                         │
│    • Load persona, LLM config, tools                            │
│    • verify_user_files() — check file ownership/access          │
│    • extract_context_files() — injection vs search decision     │
│    • determine_search_params() — enable/disable internal_search │
│    • Load chat history, build system prompt                     │
└────────────────────────────┬────────────────────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. FILE HANDLING BRANCH                                         │
│                                                                 │
│    Files fit in context?                                        │
│    ├─ YES → load text from Minio → inject into prompt          │
│    └─ NO  → set use_as_search_filter=true                       │
│              → internal_search scoped to project/persona files  │
└────────────────────────────┬────────────────────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. LLM AGENT LOOP (llm_loop.py) — up to 6 cycles               │
│                                                                 │
│    Cycle 1:                                                     │
│    • Send prompt (history + system + injected files + tools)    │
│    • LLM streams response OR calls a tool                       │
│                                                                 │
│    If tool called (e.g. internal_search):                       │
│    • Run SearchTool → OpenSearch RAG pipeline                   │
│    • Append tool result to history                              │
│    • Cycle 2: LLM reads search results, generates answer        │
│                                                                 │
│    Last cycle: tool_choice=NONE — force final answer            │
└────────────────────────────┬────────────────────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. STREAM RESPONSE TO UI                                        │
│    • AgentResponseDelta packets (answer tokens)                 │
│    • CitationInfo packets (source links)                        │
│    • Tool call UI (searching internal documents...)             │
│    • Save to PostgreSQL (chat_message, tool_call tables)        │
└─────────────────────────────────────────────────────────────────┘
```

---

## Indexing: How Documents Get Into the Search Index

RAG only works if documents were **indexed first**. Indexing is a separate background pipeline:

```
Document source
    │
    ├─► Connectors (Google Drive, Slack, GitHub, etc.)
    │     └─► background worker: fetch → parse → chunk → embed → OpenSearch
    │
    └─► User-uploaded files (Projects / chat attachments)
          └─► Celery: process_user_file_impl
                ├─► Read from Minio
                ├─► Parse + chunk (e.g. 2 chunks for your PDF)
                ├─► Embed each chunk (inference model server)
                └─► Write to OpenSearch
                      └─► user_file.status = COMPLETED (or FAILED)
```

### Chunking

Documents are split into **chunks** (passages of ~512 tokens with overlap). Each chunk gets:
- Text content
- Embedding vector (float array)
- Metadata (document ID, source, ACL, project ID, etc.)

Stored in **OpenSearch** as the vector + keyword index.

### Hybrid search at query time

```
User question: "What is data engineering?"
        │
        ▼
Embed question → [0.12, -0.34, 0.56, ...]   (768-dim vector)
        │
        ▼
OpenSearch hybrid query:
  • Vector similarity (semantic): find chunks with close embeddings
  • BM25 keyword match: find chunks with matching terms
  • Combine via RRF
        │
        ▼
Top 20-50 chunks → LLM selection → expansion → answer
```

---

## User-Uploaded Files vs Connector Documents

| Aspect | User files (Projects/chat) | Connector documents |
|--------|---------------------------|---------------------|
| Storage | Minio + OpenSearch (if indexed) | OpenSearch only |
| Immediate chat use | Yes (direct injection) | No (must be indexed) |
| Searchable later | Only if indexing succeeded | Yes (primary purpose) |
| ACL | Per-user / per-project | Connector + document-set ACLs |
| Indexing trigger | On upload (`process_user_file`) | Connector sync jobs |
| Status tracking | `user_file.status` | `index_attempt` / connector status |

---

## The LLM Agent Loop (Tools + Multiple Rounds)

Onyx is not a single-prompt chatbot. It runs an **agent loop**:

```python
# llm_loop.py (conceptual)
for cycle in range(MAX_LLM_CYCLES):  # default: 6
    if last_cycle:
        tools = []           # force answer, no more tools
        tool_choice = NONE
    else:
        tools = [internal_search, web_search, read_file, ...]
        tool_choice = AUTO   # LLM decides

    result = run_llm_step(prompt + history, tools=tools)

    if result.tool_calls:
        run tools in parallel
        append tool results to history
        continue   # another LLM cycle
    else:
        stream answer to user
        break
```

### Why this matters for local Ollama

- Each tool call = **another full LLM round-trip**
- `internal_search` alone can trigger 3–5 LLM calls (query gen → selection → expansion → answer)
- Slow local models (Llama3 ~20s/call, Qwen ~60s+) make multi-tool flows very slow or timeout
- Models without native tool support (Llama3) break the agent loop entirely

This is why we disabled tools for the local Llama3 setup — simple Q&A works; agentic RAG does not.

---

## Storage Layers Involved

```
┌──────────────────────────────────────────────────────────────┐
│ PostgreSQL (relational_db)                                   │
│  • users, chat sessions, messages                            │
│  • llm_provider, persona, tools config                       │
│  • user_file metadata (status, token_count, chunk_count)     │
│  • connector / document-set configuration                    │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ Minio (S3)                                                   │
│  • Raw uploaded files (PDF, DOCX, etc.)                      │
│  • Cached plaintext extractions                              │
│  • Used by: direct context injection, indexing input         │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ OpenSearch                                                   │
│  • Chunk text + embedding vectors                            │
│  • Keyword index for BM25                                    │
│  • Used by: RAG / internal_search only                       │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ Redis (cache)                                                │
│  • Celery task queues                                        │
│  • Per-file processing locks                                 │
│  • Session/cache data                                        │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ inference_model_server                                       │
│  • Embedding model (index + query time)                      │
│  • Optional reranking                                        │
└──────────────────────────────────────────────────────────────┘
```

---

## Real Example From This Deployment

### Scenario: Upload PDF, ask a question in chat

| Step | What happened | Path used |
|------|---------------|-----------|
| Upload `ML-IhebMejri.pdf` | Stored in Minio, `user_file` row created | — |
| Background indexing | Parsed 2 chunks, 806 tokens; OpenSearch write **failed** | Indexing (failed) |
| Attach file + ask question | `load_chat_file` read PDF from Minio in 181ms | **Direct injection** |
| LLM answer | Full PDF text in prompt, Llama3 answered | **Not RAG** |

### What would happen with RAG (if indexing worked + tools enabled)

| Step | What would happen | Path used |
|------|-------------------|-----------|
| User asks without attaching file | LLM calls `internal_search` | **RAG** |
| Query embedded | inference_model_server | RAG |
| OpenSearch returns top chunks | hybrid semantic + keyword | RAG |
| LLM selects + expands chunks | SearchTool stages 3–4 | RAG |
| Answer with citations `[[1]]` | Grounded in retrieved chunks | RAG |

---

## When Each Path Is Used (Decision Logic)

From `extract_context_files()` and `determine_search_params()`:

```
IF no files attached:
    IF connectors indexed AND internal_search tool enabled:
        → RAG on demand (LLM decides to search)
    ELSE:
        → Pure LLM (no retrieval)

IF files attached AND total_tokens ≤ 60% of context window:
    → Direct injection (file_texts in prompt)
    → internal_search DISABLED for this turn
      (content already in prompt, search would be redundant)

IF files attached AND total_tokens > 60% of context window:
    → Direct injection SKIPPED (too large)
    → use_as_search_filter = true
    → internal_search ENABLED, scoped to project/persona file IDs
    → RAG over only those files in OpenSearch
      (requires successful indexing!)
```

### The 60% rule

Onyx deliberately caps file injection at **60% of the LLM context window** (not 100%). Remaining budget is reserved for:
- System prompt
- Chat history
- Tool definitions
- Search results (if RAG runs later in the loop)

---

## Common Misconceptions

### ❌ "Attaching a file always uses RAG"
**No.** Small attached files use **direct injection**. RAG is used when files are too large, or when searching indexed corpora without attaching.

### ❌ "FAILED status means the file can't be used in chat"
**No.** `FAILED` only means OpenSearch indexing failed. Direct injection still works if the raw file is in Minio.

### ❌ "RAG and injection both need OpenSearch"
**No.** Only RAG needs OpenSearch. Injection reads from Minio directly.

### ❌ "Indexing and querying are the same step"
**No.** Indexing is async background work (Celery). Querying happens at chat time and may never touch the index.

### ❌ "One LLM call per user message"
**No.** With tools enabled, a single "hello" can trigger multiple LLM calls. `internal_search` alone adds several rounds.

### ❌ "All models support the agent/tool loop"
**No.** Ollama models like `llama3:latest` reject tool calling. Onyx's agent loop requires tool-capable models or falls back to broken behavior.

---

## Summary

| Question type | Mechanism | Needs index? |
|---------------|-----------|--------------|
| Chat with small attached file | Direct injection | No |
| Chat with huge attached file | RAG (scoped to file) | Yes |
| Search company knowledge base | RAG (`internal_search`) | Yes |
| General knowledge question | Pure LLM | No |
| Web question | `web_search` tool | No (uses internet) |

**Direct injection** = copy document into the prompt.  
**RAG** = search an index, retrieve relevant chunks, then answer.

Your PDF worked via injection. It failed indexing. Those are independent paths — and understanding that distinction is the key to debugging Onyx retrieval issues.

---

*See also: [troubleshooting.md](./troubleshooting.md) for deployment-specific fixes and error logs.*
