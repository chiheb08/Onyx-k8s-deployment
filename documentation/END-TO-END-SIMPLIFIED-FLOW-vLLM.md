# Onyx – Simplified End-to-End Flow (Login → Chat → Response) with vLLM

This document shows only the most important components and what happens to a user request from login to response rendering. It’s designed to be read by both non-technical and technical stakeholders.

---

## 1) Login Flow (Authentication and Session)

```
User (Browser)
  │  enters email/password
  ▼
NGINX (Gateway: TLS, Routing)
  │  forwards /api/auth/login
  ▼
API Server (FastAPI)
  • Validates credentials (PostgreSQL)
  • Creates secure session (Redis)
  • Issues JWT/session token
  ▼
Browser stores session token (secured)
```

- User Credentials Component: PostgreSQL (users table), managed by the API Server.
- Session Component: Redis (stores session data/blacklist), managed by the API Server.
- Security: TLS via NGINX, JWT/session token, session expiration, optional MFA.

---

## 2) App Shell (Web UI)

```
Browser (Next.js Web App)
  • Reads session
  • Shows chat UI and project context
  • All requests include the session (Authorization header)
```

- UI Component: Web App (Next.js) – renders chat screen, file sidebar, settings.
- Authentication in UI: Bearer token attached to requests.

---

## 3) Ask a Question (Chat Request)

```
User types a message → clicks Submit
  │  POST /api/chat/query { message, context }
  ▼
NGINX → API Server (FastAPI)
  • AuthZ check (session in Redis, user/org in Postgres)
  • Builds retrieval request (tenant + project filters)
```

- Authorization Component: API Server checks permissions, user/org, project membership.
- Context: May include selected files/projects to constrain retrieval.

---

## 4) Retrieval (Search Over Indexed Content)

```
API Server
  │  Generate embedding for the question
  ▼
Inference Model Server (Embeddings endpoint)
  │  returns query embedding vector
  ▼
API Server
  │  Vector search with pgvector/Vespa (retrieval)
  ▼
Search Index (pgvector or Vespa)
  │  returns top-k passages + metadata
  ▼
API Server: builds context bundle (snippets + citations)
```

- Embedding Component: Inference Model Server (text-embedding endpoint).
- Index Component: pgvector (PostgreSQL) or Vespa (vector + metadata). Only one is active depending on deployment.

---

## 5) Answer Generation (vLLM)

```
API Server
  │  Calls vLLM (LLM inference) with: { question, retrieved context }
  ▼
vLLM Server (Model Hosting)
  • Streams/generates answer tokens
  ▼
API Server
  • Streams response back to UI (SSE/WebSocket for /api/stream)
```

- LLM Component: vLLM (replaces Ollama). Hosts the chosen model and serves generation.
- Streaming: For chat streaming, NGINX keeps Connection: upgrade only for the streaming endpoint; standard HTTP uses Connection: "".

---

## 6) UI Rendering (Final Response)

```
Browser (Next.js Web App)
  • Receives streamed tokens
  • Renders assistant response progressively
  • Displays citations and sources
  • Updates chat history locally and via API
```

- Persistence: Chat messages and session metadata stored in PostgreSQL.
- Privacy: User/org isolation enforced by the API on every operation.

---

## 7) Uploading Files (Optional Context)

```
Browser → POST /api/files/upload (multipart)
  ▼
API Server
  • Stores file in Private S3 (encrypted)
  • Records metadata in PostgreSQL
  • Enqueues indexing via Celery (Redis broker)
  ▼
Celery Workers
  • Docfetching/Docprocessing
  • Chunk → embed (Inference Model Server) → index (pgvector/Vespa)
  ▼
Search Index updated → files become retrievable
```

- Storage Component: Private S3 for file blobs (at-rest encryption).
- Indexing Component: Celery workers update the search index asynchronously.

---

## Components and Responsibilities (Only the Essentials)

- NGINX (Gateway): TLS termination, routing to Web and API, streaming support.
- Web App (Next.js): Login UI, chat UI, file sidebar, streams assistant responses.
- API Server (FastAPI): AuthN/AuthZ, chat orchestration, retrieval, persistence.
- Redis: Session storage and Celery broker.
- PostgreSQL: Users, sessions, chat history, metadata; pgvector if used.
- Search Index: pgvector (in Postgres) or Vespa for vector + metadata search.
- vLLM Server: LLM inference for answer generation (replaces Ollama).
- Inference Model Server (Embeddings): Text embeddings for questions/chunks.
- Celery Workers: Background indexing pipeline (fetch → chunk → embed → index).
- Private S3: Encrypted file storage under your control.

---

## One-Page Flow Summary (ASCII Diagram)

```
User (Browser)
  │  Login / Chat / Upload
  ▼
NGINX (TLS, Routing)
  ├──> Web App (Next.js UI)
  └──> API Server (FastAPI)
          │  AuthN/AuthZ (Redis sessions + Postgres users)
          │
          ├── Retrieval
          │     ├── Embedding → Inference Model Server
          │     └── Vector search → pgvector/Vespa
          │
          ├── Generation
          │     └── vLLM (LLM) → stream tokens back
          │
          └── Persistence → Postgres (chat), S3 (files)

Celery Workers (async):
  fetch/chunk/embed/index → update search index
```

---

## Notes

- User credentials live in PostgreSQL; the API manages hashing, validation, and roles.
- Sessions live in Redis; the API issues JWT/session tokens and enforces expiry.
- Network security via NGINX (TLS), in-cluster NetworkPolicies, and service DNS.
- Data separation: every query is filtered by user/org; results and history are isolated per tenant.
- Replace Ollama with vLLM: vLLM is the LLM inference server for text generation.
