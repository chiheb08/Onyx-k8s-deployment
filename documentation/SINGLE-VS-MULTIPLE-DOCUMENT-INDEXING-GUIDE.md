# Single vs. Multiple Document Indexing: Complete Guide for 50 Concurrent Users

## 🎯 Executive Summary

This guide explains the **critical differences** between indexing **one document** vs. **multiple documents concurrently**, which variables affect each scenario, and the optimal approaches for both. This is essential for deployments with **~50 concurrent users**.

**Key Insight**: Single document indexing focuses on **throughput per document**, while multiple document indexing focuses on **system capacity and resource contention**.

---

## 📊 Table of Contents

1. [Single Document Indexing](#single-document-indexing)
2. [Multiple Document Indexing](#multiple-document-indexing)
3. [Variable Comparison Matrix](#variable-comparison-matrix)
4. [Optimization Strategies by Scenario](#optimization-strategies-by-scenario)
5. [50-User Deployment Recommendations](#50-user-deployment-recommendations)
6. [Real-World Examples](#real-world-examples)

---

## 📄 Single Document Indexing

### What It Is

**Single document indexing** occurs when **one user uploads one file** and it gets processed through the indexing pipeline.

**Flow**:
```
User uploads file.pdf
  ↓
API Server → Creates UserFile record
  ↓
Celery Task: PROCESS_SINGLE_USER_FILE
  ↓
Extract documents from file (1 file → N documents)
  ↓
Chunk documents → M chunks
  ↓
Embed chunks (batches of 8-32)
  ↓
Write to Vespa
  ↓
Mark UserFile as COMPLETED
```

### Characteristics

- **Isolated**: One task, one file, one user
- **Sequential within document**: Chunks processed in batches
- **No resource contention**: Only one file being processed at a time
- **User-facing**: User waits for completion
- **Queue**: `user_file_processing`

### Variables That Affect Single Document Indexing

#### 1. **INDEXING_EMBEDDING_MODEL_NUM_THREADS** ⚡ **HIGH IMPACT**

**What it does**: Controls parallel API calls to the embedding model server when processing chunks.

**How it works**:
```
Single Document (200 chunks, batch_size=8):

Without threads (num_threads=1):
Batch 1: [Chunk 1-8]   → Model Server → 0.5s
Batch 2: [Chunk 9-16]  → Model Server → 0.5s
Batch 3: [Chunk 17-24] → Model Server → 0.5s
...
Total: 25 batches × 0.5s = 12.5 seconds

With threads (num_threads=32):
Batch 1-4:  [Chunk 1-32]   → Model Server (parallel) → 0.8s
Batch 5-8:  [Chunk 33-64]  → Model Server (parallel) → 0.8s
...
Total: 7 parallel batches × 0.8s = 5.6 seconds

Improvement: 2.2x faster
```

**Configuration**:
```yaml
# In ConfigMap or model-infex.yaml
env:
  - name: INDEXING_EMBEDDING_MODEL_NUM_THREADS
    value: "32"  # Recommended: 16-64
```

**Impact on single document**:
- ✅ **High**: Speeds up embedding generation significantly
- ✅ **No contention**: Only one document using threads
- ⚠️ **Memory**: Each thread holds a batch in memory

**Best value for single document**: **32-64** (can be aggressive since no contention)

---

#### 2. **EMBEDDING_BATCH_SIZE** ⚡ **MEDIUM-HIGH IMPACT**

**What it does**: Controls how many chunks are sent to the model server in one request.

**How it works**:
```
Single Document (200 chunks):

Batch size = 8:
25 batches × 0.5s = 12.5 seconds
25 HTTP requests

Batch size = 16:
13 batches × 0.8s = 10.4 seconds
13 HTTP requests (48% fewer)

Batch size = 32:
7 batches × 1.2s = 8.4 seconds
7 HTTP requests (72% fewer)
```

**Configuration**:
```yaml
env:
  - name: EMBEDDING_BATCH_SIZE
    value: "16"  # Recommended: 16-32 for single documents
```

**Impact on single document**:
- ✅ **Medium-High**: Fewer HTTP calls, better GPU utilization
- ✅ **No contention**: Only one document batching
- ⚠️ **Memory**: Larger batches = more memory per request

**Best value for single document**: **16-32** (can be larger since no contention)

---

#### 3. **Chunking Parameters** ⚡ **MEDIUM IMPACT**

**Variables**:
- `CHUNK_SIZE`: Size of each chunk (default: 512 tokens)
- `CHUNK_OVERLAP`: Overlap between chunks (default: 50 tokens)

**Impact on single document**:
- ✅ **Medium**: Fewer chunks = faster indexing
- ⚠️ **Trade-off**: Larger chunks may reduce search quality

**Best values for single document**:
- `CHUNK_SIZE`: 512-1024 tokens (depending on document type)
- `CHUNK_OVERLAP`: 50-100 tokens

---

#### 4. **CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY** ⚡ **LOW IMPACT (for single document)**

**What it does**: Controls how many user file processing tasks run simultaneously.

**Impact on single document**:
- ⚠️ **Low**: Only affects if multiple files are uploaded
- ✅ **For single document**: Doesn't matter (only one task)

**Note**: This becomes **critical** for multiple document indexing (see below).

---

### Optimization Approach for Single Document

**Goal**: Maximize throughput for **one document** as fast as possible.

**Strategy**:
1. ✅ **Aggressive threading**: `INDEXING_EMBEDDING_MODEL_NUM_THREADS = 32-64`
2. ✅ **Larger batch size**: `EMBEDDING_BATCH_SIZE = 16-32`
3. ✅ **Optimize chunking**: Balance chunk size vs. quality
4. ✅ **No need for worker scaling**: One worker is sufficient

**Example Configuration**:
```yaml
# Optimized for single document indexing
env:
  - name: INDEXING_EMBEDDING_MODEL_NUM_THREADS
    value: "32"  # Aggressive - no contention
  - name: EMBEDDING_BATCH_SIZE
    value: "24"  # Larger batches - fewer HTTP calls
  - name: CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY
    value: "2"   # Doesn't matter for single document
```

**Expected Performance**:
- **Small document** (50 chunks): 5-10 seconds
- **Medium document** (200 chunks): 15-30 seconds
- **Large document** (1000 chunks): 60-120 seconds

---

## 📚 Multiple Document Indexing

### What It Is

**Multiple document indexing** occurs when:
1. **Multiple users upload files simultaneously** (e.g., 50 users)
2. **Connector indexing** processes many documents from external sources
3. **Batch processing** of multiple documents in one task

**Flow (Multiple Users)**:
```
User 1 uploads file1.pdf → Task 1 queued
User 2 uploads file2.pdf → Task 2 queued
User 3 uploads file3.pdf → Task 3 queued
...
User 50 uploads file50.pdf → Task 50 queued
  ↓
Celery Worker (concurrency=8) picks up 8 tasks
  ↓
8 tasks run in parallel:
  - Task 1: Embedding chunks for file1
  - Task 2: Embedding chunks for file2
  - Task 3: Embedding chunks for file3
  - ...
  - Task 8: Embedding chunks for file8
  ↓
All 8 tasks call Model Server simultaneously
  ↓
Model Server receives 8 parallel requests
  ↓
Resource contention occurs:
  - CPU/GPU saturation
  - Memory pressure
  - Network bandwidth limits
  - Database connection pool exhaustion
  - Vespa write queue saturation
```

### Characteristics

- **Concurrent**: Multiple tasks running simultaneously
- **Resource contention**: Shared resources (model server, database, Vespa)
- **Queue management**: Tasks wait in queue if workers are busy
- **System-wide**: Affects entire deployment
- **Scalability challenge**: Must handle peak loads

### Variables That Affect Multiple Document Indexing

#### 1. **CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY** ⚡ **CRITICAL IMPACT**

**What it does**: Controls how many user file processing tasks run **simultaneously** in one worker.

**How it works**:
```
50 users upload files simultaneously:

Without optimization (concurrency=2, 1 worker):
Queue: [Task 1, Task 2, ..., Task 50]
Worker picks 2 tasks:
  - Task 1: 60 seconds
  - Task 2: 60 seconds
After 60s: Tasks 3-4 start
After 120s: Tasks 5-6 start
...
After 1500s (25 minutes): All 50 tasks complete

With optimization (concurrency=8, 3 workers):
Queue: [Task 1, Task 2, ..., Task 50]
3 workers × 8 concurrency = 24 parallel tasks
  - Tasks 1-24: Start immediately
  - After 60s: Tasks 1-24 complete, Tasks 25-48 start
  - After 120s: Tasks 25-48 complete, Tasks 49-50 start
  - After 180s: All 50 tasks complete

Improvement: 8.3x faster (25 min → 3 min)
```

**Configuration**:
```yaml
# In ConfigMap or Deployment
env:
  - name: CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY
    value: "8"  # Recommended: 8-16 for 50 users
```

**Impact on multiple documents**:
- ✅ **Critical**: Determines system throughput
- ⚠️ **Resource contention**: More concurrency = more contention
- ⚠️ **Memory**: Each concurrent task uses memory

**Best value for 50 users**: **8-12** per worker

---

#### 2. **Worker Replicas** ⚡ **CRITICAL IMPACT**

**What it does**: Number of worker pods running user file processing tasks.

**How it works**:
```
50 users, 8 concurrency per worker:

1 worker:
  - Capacity: 8 concurrent tasks
  - Time for 50 tasks: ~6-8 minutes

3 workers:
  - Capacity: 24 concurrent tasks (3 × 8)
  - Time for 50 tasks: ~2-3 minutes

5 workers:
  - Capacity: 40 concurrent tasks (5 × 8)
  - Time for 50 tasks: ~1-2 minutes
```

**Configuration**:
```yaml
# In Helm values or Deployment
celery_worker_user_file_processing:
  replicaCount: 3  # Recommended: 3-5 for 50 users
```

**Impact on multiple documents**:
- ✅ **Critical**: Linear scaling with replicas
- ⚠️ **Cost**: More replicas = more resources

**Best value for 50 users**: **3-5 replicas**

---

#### 3. **INDEXING_EMBEDDING_MODEL_NUM_THREADS** ⚡ **MEDIUM IMPACT (with contention)**

**What it does**: Same as single document, but now **shared across multiple tasks**.

**How it works**:
```
50 users, 8 concurrency per worker, 3 workers = 24 concurrent tasks

Without optimization (num_threads=8):
Each task uses 8 threads → 24 tasks × 8 = 192 parallel API calls
Model Server overwhelmed:
  - CPU saturation
  - Memory pressure
  - Request queue backlog
  - Timeouts and failures

With optimization (num_threads=16):
Each task uses 16 threads → 24 tasks × 16 = 384 parallel API calls
Model Server still overwhelmed, but better throughput per task

With smart optimization (num_threads=4):
Each task uses 4 threads → 24 tasks × 4 = 96 parallel API calls
Model Server handles load better:
  - More stable
  - Fewer timeouts
  - Better overall throughput
```

**Configuration**:
```yaml
env:
  - name: INDEXING_EMBEDDING_MODEL_NUM_THREADS
    value: "16"  # Recommended: 8-16 for multiple documents (lower than single)
```

**Impact on multiple documents**:
- ✅ **Medium**: Still important, but must balance with contention
- ⚠️ **Contention**: Too many threads = model server overload
- ⚠️ **Sweet spot**: Lower than single document (16 vs 32)

**Best value for 50 users**: **8-16** (lower than single document to avoid contention)

---

#### 4. **EMBEDDING_BATCH_SIZE** ⚡ **MEDIUM IMPACT (with contention)**

**What it does**: Same as single document, but now **shared model server**.

**How it works**:
```
50 users, 8 concurrency per worker, 3 workers = 24 concurrent tasks

Batch size = 32 (aggressive):
Each task sends 32 chunks per request
24 tasks × 32 chunks = 768 chunks per batch cycle
Model Server:
  - Memory: 768 chunks × ~1KB = 768KB per cycle
  - Processing time: 2-3 seconds per batch
  - Risk: Memory pressure, timeouts

Batch size = 16 (balanced):
Each task sends 16 chunks per request
24 tasks × 16 chunks = 384 chunks per batch cycle
Model Server:
  - Memory: 384 chunks × ~1KB = 384KB per cycle
  - Processing time: 1-2 seconds per batch
  - Stable: Better resource utilization

Batch size = 8 (conservative):
Each task sends 8 chunks per request
24 tasks × 8 chunks = 192 chunks per batch cycle
Model Server:
  - Memory: 192 chunks × ~1KB = 192KB per cycle
  - Processing time: 0.5-1 second per batch
  - Very stable: Lower throughput but safer
```

**Configuration**:
```yaml
env:
  - name: EMBEDDING_BATCH_SIZE
    value: "12"  # Recommended: 8-16 for multiple documents (lower than single)
```

**Impact on multiple documents**:
- ✅ **Medium**: Important, but must balance with contention
- ⚠️ **Contention**: Larger batches = more memory pressure on model server
- ⚠️ **Sweet spot**: Lower than single document (12 vs 24)

**Best value for 50 users**: **8-16** (lower than single document to avoid contention)

---

#### 5. **Model Server Resources** ⚡ **CRITICAL IMPACT**

**What it does**: CPU, memory, and GPU allocation for the indexing model server.

**How it works**:
```
50 users, 24 concurrent tasks, 16 threads each = 384 parallel requests

Without optimization (2 CPU, 4GB RAM):
Model Server:
  - CPU: 100% utilization, queuing requests
  - Memory: 90%+ utilization, risk of OOM
  - Throughput: 50-100 requests/second
  - Response time: 2-5 seconds (with queuing)

With optimization (8 CPU, 16GB RAM):
Model Server:
  - CPU: 70-80% utilization, stable
  - Memory: 60-70% utilization, safe
  - Throughput: 200-300 requests/second
  - Response time: 0.5-1 second
```

**Configuration**:
```yaml
# Indexing Model Server Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: indexing-model-server
spec:
  template:
    spec:
      containers:
        - name: model-server
          resources:
            requests:
              cpu: 4000m      # 4 cores minimum
              memory: 8Gi     # 8GB minimum
            limits:
              cpu: 8000m     # 8 cores recommended
              memory: 16Gi   # 16GB recommended
```

**Impact on multiple documents**:
- ✅ **Critical**: Determines system capacity
- ⚠️ **Bottleneck**: Model server is often the limiting factor
- ⚠️ **Scaling**: Can scale horizontally (multiple model server replicas)

**Best values for 50 users**:
- **CPU**: 4-8 cores (4000m-8000m)
- **Memory**: 8-16GB
- **Replicas**: 1-2 (if using load balancer)

---

#### 6. **Database Connection Pool** ⚡ **MEDIUM IMPACT**

**What it does**: Number of concurrent database connections available.

**How it works**:
```
50 users, 24 concurrent tasks:

Without optimization (pool_size=10):
24 tasks compete for 10 connections
  - 14 tasks wait for connections
  - Database connection timeout errors
  - Slow indexing

With optimization (pool_size=50):
24 tasks have plenty of connections
  - No waiting
  - Fast indexing
```

**Configuration**:
```yaml
env:
  - name: DB_POOL_SIZE
    value: "50"  # Recommended: 2-3x concurrent tasks
```

**Impact on multiple documents**:
- ✅ **Medium**: Can become bottleneck if too small
- ⚠️ **Database limits**: Must not exceed database max connections

**Best value for 50 users**: **50-100** connections

---

#### 7. **Vespa Write Queue** ⚡ **MEDIUM IMPACT**

**What it does**: How many chunks are written to Vespa in parallel.

**How it works**:
```
50 users, 24 concurrent tasks, 200 chunks per file = 4800 chunks

Without optimization (sequential writes):
Chunks written one by one
  - 4800 chunks × 0.1s = 480 seconds (8 minutes)
  - Vespa underutilized

With optimization (parallel writes):
Chunks written in batches of 100
  - 48 batches × 0.5s = 24 seconds
  - Vespa fully utilized
```

**Configuration**:
```yaml
env:
  - name: VESPA_BATCH_SIZE
    value: "100"  # Recommended: 50-200
```

**Impact on multiple documents**:
- ✅ **Medium**: Can become bottleneck for large batches
- ⚠️ **Vespa limits**: Must not exceed Vespa write capacity

**Best value for 50 users**: **100-200** chunks per batch

---

### Optimization Approach for Multiple Documents

**Goal**: Maximize **system throughput** while avoiding resource contention.

**Strategy**:
1. ✅ **Scale workers**: 3-5 replicas with 8-12 concurrency each
2. ✅ **Balance threading**: `INDEXING_EMBEDDING_MODEL_NUM_THREADS = 8-16` (lower than single)
3. ✅ **Balance batch size**: `EMBEDDING_BATCH_SIZE = 8-16` (lower than single)
4. ✅ **Scale model server**: 4-8 CPU cores, 8-16GB RAM
5. ✅ **Optimize database pool**: 50-100 connections
6. ✅ **Optimize Vespa writes**: 100-200 chunks per batch

**Example Configuration**:
```yaml
# Optimized for 50 concurrent users
env:
  # Worker scaling
  - name: CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY
    value: "8"
  
  # Embedding optimization (balanced for contention)
  - name: INDEXING_EMBEDDING_MODEL_NUM_THREADS
    value: "16"  # Lower than single document (32)
  - name: EMBEDDING_BATCH_SIZE
    value: "12"  # Lower than single document (24)
  
  # Database optimization
  - name: DB_POOL_SIZE
    value: "50"
  
  # Vespa optimization
  - name: VESPA_BATCH_SIZE
    value: "100"

# Deployment scaling
celery_worker_user_file_processing:
  replicaCount: 3  # 3 workers × 8 concurrency = 24 concurrent tasks

indexing_model_server:
  resources:
    requests:
      cpu: 4000m
      memory: 8Gi
    limits:
      cpu: 8000m
      memory: 16Gi
```

**Expected Performance**:
- **50 users, small files** (50 chunks each): 2-3 minutes total
- **50 users, medium files** (200 chunks each): 5-8 minutes total
- **50 users, large files** (1000 chunks each): 15-25 minutes total

---

## 📊 Variable Comparison Matrix

| Variable | Single Document | Multiple Documents (50 users) | Impact Difference |
|----------|---------------|------------------------------|-------------------|
| **INDEXING_EMBEDDING_MODEL_NUM_THREADS** | 32-64 (aggressive) | 8-16 (balanced) | ⚠️ **Lower for multiple** (avoid contention) |
| **EMBEDDING_BATCH_SIZE** | 16-32 (large) | 8-16 (medium) | ⚠️ **Lower for multiple** (avoid memory pressure) |
| **CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY** | 2 (doesn't matter) | 8-12 (critical) | ✅ **Higher for multiple** (throughput) |
| **Worker Replicas** | 1 (sufficient) | 3-5 (required) | ✅ **More for multiple** (scaling) |
| **Model Server CPU** | 2-4 cores | 4-8 cores | ✅ **More for multiple** (capacity) |
| **Model Server Memory** | 4-8GB | 8-16GB | ✅ **More for multiple** (capacity) |
| **Database Pool Size** | 10-20 | 50-100 | ✅ **Larger for multiple** (concurrency) |
| **Vespa Batch Size** | 50-100 | 100-200 | ✅ **Larger for multiple** (throughput) |

---

## 🎯 Optimization Strategies by Scenario

### Scenario 1: Single User, One Large Document

**Goal**: Index one document as fast as possible.

**Strategy**:
```yaml
INDEXING_EMBEDDING_MODEL_NUM_THREADS: "32"  # Aggressive
EMBEDDING_BATCH_SIZE: "24"                   # Large batches
CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY: "2"  # Doesn't matter
Worker Replicas: 1                          # One is enough
Model Server: 2 CPU, 4GB RAM               # Minimal
```

**Expected**: 60-120 seconds for 1000 chunks

---

### Scenario 2: 50 Users, Simultaneous Uploads

**Goal**: Handle peak load without contention.

**Strategy**:
```yaml
INDEXING_EMBEDDING_MODEL_NUM_THREADS: "16"  # Balanced
EMBEDDING_BATCH_SIZE: "12"                   # Medium batches
CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY: "8"  # High concurrency
Worker Replicas: 3-5                        # Scale horizontally
Model Server: 4-8 CPU, 8-16GB RAM          # High capacity
Database Pool: 50-100                       # Large pool
Vespa Batch Size: 100-200                   # Large batches
```

**Expected**: 5-8 minutes for 50 users (200 chunks each)

---

### Scenario 3: Connector Indexing (Many Documents)

**Goal**: Process thousands of documents from connectors.

**Strategy**:
```yaml
INDEXING_EMBEDDING_MODEL_NUM_THREADS: "8"   # Conservative
EMBEDDING_BATCH_SIZE: "16"                   # Medium batches
CELERY_WORKER_DOCPROCESSING_CONCURRENCY: "12"  # High concurrency
Worker Replicas: 5-10                      # Many replicas
Model Server: 8 CPU, 16GB RAM              # Very high capacity
Database Pool: 100-200                     # Very large pool
Vespa Batch Size: 200-500                  # Very large batches
```

**Expected**: Hours to days for thousands of documents

---

## 🏢 50-User Deployment Recommendations

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                   50 CONCURRENT USERS                      │
└─────────────────────────────────────────────────────────────┘

┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   Worker 1   │    │   Worker 2   │    │   Worker 3   │
│ Concurrency:8│    │ Concurrency:8│    │ Concurrency:8│
│              │    │              │    │              │
│ Task 1-8     │    │ Task 9-16    │    │ Task 17-24   │
└──────┬───────┘    └──────┬───────┘    └──────┬───────┘
       │                  │                  │
       └──────────────────┼──────────────────┘
                          │
              ┌───────────▼───────────┐
              │  Indexing Model Server│
              │  4-8 CPU, 8-16GB RAM  │
              │  Handles 24-48 tasks  │
              └───────────┬───────────┘
                          │
              ┌───────────▼───────────┐
              │      Vespa Cluster     │
              │   Writes 100-200 chunks│
              │        per batch       │
              └───────────────────────┘
```

### Complete Configuration

```yaml
# ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: onyx-config
data:
  # Embedding optimization (balanced for 50 users)
  INDEXING_EMBEDDING_MODEL_NUM_THREADS: "16"
  EMBEDDING_BATCH_SIZE: "12"
  
  # Worker scaling
  CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY: "8"
  
  # Database optimization
  DB_POOL_SIZE: "50"
  
  # Vespa optimization
  VESPA_BATCH_SIZE: "100"

---
# Celery Worker Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: celery-worker-user-file-processing
spec:
  replicas: 3  # 3 workers × 8 concurrency = 24 concurrent tasks
  template:
    spec:
      containers:
        - name: celery-worker
          env:
            - name: CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY
              value: "8"
          resources:
            requests:
              cpu: 2000m
              memory: 4Gi
            limits:
              cpu: 4000m
              memory: 8Gi

---
# Indexing Model Server Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: indexing-model-server
spec:
  replicas: 1  # Can scale to 2 if needed
  template:
    spec:
      containers:
        - name: model-server
          env:
            - name: INDEXING_EMBEDDING_MODEL_NUM_THREADS
              value: "16"
            - name: EMBEDDING_BATCH_SIZE
              value: "12"
          resources:
            requests:
              cpu: 4000m
              memory: 8Gi
            limits:
              cpu: 8000m
              memory: 16Gi
```

### Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| **Peak concurrent tasks** | 24-40 | 3-5 workers × 8 concurrency |
| **Time for 50 users** | 5-8 minutes | Medium files (200 chunks each) |
| **Model server CPU** | 60-80% | Stable, not saturated |
| **Model server memory** | 60-70% | Safe, no OOM risk |
| **Database connections** | 30-50% | Well below limit |
| **Vespa write latency** | <1 second | Per batch |

### Monitoring Checklist

- ✅ **Celery queue length**: Should stay < 20 tasks
- ✅ **Worker CPU**: Should be 50-80% per worker
- ✅ **Model server CPU**: Should be 60-80%
- ✅ **Model server memory**: Should be < 80%
- ✅ **Database connections**: Should be < 80% of pool
- ✅ **Vespa write latency**: Should be < 1 second per batch
- ✅ **Task completion time**: Should be < 2 minutes per file (medium size)

---

## 📈 Real-World Examples

### Example 1: Single User Uploads Large PDF

**Scenario**: One user uploads a 500-page PDF (1000 chunks).

**Configuration**:
```yaml
INDEXING_EMBEDDING_MODEL_NUM_THREADS: "32"  # Aggressive
EMBEDDING_BATCH_SIZE: "24"                   # Large batches
```

**Result**:
- **Time**: 60-90 seconds
- **Model server**: 40% CPU, 30% memory (plenty of capacity)
- **No contention**: Only one task running

---

### Example 2: 50 Users Upload Simultaneously

**Scenario**: 50 users upload medium PDFs (200 chunks each) at the same time.

**Configuration**:
```yaml
INDEXING_EMBEDDING_MODEL_NUM_THREADS: "16"  # Balanced
EMBEDDING_BATCH_SIZE: "12"                   # Medium batches
CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY: "8"
Worker Replicas: 3
Model Server: 4 CPU, 8GB RAM
```

**Result**:
- **Time**: 6-8 minutes for all 50 files
- **Model server**: 75% CPU, 65% memory (stable)
- **Contention**: Managed well, no timeouts
- **Queue**: Clears within 8 minutes

---

### Example 3: Wrong Configuration (Too Aggressive)

**Scenario**: 50 users, but configured like single document.

**Configuration**:
```yaml
INDEXING_EMBEDDING_MODEL_NUM_THREADS: "32"  # Too aggressive!
EMBEDDING_BATCH_SIZE: "24"                   # Too large!
CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY: "8"
Worker Replicas: 3
```

**Result**:
- **Time**: 15-20 minutes (slower!)
- **Model server**: 100% CPU, 95% memory (saturated)
- **Contention**: Severe, many timeouts
- **Failures**: 10-20% of tasks fail due to timeouts

**Lesson**: **Lower values for multiple documents** to avoid contention.

---

## 🔑 Key Takeaways

1. **Single Document**: Optimize for **throughput per document**
   - Aggressive threading (32-64)
   - Large batch sizes (16-32)
   - No need for worker scaling

2. **Multiple Documents**: Optimize for **system capacity**
   - Balanced threading (8-16)
   - Medium batch sizes (8-16)
   - Scale workers (3-5 replicas)
   - Scale model server (4-8 CPU, 8-16GB RAM)

3. **50 Users**: Requires **horizontal scaling**
   - 3-5 worker replicas
   - 8-12 concurrency per worker
   - 4-8 CPU cores for model server
   - 50-100 database connections

4. **Contention Management**: Lower values for multiple documents
   - `INDEXING_EMBEDDING_MODEL_NUM_THREADS`: 16 (not 32)
   - `EMBEDDING_BATCH_SIZE`: 12 (not 24)
   - Prevents model server overload

5. **Monitoring**: Track system-wide metrics
   - Model server CPU/memory
   - Queue length
   - Task completion times
   - Failure rates

---

## 📚 Related Documentation

- [Complete Indexing Performance Optimization Guide](./COMPLETE-INDEXING-PERFORMANCE-OPTIMIZATION-GUIDE.md)
- [INDEXING_EMBEDDING_NUM_THREADS Explanation](./INDEXING_EMBEDDING_NUM_THREADS-EXPLANATION.md)
- [INDEXING_EMBEDDING_NUM_THREADS for Juniors](./INDEXING_EMBEDDING_NUM_THREADS-FOR-JUNIORS.md)
- [File Upload Performance Optimization](./FILE-UPLOAD-PERFORMANCE-OPTIMIZATION.md)
- [Celery Workers Architecture](./CELERY-WORKERS-ARCHITECTURE-DIAGRAM.md)

---

**Last Updated**: 2024
**Author**: Onyx Deployment Team
**Version**: 1.0

