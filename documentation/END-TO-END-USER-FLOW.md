# End-to-End User Flow - Complete Architecture

**Complete journey from user opening browser to receiving an AI-powered answer from LLM**

---

## 🎯 The Complete Picture

This document shows **EVERY STEP** of how Onyx works, from the moment a user opens their browser until they see an AI-generated answer.

---

## 🏗️ Complete Architecture Diagram

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                    COMPLETE ONYX ARCHITECTURE                             ║
║                    From Browser to LLM Response                           ║
╚═══════════════════════════════════════════════════════════════════════════╝


┌─────────────────────────────────────────────────────────────────────────┐
│  👤 USER                                                                 │
│  Opens browser: http://nginx-onyx-infra.apps.cluster.company.com       │
└─────────────────────────────┬───────────────────────────────────────────┘
                              │
                              │ HTTP Request
                              ↓
┌─────────────────────────────────────────────────────────────────────────┐
│  🌐 OPENSHIFT ROUTE                                                      │
│  ══════════════════════                                                  │
│  Name: nginx                                                             │
│  Host: nginx-onyx-infra.apps.cluster.company.com                        │
│  Target Service: nginx:80                                                │
│  Type: edge (HTTP/HTTPS)                                                 │
│                                                                          │
│  What it does: External URL → Internal Service                          │
└─────────────────────────────┬───────────────────────────────────────────┘
                              │
                              │ Routes to nginx Service
                              ↓
┌─────────────────────────────────────────────────────────────────────────┐
│  📡 NGINX SERVICE                                                        │
│  ════════════════                                                        │
│  Name: nginx                                                             │
│  Type: ClusterIP                                                         │
│  Port: 80                                                                │
│  Selector: app=nginx                                                     │
│                                                                          │
│  What it does: Load balances to nginx pods                              │
└─────────────────────────────┬───────────────────────────────────────────┘
                              │
                              │ Routes to nginx pod
                              ↓
