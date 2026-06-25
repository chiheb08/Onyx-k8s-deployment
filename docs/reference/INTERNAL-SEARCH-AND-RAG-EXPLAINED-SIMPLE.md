# Onyx `internal_search` and RAG — Simple Guide (Every Term Explained)

**Audience:** Anyone new to Onyx, RAG, or search pipelines.  
**Goal:** Understand what happens when you upload a file and ask a question — in plain language.

---

## The one sentence you need to remember

> **`internal_search` is Onyx’s built-in “search my documents” tool. It *is* RAG for your company files. It is NOT the same as pasting a whole file into the chat.**

---

## Part 1 — Glossary (every technical word)

Read this first. Every other section uses these words.

| Term | Simple meaning | Real-world analogy |
|------|----------------|-------------------|
| **LLM** (Large Language Model) | The AI that writes answers (Qwen, GPT, Llama, etc.) | A very smart intern who can write text but cannot magically open your filing cabinet |
| **Prompt** | All text sent to the LLM: your question + instructions + documents + history | The full briefing packet you hand to the intern |
| **Context window** | Maximum text the LLM can read in one request (e.g. 32k or 128k tokens) | Size of the intern’s desk — only so many pages fit at once |
| **Token** | Small piece of text (~4 characters in English). Models count size in tokens, not pages | Words/syllables on the desk — “hello” ≈ 1 token |
| **RAG** (Retrieval-Augmented Generation) | Pattern: **find** relevant pieces of documents, **then** ask the LLM to answer using only those pieces | Intern searches the library, pulls 5 relevant pages, then writes the report |
| **Retrieval** | The “find relevant pieces” step in RAG | Searching the library catalog |
| **Generation** | The LLM writing the final answer | Intern writing the report after reading those 5 pages |
| **`internal_search`** | Onyx **tool name** for RAG over **your** indexed documents (not the public web) | Button labeled “Search company files” inside Onyx |
| **Tool** (agent tool) | Extra capability the LLM can invoke: search, read file, search web, run code | Extra buttons the intern is allowed to press |
| **Agent loop** | Onyx runs multiple LLM rounds: maybe search first, then answer | Intern thinks → searches → reads results → writes answer (not one shot) |
| **Direct context injection** | Put the **entire** document text directly into the prompt. **Not RAG.** | Photocopy the whole PDF and staple it to the question |
| **Indexing** | Background job: read file → split → embed → store in search database | Librarian catalogs a new book into the library system |
| **Chunk** | Small piece of a document (~512 tokens) stored separately in the search index | One page or paragraph in the catalog |
| **Embedding** | List of numbers representing the *meaning* of text. Similar meanings → similar numbers | GPS coordinates for “what this paragraph is about” |
| **Vector search / semantic search** | Find chunks whose embeddings are close to the question’s embedding | Find paragraphs “near” your question in meaning-space |
| **Keyword search (BM25)** | Classic word matching: exact terms, names, codes | Ctrl+F in a document |
| **Hybrid search** | Combine vector search + keyword search for better results | Search by meaning **and** by exact words |
| **OpenSearch** | Database optimized for search + vectors (used in your deployment) | The library catalog + search engine |
| **MinIO** | S3-compatible file storage — stores original PDFs, DOCX, etc. | The warehouse where original files live |
| **PostgreSQL** | Normal relational database — users, file metadata, chat history | Spreadsheet of who owns what file and its status |
| **Redis** | Fast in-memory store — mainly Celery task queues in Onyx | To-do list board for background workers |
| **Celery worker** | Background process that uploads, indexes, deletes files asynchronously | Night-shift staff processing uploads |
| **Connector** | Integration that pulls docs from Google Drive, Confluence, Slack, etc. | Automatic feed from other systems into the library |
| **Persona / Assistant** | Configured AI assistant (which model, which tools are on) | Which intern + which tools they’re allowed to use |
| **Project** | Workspace where files stay available across many chats | Shared folder for a team topic |
| **Chat attachment** | File attached to one message | Paperclip on a single email |
| **Citation `[[1]]`** | Link from answer back to source chunk/document | Footnote pointing to page 3 of the PDF |
| **ACL** (Access Control) | Rules: which user can see which document | Badge levels — you only search files you’re allowed to see |
| **indexing-model-server** | Pod/service that creates embeddings **when indexing** (upload time) | Machine that labels new books when they arrive |
| **inference-model-server** | Pod/service that creates embeddings **at question time** | Machine that understands your question when you ask |
| **`user_file.status`** | State of an uploaded file: `PROCESSING`, `COMPLETED`, `FAILED`, `DELETING` | Sticky note on a file: “still scanning”, “ready”, “broken”, “throwing away” |

