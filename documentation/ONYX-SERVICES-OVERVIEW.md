# Onyx Services Overview - Quick Reference

Based on the architecture diagram, here's a brief overview of each service with the 3 key questions answered.

---

## 1. 📡 **NGINX (Reverse Proxy)**

**What is this service?**
- HTTP reverse proxy and load balancer that acts as the single entry point for all external traffic

**Why do we need it?**
- Provides single entry point, SSL termination, load balancing, and hides internal services from external access

**In/Out calls:**
- **IN**: HTTP requests from users (port 80/3000)
- **OUT**: Routes to `web_server:3000` and `api_server:8080`

---

## 2. 🖥️ **WEB SERVER (Frontend)**

**What is this service?**
- Next.js React application serving the user interface and handling client-side rendering

**Why do we need it?**
- Provides the user-facing interface, chat UI, admin panels, and handles client-side interactions

**In/Out calls:**
- **IN**: HTTP requests from NGINX (static assets, pages)
- **OUT**: API calls to `api_server:8080` for data fetching

---

## 3. ⚙️ **API SERVER (Backend)**

**What is this service?**
- FastAPI backend containing core business logic, authentication, and API endpoints

**Why do we need it?**
- Handles all business logic, user authentication, data processing, and orchestrates communication between services

**In/Out calls:**
- **IN**: HTTP requests from NGINX and web_server
- **OUT**: 
  - PostgreSQL queries (`relational_db:5432`)
  - Vespa searches (`index:19071`)
  - Redis operations (`cache:6379`)
  - Model server calls (`inference_model_server:9000`)
  - MinIO file operations (`minio:9000`)
  - vLLM API calls (`host.docker.internal:8001`)

---

## 4. 🔄 **BACKGROUND WORKERS (Celery)**

**What is this service?**
- Multiple specialized Celery workers managed by Supervisord, each handling specific types of asynchronous tasks

**Why do we need it?**
- Handles long-running tasks without blocking the API, enables scheduled operations, provides parallel processing, and separates workloads by type

**Worker Types:**

### 4a. **Primary Worker**
- **What**: Core background tasks and system-wide operations
- **Tasks**: Connector deletion, Vespa sync, pruning, LLM model updates
- **Concurrency**: 4 threads

### 4b. **Docfetching Worker**
- **What**: Fetches documents from external data sources (connectors)
- **Tasks**: Document retrieval, watchdog monitoring for stuck connectors
- **Spawns**: Docprocessing tasks for each document batch

### 4c. **Docprocessing Worker**
- **What**: Processes fetched documents through the indexing pipeline
- **Tasks**: Document upserts, chunking, embedding generation, Vespa indexing
- **Most Critical**: For document indexing functionality

### 4d. **Light Worker**
- **What**: Handles lightweight, fast operations
- **Tasks**: Vespa operations, document permissions sync, external group sync
- **Concurrency**: Higher (for quick tasks)

### 4e. **Heavy Worker**
- **What**: Handles resource-intensive operations
- **Tasks**: Document pruning operations
- **Concurrency**: 4 threads (limited for resource management)

### 4f. **KG Processing Worker**
- **What**: Knowledge Graph processing and clustering
- **Tasks**: Document relationships, clustering algorithms
- **Purpose**: Builds connections between documents