┌─────────────────────────────────────────────────────────────────────────┐
│  📡 NGINX POD (Reverse Proxy)                                           │
│  ════════════════════════════                                           │
│  Container: nginx:1.23.4-alpine                                          │
│  Port: 80                                                                │
│  ConfigMap: nginx-config (routing rules)                                 │
│                                                                          │
│  ROUTING RULES (from ConfigMap):                                         │
│  ┌────────────────────────────────────────────────────────────┐         │
│  │                                                            │         │
│  │  location / {                                              │         │
│  │      proxy_pass http://web-server:3000;                   │         │
│  │  }                                                         │         │
│  │  → All requests for / go to Web Server                    │         │
│  │                                                            │         │
│  │  location /api/ {                                          │         │
│  │      proxy_pass http://api-server:8080;                   │         │
│  │  }                                                         │         │
│  │  → All requests for /api/* go to API Server               │         │
│  │                                                            │         │
│  └────────────────────────────────────────────────────────────┘         │
│                                                                          │
│  Decision: Is URL path /api/* ?                                         │
│  ├─ NO  → Send to Web Server (Next.js)                                  │
│  └─ YES → Send to API Server (FastAPI)                                  │
└─────────────────────────────┬───────────┬───────────────────────────────┘
                              │           │
                    ┌─────────┘           └─────────┐
                    │                               │
                    │ /                             │ /api/*
                    ↓                               ↓
    ┌───────────────────────────┐   ┌───────────────────────────────────┐
    │  🖥️  WEB SERVER           │   │  ⚙️  API SERVER                   │
    │  ═══════════════           │   │  ═══════════════                  │
    │  Service: web-server      │   │  Service: api-server              │
    │  Port: 3000               │   │  Port: 8080                       │
    │  Image: onyx-web-server   │   │  Image: onyx-backend              │
    │                           │   │                                   │
    │  What it serves:          │   │  What it handles:                 │
    │  • HTML pages             │   │  • REST API endpoints             │
    │  • JavaScript/CSS         │   │  • Authentication                 │
    │  • Next.js components     │   │  • Database queries               │
    │  • Static assets          │   │  • LLM orchestration              │
    │                           │   │  • Document search                │
    │  Examples:                │   │                                   │
    │  • GET /                  │   │  Examples:                        │
    │  • GET /chat              │   │  • POST /api/chat                 │
    │  • GET /search            │   │  • POST /api/query/stream-answer  │
    │  • GET /admin             │   │  • GET /api/user                  │
    └───────────┬───────────────┘   └─────────┬─────────────────────────┘
                │                             │
                │ Calls API for data          │
                │ (AJAX/Fetch requests)       │
                └─────────────────────────────┘
                              │
                              │ All API calls from browser go through NGINX
                              │ Browser: fetch('/api/chat', ...)
                              ↓
                    ┌─────────────────────┐
                    │    API SERVER       │
                    │    Processes:       │
                    └─────────┬───────────┘
                              │
            ┌─────────────────┼─────────────────┐
            │                 │                 │
            ↓                 ↓                 ↓
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────────┐
│  💾 PostgreSQL  │ │  ⚡ Redis       │ │  🔍 Vespa           │
│  ═════════════  │ │  ═══════════    │ │  ═══════════        │
│  Service:       │ │  Service:       │ │  Service:           │
│  postgresql:5432│ │  redis:6379     │ │  vespa:8081,19071   │
│                 │ │                 │ │                     │
│  Stores:        │ │  Stores:        │ │  Stores:            │
│  • User data    │ │  • Sessions     │ │  • Doc chunks       │
│  • Doc metadata │ │  • Cache        │ │  • Embeddings       │
│  • Chat history │ │  • Task queue   │ │  • Vector index     │
└─────────────────┘ └─────────────────┘ └──────────┬──────────┘
                                                    │
                                                    │
                              ┌─────────────────────┘
                              │
                              ↓
                    ┌─────────────────────────────┐
                    │  🤖 INFERENCE MODEL SERVER  │
                    │  ═══════════════════════    │
                    │  Service: inference-model-  │
                    │           server:9000       │
                    │                             │
                    │  Purpose:                   │
                    │  • Embed user queries       │
                    │  • Convert text → vectors   │
                    │  • Enable semantic search   │
                    │                             │
                    │  Models from NFS PVC:       │
                    │  • nomic-embed-text-v1      │
                    │  • Offline mode (no internet)│
                    └─────────────────────────────┘
                              │
                              │ Returns embedding vector
                              ↓
                    ┌─────────────────────┐
                    │    API SERVER       │
                    │    Uses embedding   │
                    │    to search Vespa  │
                    └─────────┬───────────┘
                              │
                              │ Retrieves relevant doc chunks
                              ↓
                    ┌─────────────────────────────┐
                    │  🧠 EXTERNAL LLM            │
                    │  ═══════════════            │
                    │  (vLLM in another namespace)│
                    │  or OpenAI, Anthropic, etc. │
                    │                             │
                    │  API Server calls:          │
                    │  POST /v1/chat/completions  │
                    │  {                          │
                    │    "messages": [            │
                    │      {"role": "system",...},│
                    │      {"role": "user",       │
                    │       "content": "Context:  │
                    │         <chunks> Question..."│}
                    │    ]                        │
                    │  }                          │
                    └─────────┬───────────────────┘
                              │
                              │ Returns AI answer
                              ↓
                    ┌─────────────────────┐
                    │    API SERVER       │
                    │    Returns response │
                    └─────────┬───────────┘
                              │
                              │ HTTP Response
                              ↓
                    ┌─────────────────────┐
                    │     NGINX           │
                    │     Forwards back   │
                    └─────────┬───────────┘
                              │
                              ↓
                    ┌─────────────────────┐
                    │   Web Server        │
                    │   (Next.js)         │
                    └─────────┬───────────┘
                              │
                              ↓
                    ┌─────────────────────┐
                    │   User's Browser    │
                    │   Displays answer!  │
                    └─────────────────────┘
```

---

## 🔄 Step-by-Step User Journey

### STEP 1: User Opens Browser

```
┌─────────────────────────────────────────────────────────────────────┐
│  STEP 1: USER OPENS ONYX                                            │
└─────────────────────────────────────────────────────────────────────┘

User Action:
━━━━━━━━━━━
Opens browser and types:
http://nginx-onyx-infra.apps.cluster.company.com

What Happens:
━━━━━━━━━━━━━
1. DNS resolves the hostname
   → Gets OpenShift router IP
   
2. Browser sends HTTP GET request:
   GET / HTTP/1.1
   Host: nginx-onyx-infra.apps.cluster.company.com
   
3. Request hits OpenShift Router
   → Checks route table
   → Finds route "nginx" matches this hostname
   → Forwards to nginx Service (port 80)
   
4. nginx Service receives request
   → Load balances to nginx Pod
   
5. nginx Pod receives request
   → Path is "/"
   → nginx.conf says: location / → proxy_pass http://web-server:3000
   → Forwards to web-server Service
   
6. web-server Service receives request
   → Forwards to web-server Pod
   
7. web-server Pod (Next.js) processes:
   → Server-side renders the React app
   → Generates HTML with JavaScript
   → Returns HTML page
   
8. HTML flows back:
   web-server Pod → web-server Service → nginx Pod → nginx Service
   → OpenShift Route → Browser
   
9. User sees: Onyx login page! 🎉

Time: ~200-500ms
```

---

### STEP 2: User Logs In

```
┌─────────────────────────────────────────────────────────────────────┐
│  STEP 2: USER AUTHENTICATION                                        │
└─────────────────────────────────────────────────────────────────────┘

User Action:
━━━━━━━━━━━
Enters credentials:
• Email: user@company.com
• Password: ********
• Clicks "Login"

What Happens:
━━━━━━━━━━━━━
1. Browser JavaScript sends AJAX request:
   POST /api/auth/login HTTP/1.1
   Host: nginx-onyx-infra.apps.cluster.company.com
   Content-Type: application/json
   
   Body: {
     "email": "user@company.com",
     "password": "********"
   }

2. Request flows through NGINX:
   → Path is "/api/auth/login" (starts with /api/)
   → nginx.conf: location /api/ → proxy_pass http://api-server:8080
   → Forwards to api-server Service
   
3. api-server Service → api-server Pod
   
4. API Server (FastAPI) processes login:
   a. Receives POST /api/auth/login
   b. Validates credentials against PostgreSQL
      → Queries: postgresql:5432
      → SELECT * FROM users WHERE email = 'user@company.com'
   c. Checks password hash
   d. Generates session token
   e. Stores session in Redis
      → SET session:abc123xyz "user_id:42"
   f. Returns session cookie
   
5. Response flows back:
   API Server → NGINX → Browser
   
6. Browser stores session cookie
   
7. User sees: Onyx dashboard! 🎉

Time: ~100-300ms
```

---

### STEP 3: User Asks a Question

```
┌─────────────────────────────────────────────────────────────────────┐
│  STEP 3: USER SUBMITS CHAT QUERY                                    │
└─────────────────────────────────────────────────────────────────────┘

User Action:
━━━━━━━━━━━
Types in chat: "What is our vacation policy?"
Clicks "Send"

What Happens:
━━━━━━━━━━━━━
1. Browser JavaScript sends:
   POST /api/chat/send-message HTTP/1.1
   Cookie: session=abc123xyz
   
   Body: {
     "message": "What is our vacation policy?",
     "chat_session_id": null,
     "persona_id": 1
   }

2. Request → OpenShift Route → nginx Service → nginx Pod
   
3. NGINX routing decision:
   Path: /api/chat/send-message
   → Starts with /api/
   → nginx.conf: proxy_pass http://api-server:8080
   → Forwards to api-server:8080/api/chat/send-message
   
4. api-server Service → api-server Pod
   
5. API Server (FastAPI) processes:
   ┌──────────────────────────────────────────────────────────┐
   │  API Server Internal Processing                          │
   │  ══════════════════════════════════════                  │
   │                                                           │
   │  Step 5a: Authentication                                  │
   │  ────────────────────────                                 │
   │  • Checks session cookie                                  │
   │  • Queries Redis: GET session:abc123xyz                  │
   │  • Gets user_id: 42                                       │
   │  • User authenticated ✅                                  │
   │                                                           │
   │  Step 5b: Create/Get Chat Session                        │
   │  ──────────────────────────────                           │
   │  • Queries PostgreSQL: INSERT INTO chat_sessions          │
   │  • Creates new chat session                               │
   │  • chat_session_id: 789                                   │
   │                                                           │
   │  Step 5c: Save User Message                              │
   │  ────────────────────────                                 │
   │  • Queries PostgreSQL: INSERT INTO messages               │
   │  • Saves: "What is our vacation policy?"                  │
   │  • message_id: 1234                                       │
   │                                                           │
   │  Step 5d: Generate Query Embedding                       │
   │  ───────────────────────────                              │
   │  • Calls Inference Model Server:                          │
   │    POST http://inference-model-server:9000/embed          │
   │    Body: {                                                │
   │      "texts": ["What is our vacation policy?"]           │
   │    }                                                      │
   │                                                           │
   │  • inference-model-server Pod receives request            │
   │  • Loads model from NFS-mounted PVC:                      │
   │    /app/.cache/huggingface/models--nomic-ai--nomic-...   │
   │  • Converts text to 768-dimensional vector:               │
   │    [0.123, -0.456, 0.789, ..., 0.321]                    │
   │  • Returns embedding (~100ms)                             │
   │                                                           │
   │  Step 5e: Search Vespa for Relevant Documents            │
   │  ──────────────────────────────────────────               │
   │  • API Server receives embedding from model server        │
   │  • Calls Vespa:                                           │
   │    POST http://vespa:8081/search/                         │
   │    Body: {                                                │
   │      "yql": "select * from docs...",                      │
   │      "ranking.features.query(embedding)": [0.123, ...]   │
   │    }                                                      │
   │                                                           │
   │  • Vespa Pod searches vector index                        │
   │  • Finds top 10 similar document chunks:                  │
   │    [                                                      │
   │      {text: "Employees receive 15 days...", score: 0.95},│
   │      {text: "Vacation must be approved...", score: 0.87},│
   │      {text: "PTO accrues monthly...", score: 0.82},      │
   │      ...                                                  │
   │    ]                                                      │
   │  • Returns results (~50ms)                                │
   │                                                           │
   │  Step 5f: Build Context from Chunks                      │
   │  ────────────────────────────────                         │
   │  • API Server receives chunks from Vespa                  │
   │  • Combines into context string:                          │
   │    "Context: Employees receive 15 days... Vacation must..."│
   │                                                           │
   │  Step 5g: Query Metadata from PostgreSQL                 │
   │  ─────────────────────────────────────                    │
   │  • Gets document sources/citations                        │
   │  • Queries: SELECT * FROM documents WHERE id IN (...)    │
   │                                                           │
   │  Step 5h: Call External LLM                              │
   │  ───────────────────────                                  │
   │  • Prepares LLM request with context + question           │
   │  • Calls external LLM (vLLM in another namespace)         │
   │    POST http://vllm-service.vllm-namespace:8000/v1/chat/completions│
   │    Body: {                                                │
   │      "model": "meta-llama/Meta-Llama-3-8B-Instruct",     │
   │      "messages": [                                        │
   │        {                                                  │
   │          "role": "system",                                │
   │          "content": "You are a helpful assistant..."     │
   │        },                                                 │
   │        {                                                  │
   │          "role": "user",                                  │
   │          "content": "Context:\n---\nEmployees receive... │
   │                      \n---\nQuestion: What is our       │
   │                      vacation policy?"                    │
   │        }                                                  │
   │      ],                                                   │
   │      "max_tokens": 500,                                   │
   │      "temperature": 0.7                                   │
   │    }                                                      │
   │                                                           │
   │  • vLLM Pod (in vllm-namespace) processes:               │
   │    - Receives request                                     │
   │    - Loads Llama model into GPU/CPU                       │
   │    - Generates answer token-by-token                      │
   │    - Returns: "Based on your company policy..."          │
   │  • Time: ~2-10 seconds (depending on model/hardware)     │
   │                                                           │
   │  Step 5i: Save AI Response                               │
   │  ───────────────────────                                  │
   │  • API Server receives LLM response                       │
   │  • Saves to PostgreSQL: INSERT INTO messages              │
   │  • Saves to Redis cache (for 5 minutes)                   │
   │                                                           │
   │  Step 5j: Return Response to User                        │
   │  ──────────────────────────────                           │
   │  • Formats response with citations                        │
   │  • Returns JSON to browser                                │
   └──────────────────────────────────────────────────────────┘
   
6. Response flows back:
   API Server → nginx Pod → nginx Service → OpenShift Route → Browser
   
7. Browser JavaScript receives response:
   {
     "message": "Based on your company policy, employees receive 15 days...",
     "citations": [...],
     "chat_session_id": 789
   }
   
8. React app updates UI:
   • Displays AI answer
   • Shows citations/sources
   • Updates chat history
   
9. User sees: AI-generated answer! 🎉

Total Time: ~3-12 seconds
```

---

## 🌐 Network Routes & Connections Summary

### All HTTP Routes Through NGINX

```
┌─────────────────────────────────────────────────────────────────────┐
│              NGINX ROUTING RULES (Complete List)                    │
└─────────────────────────────────────────────────────────────────────┘

Route 1: Homepage & Static Pages
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Request: GET /
Routing: NGINX → web-server:3000
Purpose: Serve Next.js UI
Examples:
• GET / → Login page
• GET /chat → Chat interface
• GET /search → Search page
• GET /admin → Admin panel


Route 2: API Endpoints
━━━━━━━━━━━━━━━━━━━━━
Request: POST/GET /api/*
Routing: NGINX → api-server:8080
Purpose: Backend API calls
Examples:
• POST /api/auth/login → User login
• POST /api/chat/send-message → Send chat message
• POST /api/query/stream-answer → Search with AI
• GET /api/user → Get user info
• POST /api/connector/create → Create data connector


Route 3: WebSocket Streaming
━━━━━━━━━━━━━━━━━━━━━━━━━━━
Request: WS /api/stream
Routing: NGINX → api-server:8080 (upgraded to WebSocket)
Purpose: Real-time streaming responses
Example:
• WS /api/stream → Stream LLM response token-by-token


Route 4: Health Check
━━━━━━━━━━━━━━━━━━━━━
Request: GET /nginx-health
Routing: NGINX (responds directly)
Purpose: NGINX liveness check
Returns: 200 OK "healthy"
```

---

### Internal Service-to-Service Connections

```
┌─────────────────────────────────────────────────────────────────────┐
│           INTERNAL SERVICE COMMUNICATION (DNS Names)                │
└─────────────────────────────────────────────────────────────────────┘

From Web Server:
━━━━━━━━━━━━━━━━
• To API Server: http://api-server:8080
  (Next.js server-side calls API for data)


From API Server:
━━━━━━━━━━━━━━━━
• To PostgreSQL: postgresql:5432
  Protocol: PostgreSQL wire protocol
  Purpose: Store/retrieve data
  
• To Redis: redis:6379
  Protocol: Redis protocol
  Purpose: Cache, sessions, task queue
  
• To Vespa: vespa:8081 (query) / vespa:19071 (feed)
  Protocol: HTTP/gRPC
  Purpose: Vector search, document retrieval
  
• To Inference Model Server: http://inference-model-server:9000
  Protocol: HTTP (REST API)
  Purpose: Generate query embeddings
  Endpoint: POST /embed
  
• To External LLM: http://vllm-service.vllm-namespace:8000
  Protocol: HTTP (OpenAI-compatible API)
  Purpose: Generate AI answers
  Endpoint: POST /v1/chat/completions
  
• To Indexing Model Server: http://indexing-model-server:9000
  Protocol: HTTP (REST API)
  Purpose: Generate document embeddings (if background workers deployed)


Kubernetes DNS Resolution:
━━━━━━━━━━━━━━━━━━━━━━━━━━

Service Name: postgresql
Full DNS: postgresql.onyx-infra.svc.cluster.local
Short Name: postgresql (works within same namespace)
Resolves to: ClusterIP (e.g., 10.96.123.45)

Service Name: inference-model-server
Full DNS: inference-model-server.onyx-infra.svc.cluster.local
Short Name: inference-model-server (works within same namespace)
Resolves to: ClusterIP (e.g., 10.96.123.50)

Cross-Namespace (for vLLM):
Service Name: vllm-service.vllm-namespace
Full DNS: vllm-service.vllm-namespace.svc.cluster.local
Must use: Namespace qualifier (vllm-namespace)
```

---

## 🔄 Complete Request Flow - Detailed

### Example: "What is our vacation policy?"

```
╔═══════════════════════════════════════════════════════════════════════════╗
║              COMPLETE REQUEST FLOW (Every Network Hop)                    ║
╚═══════════════════════════════════════════════════════════════════════════╝


TIME  │  COMPONENT                    │  ACTION
──────┼───────────────────────────────┼────────────────────────────────────
00:00 │  User Browser                 │  User types question, clicks Send
      │  Location: User's laptop      │
      ↓
00:01 │  Browser JavaScript           │  Sends AJAX request:
      │  (React app)                  │  POST /api/chat/send-message
      │                               │  Headers: Cookie, Content-Type
      │                               │  Body: {"message": "What is..."}
      ↓
00:02 │  DNS Resolution               │  Resolves:
      │                               │  nginx-onyx-infra.apps.cluster...
      │                               │  → OpenShift Router IP
      ↓
00:03 │  OpenShift Router             │  Receives HTTP request
      │  (HAProxy/Ingress)            │  Checks route table
      │                               │  Finds: route "nginx" matches hostname
      │                               │  Forwards to: nginx Service
      ↓
00:04 │  Service: nginx               │  ClusterIP: 10.96.100.10
      │  Port: 80                     │  Selects pod: nginx-abc123
      │                               │  Forwards to: nginx Pod port 80
      ↓
00:05 │  Pod: nginx-abc123            │  NGINX receives request
      │  Container: nginx             │  Path: /api/chat/send-message
      │  IP: 10.244.0.50              │  Checks nginx.conf routing:
      │                               │  location /api/ → upstream api_server
      │                               │  Proxies to: http://api-server:8080
      ↓
00:06 │  DNS: api-server              │  Resolves to: 10.96.100.20
      ↓
00:07 │  Service: api-server          │  ClusterIP: 10.96.100.20
      │  Port: 8080                   │  Selects pod: api-server-xyz789
      │                               │  Forwards to: api-server Pod
      ↓
00:08 │  Pod: api-server-xyz789       │  FastAPI receives request
      │  Container: onyx-backend      │  Endpoint: /api/chat/send-message
      │  IP: 10.244.0.51              │  Handler: chat_router.send_message()
      ↓
00:09 │  API → PostgreSQL             │  Connection: postgresql:5432
      │                               │  Query: INSERT INTO messages
      │                               │  Query: SELECT user permissions
      │                               │  Response: 20ms
      ↓
00:10 │  API → Redis                  │  Connection: redis:6379
      │                               │  Check cache: GET query:hash
      │                               │  Cache MISS
      │                               │  Response: 5ms
      ↓
00:11 │  API → Inference Model Server │  POST http://inference-model-server:9000/embed
      │                               │  Body: {"texts": ["What is our vacation..."]}
      ↓
00:12 │  DNS: inference-model-server  │  Resolves to: 10.96.100.30
      ↓
00:13 │  Service: inference-model-    │  ClusterIP: 10.96.100.30
      │  server, Port: 9000           │  Forwards to: inference-model-server Pod
      ↓
00:14 │  Pod: inference-model-        │  FastAPI receives /embed request
      │  server-mmm999                │  Loads model from:
      │  IP: 10.244.0.52              │  /app/.cache/huggingface/ (NFS PVC!)
      │                               │  
      │  Model Server Processing:     │  
      │  ────────────────────────     │  
      │  • Loads nomic-embed-text-v1  │  (from NFS)
      │  • Tokenizes text             │
      │  • Runs neural network        │
      │  • Generates 768-dim vector   │
      │  • Returns: [0.123, -0.456, ...]  (~100ms)
      ↓
00:15 │  API Server (back)            │  Receives embedding vector
      │                               │  Now searches Vespa
      ↓
00:16 │  API → Vespa                  │  POST http://vespa:8081/search/
      │                               │  Body: vector + query parameters
      ↓
00:17 │  DNS: vespa                   │  Resolves to: vespa-0.vespa (StatefulSet)
      │                               │  IP: 10.244.0.53
      ↓
00:18 │  Service: vespa               │  Headless service
      │  Port: 8081                   │  Routes to: vespa-0 Pod
      ↓
00:19 │  Pod: vespa-0                 │  Vespa receives search request
      │  Container: vespaengine       │  
      │  IP: 10.244.0.53              │  Vespa Processing:
      │                               │  ─────────────────
      │                               │  • Vector similarity search
      │                               │  • Compares query embedding with
      │                               │    stored document embeddings
      │                               │  • Ranks by similarity score
      │                               │  • Returns top 10 chunks
      │                               │  Response: ~50ms
      ↓
00:20 │  API Server (back)            │  Receives 10 document chunks
      │                               │  Builds prompt for LLM:
      │                               │  
      │                               │  System: "You are helpful..."
      │                               │  Context: "<chunk1><chunk2>..."
      │                               │  Question: "What is our vacation..."
      ↓
00:21 │  API → External LLM           │  POST http://vllm-service.vllm-namespace:8000
      │  (vLLM in another namespace)  │       /v1/chat/completions
      │                               │  
      │                               │  Body: {
      │                               │    "model": "llama3...",
      │                               │    "messages": [system, user],
      │                               │    "max_tokens": 500
      │                               │  }
      ↓
00:22 │  DNS: vllm-service.vllm-      │  Cross-namespace DNS resolution
      │  namespace                    │  Resolves to: 10.96.200.50
      ↓
00:23 │  Service: vllm-service        │  ClusterIP: 10.96.200.50
      │  (in vllm-namespace)          │  Port: 8000
      │  Port: 8000                   │  Forwards to: vllm Pod
      ↓
00:24 │  Pod: vllm-server-xxx         │  vLLM receives request
      │  (in vllm-namespace)          │  
      │  Container: vllm/vllm-openai  │  LLM Processing:
      │  IP: 10.244.1.100             │  ────────────────
      │                               │  • Receives context + question
      │                               │  • Loads Llama-3-8B model (GPU)
      │                               │  • Generates tokens:
      │                               │    "Based" "on" "your" "company"...
      │                               │  • Returns complete answer
      │                               │  Response: ~2-10 seconds
      ↓
00:34 │  API Server (back)            │  Receives LLM response:
      │                               │  {
      │                               │    "choices": [{
      │                               │      "message": {
      │                               │        "content": "Based on your
      │                               │         company policy, employees
      │                               │         receive 15 days of vacation..."
      │                               │      }
      │                               │    }]
      │                               │  }
      ↓
00:35 │  API → PostgreSQL             │  INSERT INTO messages (AI response)
      │                               │  Response: 20ms
      ↓
00:36 │  API → Redis                  │  SET query:hash response (cache)
      │                               │  Response: 5ms
      ↓
00:37 │  API Server                   │  Formats final response with:
      │                               │  • AI answer
      │                               │  • Citations/sources
      │                               │  • Chat session ID
      │                               │  • Message IDs
      │                               │  Returns JSON to nginx
      ↓
00:38 │  nginx Pod                    │  Receives response from API
      │                               │  Forwards back to client
      ↓
00:39 │  OpenShift Route              │  Forwards response
      ↓
00:40 │  User Browser                 │  JavaScript receives JSON response
      │                               │  React updates UI:
      │                               │  • Displays answer in chat
      │                               │  • Shows citations
      │                               │  • Updates chat history
      ↓
00:40 │  👤 USER                       │  SEES AI ANSWER! 🎉


TOTAL TIME: ~40 seconds (worst case)
            ~3-5 seconds (with caching and fast LLM)
```

---

## 📊 Service Connection Matrix

```
┌─────────────────────────────────────────────────────────────────────┐
│              WHO TALKS TO WHO (Complete Matrix)                     │
└─────────────────────────────────────────────────────────────────────┘

FROM              TO                        PORT    PROTOCOL  PURPOSE
────────────────  ────────────────────────  ──────  ────────  ─────────────
User Browser   →  OpenShift Route           80/443  HTTP(S)   Access UI
OpenShift Route→  nginx Service             80      HTTP      Route traffic
nginx Service  →  nginx Pod                 80      HTTP      Load balance
nginx Pod      →  web-server Service        3000    HTTP      Serve UI
nginx Pod      →  api-server Service        8080    HTTP      API calls
web-server Pod →  api-server Service        8080    HTTP      Server-side API
api-server Pod →  postgresql Service        5432    PostgreSQL Data queries
api-server Pod →  redis Service             6379    Redis     Cache/sessions
api-server Pod →  vespa Service             8081    HTTP      Search docs
api-server Pod →  inference-model-server    9000    HTTP      Embed queries
api-server Pod →  vllm-service.vllm-ns     8000    HTTP      LLM inference
api-server Pod →  indexing-model-server     9000    HTTP      Embed docs*
vespa Pod      →  NFS (via PVC)             -       NFS       Store vectors
inference Pod  →  NFS (via PVC)             -       NFS       Load models
indexing Pod   →  NFS (via PVC)             -       NFS       Load models
postgresql Pod →  NFS (via PVC)             -       NFS       Store DB data

* Only if background workers are deployed (not in minimal setup)
```

---

## 🚪 Accessing Onyx UI - The Simple Way

### For Testing in OpenShift

```
┌─────────────────────────────────────────────────────────────────────┐
│              SIMPLEST WAY TO ACCESS ONYX (For Testing)              │
└─────────────────────────────────────────────────────────────────────┘

Step 1: Deploy Everything
━━━━━━━━━━━━━━━━━━━━━━━━━━

oc apply -f storage-setup/01-pv-huggingface-models.yaml
oc apply -f storage-setup/02-pvc-huggingface-models.yaml
oc apply -f 02-postgresql.yaml
oc apply -f 03-vespa.yaml
oc apply -f 04-redis.yaml
oc apply -f 05-configmap.yaml
oc apply -f 06-inference-model-server.yaml
oc apply -f 06-indexing-model-server.yaml
oc apply -f 07-api-server.yaml
oc apply -f 08-web-server.yaml
oc apply -f 09-nginx.yaml

Wait for all pods to be Running:
oc get pods


Step 2: Create OpenShift Route
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# One command!
oc expose svc/nginx

# Check the route
oc get route nginx

# Output:
# NAME    HOST/PORT                                              PATH   SERVICES
# nginx   nginx-onyx-infra.apps.cluster.company.com             /      nginx


Step 3: Access in Browser
━━━━━━━━━━━━━━━━━━━━━━━━━━

Open: http://nginx-onyx-infra.apps.cluster.company.com

You should see: Onyx login page! ✅


Step 4: Login and Test
━━━━━━━━━━━━━━━━━━━━━━

Default credentials (if using basic auth):
• Email: admin@company.com (or create your own)
• Password: (set via environment variable)

After login:
• Navigate to Chat
• Ask a question
• See AI response!
```

---

## 🔍 Port Summary (All Services)

```
┌─────────────────────────────────────────────────────────────────────┐
│                   ALL PORTS IN THE SYSTEM                           │
└─────────────────────────────────────────────────────────────────────┘

External (Accessible from Browser):
═══════════════════════════════════
• OpenShift Route → NGINX: 80 (HTTP) / 443 (HTTPS)
  URL: http://nginx-onyx-infra.apps.cluster.company.com


Internal (Pod to Pod Communication):
═══════════════════════════════════════
• nginx → web-server: 3000 (Next.js)
• nginx → api-server: 8080 (FastAPI)
• api-server → postgresql: 5432 (PostgreSQL)
• api-server → redis: 6379 (Redis)
• api-server → vespa: 8081 (HTTP query), 19071 (HTTP feed)
• api-server → inference-model-server: 9000 (HTTP)
• api-server → indexing-model-server: 9000 (HTTP)
• api-server → vllm (external): 8000 (HTTP)


Storage (NFS):
═══════════════
• Cluster nodes → NFS server: 2049 (NFS protocol)
  Server: 10.100.50.20:/exports/huggingface-models
```

---

## 🎓 Key Concepts for Functional UI

### What You Need for UI to Work

```
┌─────────────────────────────────────────────────────────────────────┐
│              MINIMUM REQUIREMENTS FOR FUNCTIONAL UI                 │
└─────────────────────────────────────────────────────────────────────┘

Layer 1: External Access
━━━━━━━━━━━━━━━━━━━━━━━━━
✅ OpenShift Route (created with `oc expose svc/nginx`)
✅ NGINX Service (ClusterIP)
✅ NGINX Pod (running)


Layer 2: Frontend
━━━━━━━━━━━━━━━━━
✅ Web Server Service
✅ Web Server Pod (Next.js)
✅ Can connect to API Server


Layer 3: Backend
━━━━━━━━━━━━━━━
✅ API Server Service
✅ API Server Pod (FastAPI)
✅ Environment variables configured (ConfigMap)


Layer 4: Data Storage
━━━━━━━━━━━━━━━━━━━
✅ PostgreSQL (for users, chat history)
✅ Redis (for sessions, cache)
✅ Vespa (for document search)


Layer 5: AI/ML
━━━━━━━━━━━━━━
✅ Inference Model Server (for search embeddings)
✅ NFS PVC with models (so model server works)
✅ External LLM configured (vLLM or OpenAI)


If ANY of these is missing → Something won't work!
```

---

## 🐛 Troubleshooting - What If It Doesn't Work?

### UI Doesn't Load (Blank Page)

```
Symptom: Browser shows nothing or loading forever
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Check:
1. Is route created?
   oc get route nginx
   
2. Is nginx pod running?
   oc get pods -l app=nginx
   
3. Is web-server pod running?
   oc get pods -l app=web-server
   
4. Check nginx logs:
   oc logs deployment/nginx
   
5. Check web-server logs:
   oc logs deployment/web-server
```

### UI Loads but Can't Login

```
Symptom: Login page appears but login fails
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Check:
1. Is api-server pod running?
   oc get pods -l app=api-server
   
2. Is postgresql pod running?
   oc get pods -l app=postgresql
   
3. Check api-server logs:
   oc logs deployment/api-server
   
4. Test API directly:
   oc exec deployment/nginx -- curl http://api-server:8080/health
```

### Can Login but Search Doesn't Work

```
Symptom: Can login, navigate UI, but search/chat fails
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Check:
1. Is vespa pod running?
   oc get pods -l app=vespa
   
2. Is inference-model-server running?
   oc get pods -l app=inference-model-server
   
3. Are models loaded from NFS?
   oc logs deployment/inference-model-server | grep "loaded model"
   Should see: "Loaded model from local cache"
   
4. Is PVC bound?
   oc get pvc huggingface-models-pvc
   Should see: STATUS = Bound
```

### Can Search but LLM Doesn't Respond

```
Symptom: Search works, but AI doesn't generate answers
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Check:
1. Is LLM configured in Onyx UI?
   Settings → LLM Configuration
   
2. Can API server reach external LLM?
   oc exec deployment/api-server -- curl http://vllm-service.vllm-namespace:8000/health
   
3. Check api-server logs for LLM errors:
   oc logs deployment/api-server | grep -i llm
```

---

## ✅ Complete Deployment & Testing Checklist

### Pre-Deployment

- [ ] Get NFS IP and path from colleague
- [ ] Update `storage-setup/01-pv-huggingface-models.yaml` with NFS details
- [ ] Verify you're in correct namespace: `oc project`

### Deploy Infrastructure

```bash
# 1. Storage
oc apply -f storage-setup/01-pv-huggingface-models.yaml
oc apply -f storage-setup/02-pvc-huggingface-models.yaml
oc get pvc huggingface-models-pvc  # Wait for Bound

# 2. Databases
oc apply -f 02-postgresql.yaml
oc apply -f 03-vespa.yaml
oc apply -f 04-redis.yaml

# Wait for ready
oc get pods -w
# Wait for: postgresql, vespa-0, redis all Running
```

### Deploy Application

```bash
# 3. Configuration
oc apply -f 05-configmap.yaml

# 4. Model Servers
oc apply -f 06-inference-model-server.yaml
oc apply -f 06-indexing-model-server.yaml

# Wait for models to load (check logs)
oc logs -f deployment/inference-model-server
# Should see: "Loaded model from local cache" (not "Downloading")

# 5. API & Web
oc apply -f 07-api-server.yaml
oc apply -f 08-web-server.yaml

# 6. NGINX
oc apply -f 09-nginx.yaml
```

### Expose Externally

```bash
# Create route
oc expose svc/nginx

# Get URL
oc get route nginx

# Access in browser
# http://nginx-<namespace>.apps.<cluster-domain>
```

### Verify Each Layer

```bash
# Check all pods running
oc get pods
# All should be: STATUS = Running, READY = 1/1

# Test web server
oc exec deployment/nginx -- curl -s http://web-server:3000 | grep -i onyx

# Test API server
oc exec deployment/nginx -- curl -s http://api-server:8080/health

# Test model server
oc exec deployment/api-server -- curl -s http://inference-model-server:9000/health

# Test database
oc exec deployment/api-server -- curl -s http://postgresql:5432
# (Will fail, but should connect - error is OK)
```

---

## 🎯 Summary

### The Complete Flow (TL;DR)

```
User Browser
    ↓ (HTTP)
OpenShift Route (nginx-onyx-infra.apps.cluster.company.com)
    ↓
NGINX Service (ClusterIP)
    ↓
NGINX Pod (reverse proxy)
    ├─ / → web-server:3000 (UI)
    └─ /api/* → api-server:8080 (API)
        ↓
    API Server Pod
        ├─ postgresql:5432 (user data, metadata)
        ├─ redis:6379 (cache, sessions)
        ├─ vespa:8081 (vector search)
        ├─ inference-model-server:9000 (embeddings from NFS models)
        └─ vllm-service.vllm-namespace:8000 (LLM answers)
            ↓
        Response flows back
            ↓
    User sees AI answer! ✅
```

### Essential Routes

1. **External:** Browser → OpenShift Route (`oc expose svc/nginx`)
2. **Frontend:** NGINX → web-server:3000
3. **API:** NGINX → api-server:8080
4. **Search:** API → vespa:8081
5. **Embeddings:** API → inference-model-server:9000
6. **LLM:** API → vllm-service.vllm-namespace:8000
7. **Models:** inference-model-server → NFS PVC (offline!)

### Critical Components

✅ OpenShift Route (for external access)
✅ NGINX (reverse proxy)
✅ Web Server (UI)
✅ API Server (backend)
✅ Inference Model Server (embeddings)
✅ Vespa (search)
✅ PostgreSQL (data)
✅ Redis (cache)
✅ NFS PVC (models)
✅ External LLM (answers)

**All connected and working together to deliver AI-powered search!** 🎉