---

## Part 2 — The three ways Onyx answers (big picture)

When you type a question and press Send, Onyx picks **one of three strategies**:

```
┌─────────────────────────────────────────────────────────────────┐
│                    YOU ASK A QUESTION                           │
└────────────────────────────┬────────────────────────────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
   ┌───────────┐      ┌─────────────┐     ┌──────────────┐
   │  PATH A   │      │   PATH B    │     │   PATH C     │
   │ Pure LLM  │      │   Direct    │     │     RAG      │
   │           │      │  injection  │     │ internal_    │
   │ No files  │      │             │     │   search     │
   │ General   │      │ Small file  │     │ Large files  │
   │ knowledge │      │ fits on     │     │ or company   │
   │           │      │ LLM desk    │     │ knowledge    │
   └───────────┘      └─────────────┘     └──────────────┘
        │                    │                   │
        ▼                    ▼                   ▼
   LLM answers          Full file text      Search OpenSearch
   from memory          pasted into         → get chunks
   + chat history       prompt from         → LLM answers
                        MinIO               with citations
```

### Path A — Pure LLM
- **When:** No documents involved; general question.
- **Example:** “What is Kubernetes?”
- **Needs index?** No.

### Path B — Direct context injection (NOT RAG)
- **When:** File is **small enough** to fit in the LLM context (~60% of max size).
- **Example:** 5-page PDF attached to chat.
- **How:** Onyx reads file from **MinIO**, puts full text in the prompt.
- **Needs index?** **No** — even if indexing failed!

### Path C — RAG via `internal_search`
- **When:** File is **too large** for the prompt, OR you search company/connector docs without attaching.
- **Example:** 200-page PDF in a Project; “search our Confluence”.
- **How:** Search **OpenSearch** → retrieve best chunks → LLM answers.
- **Needs index?** **Yes** — chunks and embeddings must exist.

---

## Part 3 — Is `internal_search` the same as RAG?

```
┌────────────────────────────────────────────────────────┐
│  RAG = general idea / architecture pattern             │
│                                                        │
│    "Search first, then generate answer"                │
└────────────────────────┬───────────────────────────────┘
                         │
                         │ Onyx implements this as:
                         ▼
┌────────────────────────────────────────────────────────┐
│  internal_search = Onyx tool that runs RAG             │
│  over YOUR documents (OpenSearch)                      │
└────────────────────────────────────────────────────────┘
```

| Question | Answer |
|----------|--------|
| Are they competitors? | **No.** |
| Is `internal_search` a type of RAG? | **Yes** — internal-document RAG. |
| Is pasting a full file into the prompt RAG? | **No** — that’s direct injection. |
| Is `web_search` RAG? | Similar idea, but searches the **internet**, not your index. |

---

## Part 4 — Simple diagram: what lives where

Think of Onyx as **four storage places** that must work together:

```
 YOU (browser)
      │
      ▼
┌─────────────┐
│  API Server │  ← brain that handles chat
└──────┬──────┘
       │
       ├──────────────────────────────────────────┐
       │                                          │
       ▼                                          ▼
┌──────────────┐                           ┌──────────────┐
│  PostgreSQL  │                           │    MinIO     │
│  (metadata)  │                           │ (raw files)  │
│              │                           │              │
│ • file name  │                           │ • PDF bytes  │
│ • status     │                           │ • DOCX bytes │
│ • token count│                           │ • plain text │
│ • chat msgs  │                           │   cache      │
└──────────────┘                           └──────┬───────┘
       │                                          │
       │         DIRECT INJECTION reads here ─────┘
       │
       ▼
┌──────────────┐      embed at upload      ┌─────────────────────┐
│  OpenSearch  │ ◄──────────────────────── │ indexing-model-     │
│  (search DB) │                           │ server              │
│              │                           └─────────────────────┘
│ • chunks     │
│ • embeddings │
│ • project id │
└──────┬───────┘
       │
       │  INTERNAL_SEARCH (RAG) reads here
       │      +
       ▼
┌─────────────────────┐
│ inference-model-  │  ← embeds your QUESTION at chat time
│ server            │
└─────────────────────┘
```

**Rule of thumb:**

| Path | Reads from |
|------|------------|
| Direct injection | **MinIO** |
| `internal_search` (RAG) | **OpenSearch** + **inference-model-server** |
| File upload/indexing | **MinIO** → worker → **OpenSearch** |

---

## Part 5 — Upload flow (what happens before you can search)

