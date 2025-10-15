# Onyx Kubernetes Architecture - For Junior DevOps & LLM Engineers

Complete architecture guide explaining how everything connects and why.

---

## 🎯 What is Onyx?

**Onyx** is an AI-powered search and chat platform that:
- Connects to your company documents (PDFs, Confluence, Google Drive, etc.)
- Uses AI to understand and search documents by meaning (not just keywords)
- Provides chat interface powered by LLMs (like ChatGPT)
- Runs entirely on your infrastructure (privacy-first)

**Think of it as:** "ChatGPT for your company documents"

---

## 🏗️ Complete Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          🌐 EXTERNAL WORLD                               │
│                                                                          │
│  ┌──────────────┐        ┌─────────────────────┐                       │
│  │   User's     │        │  vLLM Server        │                       │
│  │   Browser    │        │  (LLM Provider)     │                       │
│  └──────┬───────┘        │  Port: 8001         │                       │
│         │                │  External namespace │                       │
│         │ HTTP           └──────────┬──────────┘                       │
└─────────┼───────────────────────────┼──────────────────────────────────┘
          │                           │
          │ Port 80                   │ LLM API calls
          │                           │ (generate answers)
          ▼                           │
┌─────────────────────────────────────────────────────────────────────────┐
│                    YOUR OPENSHIFT/KUBERNETES NAMESPACE                   │
│                         (e.g., onyx-production)                          │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                    LAYER 1: GATEWAY                               │   │
│  │                                                                   │   │
│  │  ┌─────────────────────────────────────────────────────────┐     │   │
│  │  │  NGINX (Deployment + Service + ConfigMap)              │     │   │
│  │  │  • Type: LoadBalancer (or Route in OpenShift)          │     │   │
│  │  │  • Port: 80 (external)                                 │     │   │
│  │  │  • Role: Reverse proxy / Traffic router               │     │   │
│  │  │  • Routes:                                             │     │   │
│  │  │    - / → web-server:3000                              │     │   │
│  │  │    - /api/* → api-server:8080                         │     │   │
│  │  └──────────────────┬──────────────┬──────────────────────┘     │   │
│  └─────────────────────┼──────────────┼────────────────────────────┘   │
│                        │              │                                 │
│         ┌──────────────┘              └──────────────┐                  │
│         │                                            │                  │
│  ┌──────▼────────────────────────────────────────────▼──────────────┐   │
│  │                    LAYER 2: FRONTEND                             │   │
│  │                                                                   │   │
│  │  ┌────────────────────────────────────────────────────────┐      │   │
│  │  │  WEB SERVER (Deployment + Service)                     │      │   │
│  │  │  • Image: onyx-web-server:nightly-20241004            │      │   │
│  │  │  • Port: 3000 (internal ClusterIP)                    │      │   │
│  │  │  • Technology: Next.js 15 + React                     │      │   │
│  │  │  • Role: Serve UI (HTML/CSS/JS)                       │      │   │
│  │  │  • Calls: api-server:8080 for data                    │      │   │
│  │  └────────────────────────────────────────────────────────┘      │   │
│  └───────────────────────────────────────────────────────────────────┘   │
│                                    │                                     │
│                                    │ HTTP calls                          │
│                                    ▼                                     │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                    LAYER 3: BACKEND                               │   │
│  │                                                                   │   │
│  │  ┌────────────────────────────────────────────────────────┐      │   │
│  │  │  API SERVER (Deployment + Service)                     │      │   │
│  │  │  • Image: onyx-backend:nightly-20241004               │      │   │
│  │  │  • Port: 8080 (internal ClusterIP)                    │      │   │
│  │  │  • Technology: FastAPI + Python                       │      │   │
│  │  │  • Role: Business logic, orchestration                │      │   │
│  │  │  • Init Container: Runs DB migrations (Alembic)       │      │   │
│  │  └──────┬──────────────┬───────────┬───────────┬─────────┘      │   │
│  └─────────┼──────────────┼───────────┼───────────┼────────────────┘   │
│            │              │           │           │          ▲          │
│            │              │           │           │          │          │
│  ┌─────────▼──────────┐   │           │           │          │          │
│  │    LAYER 4: AI/ML  │   │           │           │          │          │
│  │                    │   │           │           │          │          │
│  │  ┌─────────────────▼───▼──────┐    │           │          │          │
│  │  │  INFERENCE MODEL SERVER    │    │           │          │          │
│  │  │  (Deployment + Service)    │    │           │          │          │
│  │  │  • Image: model-server     │    │           │          │          │
│  │  │  •   :nightly-20241004     │    │           │          │          │
│  │  │  • Port: 9000 (ClusterIP)  │    │           │          │          │
│  │  │  • Technology: PyTorch +   │    │           │          │          │
│  │  │  •   HuggingFace           │    │           │          │          │
│  │  │  • Role: Convert text to   │    │           │          │          │
│  │  │  •   vectors (embeddings)  │    │           │          │          │
│  │  │  • Model: sentence-        │    │           │          │          │
│  │  │  •   transformers/MiniLM   │    │           │          │          │
│  │  └────────────────────────────┘    │           │          │          │
│  └─────────────────────────────────────┘           │          │          │
│                                                    │          │          │
│  ┌────────────────────────────────────────────────┼──────────┼──────────┤
│  │                    LAYER 5: DATA                │          │          │
│  │                                                 │          │          │
│  │  ┌──────────────────────────────┐              │          │          │
│  │  │  POSTGRESQL                  │◄─────────────┘          │          │
│  │  │  (Deployment + Service)      │                         │          │
│  │  │  • Image: postgres:15.2-alpine                         │          │
│  │  │  • Port: 5432 (ClusterIP)                              │          │
│  │  │  • Storage: 10Gi PVC                                   │          │
│  │  │  • Role: Store metadata      │                         │          │
│  │  │  • Stores:                   │                         │          │
│  │  │    - User accounts           │                         │          │
│  │  │    - Chat history            │                         │          │
│  │  │    - LLM config               │                         │          │
│  │  │    - Document metadata       │                         │          │
│  │  └──────────────────────────────┘                         │          │
│  │                                                            │          │
│  │  ┌──────────────────────────────┐                         │          │
│  │  │  VESPA                       │◄────────────────────────┘          │
│  │  │  (StatefulSet + Service)     │                                    │
│  │  │  • Image: vespa:8.526.15     │                                    │
│  │  │  • Port: 19071 (config)      │                                    │
│  │  │  •       8081 (query)        │                                    │
│  │  │  • Storage: 30Gi PVC         │                                    │
│  │  │  • Role: Vector search       │                                    │
│  │  │  • Stores:                   │                                    │
│  │  │    - Document chunks (text)  │                                    │
│  │  │    - Vector embeddings       │                                    │
│  │  └──────────────────────────────┘                                    │
│  │                                                                       │
│  │  ┌──────────────────────────────┐                                    │
│  │  │  REDIS                       │◄───────────────────────────────────┘
│  │  │  (Deployment + Service)      │
│  │  │  • Image: redis:7.4-alpine   │
│  │  │  • Port: 6379 (ClusterIP)    │
│  │  │  • Storage: None (ephemeral) │
│  │  │  • Role: Cache & session     │
│  │  │  • Stores:                   │
│  │  │    - API response cache      │
│  │  │    - User sessions           │
│  │  └──────────────────────────────┘
│  │                                                                       │
│  └───────────────────────────────────────────────────────────────────────┘
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 📊 Service Connection Table

| From Service | To Service | Port | Protocol | What Data Flows | Why |
|--------------|------------|------|----------|-----------------|-----|
| **User** | NGINX | 80 | HTTP | HTTP requests | Access UI |
| **NGINX** | Web Server | 3000 | HTTP | HTML/CSS/JS | Serve frontend |
| **NGINX** | API Server | 8080 | HTTP | API calls | Backend requests |
| **Web Server** | API Server | 8080 | HTTP | JSON data | Fetch data for UI |
| **API Server** | PostgreSQL | 5432 | PostgreSQL | SQL queries | User data, config, chat history |
| **API Server** | Vespa | 19071 | HTTP | Search queries | Vector similarity search |
| **API Server** | Redis | 6379 | Redis | Cache ops | Store/retrieve cached data |
| **API Server** | Model Server | 9000 | HTTP | Text strings | Convert query to vector |
| **API Server** | vLLM (external) | 8001 | HTTP | Chat context | Generate AI responses |

---

## 🔄 Complete Request Flow (Junior DevOps Perspective)

### Scenario 1: User Loads Homepage

```
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 1: User opens browser                                              │
│ Action: Types http://onyx.company.com                                   │
│ Protocol: HTTP GET /                                                    │
└────────────────────────────┬────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 2: OpenShift Route receives request                                │
│ Component: OpenShift Router                                             │
│ Action: Routes to NGINX service based on hostname                       │
│ Why: OpenShift Routes map external URLs to internal services            │
└────────────────────────────┬────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 3: NGINX pod receives request                                      │
│ Component: NGINX Deployment (nginx:1.23.4-alpine)                       │
│ Port: 80                                                                │
│ Action: Checks nginx.conf ConfigMap                                     │
│ Logic: URL "/" matches "location /" block                               │
│ Decision: Forward to upstream web_server                                │
│ Why: NGINX acts as reverse proxy - routes based on URL path             │
└────────────────────────────┬────────────────────────────────────────────┘
                             │
                             │ proxy_pass http://web_server
                             │ (Kubernetes resolves to web-server:3000)
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 4: Web Server pod receives request                                 │
│ Component: Web Server Deployment (onyx-web-server:nightly-20241004)     │
│ Port: 3000                                                              │
│ Technology: Next.js (React + Server-Side Rendering)                     │
│ Action: Generates HTML page with React components                       │
│ Returns: HTML + CSS + JavaScript bundle                                 │
│ Why: Next.js provides server-side rendering for SEO and fast loads      │
└────────────────────────────┬────────────────────────────────────────────┘
                             │
                             │ Response flows back
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 5: NGINX forwards response to user                                 │
│ Action: Passes HTML back through Route                                  │
└────────────────────────────┬────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 6: User sees Onyx homepage                                         │
│ Browser: Renders HTML, loads CSS/JS                                     │
│ User: Can now interact with UI                                          │
└─────────────────────────────────────────────────────────────────────────┘

Timeline: ~500ms total
```

---

### Scenario 2: User Searches for Documents (RAG Flow)

```
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 1: User types query                                                │
│ User: "What is our vacation policy?"                                    │
│ Browser: Sends AJAX call to /api/query                                  │
│ Protocol: POST http://onyx.company.com/api/query                        │
└────────────────────────────┬────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 2: NGINX routes to API Server                                      │
│ NGINX: Sees "/api/" in URL                                              │
│ Matches: location /api/ { proxy_pass http://api_server; }               │
│ Forwards to: api-server:8080/api/query                                  │
│ Why: API calls go to backend, not frontend                              │
└────────────────────────────┬────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 3: API Server receives query                                       │
│ Component: API Server (FastAPI Python app)                              │
│ Code: onyx/server/query.py                                              │
│ Action: Processes search request                                        │
└────────────────────────────┬────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 4: Check Redis cache (optimization)                                │
│ Component: Redis (redis:7.4-alpine)                                     │
│ Connection: api-server → redis:6379                                     │
│ Action: GET cache:query:vacation_policy                                 │
│ Result: MISS (not in cache)                                             │
│ Why: Check cache first to avoid expensive operations                    │
└────────────────────────────┬────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 5: Generate query embedding (convert text → vector)                │
│ Component: Inference Model Server (onyx-model-server)                   │
│ Connection: api-server → inference-model-server:9000                    │
│ Request: POST /embed                                                    │
│ Payload: {"text": "What is our vacation policy?"}                       │
│ Processing:                                                             │
│   1. Load model: sentence-transformers/all-MiniLM-L6-v2                 │
│   2. Tokenize text into numbers                                         │
│   3. Run through neural network                                         │
│   4. Output: 768-dimensional vector                                     │
│ Response: [0.123, -0.456, 0.789, ..., 0.234]  (768 numbers)            │
│ Time: ~100ms                                                            │
│ Why: Vespa needs vectors to search by meaning, not keywords             │
└────────────────────────────┬────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 6: Search Vespa for similar documents                              │
│ Component: Vespa (vespaengine/vespa:8.526.15)                           │
│ Connection: api-server → vespa-0.vespa-service:19071                    │
│ Request: POST /search/                                                  │
│ Payload:                                                                │
│   {                                                                     │
│     "yql": "select * from documents where ...",                         │
│     "ranking.features.query(embedding)": [0.123, -0.456, ...]          │
│   }                                                                     │
│ Processing:                                                             │
│   1. Vespa compares query vector with stored document vectors           │
│   2. Finds documents with most similar vectors (cosine similarity)      │
│   3. Ranks results by relevance                                         │
│   4. Returns top 10 chunks                                              │
│ Response:                                                               │
│   [                                                                     │
│     {"text": "Employees get 15 days...", "score": 0.92},               │
│     {"text": "Vacation must be approved...", "score": 0.87},           │
│     ...                                                                 │
│   ]                                                                     │
│ Time: ~50ms                                                             │
│ Why: Semantic search - finds by meaning, not exact words                │
└────────────────────────────┬────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 7: Retrieve document metadata from PostgreSQL                      │
│ Component: PostgreSQL (postgres:15.2-alpine)                            │
│ Connection: api-server → postgresql:5432                                │
│ Query: SELECT * FROM documents WHERE id IN (...)                        │
│ Returns: Document names, sources, timestamps, permissions               │
│ Why: Vespa has chunks, PostgreSQL has metadata (file name, source)      │
└────────────────────────────┬────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 8: Build context for LLM                                           │
│ Component: API Server                                                   │
│ Action: Combine top chunks into context                                 │
│ Format:                                                                 │
│   Context:                                                              │
│   ---                                                                   │
│   [Document: HR_Policy.pdf]                                             │
│   Employees get 15 days of vacation per year...                         │
│                                                                         │
│   [Document: Employee_Handbook.pdf]                                     │
│   Vacation must be approved by manager...                               │
│   ---                                                                   │
│ Why: LLM needs context to generate accurate answers                     │
└────────────────────────────┬────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 9: Call vLLM to generate answer                                    │
│ Component: vLLM Server (external namespace)                             │
│ Connection: api-server → <vllm-service>:8001/v1/chat/completions        │
│ Request:                                                                │
│   {                                                                     │
│     "model": "meta-llama/Meta-Llama-3-8B-Instruct",                     │
│     "messages": [                                                       │
│       {                                                                 │
│         "role": "system",                                               │
│         "content": "You are a helpful assistant. Use context to answer."│
│       },                                                                │
│       {                                                                 │
│         "role": "user",                                                 │
│         "content": "Context: <chunks>\nQuestion: vacation policy?"      │
│       }                                                                 │
│     ]                                                                   │
│   }                                                                     │
│ Processing: vLLM runs Llama model, generates response                   │
│ Response: "Based on company policy, employees receive 15 days..."       │
│ Time: ~2-10 seconds (depends on model size and GPU)                     │
│ Why: LLM understands context and generates natural language answer      │
└────────────────────────────┬────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 10: Cache result in Redis                                          │
│ Component: Redis                                                        │
│ Connection: api-server → redis:6379                                     │
│ Action: SET cache:query:vacation_policy "answer" EX 300                 │
│ TTL: 5 minutes (300 seconds)                                            │
│ Why: Same query within 5 min = instant response from cache              │
└────────────────────────────┬────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 11: Save to PostgreSQL chat history                                │
│ Component: PostgreSQL                                                   │
│ Action: INSERT INTO chat_messages (user_id, query, answer, timestamp)   │
│ Why: Preserve conversation history for user                             │
└────────────────────────────┬────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 12: Response flows back to user                                    │
│ Path: API Server → NGINX → Route → User's browser                       │
│ Format: JSON {"answer": "...", "citations": [...]}                      │
│ User sees: Answer with citations/sources                                │
└─────────────────────────────────────────────────────────────────────────┘

Total time: ~3-10 seconds
  - Embedding: 100ms
  - Vespa search: 50ms
  - PostgreSQL: 50ms
  - vLLM generation: 2-10 seconds
  - Redis cache: 10ms
```

---

## 🤖 AI/ML Components (For LLM Engineers)

### 1. Inference Model Server (Embedding Service)

**Role:** Convert text to mathematical vectors (embeddings)

**Model:** `sentence-transformers/all-MiniLM-L6-v2`
- Type: BERT-based transformer
- Output: 768-dimensional dense vectors
- Size: ~90MB
- Speed: ~100ms per query

**What it does:**
```python
Input: "vacation policy"
↓ (Neural network processes text)
Output: [0.123, -0.456, 0.789, ..., 0.234]  # 768 numbers
```

**Why vectors?**
- Vectors capture semantic meaning
- Similar meanings = similar vectors
- Example:
  ```
  "vacation days"  → [0.12, -0.45, 0.78, ...]
  "time off"       → [0.11, -0.44, 0.79, ...]  ← Very similar!
  "pizza recipe"   → [-0.89, 0.23, -0.12, ...] ← Very different!
  ```

**Technical details:**
- Framework: PyTorch + HuggingFace Transformers
- API: FastAPI with `/embed` endpoint
- Batching: Can process multiple texts at once
- Caching: Models cached in `/app/.cache/huggingface`

**Resource usage:**
- RAM: 2-4Gi (model + inference)
- CPU: 500m-2000m (during inference)
- GPU: Optional (speeds up significantly)

**When it's called:**
- Every user search query
- Real-time (users wait for response)
- Must be fast (<200ms)

---

### 2. vLLM Server (Language Model)

**Role:** Generate natural language responses

**Model:** User-configurable (Llama, Mistral, GPT, etc.)
- Example: `meta-llama/Meta-Llama-3-8B-Instruct`
- Type: Autoregressive language model
- Size: 7B-70B parameters (7GB-140GB)

**What it does:**
```
Input: 
  System: "You are helpful assistant"
  Context: "Employees get 15 days vacation..."
  Question: "What is vacation policy?"
↓ (Language model generates text)
Output: "Based on your company policy, employees receive 15 days of vacation per year. Vacation must be approved by your manager..."
```

**API:** OpenAI-compatible
```python
POST /v1/chat/completions
{
  "model": "meta-llama/Meta-Llama-3-8B-Instruct",
  "messages": [...],
  "temperature": 0.7,
  "max_tokens": 500
}
```

**Technical details:**
- Framework: vLLM (optimized inference engine)
- Optimization: PagedAttention, continuous batching
- GPU: Required for good performance (NVIDIA)
- CPU: Works but very slow (5-20x slower)

**Resource usage:**
- RAM: 8-16Gi (for 7B model)
- GPU VRAM: 8-16Gi (for 7B model)
- CPU: Heavy (90%+ if no GPU)

**When it's called:**
- Every chat message
- After context retrieval from Vespa
- Generates final answer to user

**Key difference from Inference Model:**
- **Inference Model:** Text → Vector (embedding, ~100ms)
- **vLLM:** Context → Answer (generation, ~2-10 seconds)

---

## 💾 Data Storage Explained (For DevOps)

### PostgreSQL (Relational Database)

**What it stores:**

1. **Users table:**
   ```sql
   id | email | password_hash | created_at | role
   1  | admin@company.com | $2b$12$... | 2024-10-15 | admin
   ```

2. **Chat_messages table:**
   ```sql
   id | user_id | session_id | message | answer | timestamp
   1  | 1 | abc123 | "vacation?" | "15 days..." | 2024-10-15 10:30
   ```

3. **LLM_providers table:**
   ```sql
   id | name | api_base | model | api_key_encrypted
   1  | vLLM Local | http://vllm:8001/v1 | llama-3 | ...
   ```

4. **Documents table:**
   ```sql
   id | name | source | indexed_at | status
   1  | HR_Policy.pdf | Google Drive | 2024-10-15 | indexed
   ```

**Why PostgreSQL?**
- ACID transactions (data integrity)
- Relational queries (JOIN users with chats)
- Mature, reliable, well-understood

**What it does NOT store:**
- ❌ Document content (too large, goes to Vespa)
- ❌ Vector embeddings (specialized, goes to Vespa)
- ❌ File binaries (would go to MinIO if enabled)

---

### Vespa (Vector Search Engine)

**What it stores:**

1. **Document chunks (text):**
   ```json
   {
     "id": "doc1_chunk_1",
     "content": "Employees get 15 days of vacation per year.",
     "document_id": "doc1",
     "chunk_index": 1
   }
   ```

2. **Vector embeddings:**
   ```json
   {
     "id": "doc1_chunk_1",
     "embedding": [0.123, -0.456, 0.789, ..., 0.234]  # 768 dims
   }
   ```

**How search works:**

```
1. User query: "vacation policy"
   ↓
2. Convert to vector: [0.12, -0.45, ...]
   ↓
3. Vespa compares with all stored vectors:
   - Cosine similarity calculation
   - Ranks by similarity score
   ↓
4. Returns most similar chunks:
   - Chunk A: 0.92 similarity (very relevant)
   - Chunk B: 0.87 similarity (relevant)
   - Chunk C: 0.45 similarity (less relevant)
```

**Technical details:**
- Search algorithm: Approximate Nearest Neighbor (ANN)
- Index type: HNSW (Hierarchical Navigable Small World)
- Scale: Millions of vectors in milliseconds
- Hybrid search: Vector + keyword (BM25)

**Why Vespa?**
- Fast: <50ms for searches
- Scalable: Handles millions of documents
- Hybrid: Combines semantic + keyword search
- Flexible: Custom ranking formulas

---

### Redis (Cache & Message Broker)

**What it stores:**

1. **API response cache:**
   ```
   Key: cache:query:vacation_policy
   Value: {"answer": "15 days...", "citations": [...]}
   TTL: 300 seconds (5 minutes)
   ```

2. **User sessions:**
   ```
   Key: session:abc123xyz
   Value: {"user_id": 1, "expires": "2024-10-15T18:00:00Z"}
   TTL: 86400 seconds (24 hours)
   ```

3. **Rate limiting:**
   ```
   Key: ratelimit:user:1:api
   Value: 45  (requests made)
   TTL: 3600 seconds (1 hour)
   ```

**Why Redis?**
- In-memory: Microsecond latency
- TTL: Auto-expires old data
- Atomic operations: Thread-safe
- Ephemeral: Designed for temporary data

**Configuration:**
```bash
# From 04-redis.yaml
command: redis-server --save "" --appendonly no
```
- `--save ""` = No disk snapshots
- `--appendonly no` = No append-only file
- Result: Pure in-memory cache (data lost on restart - intentional!)

**Why ephemeral?**
- Cache can be rebuilt
- Faster than persistent Redis
- Simpler operations

---

## 🌐 Kubernetes Networking (For DevOps)

### Service Discovery (DNS)

**How services find each other:**

```
Within same namespace:
  postgresql           → postgresql.svc.cluster.local:5432
  vespa-0.vespa-service → vespa-0.vespa-service.svc.cluster.local:19071
  redis                → redis.svc.cluster.local:6379

Kubernetes automatically resolves short names!
```

**Example from API Server perspective:**

```python
# In Python code (onyx/db/engine.py):
POSTGRES_HOST = os.getenv("POSTGRES_HOST")  # Value: "postgresql"

# SQLAlchemy connection:
engine = create_engine(f"postgresql://{user}:{password}@{POSTGRES_HOST}:5432/db")

# Kubernetes DNS resolution:
"postgresql" → "postgresql.your-namespace.svc.cluster.local"
             → Resolves to Pod IP: 10.244.1.15
             → Connects to PostgreSQL pod
```

**DNS Resolution Flow:**

```
1. App requests: http://api-server:8080
   ↓
2. Kubernetes CoreDNS receives query
   ↓
3. Looks up Service: api-server
   ↓
4. Service selector: app=api-server
   ↓
5. Finds Pod IP: 10.244.2.20
   ↓
6. Returns IP to caller
   ↓
7. Connection established to Pod
```

---

### Service Types

| Service | Type | Why | Access |
|---------|------|-----|--------|
| **NGINX** | LoadBalancer | External access | Public internet → Pod |
| **All others** | ClusterIP | Internal only | Pod → Pod only |
| **Vespa** | ClusterIP: None | Headless (StatefulSet) | Direct Pod access |

**ClusterIP (default):**
- Creates stable internal IP
- Only accessible within cluster
- Example: `10.96.45.123:8080`

**LoadBalancer:**
- Creates external IP (cloud provider)
- Accessible from internet
- Example: `35.123.45.67:80`

**Headless Service (ClusterIP: None):**
- No cluster IP assigned
- Direct DNS to Pod IPs
- Used by StatefulSets (stable Pod identity)
- Example: `vespa-0.vespa-service` → Pod IP directly

---

### Port Mapping

**Container Port vs Service Port:**

```yaml
# In Deployment:
ports:
  - name: http
    containerPort: 8080  # Port inside container

# In Service:
ports:
  - name: http
    port: 8080           # Port Service listens on
    targetPort: 8080     # Port to forward to container
```

**Example:**

```
External request → :80 (LoadBalancer)
                    ↓
NGINX Service → :80 (Service port)
                    ↓
NGINX Pod → :80 (containerPort)
```

---

## 🔐 ConfigMap & Secrets (For DevOps)

### ConfigMap vs Secret

**ConfigMap** (`05-configmap.yaml`):
- Non-sensitive configuration
- Plain text (not encrypted)
- Examples: Service endpoints, timeouts, feature flags

```yaml
data:
  POSTGRES_HOST: "postgresql"
  VESPA_HOST: "vespa-0.vespa-service"
  QA_TIMEOUT: "60"
```

**Secret** (postgresql-secret, redis-secret):
- Sensitive data
- Base64 encoded (not encrypted, just encoded!)
- Examples: Passwords, API keys, certificates

```yaml
stringData:  # Auto-converts to base64
  POSTGRES_PASSWORD: "postgres"
```

**How they're used:**

```yaml
# In Deployment:
containers:
  - name: api-server
    envFrom:
      - configMapRef:
          name: onyx-config  # All keys become env vars
    env:
      - name: POSTGRES_PASSWORD
        valueFrom:
          secretKeyRef:
            name: postgresql-secret
            key: POSTGRES_PASSWORD
```

**Result in container:**
```bash
# Inside api-server pod:
$ env | grep POSTGRES
POSTGRES_HOST=postgresql
POSTGRES_PORT=5432
POSTGRES_PASSWORD=postgres  # From secret
```

---

### NGINX ConfigMap (Special Case)

**Different from environment ConfigMap!**

```yaml
# This ConfigMap stores a FILE, not env vars:
data:
  nginx.conf: |
    # Entire NGINX configuration file
    ...
```

**Mounting:**

```yaml
volumeMounts:
  - name: nginx-config
    mountPath: /etc/nginx/nginx.conf  # File path
    subPath: nginx.conf               # Which key from ConfigMap
volumes:
  - name: nginx-config
    configMap:
      name: nginx-config
```

**Result:**
- ConfigMap key `nginx.conf` → File `/etc/nginx/nginx.conf` in container
- NGINX reads this file on startup
- Can update ConfigMap → restart NGINX → new config active

**Advantage:**
- No custom Docker image needed
- Configuration versioned in Kubernetes
- Easy to update without rebuilding

---

## 🔄 Init Containers (For DevOps)

### Why API Server Has Init Container

**Problem:** Database schema must exist before API server starts

**Without init container:**
```
1. API Server starts
2. Tries to query database
3. Table doesn't exist → CRASH
4. Pod restarts → Loop forever
```

**With init container:**
```
1. Init container starts FIRST
2. Runs: alembic upgrade head (creates tables)
3. Init container exits successfully
4. Main container starts
5. Database ready → API works!
```

**Configuration:**

```yaml
initContainers:
  - name: migration
    image: onyxdotapp/onyx-backend:nightly-20241004
    command: ["alembic", "upgrade", "head"]
    # Connects to PostgreSQL and runs migrations
containers:
  - name: api-server
    # Starts AFTER init container succeeds
```

**Alembic migrations:**
- Creates tables: users, documents, chat_messages, etc.
- Adds columns, indexes, constraints
- Versioned schema changes
- Safe: Won't drop data

---

## 📦 Storage (For DevOps)

### Persistent Volume Claims (PVCs)

**PostgreSQL PVC:**
```yaml
spec:
  accessModes:
    - ReadWriteOnce  # Only one pod can mount
  resources:
    requests:
      storage: 10Gi
```

**What this means:**
- Requests 10Gi disk space
- ReadWriteOnce: Only one pod can write (prevents corruption)
- Kubernetes provisions a PersistentVolume (PV)
- Data survives pod restarts/deletions

**Vespa PVC (via StatefulSet):**
```yaml
volumeClaimTemplates:
  - metadata:
      name: vespa-storage
    spec:
      accessModes: [ReadWriteOnce]
      resources:
        requests:
          storage: 30Gi
```

**StatefulSet behavior:**
- Creates PVC: `vespa-storage-vespa-0`
- Stable: Same PVC always mounts to vespa-0
- Survives: Pod deletion, StatefulSet scaling

**emptyDir (Model Server):**
```yaml
volumes:
  - name: model-cache
    emptyDir: {}  # Temporary, pod-local storage
```

**Characteristics:**
- Created when pod starts
- Deleted when pod terminates
- Shared between containers in same pod
- Fast (usually node's local disk)

**Why emptyDir for model cache?**
- Models auto-download on first start
- Can re-download if lost (not critical data)
- Simpler than PVC for caching

---

## 🔧 Resource Requests vs Limits (For DevOps)

### Understanding Resources

```yaml
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 2Gi
```

**Requests:**
- **Guaranteed minimum** resources
- Kubernetes scheduler uses this to place pod
- Pod gets AT LEAST this much

**Limits:**
- **Maximum allowed** resources
- Pod killed if exceeds memory limit (OOMKilled)
- CPU throttled if exceeds CPU limit

**Example:**

```
API Server resources:
  requests: 500m CPU, 1Gi RAM
  limits: 2000m CPU, 2Gi RAM

Meaning:
  - Kubernetes finds node with 500m CPU + 1Gi RAM available
  - Pod always gets 500m CPU minimum
  - Can use UP TO 2000m CPU if available
  - Can use UP TO 2Gi RAM (killed if exceeds)
```

**Best practices:**
- Set requests = typical usage
- Set limits = peak usage
- Don't set limits too low (pods get OOMKilled)
- Monitor actual usage: `kubectl top pods`

---

## 🧪 Health Checks (For DevOps)

### Liveness vs Readiness Probes

**Liveness Probe:**
- Question: "Is the container alive?"
- If fails: Kubernetes **restarts** the container
- Use for: Detect deadlocks, hung processes

**Readiness Probe:**
- Question: "Is the container ready to serve traffic?"
- If fails: Kubernetes **removes from Service** (no traffic sent)
- Use for: Startup delays, temporary unavailability

**Example from API Server:**

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 60    # Wait 60s before first check
  periodSeconds: 30          # Check every 30s
  failureThreshold: 3        # Restart after 3 failures

readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30    # Check earlier than liveness
  periodSeconds: 10          # Check more frequently
  failureThreshold: 5        # More tolerant of failures
```

**Timeline:**

```
0s:  Pod starts
     Readiness: Not checked yet
     Liveness: Not checked yet
     Service: Pod NOT in endpoints

30s: First readiness check
     /health returns 200 OK
     Service: Pod ADDED to endpoints (receives traffic)

60s: First liveness check
     /health returns 200 OK
     Pod: Continues running

90s: Second liveness check (60s + 30s period)
     /health returns 500 Error
     Failure count: 1

120s: Third liveness check
     /health returns 500 Error
     Failure count: 2

150s: Fourth liveness check
     /health returns 500 Error
     Failure count: 3 → RESTART CONTAINER
```

---

## 🔍 Troubleshooting Guide (For Junior DevOps)

### Issue: Pods Stuck in "Pending"

**What it means:**
- Pod created but not scheduled to any node
- Kubernetes can't find resources

**Debug:**
```bash
kubectl describe pod <pod-name>

# Look for:
# Events:
#   Warning  FailedScheduling  ... Insufficient memory
#   Warning  FailedScheduling  ... Insufficient cpu
```

**Solutions:**
1. **Not enough resources:**
   ```bash
   # Check node resources
   kubectl top nodes
   
   # Reduce pod resource requests
   # Edit YAML: requests: cpu: 250m (instead of 500m)
   ```

2. **PVC not binding:**
   ```bash
   kubectl get pvc
   
   # If status: Pending
   kubectl describe pvc <pvc-name>
   
   # Check if StorageClass exists
   kubectl get storageclass
   ```

---

### Issue: Pod CrashLoopBackOff

**What it means:**
- Container keeps crashing
- Kubernetes keeps restarting it
- Restart backoff increases each time

**Debug:**
```bash
# Check current logs
kubectl logs <pod-name>

# Check previous crash logs
kubectl logs <pod-name> --previous

# Check events
kubectl describe pod <pod-name>
```

**Common causes:**

**1. Database connection failed:**
```
Error: could not connect to postgresql:5432
Solution: Check if PostgreSQL pod is running
```

**2. Missing environment variables:**
```
Error: POSTGRES_PASSWORD not set
Solution: Check if secret exists and is mounted
```

**3. Port already in use:**
```
Error: Address already in use: 8080
Solution: Check for duplicate deployments
```

**4. Out of memory:**
```
Killed (OOMKilled)
Solution: Increase memory limits
```

---

### Issue: Service Returns 502 Bad Gateway

**What it means:**
- NGINX can't reach backend service
- Backend pod might be down or not ready

**Debug flow:**

```bash
# Step 1: Check if backend pods are running
kubectl get pods -l app=api-server
kubectl get pods -l app=web-server

# Step 2: Check if services exist
kubectl get svc api-server
kubectl get svc web-server

# Step 3: Check if pods are ready
kubectl get pods  # Look for 1/1 READY

# Step 4: Test from NGINX pod
kubectl exec -it deployment/nginx -- \
  wget -O- http://api-server:8080/health

# Step 5: Check backend logs
kubectl logs deployment/api-server
```

**Common causes:**
1. Backend pod not ready (startup delay)
2. Backend pod crashed
3. Wrong service name in NGINX config
4. Port mismatch

---

## 🚀 Deployment Order & Dependencies

### Why Order Matters

```
Layer 1: Infrastructure (No dependencies)
├─ PostgreSQL
├─ Vespa  
└─ Redis
   ↓ Must be READY before next layer
   
Layer 2: Configuration
└─ ConfigMap (references services above)
   ↓
   
Layer 3: AI/ML
└─ Inference Model Server (needs ConfigMap)
   ↓ Must be READY (models downloaded)
   
Layer 4: Application
└─ API Server
   • Depends on: PostgreSQL (migrations)
   • Depends on: Vespa (config)
   • Depends on: Redis (cache)
   • Depends on: Model Server (embeddings)
   ↓ Must be READY before next layer
   
Layer 5: Frontend
└─ Web Server
   • Depends on: API Server
   ↓ Must be READY before next layer
   
Layer 6: Gateway
└─ NGINX
   • Depends on: Web Server
   • Depends on: API Server
```

**What happens if deployed out of order:**

```
Scenario: Deploy API Server BEFORE PostgreSQL

1. API Server pod starts
2. Init container tries: alembic upgrade head
3. Connects to: postgresql:5432
4. Error: Name resolution failed (service doesn't exist)
5. Init container fails
6. Pod status: Init:Error
7. Kubernetes retries...
8. Eventually: Init:CrashLoopBackOff

Solution: Deploy PostgreSQL first, wait for ready
```

**This is why deploy.sh waits between layers!**

---

## 🔗 Complete Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      USER SEARCH WITH ANSWER                             │
└─────────────────────────────────────────────────────────────────────────┘

1. USER
   Types: "vacation policy"
   Browser sends: POST /api/query
   
   ↓ (HTTP/80)
   
2. NGINX
   Config: location /api/ { proxy_pass http://api_server; }
   Action: Routes to api-server:8080
   Why: Reverse proxy based on URL path
   
   ↓ (HTTP/8080)
   
3. API SERVER
   Endpoint: /api/query
   Code: onyx/server/query.py
   
   ┌─ Action 3a: Check cache ─────────────────────┐
   │  Connection: redis:6379                      │
   │  Command: GET cache:query:vacation           │
   │  Result: MISS                                │
   │  Why: Avoid re-computing same query          │
   └──────────────────────────────────────────────┘
   
   ┌─ Action 3b: Embed query ─────────────────────┐
   │  Connection: inference-model-server:9000     │
   │  Request: POST /embed                        │
   │  Payload: {"text": "vacation policy"}        │
   │  Response: [0.12, -0.45, ..., 0.78]         │
   │  Time: ~100ms                                │
   │  Why: Convert text → vector for Vespa       │
   └──────────────────────────────────────────────┘
   
   ┌─ Action 3c: Search Vespa ────────────────────┐
   │  Connection: vespa-0.vespa-service:19071     │
   │  Request: POST /search/                      │
   │  Payload: {embedding: [0.12, ...]}          │
   │  Processing: Vector similarity search        │
   │  Response: Top 10 relevant chunks            │
   │  Time: ~50ms                                 │
   │  Why: Find similar documents by meaning      │
   └──────────────────────────────────────────────┘
   
   ┌─ Action 3d: Get metadata ────────────────────┐
   │  Connection: postgresql:5432                 │
   │  Query: SELECT name, source FROM documents   │
   │  Response: File names, sources               │
   │  Why: Vespa has content, PostgreSQL has info │
   └──────────────────────────────────────────────┘
   
   ┌─ Action 3e: Call vLLM ───────────────────────┐
   │  Connection: vllm-service:8001 (external NS) │
   │  Request: POST /v1/chat/completions          │
   │  Payload: {context + question}               │
   │  Processing: LLM generates answer            │
   │  Response: "Employees get 15 days..."        │
   │  Time: ~2-10 seconds                         │
   │  Why: Generate natural language answer       │
   └──────────────────────────────────────────────┘
   
   ┌─ Action 3f: Cache result ────────────────────┐
   │  Connection: redis:6379                      │
   │  Command: SET cache:query:vacation "answer"  │
   │  TTL: 300s (5 minutes)                       │
   │  Why: Next same query = instant response     │
   └──────────────────────────────────────────────┘
   
   ┌─ Action 3g: Save to history ─────────────────┐
   │  Connection: postgresql:5432                 │
   │  Query: INSERT INTO chat_messages ...        │
   │  Why: Preserve conversation for user         │
   └──────────────────────────────────────────────┘
   
   ↓ (HTTP response)
   
4. NGINX
   Action: Forwards response back to user
   
   ↓ (HTTP/80)
   
5. USER
   Sees: Answer with citations
   Time: ~3-10 seconds total
```

---

## 🎓 Key Concepts for Junior Engineers

### 1. Reverse Proxy (NGINX)

**Without reverse proxy:**
```
User needs to know:
  - UI is at: http://web-server.company.com:3000
  - API is at: http://api-server.company.com:8080
  
Problems:
  - Two different URLs (confusing)
  - Can't have one SSL certificate
  - Can't add authentication layer easily
```

**With reverse proxy (NGINX):**
```
User knows only: http://onyx.company.com

NGINX internally routes:
  / → web-server:3000
  /api/* → api-server:8080
  
Benefits:
  - Single entry point
  - One SSL certificate
  - Can add auth, rate limiting, caching
  - Can load balance across multiple backend pods
```

---

### 2. Vector Embeddings (For LLM Engineers)

**What are embeddings?**

Embeddings convert text into numbers that represent meaning.

**Example:**

```
Text: "The company provides vacation days"

Step 1: Tokenization
  → ["the", "company", "provides", "vacation", "days"]

Step 2: Token IDs
  → [2, 138, 945, 1234, 567]

Step 3: Neural network (BERT/Transformer)
  → Multiple layers of transformations

Step 4: Output vector (768 dimensions)
  → [0.123, -0.456, 0.789, ..., 0.234]
```

**Why 768 dimensions?**
- Model architecture (BERT-base uses 768)
- Each dimension captures different aspects of meaning
- Examples:
  - Dim 0-100: General topic
  - Dim 101-200: Sentiment
  - Dim 201-300: Entity types
  - Etc. (learned automatically)

**Similarity calculation:**

```
Vector A: "vacation policy"    = [0.12, -0.45, 0.78, ...]
Vector B: "time off rules"     = [0.11, -0.44, 0.79, ...]
Vector C: "pizza ingredients"  = [-0.89, 0.23, -0.12, ...]

Cosine Similarity:
  similarity(A, B) = 0.92  ← Very similar!
  similarity(A, C) = 0.15  ← Not similar
```

---

### 3. RAG (Retrieval Augmented Generation)

**What is RAG?**

RAG = Retrieval + Augmented + Generation

**Traditional LLM (without RAG):**
```
User: "What is our vacation policy?"
LLM:  "I don't have information about your specific company policy."

Problem: LLM doesn't know your company data
```

**With RAG:**
```
Step 1: RETRIEVAL
  - Search your documents for "vacation policy"
  - Find relevant chunks from HR_Policy.pdf
  - Result: "Employees get 15 days vacation..."

Step 2: AUGMENTED
  - Combine chunks into context
  - Add to LLM prompt
  
Step 3: GENERATION
  - LLM uses context to answer
  - Result: "Based on your company policy, employees get 15 days..."

Benefit: Accurate, company-specific answers!
```

**Onyx RAG Architecture:**
```
Query → [Inference Model] → Embedding
                              ↓
                         [Vespa Search] → Relevant chunks
                              ↓
                         [Build Context] → Chunks + Query
                              ↓
                         [vLLM] → Answer
```

---

### 4. Kubernetes Service Discovery

**How does api-server find postgresql?**

```
1. In ConfigMap:
   POSTGRES_HOST: "postgresql"

2. API Server container starts:
   env | grep POSTGRES_HOST
   → POSTGRES_HOST=postgresql

3. Python code:
   connection_string = f"postgresql://user:pass@{POSTGRES_HOST}:5432/db"
   → "postgresql://user:pass@postgresql:5432/db"

4. Container tries to connect:
   DNS query: "postgresql"
   
5. Kubernetes DNS (CoreDNS):
   - Looks for Service named "postgresql"
   - Finds Service in same namespace
   - Returns: Service ClusterIP (e.g., 10.96.15.23)
   
6. Connection established:
   api-server pod (10.244.1.5) → postgresql service (10.96.15.23:5432)
                                  ↓
                                  postgresql pod (10.244.2.8)
```

**Short name resolution:**
```
"postgresql" → "postgresql.your-namespace.svc.cluster.local"

Components:
  postgresql         = Service name
  your-namespace     = Namespace
  svc.cluster.local  = Kubernetes domain
```

---

## 📊 Resource Sizing Guide (For DevOps)

### How We Determined Resource Limits

**PostgreSQL:**
```yaml
requests: cpu: 100m, memory: 256Mi
limits: cpu: 1000m, memory: 1Gi
```

**Reasoning:**
- Minimal deployment = light usage
- Mostly reads (SELECT queries)
- Few writes (INSERT chat messages)
- Can start with 100m CPU
- Burst to 1 CPU during heavy queries

**Vespa:**
```yaml
requests: cpu: 1000m, memory: 2Gi
limits: cpu: 4000m, memory: 8Gi
```

**Reasoning:**
- Java application (higher base memory)
- Vector search is CPU-intensive
- Need 2Gi minimum for index in memory
- Can burst to 8Gi for large result sets

**API Server:**
```yaml
requests: cpu: 500m, memory: 1Gi
limits: cpu: 2000m, memory: 2Gi
```

**Reasoning:**
- Python FastAPI (moderate memory)
- Orchestrates multiple services (needs CPU)
- 1Gi for request processing
- Can burst to 2 CPU during multiple concurrent requests

**Model Server:**
```yaml
requests: cpu: 500m, memory: 2Gi
limits: cpu: 2000m, memory: 4Gi
```

**Reasoning:**
- PyTorch models in memory (~1.5Gi)
- Inference is CPU-heavy (no GPU in minimal)
- Need 2Gi minimum for model + batch
- Burst to 4Gi for larger batches

**How to adjust:**

```bash
# Monitor actual usage
kubectl top pods

# Example output:
# NAME                        CPU    MEMORY
# api-server-xxx              450m   900Mi   ← Using less than limit
# vespa-0                     1200m  3Gi     ← Using more, consider increase
# postgresql-xxx              50m    200Mi   ← Comfortable

# Adjust based on actual usage + 30% buffer
```

---

## 🧠 LLM Integration (For LLM Engineers)

### How Onyx Calls vLLM

**API Configuration:**

In Onyx UI, you configure:
```
Provider Type: OpenAI
API Base URL: http://vllm-service.vllm-namespace:8001/v1
API Key: sk-dummy (vLLM doesn't validate)
Model Name: meta-llama/Meta-Llama-3-8B-Instruct
```

**This config is saved in PostgreSQL:**
```sql
INSERT INTO llm_providers (
  name, 
  provider_type, 
  api_base, 
  api_key_encrypted, 
  default_model
) VALUES (
  'vLLM Local',
  'openai',
  'http://vllm-service.vllm-namespace:8001/v1',
  '<encrypted>',
  'meta-llama/Meta-Llama-3-8B-Instruct'
);
```

**At runtime:**

```python
# In onyx/llm/llm.py

# Load config from PostgreSQL
llm_config = db.query(LLMProvider).first()

# Make API call
import openai
openai.api_base = llm_config.api_base  # vLLM endpoint
openai.api_key = llm_config.api_key

response = openai.ChatCompletion.create(
    model=llm_config.default_model,
    messages=[
        {"role": "system", "content": "You are helpful..."},
        {"role": "user", "content": f"Context: {chunks}\nQuestion: {query}"}
    ],
    max_tokens=500,
    temperature=0.7
)

answer = response.choices[0].message.content
```

**OpenAI-compatible API:**

vLLM implements the same API as OpenAI:
- `/v1/chat/completions` - Chat
- `/v1/completions` - Text completion  
- `/v1/embeddings` - Embeddings (if model supports)
- `/v1/models` - List models

**This means:**
- Onyx thinks it's talking to OpenAI
- But it's actually talking to your local vLLM
- Can swap providers without code changes

---

### Prompt Engineering in Onyx

**System prompt:**
```
You are a helpful AI assistant. Use the provided context to answer questions accurately. If the context doesn't contain the answer, say so. Always cite your sources.
```

**User prompt with context:**
```
Context:
---
[Document: HR_Policy_2024.pdf]
Employees are entitled to 15 days of paid vacation per year. Vacation requests must be submitted at least 2 weeks in advance and approved by the direct manager.

[Document: Employee_Handbook.pdf]
Unused vacation days do not roll over to the next year. Employees should plan their time off accordingly.
---

Question: What is our vacation policy?
```

**LLM response:**
```
Based on your company policy, employees receive 15 days of paid vacation per year. Vacation requests should be submitted at least 2 weeks in advance for manager approval. Note that unused vacation days don't roll over, so employees should plan their time off within the current year.

Sources:
- HR_Policy_2024.pdf
- Employee_Handbook.pdf
```

**Key techniques:**
- **Context injection:** Provide relevant chunks
- **Source citation:** Track which documents were used
- **Instruction following:** System prompt guides behavior
- **Fallback handling:** "I don't have that information" if no context

---

## 🔧 Configuration Management (For DevOps)

### Environment Variables Flow

**Definition (05-configmap.yaml):**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: onyx-config
data:
  POSTGRES_HOST: "postgresql"
  VESPA_HOST: "vespa-0.vespa-service"
```

**Usage (07-api-server.yaml):**
```yaml
containers:
  - name: api-server
    envFrom:
      - configMapRef:
          name: onyx-config  # Injects all keys as env vars
```

**Result in container:**
```bash
# Inside api-server pod:
$ env
POSTGRES_HOST=postgresql
VESPA_HOST=vespa-0.vespa-service
...
```

**Python code reads:**
```python
import os

POSTGRES_HOST = os.getenv("POSTGRES_HOST", "localhost")
# → "postgresql"
```

**Why this approach?**
- ✅ Centralized configuration (one place to change)
- ✅ Environment-specific (dev vs prod ConfigMaps)
- ✅ No secrets in code
- ✅ Easy to override per deployment

---

## 🎯 Summary for Junior Engineers

### DevOps Perspective

**What you deployed:**
- 7 interconnected microservices
- 2 databases (SQL + Vector)
- 1 cache layer
- 1 AI embedding service
- 1 reverse proxy

**How they connect:**
- Kubernetes Services (ClusterIP)
- DNS-based discovery (service names)
- Environment variables (ConfigMaps)
- Secrets for credentials

**Key skills needed:**
- Understanding Kubernetes resources (Pod, Service, Deployment)
- Debugging (logs, describe, events)
- Networking (Services, DNS, ports)
- Storage (PVC, PV, emptyDir)
- Configuration (ConfigMap, Secrets)

---

### LLM Engineer Perspective

**What you deployed:**
- RAG system (Retrieval + Generation)
- Vector search engine (Vespa)
- Embedding model (sentence-transformers)
- LLM inference (vLLM, external)

**How AI works here:**
1. **Embedding:** Text → Vector (semantic representation)
2. **Search:** Vector similarity (find relevant docs)
3. **Context building:** Combine chunks
4. **Generation:** LLM produces answer from context

**Key skills needed:**
- Understanding embeddings (vector representations)
- RAG architecture (retrieval + generation)
- LLM APIs (OpenAI-compatible)
- Prompt engineering (system + user prompts)
- Model selection (embedding vs generation models)

---

## 🚀 Production Readiness Checklist

Before going to production:

### Security (DevOps)
- [ ] Change all default passwords
- [ ] Use Kubernetes Secrets properly (encrypt at rest)
- [ ] Enable TLS/SSL in NGINX
- [ ] Set up network policies (restrict pod-to-pod communication)
- [ ] Use service accounts with RBAC
- [ ] Enable pod security policies

### Reliability (DevOps)
- [ ] Set up monitoring (Prometheus + Grafana)
- [ ] Configure alerting (PagerDuty, Slack)
- [ ] Set up logging (EFK or Loki)
- [ ] Configure backups (PostgreSQL, Vespa PVCs)
- [ ] Test disaster recovery
- [ ] Set up high availability (multiple replicas)
- [ ] Configure autoscaling (HPA)

### AI/ML (LLM Engineers)
- [ ] Choose production LLM provider
- [ ] Tune embedding model (if needed)
- [ ] Optimize prompt templates
- [ ] Set up model monitoring (latency, quality)
- [ ] Configure fallback LLM (if primary fails)
- [ ] Test with production data
- [ ] Measure RAG quality (precision, recall)

---

**This architecture provides a complete AI-powered search platform with chat!** 🚀

