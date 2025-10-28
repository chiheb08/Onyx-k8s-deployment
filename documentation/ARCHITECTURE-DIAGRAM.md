# Onyx Docker Compose Architecture Diagram

Complete architecture breakdown showing all components, their roles, and how they communicate.

---

## 🏗️ High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              🌐 EXTERNAL ACCESS                              │
│                         http://localhost:3000 (or :80)                       │
└───────────────────────────────────────┬─────────────────────────────────────┘
                                        │
                                        ▼
                        ┌───────────────────────────────┐
                        │         📡 NGINX              │
                        │    (Reverse Proxy)            │
                        │  Port: 80, 3000 (external)    │
                        │  Image: nginx:1.23.4-alpine   │
                        └──────────┬─────────┬──────────┘
                                   │         │
                   ┌───────────────┘         └───────────────┐
                   │                                         │
                   ▼                                         ▼
    ┌──────────────────────────┐              ┌──────────────────────────┐
    │   🖥️  WEB SERVER         │              │   ⚙️  API SERVER         │◄──┐
    │   (Frontend - Next.js)   │◄─────────────┤   (Backend - FastAPI)    │   │
    │   Port: 3000 (internal)  │   Proxies    │   Port: 8080 (internal)  │   │
    │   Image: onyx-web-server │   API calls  │   Image: onyx-backend    │   │
    └──────────────────────────┘              └────────┬─────────────────┘   │
                                                       │                      │
            ┌──────────────────────────────────────────┼────────────┐         │
            │                  │                       │            │         │
            ▼                  ▼                       ▼            ▼         │
  ┌─────────────────┐  ┌──────────────┐    ┌─────────────────┐  ┌──────────────┐
  │  💾 PostgreSQL  │  │  🔍 Vespa    │    │  ⚡ Redis       │  │  📦 MinIO    │
  │  (Database)     │  │  (Search)    │    │  (Cache)        │  │  (Storage)   │
  │  Port: 5432     │  │  Port: 19071 │    │  Port: 6379     │  │  Port: 9000  │
  │  relational_db  │  │  index       │    │  cache          │  │  minio       │
  └─────────────────┘  └──────────────┘    └─────────────────┘  └──────────────┘
            ▲                  ▲                       ▲            ▲         │
            │                  │                       │            │         │
            └──────────────────┼───────────────────────┼────────────┘         │
                               │                       │                      │
                      ┌────────┴───────────────────────┴─────────┐            │
                      │                                           │            │
                      ▼                                           ▼            │
        ┌──────────────────────────┐              ┌──────────────────────────┐│
        │  🔄 BACKGROUND WORKERS   │              │  🤖 MODEL SERVERS        ││
        │  (8 Specialized Workers) │              │  (AI/ML Embeddings)      ││
        │  ├─ Primary Worker       │              │                          ││
        │  ├─ Docfetching Worker   │              │  1️⃣ Inference Server    ││
        │  ├─ Docprocessing Worker │              │     Port: 9000           ││
        │  ├─ Light Worker         │              │                          ││
        │  ├─ Heavy Worker         │              │  2️⃣ Indexing Server     ││
        │  ├─ KG Processing Worker │              │     Port: 9000           ││
        │  ├─ Monitoring Worker    │              │  Image: onyx-model-server││
        │  └─ Beat Worker          │              │  ↕️ HuggingFace Downloads │
        │  Image: onyx-backend     │              └──────────────────────────┘│
        └──────────────────────────┘
                                                                               │
                                                                               │
                                      ┌────────────────────────────────────────┘
                                      │ LLM API calls
                                      │ (Chat completion)
                                      ▼
                        ┌──────────────────────────────┐
                        │  🧠 vLLM SERVER              │
                        │  (LLM Provider)              │
                        │  Port: 8001 (external)       │
                        │  OpenAI-compatible API       │
                        │  Image: vllm/vllm-openai     │
                        │                              │
                        │  Purpose: Generate answers   │
                        │  Model: llama3/mistral/etc   │
                        │  ↕️ HuggingFace Downloads     │
                        └──────────────────────────────┘
                                      ▲
                                      │ (Optional: Can run
                                      │  in Docker or host)
```

---

## 🔄 Data Flow Diagram

```
USER REQUEST FLOW:
═════════════════

1. User opens browser → http://localhost:3000
                               ↓
2. NGINX receives request → Routes to web_server or api_server
                               ↓
3a. Static assets (HTML/CSS/JS) → web_server (Next.js)
                               ↓