```
 STEP 1: You upload PDF
 ─────────────────────
 Browser → API → MinIO (file saved)
              → PostgreSQL (row created, status = PROCESSING)


 STEP 2: Background worker (Celery)
 ──────────────────────────────────
 Redis queue: "please process this file"
        │
        ▼
 Celery worker picks up job
        │
        ├─ Read file from MinIO
        ├─ Extract text (PDF → plain text)
        ├─ Split into CHUNKS (many small pieces)
        ├─ Call indexing-model-server → EMBEDDING per chunk
        └─ Write chunks to OpenSearch
        │
        ▼
 PostgreSQL: status = COMPLETED  (or FAILED if something broke)
```

**If indexing fails** (e.g. embedding model offline, OpenSearch down):
- `user_file.status = FAILED`
- **Small files** may still work in chat (direct injection from MinIO)
- **Large files** will **not** work with `internal_search` — no chunks in OpenSearch

---

## Part 6 — Question flow with `internal_search` (RAG step by step)

Imagine you ask: *“What does chapter 3 say about penalties?”* about a **large** project PDF.

```
 STEP 1 — You press Send
 ═════════════════════
 API loads: chat history, persona, tools list
 File too big for prompt → enable internal_search scoped to project files


 STEP 2 — Agent loop, round 1
 ═══════════════════════════
 LLM sees your question + tool list
 LLM decides: "I need internal_search"
 (emits a tool_call — not visible to user in normal UI)


 STEP 3 — SearchTool runs (this IS the RAG pipeline)
 ═══════════════════════════════════════════════════

   3a. QUERY GENERATION
       "penalties chapter 3" + maybe more query variants

   3b. HYBRID RETRIEVAL (OpenSearch)
       • Semantic: embed question → find similar chunks
       • Keyword: match words "penalties", "chapter 3"
       • Merge results (RRF)

   3c. LLM CHUNK SELECTION
       Too many hits → LLM picks best ones

   3d. CHUNK EXPANSION
       Pull neighboring chunks for context

   3e. Return tool result to LLM
       JSON with text snippets + metadata


 STEP 4 — Agent loop, round 2
 ═══════════════════════════
 LLM reads search results
 LLM writes human answer with citations [[1]] [[2]]


 STEP 5 — Stream to browser
 ════════════════════════
 You see answer + source links
 Postgres saves message + tool_call record
```

**Why it feels slow:** One question can trigger **3–6 LLM calls** (search decision + query gen + chunk pick + final answer).

---

## Part 7 — Direct injection flow (for comparison)

Small file (e.g. 800 tokens):

```
 Upload → MinIO + Postgres (token_count = 800)
                │
 Ask question ───┤
                │
                ▼
        Fits in 60% of context?  YES
                │
                ▼
        Read full text from MinIO
                │
                ▼
        Paste into prompt:
        "Here is the document: ... full text ...
         User question: ..."
                │
                ▼
        ONE LLM call → answer
        (no OpenSearch, no internal_search)
```

---

## Part 8 — Decision tree (which path does Onyx pick?)

```
START: User sends message
│
├─ No files attached?
│   ├─ internal_search enabled + indexed docs exist?
│   │   └─ YES → LLM MAY call internal_search (RAG) on demand
│   └─ NO  → Pure LLM answer
│
└─ Files attached (or project files)?
    │
    ├─ Total file tokens ≤ 60% of LLM context?
    │   └─ YES → DIRECT INJECTION (not RAG)
    │            internal_search usually OFF this turn
    │
    └─ Total file tokens > 60% of LLM context?
        └─ YES → TOO BIG to paste
                 → internal_search ON, scoped to those files
                 → RAG (needs successful indexing!)
```

**The 60% rule:** Onyx never uses 100% of context for files. Room is left for system prompt, history, and search results.

---

## Part 9 — Side-by-side comparison table

| | Direct injection | RAG (`internal_search`) |
|---|------------------|-------------------------|
| **Plain English** | “Read this whole document” | “Find the relevant pages, then answer” |
| **When** | Small / medium files | Large files, connectors, knowledge base |
| **Data source** | MinIO | OpenSearch |
| **Indexing required?** | No | Yes |
| **OpenSearch required?** | No | Yes |
| **Embedding at question time?** | No | Yes |
| **LLM sees** | Entire document | Top relevant chunks only |
| **Speed** | Usually faster | Usually slower (more steps) |
| **Citations** | Optional | Yes `[[1]]` |
| **Works if index FAILED?** | Often yes (if file in MinIO) | No |

---

## Part 10 — Real examples

### Example 1 — Small PDF (800 tokens), indexing failed