### 4g. **Monitoring Worker**
- **What**: System health monitoring and metrics collection
- **Tasks**: Celery queue monitoring, process memory checks, system status
- **Concurrency**: Single thread (monitoring doesn't need parallelism)

### 4h. **Beat Worker**
- **What**: Celery's scheduler for periodic tasks (cron-like)
- **Tasks**: Schedules indexing checks (15s), connector deletion (20s), Vespa sync (20s), pruning (20s), KG processing (60s), monitoring (5min), cleanup (hourly)
- **Uses**: DynamicTenantScheduler for multi-tenant support

**Collective In/Out calls:**
- **IN**: Tasks from Redis queue (`cache:6379`)
- **OUT**:
  - PostgreSQL updates (`relational_db:5432`)
  - Vespa indexing (`index:19071`)
  - Redis task coordination (`cache:6379`)
  - Indexing model server (`indexing_model_server:9000`)
  - MinIO file operations (`minio:9000`)

---

## 5. 🤖 **INFERENCE MODEL SERVER**

**What is this service?**
- AI/ML service that generates embeddings for real-time user queries and search operations

**Why do we need it?**
- Converts text queries into vector embeddings for semantic search functionality

**In/Out calls:**
- **IN**: HTTP embedding requests from `api_server:8080`
- **OUT**: Returns vector embeddings (no external calls)

---

## 6. 🤖 **INDEXING MODEL SERVER**

**What is this service?**
- AI/ML service dedicated to generating embeddings for document indexing and bulk processing

**Why do we need it?**
- Handles heavy document processing workloads separately from real-time queries to avoid performance conflicts

**In/Out calls:**
- **IN**: HTTP embedding requests from `background` workers
- **OUT**: Returns vector embeddings (no external calls)

---

## 7. 💾 **POSTGRESQL (Database)**

**What is this service?**
- Relational database storing structured data like users, document metadata, configurations, and chat history

**Why do we need it?**
- Provides ACID transactions, structured data storage, and relational queries for core application data

**In/Out calls:**
- **IN**: SQL queries from `api_server` and `background` workers
- **OUT**: None (data storage service)

---

## 8. 🔍 **VESPA (Vector Search)**

**What is this service?**
- Vector database and search engine that stores document chunks with their embeddings for semantic search

**Why do we need it?**
- Enables fast vector similarity search, hybrid search (keyword + semantic), and scalable document retrieval

**In/Out calls:**
- **IN**: 
  - Search queries from `api_server:8080`
  - Document indexing from `background` workers
- **OUT**: None (search engine service)

---

## 9. ⚡ **REDIS (Cache)**

**What is this service?**
- In-memory cache and message broker for fast data access and Celery task queue management

**Why do we need it?**
- Provides fast caching, session storage, rate limiting, and coordinates background task processing

**In/Out calls:**
- **IN**: 
  - Cache operations from `api_server:8080`
  - Task queue operations from `background` workers
- **OUT**: None (cache/broker service)

---

## 10. 📦 **MINIO (Object Storage)**

**What is this service?**
- S3-compatible object storage for files, documents, and binary data

**Why do we need it?**
- Stores uploaded files, processed documents, and provides scalable file storage with S3 API compatibility

**In/Out calls:**
- **IN**: 
  - File operations from `api_server:8080`
  - File operations from `background` workers
- **OUT**: None (storage service)

---

## 11. 🧠 **vLLM SERVER (Optional)**

**What is this service?**
- Local LLM inference server providing OpenAI-compatible API for generating AI responses

**Why do we need it?**
- Enables local AI chat functionality, provides data privacy, eliminates external API costs, and allows custom models

**In/Out calls:**
- **IN**: HTTP chat completion requests from `api_server:8080`
- **OUT**: None (inference service, may download models initially)

---

## 📊 **Service Communication Summary**

### **External Entry Points:**
- **NGINX**: Only service exposed to internet (ports 80, 3000)

### **Core Orchestrators:**
- **API Server**: Main coordinator, calls 6 other services
- **Background Workers**: 8 specialized workers processing different task types, collectively call 5 other services

### **Data Services (No Outbound Calls):**
- **PostgreSQL**: Database storage
- **Vespa**: Vector search
- **Redis**: Cache/queue
- **MinIO**: File storage
- **Model Servers**: AI inference
- **vLLM**: LLM inference

### **Frontend Services:**
- **Web Server**: UI layer, calls API server only
- **NGINX**: Proxy layer, routes to web/api servers

---

## 🔄 **Typical Request Flow:**

```
User → NGINX → Web Server → API Server → {PostgreSQL, Vespa, Redis, Model Server, MinIO} → vLLM → Response
```

**Background Processing:**
```
API Server → Redis Queue → 8 Specialized Workers → {PostgreSQL, Vespa, Model Server, MinIO}
                          ├─ Primary Worker (system tasks)
                          ├─ Docfetching Worker (document retrieval)
                          ├─ Docprocessing Worker (indexing pipeline)
                          ├─ Light Worker (quick operations)
                          ├─ Heavy Worker (resource-intensive tasks)
                          ├─ KG Processing Worker (knowledge graphs)
                          ├─ Monitoring Worker (system health)
                          └─ Beat Worker (task scheduling)
```

This architecture provides clear separation of concerns with each service having a specific role in the overall system! 🎯
