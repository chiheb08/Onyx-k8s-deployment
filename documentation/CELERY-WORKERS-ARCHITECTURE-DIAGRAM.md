# Celery Workers Architecture Diagram - Onyx

## 🎯 Overview

This diagram shows how the 6 Celery background workers operate in Onyx, their communication flows, and how they solve the "API server can't talk to model server" issue.

---

## 🏗️ Complete Celery Workers Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    🌐 USER INTERFACE LAYER                                              │
│                                                                                                         │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐              │
│  │   User Uploads  │    │   User Searches │    │   User Chats    │    │   Admin Tasks   │              │
│  │   Document      │    │   Documents     │    │   with LLM      │    │   (Connectors)  │              │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘              │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    📡 NGINX GATEWAY                                                     │
│                                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              nginx:80 (Reverse Proxy)                                           │   │
│  │  Routes: / → web-server:3000, /api/* → api-server:8080                                         │   │
│  └─────────────────────────────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    🖥️ APPLICATION LAYER                                                 │
│                                                                                                         │
│  ┌─────────────────────────────────┐              ┌─────────────────────────────────┐                  │
│  │        WEB SERVER               │              │        API SERVER               │                  │
│  │     (Next.js Frontend)          │              │      (FastAPI Backend)          │                  │
│  │                                 │              │                                 │                  │
│  │  • Serves UI                    │              │  • Handles user requests        │                  │
│  │  • User authentication          │              │  • Creates Celery tasks        │                  │
│  │  • Document upload UI           │              │  • Uses Inference Model Server │                  │
│  │  • Search interface             │              │  • Stores files in MinIO       │                  │
│  └─────────────────────────────────┘              └─────────────────────────────────┘                  │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    ⚡ REDIS TASK QUEUE                                                   │
│                                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              Redis:6379 (Message Broker)                                        │   │
│  │                                                                                                 │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │   │
│  │  │   celery    │  │docprocessing│  │docfetching  │  │   light     │  │   heavy     │           │   │
│  │  │   queue     │  │   queue     │  │   queue     │  │   queue     │  │   queue     │           │   │
│  │  │             │  │             │  │             │  │             │  │             │           │   │
│  │  │ • Core tasks│  │ • Doc index │  │ • Fetch docs│  │ • Metadata  │  │ • Pruning   │           │   │
│  │  │ • Periodic  │  │ • Embedding │  │ • Connectors│  │ • Permissions│  │ • Bulk sync │           │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘           │   │
│  └─────────────────────────────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    🔄 CELERY WORKERS LAYER                                              │
│                                                                                                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │   CELERY BEAT   │  │ PRIMARY WORKER  │  │  LIGHT WORKER   │  │  HEAVY WORKER   │  │ DOCFETCHING     │ │
│  │   (Scheduler)   │  │                 │  │                 │  │                 │  │ WORKER          │ │
│  │                 │  │ Queues:         │  │ Queues:         │  │ Queues:         │  │                 │ │
│  │ • Schedules     │  │ • celery        │  │ • vespa_metadata│  │ • connector_    │  │ Queues:         │ │
│  │   periodic      │  │ • periodic_tasks│  │   _sync         │  │   pruning       │  │ • docfetching   │ │
│  │   tasks         │  │                 │  │ • connector_    │  │ • connector_    │  │                 │ │
│  │ • Every 15s-5min│  │ • Core tasks    │  │   deletion      │  │   doc_perms_    │  │ • Fetches docs  │ │
│  │ • 1 replica     │  │ • System mgmt   │  │ • doc_perms_    │  │   sync          │  │   from external │ │
│  │   (critical!)   │  │                 │  │   upsert        │  │ • external_     │  │   connectors    │ │
│  │                 │  │                 │  │ • checkpoint_   │  │   group_sync    │  │ • Google Drive  │ │
│  │                 │  │                 │  │   cleanup       │  │ • csv_generation│  │ • Confluence    │ │
│  │                 │  │                 │  │ • index_attempt │  │                 │  │ • SharePoint    │ │
│  │                 │  │                 │  │   _cleanup      │  │                 │  │ • etc.          │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
│                                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐   │
│  │                            DOCPROCESSING WORKER (CRITICAL!)                                     │   │
│  │                                                                                                 │   │
│  │  Queue: docprocessing                                                                           │   │
│  │                                                                                                 │   │
│  │  ┌─────────────────────────────────────────────────────────────────────────────────────────┐   │   │
│  │  │                    DOCUMENT PROCESSING PIPELINE                                          │   │   │
│  │  │                                                                                         │   │   │
│  │  │  1. Receive task from Redis queue                                                       │   │   │
│  │  │     ↓                                                                                   │   │   │
│  │  │  2. Download document from MinIO                                                        │   │   │
│  │  │     ↓                                                                                   │   │   │
│  │  │  3. Extract text from document (PDF, Word, etc.)                                        │   │   │
│  │  │     ↓                                                                                   │   │   │
│  │  │  4. Chunk document into paragraphs (~512 tokens each)                                   │   │   │
│  │  │     ↓                                                                                   │   │   │
│  │  │  5. For each chunk:                                                                     │   │   │
│  │  │     a. Call INDEXING MODEL SERVER                                                       │   │   │
│  │  │     b. Get embedding vector (768 dimensions)                                            │   │   │
│  │  │     c. Store chunk + embedding in Vespa                                                │   │   │
│  │  │     ↓                                                                                   │   │   │
│  │  │  6. Update PostgreSQL metadata                                                          │   │   │
│  │  │     ↓                                                                                   │   │   │
│  │  │  7. Mark task as complete                                                               │   │   │
│  │  └─────────────────────────────────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    🤖 AI/ML MODEL SERVERS                                               │
│                                                                                                         │
│  ┌─────────────────────────────────┐              ┌─────────────────────────────────┐                  │
│  │    INFERENCE MODEL SERVER       │              │    INDEXING MODEL SERVER        │                  │
│  │                                 │              │                                 │                  │
│  │  • Used by: API Server          │              │  • Used by: Docprocessing Worker│                  │
│  │  • Purpose: Real-time queries   │              │  • Purpose: Bulk document       │                  │
│  │  • Port: 9000                   │              │    embedding                    │                  │
│  │  • Model: sentence-transformers │              │  • Port: 9000                   │                  │
│  │  • Input: User search queries   │              │  • Model: sentence-transformers │                  │
│  │  • Output: Query embeddings     │              │  • Input: Document chunks       │                  │
│  │                                 │              │  • Output: Chunk embeddings     │                  │
│  │  Example:                       │              │                                 │                  │
│  │  User: "vacation policy"        │              │  Example:                       │                  │
│  │  → Embedding: [0.1, 0.2, ...]  │              │  Chunk: "Employees get 15 days"│                  │
│  │                                 │              │  → Embedding: [0.3, 0.4, ...]  │                  │
│  └─────────────────────────────────┘              └─────────────────────────────────┘                  │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    💾 DATA STORAGE LAYER                                                │
│                                                                                                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐                  │
│  │   POSTGRESQL    │  │     VESPA       │  │     MINIO       │  │     REDIS       │                  │
│  │   (Metadata)    │  │  (Vector DB)    │  │ (File Storage)  │  │   (Cache)       │                  │
│  │                 │  │                 │  │                 │  │                 │                  │
│  │ • User accounts │  │ • Document      │  │ • Original      │  │ • Task queue    │                  │
│  │ • Document      │  │   chunks        │  │   files         │  │ • Session data  │                  │
│  │   metadata      │  │ • Embeddings    │  │ • Processed     │  │ • API cache     │                  │
│  │ • Connector     │  │ • Search index  │  │   documents     │  │ • Rate limiting │                  │
│  │   configs       │  │ • Vector        │  │ • Images        │  │                 │                  │
│  │ • Chat history  │  │   similarity    │  │ • Exports       │  │                 │                  │
│  │ • Permissions   │  │ • Metadata      │  │                 │  │                 │                  │
│  │                 │  │   filtering     │  │                 │  │                 │                  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  └─────────────────┘                  │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Detailed Communication Flows

### 1. Document Upload & Indexing Flow

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                              DOCUMENT UPLOAD & INDEXING FLOW                                            │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

1. USER UPLOADS DOCUMENT
   ┌─────────────────┐
   │ User selects    │
   │ "HR_Policy.pdf" │
   │ via Onyx UI     │
   └─────────────────┘
           │
           ▼
2. WEB SERVER → API SERVER
   ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
   │ POST /api/upload                                                                                │
   │ Content-Type: multipart/form-data                                                               │
   │ File: HR_Policy.pdf                                                                             │
   └─────────────────────────────────────────────────────────────────────────────────────────────────┘
           │
           ▼
3. API SERVER PROCESSES UPLOAD
   ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
   │ 1. Validate file type and size                                                                  │
   │ 2. Upload to MinIO:                                                                             │
   │    PUT /onyx-file-store-bucket/HR_Policy.pdf                                                    │
   │ 3. Create database record:                                                                      │
   │    INSERT INTO documents (id, name, status, created_at)                                         │
   │    VALUES ('doc-123', 'HR_Policy.pdf', 'pending', NOW())                                        │
   │ 4. Create Celery task:                                                                          │
   │    task = process_document.delay('doc-123')                                                     │
   │ 5. Return 200 OK to user                                                                        │
   └─────────────────────────────────────────────────────────────────────────────────────────────────┘
           │
           ▼
4. TASK QUEUED IN REDIS
   ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
   │ Redis Queue: docprocessing                                                                      │
   │                                                                                                 │
   │ LPUSH docprocessing {                                                                           │
   │   "task": "process_document",                                                                   │
   │   "args": ["doc-123"],                                                                          │
   │   "id": "task-456",                                                                             │
   │   "retries": 0                                                                                  │
   │ }                                                                                               │
   └─────────────────────────────────────────────────────────────────────────────────────────────────┘
           │
           ▼
5. DOCPROCESSING WORKER PICKS UP TASK
   ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
   │ Worker: celery-worker-docprocessing                                                             │
   │                                                                                                 │
   │ 1. Polls Redis queue: BRPOP docprocessing                                                       │
   │ 2. Receives task: process_document('doc-123')                                                   │
   │ 3. Starts processing...                                                                         │
   └─────────────────────────────────────────────────────────────────────────────────────────────────┘
           │
           ▼
6. DOCUMENT PROCESSING PIPELINE
   ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
   │ Step 1: Download from MinIO                                                                     │
   │   GET /onyx-file-store-bucket/HR_Policy.pdf                                                     │
   │                                                                                                 │
   │ Step 2: Extract text                                                                            │
   │   - Use PyPDF2/pdfplumber for PDFs                                                              │
   │   - Use python-docx for Word docs                                                               │
   │   - Extract plain text content                                                                  │
   │                                                                                                 │
   │ Step 3: Chunk document                                                                          │
   │   - Split into paragraphs (~512 tokens each)                                                    │
   │   - Preserve context and metadata                                                               │
   │   - Create chunk IDs                                                                            │
   │                                                                                                 │
   │ Step 4: Generate embeddings (FOR EACH CHUNK)                                                    │
   │   POST http://indexing-model-server:9000/embed                                                  │
   │   {                                                                                             │
   │     "text": "Employees are entitled to 15 days of vacation...",                                 │
   │     "model": "sentence-transformers/all-MiniLM-L6-v2"                                           │
   │   }                                                                                             │
   │   Response: {                                                                                   │
   │     "embedding": [0.123, 0.456, 0.789, ...]  // 768 dimensions                                 │
   │   }                                                                                             │
   │                                                                                                 │
   │ Step 5: Store in Vespa                                                                          │
   │   PUT http://vespa:19071/document/v1/onyx/document/doc-123-chunk-1                             │
   │   {                                                                                             │
   │     "fields": {                                                                                 │
   │       "id": "doc-123-chunk-1",                                                                  │
   │       "title": "HR Policy - Vacation",                                                          │
   │       "content": "Employees are entitled to 15 days...",                                        │
   │       "embedding": [0.123, 0.456, 0.789, ...],                                                 │
   │       "document_id": "doc-123",                                                                 │
   │       "chunk_index": 1,                                                                         │
   │       "created_at": "2025-10-21T10:00:00Z"                                                     │
   │     }                                                                                           │
   │   }                                                                                             │
   │                                                                                                 │
   │ Step 6: Update PostgreSQL                                                                       │
   │   UPDATE documents                                                                              │
   │   SET status = 'indexed',                                                                       │
   │       indexed_at = NOW(),                                                                       │
   │       chunk_count = 5                                                                           │
   │   WHERE id = 'doc-123'                                                                          │
   │                                                                                                 │
   │ Step 7: Mark task complete                                                                      │
   │   - Update task status in Redis                                                                 │
   │   - Log completion                                                                              │
   └─────────────────────────────────────────────────────────────────────────────────────────────────┘
           │
           ▼
7. DOCUMENT READY FOR SEARCH!
   ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
   │ Status: ✅ INDEXED                                                                              │
   │                                                                                                 │
   │ - 5 chunks created                                                                              │
   │ - 5 embeddings generated                                                                        │
   │ - Stored in Vespa                                                                               │
   │ - Metadata in PostgreSQL                                                                        │
   │ - Ready for semantic search                                                                     │
   └─────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 2. Search Query Flow

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    SEARCH QUERY FLOW                                                    │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

1. USER SEARCHES
   ┌─────────────────┐
   │ User types:     │
   │ "vacation days" │
   │ in search box   │
   └─────────────────┘
           │
           ▼
2. WEB SERVER → API SERVER
   ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
   │ POST /api/query                                                                                │
   │ {                                                                                              │
   │   "query": "vacation days",                                                                    │
   │   "filters": {},                                                                               │
   │   "limit": 10                                                                                  │
   │ }                                                                                              │
   └─────────────────────────────────────────────────────────────────────────────────────────────────┘
           │
           ▼
3. API SERVER PROCESSES QUERY
   ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
   │ Step 1: Generate query embedding                                                               │
   │   POST http://inference-model-server:9000/embed                                                │
   │   {                                                                                             │
   │     "text": "vacation days",                                                                   │
   │     "model": "sentence-transformers/all-MiniLM-L6-v2"                                          │
   │   }                                                                                             │
   │   Response: {                                                                                   │
   │     "embedding": [0.111, 0.222, 0.333, ...]  // 768 dimensions                                │
   │   }                                                                                             │
   │                                                                                                 │
   │ Step 2: Search Vespa                                                                           │
   │   POST http://vespa:19071/search/                                                               │
   │   {                                                                                             │
   │     "yql": "select * from sources * where {targetHits:10}nearestNeighbor(embedding,query_vector)",│
   │     "query_vector": [0.111, 0.222, 0.333, ...],                                               │
   │     "ranking": "semantic_similarity"                                                            │
   │   }                                                                                             │
   │                                                                                                 │
   │ Step 3: Get results                                                                            │
   │   Response: {                                                                                   │
   │     "root": {                                                                                   │
   │       "children": [                                                                             │
   │         {                                                                                       │
   │           "fields": {                                                                           │
   │             "id": "doc-123-chunk-1",                                                            │
   │             "title": "HR Policy - Vacation",                                                    │
   │             "content": "Employees are entitled to 15 days of vacation...",                     │
   │             "relevance": 0.95                                                                   │
   │           }                                                                                     │
   │         }                                                                                       │
   │       ]                                                                                         │
   │     }                                                                                           │
   │   }                                                                                             │
   │                                                                                                 │
   │ Step 4: Return results to user                                                                 │
   └─────────────────────────────────────────────────────────────────────────────────────────────────┘
           │
           ▼
4. USER SEES RESULTS
   ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
   │ Search Results for "vacation days":                                                            │
   │                                                                                                 │
   │ 📄 HR Policy - Vacation (95% match)                                                            │
   │ "Employees are entitled to 15 days of vacation per year..."                                    │
   │                                                                                                 │
   │ 📄 Employee Handbook (87% match)                                                               │
   │ "Vacation requests must be submitted at least 2 weeks..."                                      │
   └─────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 3. Connector Sync Flow

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    CONNECTOR SYNC FLOW                                                  │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

1. CELERY BEAT SCHEDULER
   ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
   │ Every 1 hour: Check for connector sync tasks                                                    │
   │                                                                                                 │
   │ 1. Query PostgreSQL:                                                                            │
   │    SELECT * FROM connectors WHERE enabled = true AND last_sync < NOW() - INTERVAL '1 hour'    │
   │                                                                                                 │
   │ 2. For each connector, create sync task:                                                        │
   │    task = sync_connector.delay(connector_id=5)                                                  │
   │                                                                                                 │
   │ 3. Queue task in Redis:                                                                         │
   │    LPUSH docfetching {                                                                          │
   │      "task": "sync_connector",                                                                  │
   │      "args": [5],                                                                               │
   │      "id": "sync-task-789"                                                                      │
   │    }                                                                                            │
   └─────────────────────────────────────────────────────────────────────────────────────────────────┘
           │
           ▼
2. DOCFETCHING WORKER
   ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
   │ Worker: celery-worker-docfetching                                                               │
   │                                                                                                 │
   │ 1. Polls Redis: BRPOP docfetching                                                               │
   │ 2. Receives: sync_connector(5)                                                                  │
   │ 3. Fetches connector config from PostgreSQL                                                     │
   │ 4. Authenticates to external service (Google Drive, Confluence, etc.)                          │
   │ 5. Lists new/updated files since last sync                                                      │
   │ 6. For each file, creates docprocessing task:                                                   │
   │    task = process_document.delay(file_id, connector_id=5)                                       │
   └─────────────────────────────────────────────────────────────────────────────────────────────────┘
           │
           ▼
3. DOCPROCESSING WORKER
   ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
   │ (Same as document upload flow above)                                                            │
   │                                                                                                 │
   │ 1. Download file from external service                                                          │
   │ 2. Upload to MinIO                                                                              │
   │ 3. Extract text                                                                                 │
   │ 4. Chunk document                                                                               │
   │ 5. Call INDEXING MODEL SERVER for embeddings                                                    │
   │ 6. Store in Vespa                                                                               │
   │ 7. Update PostgreSQL metadata                                                                   │
   └─────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 🔧 Worker Configuration Details

### Celery Beat (Scheduler)
```yaml
# File: 10-celery-beat.yaml
command:
  - celery
  - -A
  - onyx.background.celery.versioned_apps.beat
  - beat
  - --loglevel=INFO

# CRITICAL: Must be exactly 1 replica
replicas: 1

# Schedules:
# - Every 15s: Check for indexing tasks
# - Every 20s: Check for connector sync
# - Every 1min: Check for pruning tasks
# - Every 5min: System health checks
```

### Primary Worker
```yaml
# File: 11-celery-worker-primary.yaml
command:
  - celery
  - -A
  - onyx.background.celery.versioned_apps.primary
  - worker
  - --loglevel=INFO
  - --hostname=primary@%n
  - -Q
  - celery,periodic_tasks

# Queues:
# - celery: Default queue for general tasks
# - periodic_tasks: Tasks scheduled by Beat

# Tasks:
# - Connector deletion
# - Vespa sync operations
# - LLM model updates
# - System-wide operations
```

### Light Worker
```yaml
# File: 12-celery-worker-light.yaml
command:
  - celery
  - -A
  - onyx.background.celery.versioned_apps.light
  - worker
  - --loglevel=INFO
  - --hostname=light@%n
  - -Q
  - vespa_metadata_sync,connector_deletion,doc_permissions_upsert,checkpoint_cleanup,index_attempt_cleanup

# Queues:
# - vespa_metadata_sync: Sync Vespa metadata
# - connector_deletion: Delete connectors
# - doc_permissions_upsert: Update document permissions
# - checkpoint_cleanup: Clean up indexing checkpoints
# - index_attempt_cleanup: Clean up failed indexing attempts
```

### Heavy Worker
```yaml
# File: 13-celery-worker-heavy.yaml
command:
  - celery
  - -A
  - onyx.background.celery.versioned_apps.heavy
  - worker
  - --loglevel=INFO
  - --hostname=heavy@%n
  - -Q
  - connector_pruning,connector_doc_permissions_sync,connector_external_group_sync,csv_generation

# Queues:
# - connector_pruning: Prune deleted documents
# - connector_doc_permissions_sync: Sync document permissions
# - connector_external_group_sync: Sync external groups
# - csv_generation: Generate CSV exports

# High resource usage for bulk operations
resources:
  requests:
    cpu: 1000m
    memory: 4Gi
  limits:
    cpu: 2000m
    memory: 8Gi
```

### Docfetching Worker
```yaml
# File: 14-celery-worker-docfetching.yaml
command:
  - celery
  - -A
  - onyx.background.celery.versioned_apps.docfetching
  - worker
  - --pool=threads
  - --concurrency=4
  - --loglevel=INFO
  - --hostname=docfetching@%n
  - -Q
  - docfetching

# Special configuration:
# - --pool=threads: Uses thread pool for I/O-bound operations
# - --concurrency=4: 4 concurrent threads

# Tasks:
# - Fetch documents from Google Drive
# - Fetch documents from Confluence
# - Fetch documents from SharePoint
# - Fetch documents from other connectors
```

### Docprocessing Worker (CRITICAL!)
```yaml
# File: 15-celery-worker-docprocessing.yaml
command:
  - celery
  - -A
  - onyx.background.celery.versioned_apps.docprocessing
  - worker
  - --pool=threads
  - --concurrency=6
  - --prefetch-multiplier=1
  - --loglevel=INFO
  - --hostname=docprocessing@%n
  - -Q
  - docprocessing

# Special configuration:
# - --pool=threads: Uses thread pool for embedding operations
# - --concurrency=6: 6 concurrent threads
# - --prefetch-multiplier=1: Process one task at a time per thread

# CRITICAL OPERATIONS:
# 1. Download document from MinIO
# 2. Extract text content
# 3. Chunk document into paragraphs
# 4. Call INDEXING MODEL SERVER for each chunk
# 5. Store chunks + embeddings in Vespa
# 6. Update PostgreSQL metadata

# High resource usage for embedding generation
resources:
  requests:
    cpu: 1000m
    memory: 8Gi
  limits:
    cpu: 4000m
    memory: 16Gi
```

---

## 🎯 Why This Solves the "API Server Can't Talk to Model Server" Issue

### The Misunderstanding
**What you thought:**
- API server should talk to both Inference and Indexing model servers
- Problem must be network/DNS/configuration

**What actually happens:**

### API Server Responsibilities
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    API SERVER ROLE                                                     │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│  API SERVER (FastAPI Backend)                                                                          │
│                                                                                                         │
│  ✅ USES INFERENCE MODEL SERVER                                                                        │
│     • Real-time query embedding                                                                        │
│     • User search queries                                                                              │
│     • Chat interactions                                                                                │
│     • Live embedding generation                                                                        │
│                                                                                                         │
│  ❌ DOES NOT USE INDEXING MODEL SERVER                                                                  │
│     • Not designed for bulk processing                                                                 │
│     • Would block user requests                                                                        │
│     • Not scalable for large documents                                                                 │
│                                                                                                         │
│  ✅ CREATES CELERY TASKS                                                                                │
│     • Queues document processing tasks                                                                 │
│     • Queues connector sync tasks                                                                      │
│     • Queues cleanup tasks                                                                             │
│                                                                                                         │
│  ✅ HANDLES USER REQUESTS                                                                               │
│     • Document uploads                                                                                 │
│     • Search queries                                                                                   │
│     • Chat interactions                                                                                │
│     • Admin operations                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Background Workers Responsibilities
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                BACKGROUND WORKERS ROLE                                                  │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│  BACKGROUND WORKERS (Celery)                                                                            │
│                                                                                                         │
│  ✅ USES INDEXING MODEL SERVER                                                                          │
│     • Bulk document embedding                                                                           │
│     • Background processing                                                                             │
│     • Non-blocking operations                                                                           │
│     • Scalable for large documents                                                                      │
│                                                                                                         │
│  ✅ PROCESSES DOCUMENTS                                                                                  │
│     • Downloads from MinIO                                                                              │
│     • Extracts text content                                                                             │
│     • Chunks documents                                                                                  │
│     • Generates embeddings                                                                              │
│     • Stores in Vespa                                                                                   │
│                                                                                                         │
│  ✅ HANDLES BACKGROUND TASKS                                                                             │
│     • Connector synchronization                                                                         │
│     • Document pruning                                                                                  │
│     • Metadata synchronization                                                                          │
│     • System maintenance                                                                                │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### The Solution
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    THE SOLUTION                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

BEFORE (Missing Workers):
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   API Server    │    │ Indexing Model  │    │     Vespa       │
│                 │    │    Server       │    │                 │
│ Creates tasks   │───▶│                 │    │                 │
│ in Redis        │    │ NEVER USED!     │    │ EMPTY!          │
│                 │    │                 │    │                 │
│ Tasks pile up   │    │ No workers to   │    │ No documents    │
│ forever         │    │ call it         │    │ indexed         │
└─────────────────┘    └─────────────────┘    └─────────────────┘

AFTER (With Workers):
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   API Server    │    │ Docprocessing   │    │ Indexing Model  │    │     Vespa       │
│                 │    │    Worker       │    │    Server       │    │                 │
│ Creates tasks   │───▶│                 │───▶│                 │───▶│                 │
│ in Redis        │    │ Picks up tasks  │    │ Generates       │    │ Stores chunks   │
│                 │    │                 │    │ embeddings      │    │ + embeddings    │
│ Tasks processed │    │ Calls model     │    │ USED!           │    │ DOCUMENTS       │
│ immediately     │    │ server          │    │                 │    │ INDEXED!        │
└─────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘
```

---

## 📊 Resource Usage Summary

### Full Deployment (All 6 Workers)
| Worker | CPU Request | CPU Limit | Memory Request | Memory Limit | Purpose |
|--------|-------------|-----------|----------------|--------------|---------|
| Beat | 100m | 500m | 256Mi | 512Mi | Task scheduling |
| Primary | 500m | 1000m | 1Gi | 2Gi | Core tasks |
| Light | 500m | 1000m | 1Gi | 2Gi | Lightweight ops |
| Heavy | 1000m | 2000m | 4Gi | 8Gi | Resource-intensive |
| Docfetching | 500m | 2000m | 8Gi | 16Gi | Document fetching |
| Docprocessing | 1000m | 4000m | 8Gi | 16Gi | **Document indexing** |
| **TOTAL** | **3.6 cores** | **10.5 cores** | **22 GB** | **44 GB** | |

### Minimal Deployment (3 Critical Workers)
| Worker | CPU Request | CPU Limit | Memory Request | Memory Limit | Purpose |
|--------|-------------|-----------|----------------|--------------|---------|
| Beat | 100m | 500m | 256Mi | 512Mi | Task scheduling |
| Primary | 500m | 1000m | 1Gi | 2Gi | Core tasks |
| Docprocessing | 1000m | 4000m | 8Gi | 16Gi | **Document indexing** |
| **TOTAL** | **1.6 cores** | **5.5 cores** | **9.2 GB** | **18.5 GB** | |

---

## 🚀 Deployment Commands

### Full Deployment
```bash
# Deploy all 6 workers
oc apply -f manifests/10-celery-beat.yaml
oc apply -f manifests/11-celery-worker-primary.yaml
oc apply -f manifests/12-celery-worker-light.yaml
oc apply -f manifests/13-celery-worker-heavy.yaml
oc apply -f manifests/14-celery-worker-docfetching.yaml
oc apply -f manifests/15-celery-worker-docprocessing.yaml

# Wait for all workers to be ready
oc get pods -l scope=onyx-backend-celery -w
```

### Minimal Deployment (Resource-Constrained)
```bash
# Deploy only critical workers
oc apply -f manifests/10-celery-beat.yaml
oc apply -f manifests/11-celery-worker-primary.yaml
oc apply -f manifests/15-celery-worker-docprocessing.yaml

# Wait for workers to be ready
oc get pods -l scope=onyx-backend-celery -w
```

---

## 🔍 Verification Steps

### 1. Check All Workers Running
```bash
oc get pods -l scope=onyx-backend-celery

# Expected output:
# NAME                                         READY   STATUS    RESTARTS   AGE
# celery-beat-xxx                              1/1     Running   0          2m
# celery-worker-primary-xxx                    1/1     Running   0          2m
# celery-worker-light-xxx                      1/1     Running   0          2m
# celery-worker-heavy-xxx                      1/1     Running   0          2m
# celery-worker-docfetching-xxx                1/1     Running   0          2m
# celery-worker-docprocessing-xxx              1/1     Running   0          2m
```

### 2. Check Worker Logs
```bash
# Check Beat scheduler
oc logs -l app=celery-beat --tail=20

# Check Primary worker
oc logs -l app=celery-worker-primary --tail=20

# Check Docprocessing worker (CRITICAL)
oc logs -l app=celery-worker-docprocessing --tail=20
```

### 3. Test Document Upload
```bash
# Upload a document via Onyx UI
# Then watch docprocessing worker logs

oc logs -l app=celery-worker-docprocessing --tail=100 -f

# Should see:
# "Task onyx.background.celery.tasks.indexing.upsert_documents[xxx] received"
# "Calling indexing model server at indexing-model-server.onyx-infra.svc.cluster.local:9000"
# "Received embeddings from model server"
# "Writing to Vespa..."
# "Task succeeded"
```

---

## 📚 Key Takeaways

1. **API Server ≠ Background Workers**: API server handles user requests, workers handle background processing
2. **Two Model Servers, Two Purposes**: Inference for real-time queries, Indexing for bulk processing
3. **Redis is the Bridge**: API server creates tasks, workers consume tasks
4. **Docprocessing Worker is Critical**: This is the worker that calls the Indexing Model Server
5. **Without Workers**: Documents never get indexed, search returns no results
6. **With Workers**: Complete document processing pipeline works correctly

This architecture ensures that:
- User requests are handled quickly (API server + Inference Model Server)
- Background processing doesn't block user interactions (separate workers)
- Large documents can be processed efficiently (bulk processing with Indexing Model Server)
- System is scalable and resilient (multiple workers, task queues)