| Step | What happens |
|------|----------------|
| Upload | Saved to MinIO, indexing fails → `status = FAILED` |
| You ask in chat | Direct injection reads MinIO |
| Path used | **Direct injection** — **not** RAG |
| Why it works | MinIO has the file; size fits in prompt |

### Example 2 — Large legal PDF (50,000 tokens) in Project

| Step | What happens |
|------|----------------|
| Upload | Must index into OpenSearch |
| You ask | Too big for prompt → `internal_search` |
| Path used | **RAG** |
| Needs | OpenSearch up + embeddings working + `status = COMPLETED` |

### Example 3 — “Search our Confluence” (no attachment)

| Step | What happens |
|------|----------------|
| Connector synced docs into index earlier | — |
| You ask | LLM calls `internal_search` |
| Path used | **RAG** over connector documents |

---

## Part 11 — Common mistakes (explained simply)

| Wrong belief | Truth |
|--------------|-------|
| “Every uploaded file uses RAG” | Only **large** files or corpus search. Small files use **direct injection**. |
| “internal_search and RAG are different systems” | `internal_search` **is** Onyx’s name for internal RAG. |
| “FAILED on file means chat never works” | FAILED = indexing failed. **Small files** can still work via MinIO. |
| “Project and Chat use different databases” | Same Postgres + OpenSearch. Different **rules** for which files are visible. |
| “One question = one AI call” | With `internal_search`, often **many** AI calls. |
| “Health check OK means search works” | Health = process alive. Embedding model can still be broken. |

---

## Part 12 — What breaks `internal_search` in production

```
┌─────────────────────┬──────────────────────────────────────────┐
│ Broken component    │ Symptom                                  │
├─────────────────────┼──────────────────────────────────────────┤
│ OpenSearch down     │ No chunks retrieved; search errors       │
│ Indexing failed     │ No chunks exist for that file              │
│ Embedding model     │ Cannot embed question or index chunks    │
│ offline (HF cache)  │ (your qwen embedding error)              │
│ Delete stuck        │ Old chunks still searchable OR weird     │
│ DELETING            │ behavior after delete                    │
│ Model bad at tools  │ Raw XML like <tool_call> shown to user   │
│ (some Qwen setups)  │                                          │
│ Timeouts too low    │ Answer stops mid-stream                  │
└─────────────────────┴──────────────────────────────────────────┘
```

---

## Part 13 — ASCII timeline: one message end-to-end

```
TIME ──────────────────────────────────────────────────────────────►

You: "Summarize the contract"
         │
         ▼
    [API Server]
         │
         ├─ Postgres: load chat + file metadata
         ├─ MinIO: (skip full read — file too big)
         └─ Enable internal_search for project files
         │
         ▼
    [LLM Round 1]  "I will call internal_search"
         │
         ▼
    [SearchTool / RAG]
         ├─ inference-model-server: embed question
         ├─ OpenSearch: hybrid search
         ├─ LLM: pick best chunks
         └─ expand context around chunks
         │
         ▼
    [LLM Round 2]  write answer + citations
         │
         ▼
    [Browser]  streamed text + source links
```

---

## Part 14 — Summary cheat sheet

```
┌─────────────────────────────────────────────────────────────┐
│  TERM              │  REMEMBER AS                           │
├────────────────────┼────────────────────────────────────────┤
│  RAG               │  Search library → then answer          │
│  internal_search   │  Onyx tool that does RAG internally    │
│  Direct injection  │  Paste whole file in prompt (not RAG)  │
│  Indexing          │  Prepare files for search (background) │
│  Chunk             │  Small piece of document in index      │
│  Embedding         │  Numbers = meaning of text             │
│  OpenSearch        │  Where chunks live for search          │
│  MinIO             │  Where original files live             │
│  Agent loop        │  Multiple AI steps per one question    │
└─────────────────────────────────────────────────────────────┘
```

---

## Related docs in this repo

- [querying-in-onyx.md](../../troubleshooting/querying-in-onyx.md) — deeper technical version
- [FILE-DELETION-PROCESS-EXPLAINED.md](../../documentation/FILE-DELETION-PROCESS-EXPLAINED.md) — what happens when you delete
- [PROJECT-VS-CHAT-ARCHITECTURE.md](../../documentation/PROJECT-VS-CHAT-ARCHITECTURE.md) — Project vs Chat file behavior
- [DELETING-FILES-STUCK-INVESTIGATION-AND-REMEDIATION.md](../troubleshooting/DELETING-FILES-STUCK-INVESTIGATION-AND-REMEDIATION.md) — stuck `DELETING` status

---

*Last updated: June 2026 — Onyx v4.x / OpenSearch deployments*