3b. API calls (/api/*) → api_server (FastAPI)
                               ↓
4. API Server processes request:
   ├─→ Checks Redis cache (fast lookup)
   ├─→ Queries PostgreSQL (user data, documents metadata)
   ├─→ Searches Vespa (vector search for documents)
   ├─→ Calls Model Server (generate embeddings)
   └─→ Accesses MinIO (retrieve files)
                               ↓
5. Response sent back through NGINX → User's browser


BACKGROUND INDEXING FLOW:
═════════════════════════

1. User uploads document → API Server
                               ↓
2. API Server stores file → MinIO
                               ↓
3. API Server creates task → Redis queue
                               ↓
4. Background Workers pick up task (8 specialized workers):
   ├─→ Docfetching Worker: Fetches document from MinIO
   ├─→ Docprocessing Worker: Chunks document
   ├─→ Docprocessing Worker: Calls Indexing Model Server (generate embeddings)
   ├─→ Docprocessing Worker: Stores chunks + embeddings in Vespa
   └─→ Primary Worker: Updates metadata in PostgreSQL
                               ↓
5. Document ready for search!


SEARCH QUERY FLOW (with vLLM):
═══════════════════════════════

1. User types search query → Web Server → API Server
                               ↓
2. API Server:
   ├─→ Calls Inference Model Server (embed query)
   ├─→ Searches Vespa (vector similarity search)
   └─→ Retrieves document chunks
                               ↓
3. API Server sends to vLLM (http://host.docker.internal:8001):
   ├─→ Endpoint: POST /v1/chat/completions
   ├─→ Payload: system prompt + context chunks + user query
   └─→ vLLM generates answer using local LLM model
                               ↓
4. vLLM returns response → API Server
                               ↓
5. API Server caches in Redis → Response → User
```

---

## 📦 Component Details

### 1. 📡 NGINX (Reverse Proxy)

**Role:** Entry point for all external traffic

**Image:** `nginx:1.23.4-alpine` (62MB)

**Ports:**
- `80:80` - HTTP access
- `3000:80` - Alternative port (for localhost:3000)

**Routes:**
- `/` → `web_server:3000` (Next.js frontend)
- `/api/*` → `api_server:8080` (FastAPI backend)
- `/admin/*` → `web_server:3000` (Admin UI)

**Dependencies:**
- Requires: `web_server`, `api_server`

**Configuration:**
- Located: `../data/nginx/app.conf.template`
- Custom SSL: Use `app.conf.template.prod`

**Why needed:**
- Single entry point for all services
- Load balancing (if scaled)
- SSL termination (in production)
- Security (hides internal services)

---

### 2. 🖥️ WEB SERVER (Frontend)

**Role:** Serves the user interface (Next.js React app)

**Image:** `onyxdotapp/onyx-web-server:latest` (423MB)

**Port:** `3000` (internal only, accessed via NGINX)

**Technology Stack:**
- Next.js 15+
- React 18
- TypeScript
- Tailwind CSS

**Dependencies:**
- Requires: `api_server`
- Environment: `INTERNAL_URL=http://api_server:8080`

**Functionality:**
- Chat interface
- Document search UI
- Admin panels
- User authentication UI
- Settings and configuration pages

**Why needed:**
- User-facing interface
- Client-side rendering
- SSR (Server-Side Rendering) for SEO
- Responsive design

---

### 3. ⚙️ API SERVER (Backend)

**Role:** Core application logic and API endpoints

**Image:** `onyxdotapp/onyx-backend:latest` (5.89GB)

**Port:** `8080` (internal only)

**Technology Stack:**
- Python 3.11
- FastAPI
- SQLAlchemy
- Alembic (migrations)
- LangChain

**Dependencies:**
- Requires: `relational_db`, `index`, `cache`, `inference_model_server`, `minio`

**Startup Command:**
```bash
alembic upgrade head  # Run DB migrations
uvicorn onyx.main:app --host 0.0.0.0 --port 8080
```

**Key Functions:**
1. **Authentication & Authorization**
   - User login/logout
   - OAuth, SAML, Basic Auth
   - Session management

2. **Chat & Search**
   - Process user queries
   - LLM orchestration
   - Context retrieval

3. **Document Management**
   - Upload/delete documents
   - Connector management
   - Access control

4. **API Endpoints:**
   - `/api/chat` - Chat interactions
   - `/api/query` - Search queries
   - `/api/manage` - Admin functions
   - `/api/persona` - AI personas
   - `/api/connector` - Data sources

**Environment Variables:**
- `POSTGRES_HOST=relational_db`
- `VESPA_HOST=index`
- `REDIS_HOST=cache`
- `MODEL_SERVER_HOST=inference_model_server`
- `S3_ENDPOINT_URL=http://minio:9000`

**Why needed:**
- Business logic
- API gateway
- Database orchestration
- External integrations

---

### 4. 🔄 BACKGROUND WORKERS (Celery)

**Role:** Asynchronous task processing

**Image:** `onyxdotapp/onyx-backend:latest` (same as API server)

**Technology Stack:**
- Celery (task queue)
- Supervisord (process manager)
- Redis (task broker)

**Dependencies:**
- Requires: `relational_db`, `index`, `cache`, `inference_model_server`, `indexing_model_server`

**8 Specialized Worker Types (via Supervisord):**

1. **Primary Worker** (4 threads)
   - Connector deletion, Vespa sync, pruning, LLM model updates

2. **Docfetching Worker** (configurable concurrency)
   - Fetch documents from connectors, watchdog monitoring
   - Spawns docprocessing tasks for each document batch

3. **Docprocessing Worker** (configurable concurrency) - **MOST CRITICAL**
   - Document upserts, chunking, embedding generation, Vespa indexing
   - Core document indexing pipeline

4. **Light Worker** (higher concurrency)
   - Vespa operations, document permissions sync, external group sync
   - Quick operations

5. **Heavy Worker** (4 threads, limited)
   - Document pruning operations
   - Resource-intensive tasks

6. **KG Processing Worker** (configurable concurrency)
   - Knowledge graph processing, document clustering
   - Builds relationships between documents

7. **Monitoring Worker** (single thread)
   - System health checks, Celery queue monitoring, process memory checks
   - System status monitoring

8. **Beat Worker** (scheduler)
   - Task scheduling with DynamicTenantScheduler (multi-tenant)
   - Periodic checks: indexing (15s), connector deletion (20s), Vespa sync (20s), 
     pruning (20s), KG processing (60s), monitoring (5min), cleanup (hourly)

**Task Examples:**
- Index new documents from connectors
- Prune deleted documents
- Sync permissions
- Monitor system health
- Update embeddings

**Why needed:**
- Long-running tasks (don't block API)
- Scheduled tasks (periodic sync)
- Parallel processing (multiple workers)
- Reliable task execution (retry logic)

---

### 5. 🤖 MODEL SERVERS (AI/ML)

**Role:** Generate embeddings for semantic search

**Image:** `onyxdotapp/onyx-model-server:latest` (~3GB each)

**Port:** `9000` (both servers use same port, different containers)

**Technology Stack:**
- PyTorch
- HuggingFace Transformers
- FastAPI
- Sentence Transformers

**Two Instances:**

#### 5a. Inference Model Server
- **Purpose:** Real-time query embedding
- **Used by:** API Server
- **Usage:** User queries, search embedding
- **Volume:** `model_cache_huggingface`

#### 5b. Indexing Model Server
- **Purpose:** Document indexing
- **Used by:** Background Workers
- **Usage:** Bulk document embedding
- **Volume:** `indexing_huggingface_model_cache`
- **Environment:** `INDEXING_ONLY=True`

**Default Models:**
- Embedding: `sentence-transformers/all-MiniLM-L6-v2`
- Reranking: `cross-encoder/ms-marco-MiniLM-L-6-v2`

**Why Two Servers:**
- **Separation of concerns:** Query vs indexing workloads
- **Resource isolation:** Heavy indexing doesn't slow queries
- **Model caching:** Different model versions/configs

**Why needed:**
- Convert text to vectors (embeddings)
- Semantic search capability
- Context understanding
- Local AI processing (privacy)

---

### 6. 💾 POSTGRESQL (Database)

**Role:** Primary data store

**Image:** `postgres:15.2-alpine` (343MB)

**Port:** `5432` (internal only)

**Configuration:**
- Max connections: 250
- Shared memory: 1GB
- User: `postgres`
- Password: `password` (default, change in production)

**Stored Data:**
1. **User Information**
   - Users, roles, permissions
   - Authentication tokens
   - User preferences

2. **Document Metadata**
   - Document IDs, names, sources
   - Timestamps, owners
   - Access permissions

3. **Connector Configurations**
   - Connector settings
   - Credentials (encrypted)
   - Sync schedules

4. **Chat History**
   - Chat sessions
   - Messages
   - Feedback

5. **System Configuration**
   - LLM settings
   - Persona configurations
   - Feature flags

**Volumes:**
- `db_volume:/var/lib/postgresql/data` (persistent)

**Why needed:**
- Structured data storage
- ACID transactions
- Relational queries
- Data integrity

---

### 7. 🔍 VESPA (Vector Search)

**Role:** Vector database for semantic search

**Image:** `vespaengine/vespa:8.526.15` (1.92GB)

**Ports:**
- `19071` - Config server
- `8081` - Query API

**Technology:**
- Java-based
- Distributed search engine
- Vector similarity search
- Hybrid search (keyword + vector)

**Stored Data:**
1. **Document Chunks**
   - Text chunks (paragraphs)
   - Chunk metadata

2. **Embeddings**
   - Vector representations (768-dim)
   - Generated by Model Server

3. **Attributes**
   - Document IDs
   - Source references
   - Timestamps

**Search Capabilities:**
- Vector similarity (semantic search)
- Keyword search (BM25)
- Hybrid ranking
- Filtering by metadata

**Volumes:**
- `vespa_volume:/opt/vespa/var` (persistent)

**Why needed:**
- Fast vector search (milliseconds)
- Scalable (millions of documents)
- Hybrid search (keyword + semantic)
- Relevance ranking

---

### 8. ⚡ REDIS (Cache)

**Role:** In-memory cache and task queue

**Image:** `redis:7.4-alpine` (61.4MB)

**Port:** `6379` (internal only)

**Configuration:**
- Mode: Ephemeral (no persistence)
- Command: `redis-server --save "" --appendonly no`

**Usage:**

1. **Caching:**
   - API responses, User sessions, Frequent queries, LLM responses

2. **Celery Task Queue & Coordination:**
   - Task messages and distribution to 8 specialized workers
   - Task results and status tracking
   - Worker coordination and communication
   - Task scheduling and priority management

3. **Rate Limiting:**
   - API rate limits, User quotas

4. **Pub/Sub & Real-time:**
   - Real-time updates, Worker communication
   - Task notifications and coordination messages

**Why needed:**
- Fast lookups (microseconds)
- Reduce database load
- Session management
- Celery message broker

---

### 9. 📦 MINIO (Object Storage)

**Role:** S3-compatible file storage

**Image:** `minio/minio:RELEASE.2025-07-23T15-54-02Z-cpuv1` (~200MB)

**Ports:**
- `9000` - API endpoint
- `9001` - Web console

**Configuration:**
- Root user: `minioadmin`
- Root password: `minioadmin`
- Default bucket: `onyx-file-store-bucket`

**Stored Data:**
1. **User Uploaded Files**
   - PDFs, Word docs, presentations
   - Images, videos

2. **Processed Documents**
   - Extracted text
   - Intermediate files

3. **System Files**
   - Logos, avatars
   - Exported data

**Volumes:**
- `minio_data:/data` (persistent)

**API Compatibility:**
- S3-compatible API
- Works with AWS SDK
- Alternative to AWS S3

**Why needed:**
- File storage (not in DB)
- S3-compatible (easy migration)
- Self-hosted (data privacy)
- Scalable storage

---

### 10. 🧠 vLLM SERVER (LLM Provider - Optional)

**Role:** Local LLM inference for generating AI responses

**Image:** `vllm/vllm-openai:latest` (~8-15GB depending on model)

**Port:** `8001` (external, or internal if added to Docker network)

**Technology Stack:**
- vLLM inference engine
- OpenAI-compatible API
- PyTorch backend
- Optimized for GPU (also works on CPU)

**Configuration:**
```bash
docker run -d \
  --name vllm-server \
  -p 8001:8000 \
  vllm/vllm-openai:latest \
  --model meta-llama/Meta-Llama-3-8B-Instruct \
  --host 0.0.0.0 \
  --port 8000
```

**API Endpoint:**
- `http://host.docker.internal:8001/v1/chat/completions` (from Onyx containers)
- `http://localhost:8001/v1/chat/completions` (from host)

**Compatible Models:**
- **Small (2-3GB RAM):** TinyLlama, Phi-2, facebook/opt-125m
- **Medium (8GB RAM):** Llama-2-7B, Mistral-7B
- **Large (16GB+ RAM):** Llama-2-13B, Mixtral-8x7B

**Configuration in Onyx:**

In Onyx UI (Settings → LLM Configuration):
```
Provider Type: OpenAI
Display Name: vLLM Local
API Base URL: http://host.docker.internal:8001/v1
API Key: sk-dummy (any value, vLLM doesn't validate)
Model Name: meta-llama/Meta-Llama-3-8B-Instruct
```

**Communication Flow:**

```
User asks question
      ↓
API Server retrieves context from Vespa
      ↓
API Server calls vLLM:
  POST http://host.docker.internal:8001/v1/chat/completions
  {
    "model": "meta-llama/Meta-Llama-3-8B-Instruct",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant..."},
      {"role": "user", "content": "Context: <chunks>\nQuestion: ..."}
    ]
  }
      ↓
vLLM generates response
      ↓
API Server receives answer → User
```

**Deployment Options:**

1. **Separate Docker Container (Recommended):**
   - Run vLLM in its own container
   - Access via `host.docker.internal:8001`
   - Easy to restart/update independently

2. **Add to docker-compose.yml:**
   ```yaml
   vllm:
     image: vllm/vllm-openai:latest
     ports:
       - "8001:8000"
     command: >
       --model meta-llama/Meta-Llama-3-8B-Instruct
       --host 0.0.0.0
       --port 8000
     volumes:
       - vllm_cache:/root/.cache/huggingface
   ```
   - Access via `http://vllm:8000` from Onyx services

3. **External Host:**
   - Run vLLM on separate machine with GPU
   - Access via IP: `http://192.168.1.100:8001`

**Why vLLM:**
- **Privacy:** All data stays local (no OpenAI/external calls)
- **Cost:** No per-token charges
- **Customization:** Use any open-source model
- **Control:** Full control over model behavior
- **Speed:** Optimized inference (especially with GPU)

**Why Optional:**
- Onyx can use other LLM providers (OpenAI, Anthropic, Azure, etc.)
- vLLM requires significant resources (RAM/GPU)
- Can start without LLM and add later

**Resource Requirements:**

| Model Size | RAM | GPU VRAM | CPU | Storage |
|------------|-----|----------|-----|---------|
| Small (1-3B) | 4GB | 4GB | Slow | 2-5GB |
| Medium (7B) | 8GB | 8GB | Very slow | 5-15GB |
| Large (13B+) | 16GB+ | 16GB+ | Unusable | 15-30GB |

**On macOS (no NVIDIA GPU):**
- vLLM runs on CPU only (slow)
- Consider Ollama instead (Metal GPU support)
- Or use cloud LLM (OpenAI, Anthropic)

**Why needed:**
- Generate natural language responses
- Answer user questions
- Summarize documents
- Extract information from context
- Core AI capability of Onyx

---

## 🔗 Inter-Service Communication

### Communication Matrix

| From Service | To Service | Protocol | Purpose | Example |
|--------------|------------|----------|---------|---------|
| **nginx** | web_server | HTTP | Serve UI | GET / |
| **nginx** | api_server | HTTP | Proxy API | POST /api/chat |
| **web_server** | api_server | HTTP | Fetch data | GET /api/user |
| **api_server** | relational_db | TCP/PostgreSQL | Query data | SELECT users |
| **api_server** | index (Vespa) | HTTP/gRPC | Search docs | Vector search |
| **api_server** | cache (Redis) | TCP/Redis | Cache ops, Task submission | GET cache_key, LPUSH tasks |
| **api_server** | inference_model_server | HTTP | Embed query | POST /embed |
| **api_server** | minio | HTTP/S3 | Store files | PUT /bucket/file |
| **api_server** | vllm (optional) | HTTP | Generate answer | POST /v1/chat/completions |
| **cache (Redis)** | background workers | TCP/Redis | Task distribution | Task routing to 8 workers |
| **background workers** | relational_db | TCP/PostgreSQL | Update status | UPDATE connectors |
| **background workers** | index (Vespa) | HTTP/gRPC | Index docs | PUT /document |
| **background workers** | cache (Redis) | TCP/Redis | Task results | Task status updates |
| **background workers** | indexing_model_server | HTTP | Embed docs | POST /embed |
| **background workers** | minio | HTTP/S3 | Fetch files | GET /bucket/file |
| **model servers** | HuggingFace | HTTPS | Download models | Model downloads |
| **vllm** | HuggingFace | HTTPS | Download models | Model downloads |

---

## 🌐 Network Architecture

All Onyx services run on the same Docker network (`onyx_default`):

```
Docker Network: onyx_default (bridge mode)
├─ nginx              → 172.18.0.2
├─ web_server         → 172.18.0.3
├─ api_server         → 172.18.0.4
├─ background         → 172.18.0.5
├─ inference_model_server → 172.18.0.6
├─ indexing_model_server  → 172.18.0.7
├─ relational_db      → 172.18.0.8
├─ cache              → 172.18.0.9
├─ index              → 172.18.0.10
└─ minio              → 172.18.0.11

External (not in onyx_default network):
└─ vllm-server        → Separate container or host machine
                         Accessed via: host.docker.internal:8001
```

**Internal DNS:**
- Services reference each other by container name
- Example: `http://api_server:8080`
- Docker provides automatic DNS resolution

**External Access:**
- Only NGINX is exposed (ports 80, 3000)
- All other Onyx services are internal
- vLLM is external (if used) - accessed via `host.docker.internal:8001`

**vLLM Network Options:**

1. **Separate Container (Default):**
   - vLLM runs independently
   - Onyx accesses via: `http://host.docker.internal:8001`
   - Easier to manage and restart

2. **Add to onyx_default network:**
   ```yaml
   # In docker-compose.yml
   vllm:
     networks:
       - default  # joins onyx_default
   ```
   - Onyx accesses via: `http://vllm:8000`
   - Fully integrated

3. **External Host:**
   - vLLM runs on GPU server
   - Onyx accesses via: `http://192.168.1.100:8001`
   - Best for GPU acceleration

---

## 💾 Data Persistence

### Persistent Volumes (Survive Restarts)

| Volume | Used By | Purpose | Size |
|--------|---------|---------|------|
| `db_volume` | relational_db | PostgreSQL data | ~500MB-10GB |
| `vespa_volume` | index | Vespa indexes | ~1GB-100GB |
| `minio_data` | minio | File storage | ~1GB-1TB |
| `model_cache_huggingface` | inference_model_server | Model weights | ~2GB |
| `indexing_huggingface_model_cache` | indexing_model_server | Model weights | ~2GB |

### Log Volumes (Debugging)

| Volume | Purpose |
|--------|---------|
| `api_server_logs` | API server logs |
| `background_logs` | Worker logs |
| `inference_model_server_logs` | Inference logs |
| `indexing_model_server_logs` | Indexing logs |

### Ephemeral Data (Lost on Restart)

- **Redis cache** - Intentionally ephemeral
- **Container filesystems** - Temporary

---

## 🚀 Startup Sequence

**Dependency Order:**

```
1. Infrastructure Layer (No Dependencies)
   ├─ relational_db      (PostgreSQL)
   ├─ cache              (Redis)
   ├─ index              (Vespa)
   └─ minio              (MinIO)
         ↓
2. AI/ML Layer
   ├─ inference_model_server
   └─ indexing_model_server
         ↓
3. Application Layer
   ├─ api_server         (depends on: relational_db, index, cache, 
   │                                  inference_model_server, minio)
   └─ background         (depends on: relational_db, index, cache,
                                      inference_model_server,
                                      indexing_model_server)
         ↓
4. Frontend Layer
   └─ web_server         (depends on: api_server)
         ↓
5. Gateway Layer
   └─ nginx              (depends on: api_server, web_server)
```

**Typical Startup Times:**

1. Infrastructure: ~10-30 seconds
2. Model Servers: ~2-5 minutes (model download)
3. API Server: ~30 seconds (migrations + startup)
4. Background: ~30 seconds
5. Web Server: ~20 seconds
6. NGINX: ~5 seconds
7. vLLM (optional): ~2-10 minutes (model download + loading)

**Total:** ~10-15 minutes (without vLLM)
**Total with vLLM:** ~12-25 minutes (first time with model download)

**Note:** If using vLLM, start it **before** starting Onyx to ensure it's ready when needed:
```bash
# Start vLLM first
docker run -d --name vllm-server -p 8001:8000 \
  vllm/vllm-openai:latest \
  --model meta-llama/Meta-Llama-3-8B-Instruct

# Wait for vLLM to be ready
docker logs -f vllm-server
# (Wait for: "Uvicorn running on http://0.0.0.0:8000")

# Then start Onyx
cd /path/to/onyx/deployment/docker_compose
docker compose up -d
```

---

## 🔄 Request Flow Examples

### Example 1: User Search Query (with vLLM)

```
1. User types: "What is our vacation policy?"
   ↓
2. Browser → http://localhost:3000/search?q=vacation+policy
   ↓
3. NGINX → web_server (serve search page)
   ↓
4. Browser runs JavaScript → AJAX call to /api/query
   ↓
5. NGINX → api_server:8080/api/query
   ↓
6. API Server:
   a. Check Redis cache for this query → MISS
   b. Call inference_model_server:9000/embed
      - Input: "What is our vacation policy?"
      - Output: [0.123, 0.456, ..., 0.789] (768-dim vector)
   c. Query Vespa (index:19071/search)
      - Vector similarity search
      - Returns top 10 chunks from indexed documents
   d. Retrieve chunk metadata from PostgreSQL
   e. Build context from chunks (combine relevant text)
   f. Call vLLM (http://host.docker.internal:8001/v1/chat/completions)
      Request:
      {
        "model": "meta-llama/Meta-Llama-3-8B-Instruct",
        "messages": [
          {
            "role": "system",
            "content": "You are a helpful assistant. Use the context to answer."
          },
          {
            "role": "user",
            "content": "Context:\n---\n<chunk 1: Employees get 15 days...>\n<chunk 2: Vacation must be approved...>\n---\nQuestion: What is our vacation policy?"
          }
        ],
        "max_tokens": 500
      }
      Response from vLLM:
      {
        "choices": [{
          "message": {
            "content": "Based on your company policy, employees receive 15 days of vacation..."
          }
        }]
      }
   g. Store result in Redis cache (5 min TTL)
   ↓
7. API Server → NGINX → Browser
   ↓
8. User sees answer with citations!

Timeline:
- Embedding: ~100ms
- Vespa search: ~50ms
- vLLM generation: ~2-10 seconds (depends on model/hardware)
- Total: ~3-10 seconds
```

### Example 2: Document Upload & Indexing

```
1. User uploads document "HR_Policy_2025.pdf" via web UI
   ↓
2. Browser → http://localhost:3000/api/upload (POST)
   ↓
3. NGINX → api_server:8080/api/upload
   ↓
4. API Server:
   a. Validate file
   b. Upload to MinIO (minio:9000/onyx-file-store-bucket/)
   c. Create database record in PostgreSQL
   d. Create Celery task in Redis queue
   e. Return 200 OK to user
   ↓
5. Background Worker (monitoring Redis):
   a. Picks up indexing task from Redis
   b. Downloads file from MinIO
   c. Extract text from PDF
   d. Chunk text into paragraphs (~512 tokens each)
   e. For each chunk:
      - Call indexing_model_server:9000/embed
      - Get embedding vector
   f. Batch upload to Vespa (index:19071/document/v1/)
   g. Update PostgreSQL (status: "indexed")
   h. Mark task as complete in Redis
   ↓
6. Document ready for search!
```

### Example 3: Scheduled Connector Sync

```
1. Beat Worker (scheduler):
   - Every 1 hour: check for connector sync tasks
   ↓
2. Beat Worker creates task in Redis:
   - Task: "Sync Google Drive Connector #5"
   ↓
3. Docfetching Worker picks up task:
   a. Fetch connector config from PostgreSQL
   b. Authenticate to Google Drive API
   c. List new/updated files since last sync
   d. For each file:
      - Create download task
   ↓
4. Docprocessing Worker:
   a. Download file from Google Drive
   b. Upload to MinIO (storage)
   c. Process and chunk file
   d. Call indexing_model_server for embeddings
   e. Index to Vespa
   f. Update PostgreSQL metadata
   ↓
5. Monitoring Worker:
   - Track progress
   - Alert if stuck
   ↓
6. Sync complete!
```

---

## 🎯 Component Criticality

### Critical (System Won't Work Without These)

1. **PostgreSQL** - Core data storage
2. **API Server** - Application logic
3. **Web Server** - User interface
4. **NGINX** - External access

### Important (Most Features Need These)

5. **Vespa** - Search functionality
6. **Inference Model Server** - Real-time search
7. **Redis** - Caching & task queue

### Optional (Specific Features)

8. **Background Workers** - Document indexing, scheduled tasks
9. **Indexing Model Server** - Document processing
10. **MinIO** - File storage (can use S3 instead)
11. **vLLM** - Local LLM for chat (can use OpenAI/Anthropic/etc. instead)

---

## 📊 Resource Usage (Typical)

| Service | CPU (idle) | CPU (active) | RAM | Disk |
|---------|-----------|--------------|-----|------|
| nginx | <1% | 5% | ~10MB | ~50MB |
| web_server | 1% | 10% | ~200MB | ~500MB |
| api_server | 5% | 30% | ~800MB | ~2GB |
| background | 10% | 50% | ~1GB | ~2GB |
| inference_model_server | 5% | 60% | ~2GB | ~3GB |
| indexing_model_server | 1% | 80% | ~2GB | ~3GB |
| relational_db | 2% | 20% | ~300MB | ~5GB |
| index (Vespa) | 10% | 40% | ~2GB | ~20GB |
| cache (Redis) | 1% | 5% | ~50MB | ~100MB |
| minio | 1% | 10% | ~100MB | ~10GB |
| **ONYX TOTAL** | **~35%** | **~300%** | **~8.5GB** | **~45GB** |
| | | | | |
| vllm (optional, 7B model) | 10% | 90% | ~8GB | ~15GB |
| **WITH vLLM** | **~45%** | **~390%** | **~16.5GB** | **~60GB** |

**Notes:**
- CPU percentages are per core (390% = ~4 full cores)
- Active = During heavy search/indexing/chat
- Disk includes images + data + model weights
- vLLM resource usage depends on model size (7B shown as example)
- vLLM on GPU: Less CPU, requires GPU VRAM
- vLLM on CPU (macOS): Very slow, high CPU usage

---

## 🔐 Security Architecture

### Network Isolation

```
Public Internet
      │
      │ (only port 80, 3000)
      ▼
   [NGINX] ← Firewall
      │
      │ (internal network only)
      ▼
[All other services] ← Not exposed
```

**Security Layers:**

1. **External:** Only NGINX exposed
2. **Internal:** All services communicate via Docker network
3. **Authentication:** API Server validates all requests
4. **Authorization:** Role-based access control
5. **Encryption:** HTTPS (in production with SSL)

### Production Hardening

**Checklist:**
- ✅ Remove port exposures (only NGINX)
- ✅ Enable SSL/TLS (HTTPS)
- ✅ Change default passwords
- ✅ Use secrets management
- ✅ Enable authentication (OAuth/SAML)
- ✅ Configure firewall rules
- ✅ Regular security updates

---

## 🛠️ Troubleshooting Guide

### Service Health Checks

```bash
# Check all services
docker compose ps

# Check logs
docker compose logs -f api_server
docker compose logs -f background

# Check resource usage
docker stats

# Check networks
docker network inspect onyx_default
```

### Common Issues

**NGINX 502 Bad Gateway:**
- Cause: api_server or web_server not ready
- Check: `docker compose logs api_server`

**Slow searches:**
- Cause: Model server overloaded
- Check: `docker stats inference_model_server`

**Documents not indexing:**
- Cause: Background workers stuck
- Check: `docker compose logs background`

**Database connection errors:**
- Cause: PostgreSQL not ready
- Check: `docker compose logs relational_db`

---

## 📝 Summary

**Onyx Architecture = 4 Layers:**

1. **Gateway Layer:** NGINX (reverse proxy)
2. **Application Layer:** Web Server + API Server + Background Workers
3. **Data Layer:** PostgreSQL + Vespa + Redis + MinIO + Model Servers
4. **AI Layer (Optional):** vLLM for local LLM inference

**Key Principles:**
- **Microservices:** Each service has one responsibility
- **Decoupling:** Services communicate via APIs
- **Scalability:** Can scale individual services
- **Resilience:** If one service fails, others continue
- **Privacy:** All data stored locally (no cloud required)
- **Flexibility:** Use vLLM (local) or cloud LLMs (OpenAI, etc.)

**Communication:**
- Frontend ↔ Backend: HTTP/REST
- Backend ↔ Database: PostgreSQL protocol
- Backend ↔ Search: HTTP/gRPC
- Backend ↔ vLLM: HTTP (OpenAI-compatible API)
- Workers ↔ Queue: Redis protocol
- All services ↔ Storage: S3 API

**Data Flow:**
- User queries → NGINX → Web Server → API Server → Databases → Response
- Document uploads → API Server → MinIO → Background Workers → Vespa
- Chat queries → API Server → Vespa (context) → vLLM (answer) → User

**With vLLM Integration:**
```
User Question
      ↓
Onyx retrieves relevant documents (Vespa)
      ↓
vLLM generates answer using context
      ↓
User gets AI-powered response
```

**Benefits of vLLM:**
- ✅ Complete data privacy (no external API calls)
- ✅ No usage costs (pay for hardware only)
- ✅ Customizable models (Llama, Mistral, etc.)
- ✅ Fast inference (especially with GPU)
- ✅ Offline capable (no internet needed)

---

**This architecture provides a production-ready, scalable, and secure AI-powered search platform with optional local LLM capabilities!**

