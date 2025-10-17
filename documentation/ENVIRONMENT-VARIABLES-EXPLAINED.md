# Environment Variables Complete Guide

**Complete explanation of all Onyx environment variables, their purpose, and architecture flow**

---

## 📚 Table of Contents

1. [Overview](#overview)
2. [Architecture Diagram](#architecture-diagram)
3. [Variable Categories](#variable-categories)
4. [Detailed Variable Explanations](#detailed-variable-explanations)
5. [Service-Specific Usage](#service-specific-usage)
6. [Production Configuration](#production-configuration)

---

## 1. Overview

The `onyx-config` ConfigMap contains all environment variables needed by Onyx services. This document explains:
- What each variable does
- Which services use it
- Why it's needed
- How to configure it for production

**ConfigMap Location:** `manifests/05-configmap.yaml`

---

## 2. Architecture Diagram

### Complete Variable Flow Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         ONYX KUBERNETES DEPLOYMENT                           │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │                       onyx-config ConfigMap                         │    │
│  │  ┌──────────────────────────────────────────────────────────────┐  │    │
│  │  │ POSTGRES_HOST, POSTGRES_PORT, POSTGRES_DB                    │  │    │
│  │  │ REDIS_HOST, REDIS_PORT                                        │  │    │
│  │  │ VESPA_HOST                                                    │  │    │
│  │  │ MODEL_SERVER_HOST, MODEL_SERVER_PORT                         │  │    │
│  │  │ INTERNAL_URL, WEB_DOMAIN, DOMAIN                            │  │    │
│  │  │ AUTH_TYPE, SESSION_EXPIRE_TIME_SECONDS                       │  │    │
│  │  │ DISABLE_GENERATIVE_AI, QA_TIMEOUT                           │  │    │
│  │  └──────────────────────────────────────────────────────────────┘  │    │
│  └────────────────┬────────────┬────────────┬──────────────┬──────────┘    │
│                   │            │            │              │                │
│                   ▼            ▼            ▼              ▼                │
│  ┌──────────────────┐ ┌──────────────┐ ┌────────────┐ ┌──────────────┐   │
│  │   API Server     │ │  Web Server  │ │  Workers   │ │ Model Servers│   │
│  │   (Backend)      │ │  (Frontend)  │ │  (Celery)  │ │  (AI/ML)     │   │
│  └────────┬─────────┘ └──────┬───────┘ └─────┬──────┘ └──────┬───────┘   │
│           │                  │               │                │            │
│           │ Uses:            │ Uses:         │ Uses:          │ Uses:      │
│           │ • POSTGRES_*     │ • INTERNAL_URL│ • POSTGRES_*   │ • (All     │
│           │ • REDIS_*        │ • WEB_DOMAIN  │ • REDIS_*      │    from    │
│           │ • VESPA_HOST     │ • DOMAIN      │ • VESPA_HOST   │    CM)     │
│           │ • MODEL_SERVER_* │ • AUTH_TYPE   │ • MODEL_SERVER_*│           │
│           │ • AUTH_TYPE      │               │                │            │
│           │ • QA_TIMEOUT     │               │                │            │
│           │                  │               │                │            │
│           ▼                  ▼               ▼                ▼            │
│  ┌────────────────────────────────────────────────────────────────────┐   │
│  │                       INFRASTRUCTURE LAYER                          │   │
│  │                                                                     │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │   │
│  │  │PostgreSQL│  │  Redis   │  │  Vespa   │  │  Model Servers   │  │   │
│  │  │  :5432   │  │  :6379   │  │  :19071  │  │     :9000        │  │   │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────────────┘  │   │
│  └────────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Variable Usage by Service

```
┌────────────────────────────────────────────────────────────────────────┐
│                     VARIABLE USAGE MATRIX                               │
└────────────────────────────────────────────────────────────────────────┘

Variable                    │ API │ Web │ Workers │ Models │ Purpose
───────────────────────────┼─────┼─────┼─────────┼────────┼───────────────
POSTGRES_HOST              │  ✓  │     │    ✓    │        │ DB connection
POSTGRES_PORT              │  ✓  │     │    ✓    │        │ DB port
POSTGRES_DB                │  ✓  │     │    ✓    │        │ DB name
                           │     │     │         │        │
REDIS_HOST                 │  ✓  │     │    ✓    │        │ Cache/Queue
REDIS_PORT                 │  ✓  │     │    ✓    │        │ Cache port
                           │     │     │         │        │
VESPA_HOST                 │  ✓  │     │    ✓    │        │ Vector DB
                           │     │     │         │        │
MODEL_SERVER_HOST          │  ✓  │     │    ✓    │   ✓    │ Embeddings
MODEL_SERVER_PORT          │  ✓  │     │    ✓    │   ✓    │ Embed port
                           │     │     │         │        │
INTERNAL_URL               │     │  ✓  │         │        │ SSR API calls
WEB_DOMAIN                 │  ✓  │  ✓  │         │        │ CORS/redirects
DOMAIN                     │  ✓  │  ✓  │         │        │ Cookie domain
                           │     │     │         │        │
AUTH_TYPE                  │  ✓  │  ✓  │         │        │ Auth method
SESSION_EXPIRE_TIME_SECONDS│  ✓  │  ✓  │         │        │ Session TTL
                           │     │     │         │        │
DISABLE_GENERATIVE_AI      │  ✓  │  ✓  │         │        │ Feature flag
QA_TIMEOUT                 │  ✓  │     │         │        │ Query timeout
```

---

## 3. Variable Categories

### 🗄️ Database Configuration
- `POSTGRES_HOST`
- `POSTGRES_PORT`
- `POSTGRES_DB`

### 💾 Cache & Message Broker
- `REDIS_HOST`
- `REDIS_PORT`

### 🔍 Vector Search
- `VESPA_HOST`

### 🤖 AI/ML Services
- `MODEL_SERVER_HOST`
- `MODEL_SERVER_PORT`

### 🌐 Network & Routing
- `INTERNAL_URL`
- `WEB_DOMAIN`
- `DOMAIN`

### 🔐 Authentication
- `AUTH_TYPE`
- `SESSION_EXPIRE_TIME_SECONDS`

### ⚙️ Feature Flags & Settings
- `DISABLE_GENERATIVE_AI`
- `QA_TIMEOUT`

---

## 4. Detailed Variable Explanations

### 🗄️ Database Configuration

#### `POSTGRES_HOST`
```yaml
POSTGRES_HOST: "postgresql"
```

**What it does:**
- Specifies the hostname/service name of PostgreSQL database
- Used to establish database connections

**Used by:**
- ✅ API Server (for all database operations)
- ✅ Background Workers (for task processing)
- ✅ Alembic migrations (initContainer in API server)

**Data stored in PostgreSQL:**
1. **User Management**
   - User accounts, passwords (hashed), profiles
   - Roles and permissions
   - OAuth tokens
   
2. **Document Metadata**
   - Document IDs, names, sources
   - Upload timestamps, ownership
   - Access permissions and sharing settings
   
3. **Connector Configurations**
   - Data source connections (Google Drive, Slack, etc.)
   - Sync schedules and credentials (encrypted)
   - Last sync timestamps
   
4. **Chat History**
   - Chat sessions and messages
   - User feedback and ratings
   - Conversation context
   
5. **System Configuration**
   - LLM provider settings
   - Persona configurations
   - Feature flags and settings

**Flow Diagram:**
```
API Server/Workers
      │
      │ Connects using:
      │ postgres://user:pass@POSTGRES_HOST:POSTGRES_PORT/POSTGRES_DB
      ▼
┌─────────────────┐
│   PostgreSQL    │
│   Service       │
│   (postgresql)  │
└─────────────────┘
      ↓
   Stores:
   - Users
   - Documents
   - Settings
```

**Production Notes:**
- Change to fully qualified name if using external database
- Example: `my-postgres-cluster.us-east-1.rds.amazonaws.com`

---

#### `POSTGRES_PORT`
```yaml
POSTGRES_PORT: "5432"
```

**What it does:**
- Specifies the port PostgreSQL listens on
- Standard PostgreSQL port is 5432

**Why needed:**
- Different environments might use different ports
- Allows flexibility in database configuration

**Used by:** Same services as `POSTGRES_HOST`

---

#### `POSTGRES_DB`
```yaml
POSTGRES_DB: "postgres"
```

**What it does:**
- Specifies which database name to use within PostgreSQL
- PostgreSQL can host multiple databases

**Why needed:**
- Allows multiple applications to share one PostgreSQL instance
- Isolates Onyx data from other databases

**Used by:** Same services as `POSTGRES_HOST`

---

### 💾 Cache & Message Broker

#### `REDIS_HOST` and `REDIS_PORT`
```yaml
REDIS_HOST: "redis"
REDIS_PORT: "6379"
```

**What it does:**
Redis serves **TWO critical roles** in Onyx:

**Role 1: Cache (Fast Data Storage)**
- API response caching
- User session data
- LLM response caching (saves money & time)
- Rate limiting counters
- Temporary data storage

**Role 2: Message Broker (Task Queue)**
- Celery task queue for background jobs
- Task results and status
- Worker coordination
- Inter-process communication
- **Alembic migration locking** (prevents concurrent migrations!)

**Used by:**
- ✅ API Server (caching, session management)
- ✅ Background Workers (task queue, coordination)
- ✅ Alembic (migration locking - this is why API server initContainer needs Redis!)

**Why Alembic needs Redis:**
```
Multiple API Server Pods Starting Simultaneously
     │
     ├─► Pod 1: alembic upgrade head
     ├─► Pod 2: alembic upgrade head  ← Both try to migrate at once!
     └─► Pod 3: alembic upgrade head
              ↓
       ❌ RACE CONDITION! Database corruption possible
              ↓
       Redis provides locking:
       - Only ONE pod runs migrations
       - Others wait until first pod completes
       - Safe concurrent startups ✅
```

**Flow Diagram:**
```
┌──────────────┐        ┌──────────────┐        ┌──────────────┐
│  API Server  │        │   Workers    │        │   Alembic    │
└──────┬───────┘        └──────┬───────┘        └──────┬───────┘
       │                       │                       │
       │ 1. Cache responses    │ 2. Get tasks         │ 3. Lock
       │ 2. Store sessions     │ 3. Store results     │    migrations
       │                       │                       │
       └───────────────────────┴───────────────────────┘
                               │
                               ▼
                        ┌─────────────┐
                        │    Redis    │
                        │   Service   │
                        │   (:6379)   │
                        └─────────────┘
                               │
                   ┌───────────┴───────────┐
                   │                       │
                   ▼                       ▼
          ┌────────────────┐      ┌────────────────┐
          │  Cache Store   │      │  Task Queue    │
          │  - Sessions    │      │  - Pending     │
          │  - API cache   │      │  - In Progress │
          │  - LLM cache   │      │  - Completed   │
          └────────────────┘      └────────────────┘
```

**Celery Tasks Using Redis:**
- Document indexing
- Connector synchronization
- Document pruning
- Permission sync
- Email notifications
- Scheduled cleanup tasks

**Production Notes:**
- Consider Redis Sentinel or Cluster for high availability
- Set appropriate memory limits
- Configure persistence if needed (currently ephemeral)

---

### 🔍 Vector Search

#### `VESPA_HOST`
```yaml
VESPA_HOST: "vespa-0.vespa-service"
```

**What it does:**
- Points to Vespa vector database
- Vespa stores document chunks and their embeddings

**Format explained:**
- `vespa-0`: First pod in StatefulSet (pod-0)
- `vespa-service`: Headless service name
- StatefulSets get predictable pod names: `vespa-0`, `vespa-1`, etc.

**Data stored in Vespa:**
1. **Document Chunks**
   - Text segments (typically 512 tokens)
   - Original document references
   - Chunk metadata
   
2. **Embeddings (Vectors)**
   - 768-dimensional vectors (for MiniLM)
   - Generated by model servers
   - Enable semantic search
   
3. **Search Metadata**
   - Document source
   - Timestamps
   - Access permissions
   - Custom metadata

**Used by:**
- ✅ API Server (for search queries)
- ✅ Background Workers (for indexing documents)

**Flow Diagram:**
```
User Query: "What is our vacation policy?"
      │
      ▼
┌─────────────────┐
│   API Server    │
└────────┬────────┘
         │
         │ 1. Send query to model server
         ▼
┌─────────────────────┐
│ Inference Model     │
│ Server              │
└──────┬──────────────┘
       │
       │ 2. Returns embedding: [0.123, 0.456, ..., 0.789]
       ▼
┌─────────────────┐
│   API Server    │
└────────┬────────┘
         │
         │ 3. Search Vespa with embedding
         ▼
┌─────────────────┐
│  VESPA_HOST     │
│  (Vespa DB)     │
└────────┬────────┘
         │
         │ 4. Returns top 10 matching chunks
         ▼
    Relevant document
    chunks with context
```

**Indexing Flow:**
```
Background Worker
      │
      │ 1. Fetch document from connector
      ▼
┌─────────────────┐
│  Document Text  │
│  "Employees get"│
│  "15 days of..."│
└────────┬────────┘
         │
         │ 2. Chunk into segments
         ▼
┌─────────────────────┐
│ Indexing Model      │
│ Server              │
└──────┬──────────────┘
       │
       │ 3. Generate embeddings for each chunk
       ▼
┌─────────────────┐
│   Background    │
│     Worker      │
└────────┬────────┘
         │
         │ 4. Store chunks + embeddings
         ▼
┌─────────────────┐
│  VESPA_HOST     │
│  (Vespa DB)     │
└─────────────────┘
```

**Why Vespa:**
- Fast vector similarity search
- Hybrid search (keyword + semantic)
- Scales to millions of documents
- Rich query language
- Real-time indexing

---

### 🤖 AI/ML Services

#### `MODEL_SERVER_HOST` and `MODEL_SERVER_PORT`
```yaml
MODEL_SERVER_HOST: "inference-model-server"
MODEL_SERVER_PORT: "9000"
```

**What it does:**
- Points to the **Inference Model Server**
- Generates embeddings for real-time operations

**Important:** This is ONLY for the inference server
- Indexing server is accessed separately by workers
- Environment variable: `INDEXING_MODEL_SERVER_HOST` (handled internally)

**Inference vs Indexing:**
```
┌─────────────────────────────────────────────────────────────────────┐
│                  TWO MODEL SERVERS IN ONYX                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌───────────────────────────┐    ┌───────────────────────────┐   │
│  │  INFERENCE Model Server   │    │  INDEXING Model Server    │   │
│  │  (inference-model-server) │    │  (indexing-model-server)  │   │
│  ├───────────────────────────┤    ├───────────────────────────┤   │
│  │                           │    │                           │   │
│  │ Purpose:                  │    │ Purpose:                  │   │
│  │ • Real-time queries       │    │ • Bulk indexing           │   │
│  │ • User search             │    │ • Background processing   │   │
│  │ • Chat embeddings         │    │ • Document chunks         │   │
│  │                           │    │                           │   │
│  │ Used by:                  │    │ Used by:                  │   │
│  │ • API Server              │    │ • Background Workers      │   │
│  │                           │    │                           │   │
│  │ Priority:                 │    │ Priority:                 │   │
│  │ • LOW LATENCY (fast)      │    │ • HIGH THROUGHPUT (bulk)  │   │
│  │                           │    │                           │   │
│  │ Concurrency:              │    │ Concurrency:              │   │
│  │ • Unlimited (fast queries)│    │ • Limited to 4 (safe)     │   │
│  │                           │    │                           │   │
│  │ Command:                  │    │ Command:                  │   │
│  │ uvicorn ... --port 9000   │    │ uvicorn ... --port 9000   │   │
│  │                           │    │ --limit-concurrency 4     │   │
│  │                           │    │                           │   │
│  │ Env Var:                  │    │ Env Var:                  │   │
│  │ (none special)            │    │ INDEXING_ONLY=True        │   │
│  └───────────────────────────┘    └───────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

**Why TWO servers:**
1. **Resource Isolation**
   - Bulk indexing doesn't slow down user queries
   - Each server optimized for its workload
   
2. **Different Models (optional)**
   - Can use different embedding models
   - Different configurations
   
3. **Scalability**
   - Scale inference for more users
   - Scale indexing for more documents
   - Independent scaling

**Used by:**
- ✅ API Server (for user queries)
- ✅ Background Workers (use indexing server separately)
- ✅ Model Servers (inherit from ConfigMap)

---

### 🌐 Network & Routing

#### `INTERNAL_URL`
```yaml
INTERNAL_URL: "http://api-server:8080"
```

**What it does:**
- Provides URL for Web Server to call API Server
- Used for server-to-server communication
- Enables Server-Side Rendering (SSR)

**Why needed:**
Next.js (Web Server) runs in TWO places:
1. **Browser** (client-side)
2. **Server** (server-side rendering)

When running on server, it needs to know how to reach the API:

```
┌─────────────────────────────────────────────────────────────────┐
│                    NEXT.JS WEB SERVER                            │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  Server-Side Rendering (SSR)                           │    │
│  │                                                         │    │
│  │  User requests page → Next.js server fetches data     │    │
│  │  from API before rendering HTML                        │    │
│  │                                                         │    │
│  │  Uses INTERNAL_URL to call API:                       │    │
│  │  fetch(`${INTERNAL_URL}/api/documents`)              │    │
│  └────────────────────┬───────────────────────────────────┘    │
│                       │                                         │
└───────────────────────┼─────────────────────────────────────────┘
                        │
                        │ http://api-server:8080/api/documents
                        ▼
                ┌────────────────┐
                │   API Server   │
                │     :8080      │
                └────────────────┘
```

**Used by:**
- ✅ Web Server (Next.js backend for SSR)

**Production Notes:**
- Keep as internal service name if Web Server is in cluster
- Use external URL if Web Server is outside cluster

---

#### `WEB_DOMAIN`
```yaml
WEB_DOMAIN: "http://localhost:3000"
```

**What it does:**
- Full URL where Onyx UI is accessible to users
- Used for redirects, OAuth callbacks, email links

**Use cases:**
1. **OAuth Redirects**
   - After Google login: redirect to `${WEB_DOMAIN}/auth/callback`
   
2. **Email Links**
   - Password reset: `${WEB_DOMAIN}/reset-password?token=...`
   - Document shared: `${WEB_DOMAIN}/documents/123`
   
3. **CORS Configuration**
   - API Server allows requests from `WEB_DOMAIN`
   
4. **Webhooks**
   - External services callback to `${WEB_DOMAIN}/webhooks/...`

**Used by:**
- ✅ API Server (redirects, OAuth, CORS)
- ✅ Web Server (client-side configuration)

**Production Configuration:**
```yaml
# Development
WEB_DOMAIN: "http://localhost:3000"

# Production
WEB_DOMAIN: "https://onyx.company.com"
```

---

#### `DOMAIN`
```yaml
DOMAIN: "localhost"
```

**What it does:**
- Base domain without protocol
- Used for cookie domain and CORS origin

**Why needed:**
Cookies must be set for the correct domain:
```javascript
// API Server sets cookie:
Set-Cookie: session=abc123; Domain=.company.com

// This cookie works for:
// - onyx.company.com
// - api.company.com
// - www.company.com
```

**Used by:**
- ✅ API Server (cookie domain)
- ✅ Web Server (CORS validation)

**Production Configuration:**
```yaml
# Development
DOMAIN: "localhost"

# Production
DOMAIN: "company.com"  # Without subdomain!
```

---

### 🔐 Authentication

#### `AUTH_TYPE`
```yaml
AUTH_TYPE: "basic"
```

**What it does:**
- Specifies authentication method for user login

**Supported Types:**
1. **`basic`** (default)
   - Username/password authentication
   - Stored in PostgreSQL
   - No external dependencies
   
2. **`google_oauth`**
   - Google OAuth 2.0
   - Requires Google Cloud project
   - Users log in with Google accounts
   
3. **`oidc`**
   - OpenID Connect
   - Works with any OIDC provider (Okta, Auth0, etc.)
   - Enterprise SSO
   
4. **`saml`**
   - SAML 2.0
   - Enterprise SSO
   - Common in large organizations

**Flow for `basic` auth:**
```
User enters credentials
      │
      ▼
┌─────────────────┐
│   Web Server    │
└────────┬────────┘
         │
         │ POST /api/auth/login
         │ {username, password}
         ▼
┌─────────────────┐
│   API Server    │
└────────┬────────┘
         │
         │ 1. Check AUTH_TYPE = "basic"
         │ 2. Query PostgreSQL for user
         │ 3. Verify password hash
         │ 4. Create session in Redis
         ▼
    Session token
    returned to user
```

**Flow for OAuth:**
```
User clicks "Sign in with Google"
      │
      ▼
  Redirect to Google
      │
      ▼
  User approves
      │
      ▼
  Google redirects to WEB_DOMAIN/auth/callback
      │
      ▼
┌─────────────────┐
│   API Server    │
│ 1. Verify token │
│ 2. Get user info│
│ 3. Create/update│
│    user in DB   │
│ 4. Create session│
└─────────────────┘
```

**Used by:**
- ✅ API Server (authentication logic)
- ✅ Web Server (login UI)

---

#### `SESSION_EXPIRE_TIME_SECONDS`
```yaml
SESSION_EXPIRE_TIME_SECONDS: "86400"
```

**What it does:**
- Controls how long user sessions last
- `86400` = 24 hours (60 × 60 × 24)

**Why needed:**
- Security: Limit session lifetime
- User experience: Balance between security and convenience

**How it works:**
```
User logs in at 9:00 AM
      │
      ▼
API Server creates session
- Store in Redis
- TTL = 86400 seconds
      │
      ▼
User active until 9:00 AM next day
      │
      ▼
After 24 hours → Session expires
      │
      ▼
User must log in again
```

**Used by:**
- ✅ API Server (session management)
- ✅ Web Server (session checking)

**Production Recommendations:**
```yaml
# High security (banking, healthcare)
SESSION_EXPIRE_TIME_SECONDS: "3600"  # 1 hour

# Normal security (internal tools)
SESSION_EXPIRE_TIME_SECONDS: "86400"  # 24 hours

# Convenience (low security)
SESSION_EXPIRE_TIME_SECONDS: "604800"  # 7 days
```

---

### ⚙️ Feature Flags & Settings

#### `DISABLE_GENERATIVE_AI`
```yaml
DISABLE_GENERATIVE_AI: "false"
```

**What it does:**
- Controls whether LLM chat functionality is available
- When `true`: Onyx becomes search-only system

**Values:**
- `"false"`: Chat with LLM enabled (default)
- `"true"`: Chat disabled, search only

**Use cases for disabling:**
1. **No LLM provider configured**
   - Running Onyx for search only
   - Don't want to pay for LLM API
   
2. **Compliance/Security**
   - Organization prohibits sending data to LLMs
   - Air-gapped environment without LLM
   
3. **Cost control**
   - LLM usage can be expensive
   - Start with search, add chat later

**What changes when disabled:**
```
DISABLE_GENERATIVE_AI = "false"     │  DISABLE_GENERATIVE_AI = "true"
────────────────────────────────────┼──────────────────────────────────
User can:                           │  User can:
✅ Search documents                 │  ✅ Search documents
✅ Ask questions (LLM responds)     │  ❌ Ask questions
✅ Chat with documents              │  ❌ Chat
✅ Summarize results                │  ❌ Summarize
                                    │
UI shows:                           │  UI shows:
✅ Chat interface                   │  ❌ No chat interface
✅ "Ask AI" button                  │  ❌ Search only
```

**Used by:**
- ✅ API Server (enables/disables LLM endpoints)
- ✅ Web Server (shows/hides chat UI)

---

#### `QA_TIMEOUT`
```yaml
QA_TIMEOUT: "60"
```

**What it does:**
- Maximum time (seconds) allowed for question-answering requests
- Prevents queries from running forever

**What's included in timeout:**
1. Vector search in Vespa
2. Retrieval of document chunks
3. LLM API call (if enabled)
4. Response processing

**Typical timings:**
```
Vector Search:     ~50-200ms
Chunk Retrieval:   ~50-100ms
LLM Generation:    ~2-30 seconds (depending on model)
Processing:        ~100-500ms
─────────────────────────────────
Total:             ~3-35 seconds typical
Timeout:           60 seconds (safe buffer)
```

**When to adjust:**
```yaml
# Fast LLM (GPT-4, Claude with low token limits)
QA_TIMEOUT: "30"

# Normal (default)
QA_TIMEOUT: "60"

# Slow LLM or large context windows
QA_TIMEOUT: "120"

# Very large documents or slow LLM
QA_TIMEOUT: "180"
```

**Used by:**
- ✅ API Server (enforces timeout on QA endpoints)

**What happens on timeout:**
```
User asks question
      │
      ▼
API Server starts processing
      │
      ├─ Vector search: ✅ 100ms
      ├─ Chunk retrieval: ✅ 50ms
      ├─ LLM call starts...
      │     │
      │     │ (60 seconds pass)
      │     │
      │     ✗ TIMEOUT!
      ▼
API returns error:
"Query timeout exceeded"
```

---

## 5. Service-Specific Usage

### API Server (Backend)

**Uses ALL variables:**
```yaml
envFrom:
  - configMapRef:
      name: onyx-config
```

**Plus secrets:**
- `POSTGRES_USER` (from postgresql-secret)
- `POSTGRES_PASSWORD` (from postgresql-secret)
- `REDIS_PASSWORD` (from redis-secret)

**Why API server needs everything:**
- Connects to all infrastructure (DB, Redis, Vespa)
- Orchestrates search and chat
- Manages authentication
- Coordinates with model servers
- Enforces timeouts and feature flags

---

### Web Server (Frontend)

**Uses specific variables:**
- `INTERNAL_URL` - To call API server during SSR
- `WEB_DOMAIN` - For client-side config
- `DOMAIN` - For cookie domain
- `AUTH_TYPE` - To show correct login UI

**How it's injected:**
```yaml
env:
  - name: INTERNAL_URL
    valueFrom:
      configMapKeyRef:
        name: onyx-config
        key: INTERNAL_URL
  # ... etc
```

**Why limited variables:**
- Web server doesn't directly access database
- All backend operations go through API server
- Only needs routing and auth UI configuration

---

### Background Workers (Celery)

**Uses most variables:**
- `POSTGRES_*` - Database operations
- `REDIS_*` - Task queue
- `VESPA_HOST` - Document indexing
- `MODEL_SERVER_*` - Embedding generation

**Plus additional:**
- `INDEXING_MODEL_SERVER_HOST` - For bulk operations

**Why workers need these:**
- Process background tasks (indexing, sync)
- Write to database
- Index documents to Vespa
- Generate embeddings
- Coordinate via Redis

---

### Model Servers (Inference & Indexing)

**Inherit all variables:**
```yaml
envFrom:
  - configMapRef:
      name: onyx-config
```

**Why:**
- May need various configurations
- Model paths and cache settings
- Coordination with other services
- Flexible configuration

---

## 6. Production Configuration

### Minimal Changes for Production

```yaml
# ============================================================================
# PRODUCTION CONFIGURATION
# ============================================================================

# 1. Update domain settings
WEB_DOMAIN: "https://onyx.company.com"  # ← Your actual domain
DOMAIN: "company.com"                    # ← Base domain

# 2. Keep internal service names (these are correct for Kubernetes)
POSTGRES_HOST: "postgresql"              # ✅ Keep as-is
REDIS_HOST: "redis"                      # ✅ Keep as-is
VESPA_HOST: "vespa-0.vespa-service"     # ✅ Keep as-is
MODEL_SERVER_HOST: "inference-model-server"  # ✅ Keep as-is

# 3. Choose authentication method
AUTH_TYPE: "oidc"                        # ← Or "google_oauth", "saml"

# 4. Adjust session timeout (optional)
SESSION_EXPIRE_TIME_SECONDS: "28800"    # 8 hours

# 5. Feature flags (optional)
DISABLE_GENERATIVE_AI: "false"          # ✅ Enable chat
QA_TIMEOUT: "60"                         # ✅ Good default
```

### External Database Configuration

If using external PostgreSQL (AWS RDS, Cloud SQL, etc.):

```yaml
# ============================================================================
# EXTERNAL DATABASE
# ============================================================================
POSTGRES_HOST: "my-onyx-db.abc123.us-east-1.rds.amazonaws.com"
POSTGRES_PORT: "5432"
POSTGRES_DB: "onyx_production"

# Keep everything else the same
REDIS_HOST: "redis"  # Still internal
VESPA_HOST: "vespa-0.vespa-service"  # Still internal
```

### High Security Configuration

```yaml
# ============================================================================
# HIGH SECURITY
# ============================================================================

# Shorter sessions
SESSION_EXPIRE_TIME_SECONDS: "3600"  # 1 hour

# Enterprise SSO
AUTH_TYPE: "saml"

# Production domains with HTTPS
WEB_DOMAIN: "https://onyx.company.com"
DOMAIN: "company.com"

# Longer timeout for complex queries
QA_TIMEOUT: "120"
```

---

## 📊 Summary Table

| Variable | Type | Required | Default | Production Change? |
|----------|------|----------|---------|-------------------|
| `POSTGRES_HOST` | String | ✅ Yes | `postgresql` | Only if external DB |
| `POSTGRES_PORT` | String | ✅ Yes | `5432` | Only if custom port |
| `POSTGRES_DB` | String | ✅ Yes | `postgres` | Optional |
| `REDIS_HOST` | String | ✅ Yes | `redis` | Rarely |
| `REDIS_PORT` | String | ✅ Yes | `6379` | Rarely |
| `VESPA_HOST` | String | ✅ Yes | `vespa-0.vespa-service` | Rarely |
| `MODEL_SERVER_HOST` | String | ✅ Yes | `inference-model-server` | Rarely |
| `MODEL_SERVER_PORT` | String | ✅ Yes | `9000` | Rarely |
| `INTERNAL_URL` | String | ✅ Yes | `http://api-server:8080` | Rarely |
| `WEB_DOMAIN` | String | ✅ Yes | `http://localhost:3000` | **⚠️ YES - Update!** |
| `DOMAIN` | String | ✅ Yes | `localhost` | **⚠️ YES - Update!** |
| `AUTH_TYPE` | String | ✅ Yes | `basic` | Maybe (for SSO) |
| `SESSION_EXPIRE_TIME_SECONDS` | String | ✅ Yes | `86400` | Optional |
| `DISABLE_GENERATIVE_AI` | String | ✅ Yes | `false` | Optional |
| `QA_TIMEOUT` | String | ✅ Yes | `60` | Optional |

---

## 🔗 Related Documentation

- [ConfigMap File](../manifests/05-configmap.yaml)
- [Architecture Guide](ARCHITECTURE-FOR-JUNIOR-ENGINEERS.md)
- [Networking Guide](KUBERNETES-NETWORKING-COMPLETE-GUIDE.md)
- [Deployment Guide](../guides/QUICK-START.md)

---

**This guide should help you understand every environment variable in Onyx!** 🎯
