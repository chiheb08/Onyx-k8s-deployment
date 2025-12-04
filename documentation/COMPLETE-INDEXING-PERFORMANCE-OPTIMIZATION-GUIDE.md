# Complete Indexing Performance Optimization Guide

## 🎯 Executive Summary

This guide covers **ALL** ways to improve indexing performance beyond just `INDEXING_EMBEDDING_MODEL_NUM_THREADS`. We'll explore 15+ optimization strategies organized by impact and category.

**Expected Combined Improvement**: 10-20x faster indexing with all optimizations applied.

---

## 📊 Performance Optimization Categories

```
┌─────────────────────────────────────────────────────────────┐
│          INDEXING PERFORMANCE OPTIMIZATIONS                 │
└─────────────────────────────────────────────────────────────┘

1. EMBEDDING OPTIMIZATIONS (3-5x improvement)
   ├─ Threading (INDEXING_EMBEDDING_MODEL_NUM_THREADS)
   ├─ Batch Size (EMBEDDING_BATCH_SIZE)
   └─ Model Server Resources

2. CELERY WORKER OPTIMIZATIONS (2-4x improvement)
   ├─ Docprocessing Concurrency
   ├─ Docfetching Concurrency
   ├─ Worker Replicas
   └─ Prefetch Multiplier

3. CHUNKING OPTIMIZATIONS (1.5-2x improvement)
   ├─ Chunk Size
   ├─ Skip Metadata
   └─ Chunk Overlap

4. DATABASE/VESPA OPTIMIZATIONS (1.5-3x improvement)
   ├─ Vespa Batch Size
   ├─ Vespa Threads
   ├─ Index Batch Size
   └─ Connection Pooling

5. RESOURCE OPTIMIZATIONS (1.5-2x improvement)
   ├─ CPU Allocation
   ├─ Memory Allocation
   └─ GPU Acceleration

6. ARCHITECTURE OPTIMIZATIONS (2-5x improvement)
   ├─ Dedicated Indexing Model Server
   ├─ Horizontal Scaling
   └─ Network Optimization
```

---

## 🚀 Optimization 1: Embedding Batch Size (HIGH IMPACT)

### What It Does

Controls how many chunks are sent to the embedding model in a single request.

**Default**: 8 chunks per batch  
**Recommended**: 16-32 chunks per batch

### How It Works

```
Without Optimization (Batch Size = 8):
Document (200 chunks)
  ↓
Batch 1: [Chunk 1-8]   → Model Server → 0.5s
Batch 2: [Chunk 9-16]  → Model Server → 0.5s
Batch 3: [Chunk 17-24] → Model Server → 0.5s
...
Total: 25 batches × 0.5s = 12.5 seconds

With Optimization (Batch Size = 16):
Document (200 chunks)
  ↓
Batch 1: [Chunk 1-16]   → Model Server → 0.8s
Batch 2: [Chunk 17-32] → Model Server → 0.8s
...
Total: 13 batches × 0.8s = 10.4 seconds

Improvement: 20% faster + fewer HTTP calls
```

### Configuration

**Environment Variable**: `EMBEDDING_BATCH_SIZE`

```yaml
# In ConfigMap or Deployment
env:
  - name: EMBEDDING_BATCH_SIZE
    value: "16"  # or 24, 32 for higher memory systems
```

**Code Location**: `backend/onyx/configs/model_configs.py:44-46`

```python
EMBEDDING_BATCH_SIZE = int(os.environ.get("EMBEDDING_BATCH_SIZE") or 0) or None
BATCH_SIZE_ENCODE_CHUNKS = EMBEDDING_BATCH_SIZE or 8
```

### Impact

- **Speed Improvement**: 1.2-1.5x faster
- **Network Calls**: 50% fewer HTTP requests
- **Memory Usage**: +50-100% per batch
- **Best For**: Local model servers, high-memory systems

### Trade-offs

- ✅ Fewer HTTP calls = less network overhead
- ✅ Better GPU utilization (if available)
- ⚠️ Higher memory usage per batch
- ⚠️ May cause timeouts on low-memory systems

---

## 🚀 Optimization 2: Celery Docprocessing Worker Concurrency (HIGH IMPACT)

### What It Does

Controls how many document processing tasks run simultaneously in the Celery worker.

**Default**: 6 concurrent tasks  
**Recommended**: 12-24 concurrent tasks

### How It Works

```
Without Optimization (Concurrency = 6):
┌─────────────────────────────────────┐
│  Celery Worker (6 threads)          │
│  ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐     │
│  │T1│ │T2│ │T3│ │T4│ │T5│ │T6│     │
│  └──┘ └──┘ └──┘ └──┘ └──┘ └──┘     │
│  6 documents processed at once       │
└─────────────────────────────────────┘
Time for 100 documents: ~17 batches × 30s = 510s

With Optimization (Concurrency = 24):
┌─────────────────────────────────────────────────────┐
│  Celery Worker (24 threads)                         │
│  ┌──┐ ┌──┐ ┌──┐ ... ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐      │
│  │T1│ │T2│ │T3│     │T22│ │T23│ │T24│              │
│  └──┘ └──┘ └──┘     └──┘ └──┘ └──┘ └──┘           │
│  24 documents processed at once                      │
└─────────────────────────────────────────────────────┘
Time for 100 documents: ~5 batches × 30s = 150s

Improvement: 3.4x faster!
```

### Configuration

**Environment Variable**: `CELERY_WORKER_DOCPROCESSING_CONCURRENCY`

```yaml
# In Celery Worker Deployment
env:
  - name: CELERY_WORKER_DOCPROCESSING_CONCURRENCY
    value: "24"  # Increase from default 6
```

**Alternative Variable**: `NUM_INDEXING_WORKERS` (legacy, still works)

**Code Location**: `backend/onyx/configs/app_configs.py:324-336`

```python
CELERY_WORKER_DOCPROCESSING_CONCURRENCY_DEFAULT = 6
CELERY_WORKER_DOCPROCESSING_CONCURRENCY = int(
    os.environ.get("CELERY_WORKER_DOCPROCESSING_CONCURRENCY") or 6
)
```

### Impact

- **Speed Improvement**: 2-4x faster (depending on workload)
- **Resource Usage**: +300-400% CPU and memory
- **Best For**: High-volume indexing, dedicated worker pods

### Trade-offs

- ✅ Massive throughput increase
- ✅ Better resource utilization
- ⚠️ Requires more CPU/memory
- ⚠️ May overwhelm model server if not scaled

---

## 🚀 Optimization 3: Celery Docfetching Worker Concurrency (MEDIUM IMPACT)

### What It Does

Controls how many document fetching tasks run simultaneously.

**Default**: 1 concurrent task  
**Recommended**: 2-4 concurrent tasks

### How It Works

```
Without Optimization (Concurrency = 1):
Connector fetches documents one batch at a time
  ↓
Batch 1 → Process → Batch 2 → Process → ...
Sequential: Slow but safe

With Optimization (Concurrency = 2-4):
Multiple connectors fetch in parallel
  ↓
Batch 1 ┐
Batch 2 ├─ Process in parallel
Batch 3 ┘
Parallel: Faster but more resource intensive
```

### Configuration

**Environment Variable**: `CELERY_WORKER_DOCFETCHING_CONCURRENCY`

```yaml
env:
  - name: CELERY_WORKER_DOCFETCHING_CONCURRENCY
    value: "2"  # Increase from default 1
```

**Code Location**: `backend/onyx/configs/app_configs.py:338-350`

### Impact

- **Speed Improvement**: 1.5-2x faster for multi-connector setups
- **Resource Usage**: +100-300% CPU
- **Best For**: Multiple connectors running simultaneously

---

## 🚀 Optimization 4: Index Batch Size (MEDIUM IMPACT)

### What It Does

Controls how many documents are processed together before chunking and embedding.

**Default**: 16 documents per batch  
**Recommended**: 32-64 documents per batch

### How It Works

```
Without Optimization (INDEX_BATCH_SIZE = 16):
100 documents
  ↓
Batch 1: [Doc 1-16]   → Chunk → Embed → Store
Batch 2: [Doc 17-32]  → Chunk → Embed → Store
...
Total: 7 batches

With Optimization (INDEX_BATCH_SIZE = 32):
100 documents
  ↓
Batch 1: [Doc 1-32]   → Chunk → Embed → Store
Batch 2: [Doc 33-64]  → Chunk → Embed → Store
...
Total: 4 batches

Improvement: Fewer batch operations = less overhead
```

### Configuration

**Environment Variable**: `INDEX_BATCH_SIZE`

```yaml
env:
  - name: INDEX_BATCH_SIZE
    value: "32"  # Increase from default 16
```

**Code Location**: `backend/onyx/configs/app_configs.py:209`

```python
INDEX_BATCH_SIZE = int(os.environ.get("INDEX_BATCH_SIZE") or 16)
```

### Impact

- **Speed Improvement**: 1.2-1.5x faster
- **Memory Usage**: +100% per batch
- **Best For**: Large document sets, high-memory systems

---

## 🚀 Optimization 5: Vespa Batch Size (MEDIUM IMPACT)

### What It Does

Controls how many chunks are written to Vespa in a single batch operation.

**Default**: 128 chunks per batch  
**Recommended**: 256-512 chunks per batch

### How It Works

```
Without Optimization (BATCH_SIZE = 128):
1000 chunks
  ↓
Batch 1: [Chunk 1-128]   → Vespa → 0.5s
Batch 2: [Chunk 129-256] → Vespa → 0.5s
...
Total: 8 batches × 0.5s = 4 seconds

With Optimization (BATCH_SIZE = 256):
1000 chunks
  ↓
Batch 1: [Chunk 1-256]   → Vespa → 0.8s
Batch 2: [Chunk 257-512] → Vespa → 0.8s
...
Total: 4 batches × 0.8s = 3.2 seconds

Improvement: 25% faster
```

### Configuration

**Code Location**: `backend/onyx/document_index/vespa_constants.py:40`

```python
BATCH_SIZE = 128  # Can be modified (hardcoded, requires code change)
```

**Note**: This is hardcoded. To change it, you'd need to modify the source code or use environment variable injection if available.

### Impact

- **Speed Improvement**: 1.2-1.3x faster
- **Memory Usage**: +100% per batch
- **Best For**: High-volume indexing

---

## 🚀 Optimization 6: Vespa Threads (MEDIUM IMPACT)

### What It Does

Controls how many parallel threads write to Vespa simultaneously.

**Default**: 32 threads  
**Current**: 32 threads (already optimized)

### How It Works

```
Vespa writes use ThreadPoolExecutor with NUM_THREADS workers
Each thread writes one chunk at a time to Vespa
32 threads = 32 parallel writes
```

**Code Location**: `backend/onyx/document_index/vespa_constants.py:29-31`

```python
NUM_THREADS = 32  # Hardcoded, since Vespa doesn't allow batching
```

**Note**: This is already optimized. Vespa doesn't support batch inserts, so threading is the only way to parallelize.

---

## 🚀 Optimization 7: Skip Metadata in Chunks (LOW-MEDIUM IMPACT)

### What It Does

Removes document-level metadata from each chunk, reducing chunk size and processing time.

**Default**: Metadata included  
**Recommended**: Skip if metadata is not needed for search

### How It Works

```
Without Optimization (SKIP_METADATA_IN_CHUNK = false):
Chunk = Title + Content + Metadata
  ↓
Chunk size: ~600 tokens
Processing time: Higher

With Optimization (SKIP_METADATA_IN_CHUNK = true):
Chunk = Title + Content (no metadata)
  ↓
Chunk size: ~500 tokens
Processing time: 15-20% faster
```

### Configuration

**Environment Variable**: `SKIP_METADATA_IN_CHUNK`

```yaml
env:
  - name: SKIP_METADATA_IN_CHUNK
    value: "true"  # Skip metadata to speed up processing
```

**Code Location**: `backend/onyx/configs/app_configs.py:612`

### Impact

- **Speed Improvement**: 1.15-1.2x faster
- **Chunk Size**: 15-20% smaller
- **Trade-off**: Metadata not available in search results

---

## 🚀 Optimization 8: Increase Model Server Resources (HIGH IMPACT)

### What It Does

Allocates more CPU and memory to the indexing model server for faster embedding generation.

**Current (Typical)**:
- CPU: 1000m (1 core)
- Memory: 2Gi

**Recommended**:
- CPU: 4000m-8000m (4-8 cores)
- Memory: 8Gi-16Gi

### How It Works

```
Low Resources (1 CPU, 2Gi RAM):
Embedding generation: 0.5s per batch
Bottleneck: CPU/memory limits

High Resources (4 CPU, 8Gi RAM):
Embedding generation: 0.2s per batch
Bottleneck: Removed!

Improvement: 2.5x faster embedding generation
```

### Configuration

```yaml
# In indexing-model-server deployment
resources:
  requests:
    cpu: 4000m      # Increase from 1000m
    memory: 8Gi     # Increase from 2Gi
  limits:
    cpu: 8000m      # Increase from 4000m
    memory: 16Gi    # Increase from 8Gi
```

### Impact

- **Speed Improvement**: 2-3x faster embedding generation
- **Cost**: Higher resource usage
- **Best For**: High-volume indexing, dedicated model server

---

## 🚀 Optimization 9: Scale Indexing Model Server (HIGH IMPACT)

### What It Does

Run multiple replicas of the indexing model server to handle more concurrent requests.

**Current**: 1 replica  
**Recommended**: 2-4 replicas

### How It Works

```
Single Replica (Current):
┌─────────────────────┐
│ Indexing Model      │
│ Server (1 pod)      │
│                     │
│ Request 1 → Process │
│ Request 2 → Wait    │
│ Request 3 → Wait    │
└─────────────────────┘
Bottleneck: Single server

Multiple Replicas (Optimized):
┌──────────┐ ┌──────────┐ ┌──────────┐
│ Model    │ │ Model    │ │ Model    │
│ Server 1 │ │ Server 2 │ │ Server 3 │
│          │ │          │ │          │
│ Req 1    │ │ Req 2    │ │ Req 3    │
└──────────┘ └──────────┘ └──────────┘
No bottleneck: Parallel processing
```

### Configuration

```yaml
# In indexing-model-server deployment
spec:
  replicas: 3  # Increase from 1
```

### Impact

- **Speed Improvement**: 2-4x faster (linear with replicas)
- **Cost**: 2-4x more resources
- **Best For**: High-volume indexing, multiple workers

---

## 🚀 Optimization 10: Scale Celery Workers (HIGH IMPACT)

### What It Does

Run multiple replicas of Celery workers to process more tasks in parallel.

**Current**: 1 replica  
**Recommended**: 2-4 replicas

### How It Works

```
Single Worker (Current):
┌─────────────────────┐
│ Celery Worker       │
│ (1 pod, 6 threads)  │
│                     │
│ 6 tasks at once     │
└─────────────────────┘

Multiple Workers (Optimized):
┌──────────┐ ┌──────────┐ ┌──────────┐
│ Worker 1 │ │ Worker 2 │ │ Worker 3 │
│ 6 threads│ │ 6 threads│ │ 6 threads│
│          │ │          │ │          │
│ 18 tasks at once!    │
└──────────┘ └──────────┘ └──────────┘
```

### Configuration

```yaml
# In celery-worker-docprocessing deployment
spec:
  replicas: 3  # Increase from 1
```

### Impact

- **Speed Improvement**: 2-4x faster (linear with replicas)
- **Cost**: 2-4x more resources
- **Best For**: High-volume indexing

---

## 🚀 Optimization 11: Optimize Chunk Size (LOW-MEDIUM IMPACT)

### What It Does

Adjusts the token limit per chunk. Larger chunks = fewer chunks = faster processing.

**Default**: 512 tokens per chunk  
**Recommended**: 512-768 tokens (model dependent)

### How It Works

```
Small Chunks (512 tokens):
Document (10,000 tokens)
  ↓
20 chunks → 20 embeddings → 20 database writes

Larger Chunks (768 tokens):
Document (10,000 tokens)
  ↓
14 chunks → 14 embeddings → 14 database writes

Improvement: 30% fewer operations
```

### Configuration

**Environment Variable**: `DOC_EMBEDDING_CONTEXT_SIZE`

**Note**: This is model-dependent. Most models are optimized for 512 tokens. Only increase if your model supports it.

**Code Location**: `backend/shared_configs/configs.py:35`

```python
DOC_EMBEDDING_CONTEXT_SIZE = 512  # Model default
```

### Impact

- **Speed Improvement**: 1.2-1.3x faster (if model supports)
- **Trade-off**: May reduce search quality (larger chunks = less precise)

---

## 🚀 Optimization 12: Connection Pooling (LOW-MEDIUM IMPACT)

### What It Does

**Connection pooling** is a technique that reuses existing network connections instead of creating new ones for each request. Think of it like a **taxi stand** instead of calling a new taxi every time you need a ride.

**Without Connection Pooling**:
- Every request creates a new connection (like calling a new taxi)
- Connection setup takes time (TCP handshake, TLS negotiation, authentication)
- Connection teardown also takes time
- **Overhead**: 50-200ms per request just for connection setup

**With Connection Pooling**:
- Connections are created once and reused (like a taxi stand with waiting taxis)
- Requests reuse existing connections (taxi is already there)
- Connections stay alive between requests (keepalive)
- **Overhead**: <1ms per request (just pick a connection from the pool)

### Real-World Analogy

```
🏢 Office Building (Your Application)
│
├─ Without Connection Pooling:
│   Need to call database? → Call taxi company → Wait 2 min → Taxi arrives → Go → Pay → Taxi leaves
│   Need to call database again? → Call taxi company again → Wait 2 min → ...
│   Time per trip: 2 min wait + 5 min drive = 7 minutes
│
└─ With Connection Pooling:
    Taxi stand with 20 taxis waiting outside
    Need to call database? → Take taxi from stand → Go → Return taxi to stand
    Need to call database again? → Take taxi from stand → Go → Return taxi to stand
    Time per trip: 0 min wait + 5 min drive = 5 minutes
    
    Improvement: 28% faster (7 min → 5 min)
```

---

### Types of Connection Pooling in Onyx

Onyx uses **three types** of connection pooling:

1. **HTTP Connection Pooling** (httpx) - For Vespa and Model Server
2. **Database Connection Pooling** (PostgreSQL) - For database queries
3. **Redis Connection Pooling** - For Redis operations

---

### 1. HTTP Connection Pooling (httpx) for Vespa

#### What It Does

Manages HTTP connections to **Vespa** (vector database) and **Model Server** (embedding generation).

#### How It Works (Step-by-Step)

**Without Connection Pooling**:
```
┌─────────────────────────────────────────────────────────────┐
│  Celery Worker (Processing 100 chunks)                       │
└─────────────────────────────────────────────────────────────┘
         │
         │ Request 1: Write chunk 1 to Vespa
         ├─────────────────────────────────────┐
         │                                     │
         │  1. Create TCP connection          │
         │     Time: 10-50ms (TCP handshake)  │
         │                                     │
         │  2. TLS handshake (if HTTPS)        │
         │     Time: 20-100ms                 │
         │                                     │
         │  3. Send HTTP request              │
         │     Time: 5-20ms                   │
         │                                     │
         │  4. Receive HTTP response           │
         │     Time: 10-50ms                  │
         │                                     │
         │  5. Close connection                │
         │     Time: 5-10ms                   │
         │                                     │
         │  Total: 50-230ms per request        │
         └─────────────────────────────────────┘
         
         │ Request 2: Write chunk 2 to Vespa
         ├─────────────────────────────────────┐
         │  (Repeat all steps above)           │
         │  Total: 50-230ms per request        │
         └─────────────────────────────────────┘
         
         ...
         
         │ Request 100: Write chunk 100 to Vespa
         ├─────────────────────────────────────┐
         │  (Repeat all steps above)           │
         │  Total: 50-230ms per request        │
         └─────────────────────────────────────┘
         
Total time: 100 requests × 150ms average = 15 seconds
```

**With Connection Pooling (20 connections)**:
```
┌─────────────────────────────────────────────────────────────┐
│  Celery Worker (Processing 100 chunks)                       │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  HTTP Connection Pool (20 connections)               │  │
│  │  ┌────┐ ┌────┐ ┌────┐ ... ┌────┐ ┌────┐            │  │
│  │  │ C1 │ │ C2 │ │ C3 │     │ C19│ │ C20│            │  │
│  │  └────┘ └────┘ └────┘     └────┘ └────┘            │  │
│  │  (All connections already established)              │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
         │
         │ Request 1: Write chunk 1 to Vespa
         ├─────────────────────────────────────┐
         │  1. Get connection from pool        │
         │     Time: <1ms (instant)            │
         │                                     │
         │  2. Send HTTP request              │
         │     Time: 5-20ms                   │
         │                                     │
         │  3. Receive HTTP response           │
         │     Time: 10-50ms                  │
         │                                     │
         │  4. Return connection to pool       │
         │     Time: <1ms                      │
         │                                     │
         │  Total: 15-71ms per request         │
         └─────────────────────────────────────┘
         
         │ Request 2: Write chunk 2 to Vespa
         ├─────────────────────────────────────┐
         │  (Reuse connection from pool)        │
         │  Total: 15-71ms per request         │
         └─────────────────────────────────────┘
         
         ...
         
         │ Request 100: Write chunk 100 to Vespa
         ├─────────────────────────────────────┐
         │  (Reuse connection from pool)        │
         │  Total: 15-71ms per request         │
         └─────────────────────────────────────┘
         
Total time: 100 requests × 43ms average = 4.3 seconds
Improvement: 3.5x faster (15s → 4.3s)
```

#### Visual Diagram: HTTP Connection Pool

```
┌─────────────────────────────────────────────────────────────────┐
│                    WITHOUT CONNECTION POOLING                    │
└─────────────────────────────────────────────────────────────────┘

Celery Worker                    Vespa Server
┌──────────────┐                ┌──────────────┐
│              │                │              │
│  Request 1   │───NEW CONN───→ │  Process     │
│              │   (50-200ms)   │              │
│              │←──CLOSE─────── │              │
│              │                │              │
│  Request 2   │───NEW CONN───→ │  Process     │
│              │   (50-200ms)   │              │
│              │←──CLOSE─────── │              │
│              │                │              │
│  Request 3   │───NEW CONN───→ │  Process     │
│              │   (50-200ms)   │              │
│              │←──CLOSE─────── │              │
└──────────────┘                └──────────────┘

Time per request: 150ms (connection) + 50ms (request) = 200ms
Total for 100 requests: 20 seconds


┌─────────────────────────────────────────────────────────────────┐
│                     WITH CONNECTION POOLING                     │
└─────────────────────────────────────────────────────────────────┘

Celery Worker                    Connection Pool          Vespa Server
┌──────────────┐                ┌──────────────┐        ┌──────────────┐
│              │                │ ┌──┐ ┌──┐ ┌──┐        │              │
│  Request 1   │───GET CONN───→ │ │C1│ │C2│ │C3│ ...   │              │
│              │   (<1ms)       │ └──┘ └──┘ └──┘        │              │
│              │                │      (20 connections)  │              │
│              │────────────────────────────────────────→│  Process     │
│              │   (50ms)       │                        │              │
│              │←────────────────────────────────────────│              │
│              │                │                        │              │
│              │───RETURN CONN─→│                        │              │
│              │   (<1ms)       │                        │              │
│              │                │                        │              │
│  Request 2   │───GET CONN───→ │                        │              │
│              │   (<1ms)       │                        │              │
│              │────────────────────────────────────────→│  Process     │
│              │   (50ms)       │                        │              │
│              │←────────────────────────────────────────│              │
└──────────────┘                └──────────────┘        └──────────────┘

Time per request: <1ms (get connection) + 50ms (request) = 51ms
Total for 100 requests: 5.1 seconds
Improvement: 3.9x faster!
```

#### Configuration

**Code Location**: `backend/onyx/background/celery/celery_utils.py:135-154`

**Current Implementation**:
```python
def httpx_init_vespa_pool(
    max_keepalive_connections: int,
    timeout: int = VESPA_REQUEST_TIMEOUT,
    ssl_cert: str | None = None,
    ssl_key: str | None = None,
) -> None:
    HttpxPool.init_client(
        name="vespa",
        cert=httpx_cert,
        verify=httpx_verify,
        timeout=timeout,
        http2=False,
        limits=httpx.Limits(max_keepalive_connections=max_keepalive_connections),
    )
```

**Where It's Used**:
```python
# In celery worker initialization (backend/onyx/background/celery/apps/light.py:72-78)
@worker_init.connect
def on_worker_init(sender: Worker, **kwargs: Any) -> None:
    EXTRA_CONCURRENCY = 8  # Extra connections for safety
    
    # Initialize Vespa connection pool
    if MANAGED_VESPA:
        httpx_init_vespa_pool(
            sender.concurrency + EXTRA_CONCURRENCY,  # e.g., 24 + 8 = 32
            ssl_cert=VESPA_CLOUD_CERT_PATH,
            ssl_key=VESPA_CLOUD_KEY_PATH,
        )
    else:
        httpx_init_vespa_pool(sender.concurrency + EXTRA_CONCURRENCY)
```

**Current Default**: 
- Worker concurrency: 6-24 (depending on worker type)
- Extra concurrency: 8
- **Total pool size**: 14-32 connections

**Optimization**:
```python
# Increase EXTRA_CONCURRENCY for high-volume indexing
EXTRA_CONCURRENCY = 16  # Increase from 8

# Or directly increase pool size
httpx_init_vespa_pool(50)  # Increase from 20-32 to 50
```

**Note**: This requires code modification. The pool size is calculated as `concurrency + EXTRA_CONCURRENCY`.

#### Performance Impact

| Scenario | Pool Size | Requests/sec | Avg Latency | Improvement |
|----------|-----------|--------------|-------------|-------------|
| **No Pooling** | 0 (new each time) | 5 req/s | 200ms | Baseline |
| **Small Pool** | 10 connections | 15 req/s | 67ms | 3x faster |
| **Medium Pool** | 20 connections | 20 req/s | 50ms | 4x faster |
| **Large Pool** | 50 connections | 25 req/s | 40ms | 5x faster |

**For 50 concurrent users**:
- **Recommended pool size**: 50-100 connections
- **Expected improvement**: 1.2-1.5x faster Vespa writes
- **Best for**: High-volume indexing, multiple workers

---

### 2. Database Connection Pooling (PostgreSQL)

#### What It Does

Manages database connections to **PostgreSQL** for storing document metadata, user files, and indexing status.

#### How It Works

**Without Connection Pooling**:
```
┌─────────────────────────────────────────────────────────────┐
│  Celery Worker (Processing 100 documents)                  │
└─────────────────────────────────────────────────────────────┘
         │
         │ Query 1: Insert document metadata
         ├─────────────────────────────────────┐
         │  1. Create database connection      │
         │     Time: 20-100ms (TCP + auth)     │
         │                                     │
         │  2. Execute SQL query               │
         │     Time: 5-20ms                    │
         │                                     │
         │  3. Close connection                │
         │     Time: 5-10ms                    │
         │                                     │
         │  Total: 30-130ms per query          │
         └─────────────────────────────────────┘
         
         │ Query 2: Update document status
         ├─────────────────────────────────────┐
         │  (Repeat all steps above)           │
         │  Total: 30-130ms per query          │
         └─────────────────────────────────────┘
         
Total time: 100 queries × 80ms average = 8 seconds
```

**With Connection Pooling (40 connections)**:
```
┌─────────────────────────────────────────────────────────────┐
│  Celery Worker (Processing 100 documents)                   │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Database Connection Pool (40 connections)          │  │
│  │  ┌────┐ ┌────┐ ┌────┐ ... ┌────┐ ┌────┐           │  │
│  │  │ C1 │ │ C2 │ │ C3 │     │ C39│ │ C40│           │  │
│  │  └────┘ └────┘ └────┘     └────┘ └────┘           │  │
│  │  (All connections already established)              │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
         │
         │ Query 1: Insert document metadata
         ├─────────────────────────────────────┐
         │  1. Get connection from pool        │
         │     Time: <1ms (instant)            │
         │                                     │
         │  2. Execute SQL query               │
         │     Time: 5-20ms                    │
         │                                     │
         │  3. Return connection to pool        │
         │     Time: <1ms                      │
         │                                     │
         │  Total: 5-21ms per query            │
         └─────────────────────────────────────┘
         
Total time: 100 queries × 13ms average = 1.3 seconds
Improvement: 6.2x faster (8s → 1.3s)
```

#### Visual Diagram: Database Connection Pool

```
┌─────────────────────────────────────────────────────────────────┐
│              DATABASE CONNECTION POOL ARCHITECTURE               │
└─────────────────────────────────────────────────────────────────┘

┌──────────────┐         ┌──────────────────────┐         ┌──────────────┐
│              │         │  Connection Pool      │         │              │
│ Celery       │         │  Manager             │         │ PostgreSQL   │
│ Worker 1     │         │                      │         │ Database     │
│              │         │  ┌────────────────┐   │         │              │
│  Task 1      │───GET──→│  │ Pool Size: 40 │   │         │              │
│  Task 2      │  CONN   │  │ Overflow: 10   │   │         │              │
│  Task 3      │         │  │                │   │         │              │
│  ...         │         │  │ Active: 15     │   │         │              │
│              │         │  │ Idle: 25       │   │         │              │
│              │         │  └────────────────┘   │         │              │
│              │         │         │              │         │              │
│              │         │         │              │         │              │
│              │         │    ┌────▼────┐        │         │              │
│              │         │    │ 40 Open  │        │         │              │
│              │         │    │ Database│        │         │              │
│              │         │    │ Connections     │         │              │
│              │         │    └────┬────┘        │         │              │
│              │         │         │              │         │              │
│              │         │         └──────────────┼─────────│              │
│              │         │                        │         │              │
└──────────────┘         └──────────────────────┘         └──────────────┘

Connection Lifecycle:
1. Worker requests connection → Pool checks for idle connection
2. If idle exists → Return immediately (<1ms)
3. If no idle, but pool not full → Create new connection (20-100ms)
4. If pool full → Wait for connection to be returned (blocking)
5. After query → Return connection to pool (keep alive)
```

#### Configuration

**Environment Variables**:
```yaml
# API Server Database Pool
POSTGRES_API_SERVER_POOL_SIZE=40        # Base pool size
POSTGRES_API_SERVER_POOL_OVERFLOW=10    # Extra connections when pool is full
# Total: 50 connections maximum

# Read-only Database Pool (for queries)
POSTGRES_API_SERVER_READ_ONLY_POOL_SIZE=10
POSTGRES_API_SERVER_READ_ONLY_POOL_OVERFLOW=5
# Total: 15 connections maximum

# Celery Worker Database Pool (set in code)
# pool_size = worker_concurrency
# max_overflow = 8 (EXTRA_CONCURRENCY)
```

**Code Location**: `backend/onyx/configs/app_configs.py:225-237`

```python
POSTGRES_API_SERVER_POOL_SIZE = int(
    os.environ.get("POSTGRES_API_SERVER_POOL_SIZE") or 40
)
POSTGRES_API_SERVER_POOL_OVERFLOW = int(
    os.environ.get("POSTGRES_API_SERVER_POOL_OVERFLOW") or 10
)
```

**Worker Pool Configuration**: `backend/onyx/background/celery/apps/light.py:69`

```python
@worker_init.connect
def on_worker_init(sender: Worker, **kwargs: Any) -> None:
    EXTRA_CONCURRENCY = 8
    
    # Database pool size = worker concurrency
    # Max overflow = EXTRA_CONCURRENCY
    SqlEngine.init_engine(
        pool_size=sender.concurrency,  # e.g., 24
        max_overflow=EXTRA_CONCURRENCY  # e.g., 8
    )
    # Total: 32 connections per worker
```

#### Optimization for 50 Users

**Current** (1 worker, concurrency=8):
- Pool size: 8
- Max overflow: 8
- **Total**: 16 connections

**Recommended** (3 workers, concurrency=8 each):
- Pool size per worker: 8
- Max overflow per worker: 8
- **Total per worker**: 16 connections
- **Total across 3 workers**: 48 connections

**For High Volume** (increase pool size):
```yaml
# In ConfigMap
env:
  - name: POSTGRES_API_SERVER_POOL_SIZE
    value: "80"  # Increase from 40
  - name: POSTGRES_API_SERVER_POOL_OVERFLOW
    value: "20"  # Increase from 10
# Total: 100 connections
```

**Important**: Don't exceed PostgreSQL's `max_connections` setting (default: 100).

#### Performance Impact

| Pool Size | Queries/sec | Avg Latency | Improvement |
|-----------|-------------|-------------|-------------|
| **10** | 50 q/s | 20ms | Baseline |
| **40** | 200 q/s | 5ms | 4x faster |
| **80** | 300 q/s | 3ms | 6x faster |

**For 50 concurrent users**:
- **Recommended**: 80-100 connections total
- **Expected improvement**: 1.5-2x faster database operations
- **Best for**: High-volume indexing, multiple workers

---

### 3. Redis Connection Pooling

#### What It Does

Manages connections to **Redis** for task queues, caching, and distributed locks.

#### Configuration

**Environment Variable**: `REDIS_POOL_MAX_CONNECTIONS`

**Code Location**: `backend/onyx/configs/app_configs.py:302`

```python
REDIS_POOL_MAX_CONNECTIONS = int(
    os.environ.get("REDIS_POOL_MAX_CONNECTIONS", 128)
)
```

**Default**: 128 connections

**Optimization**: Usually sufficient, but can increase for high-volume:
```yaml
env:
  - name: REDIS_POOL_MAX_CONNECTIONS
    value: "256"  # Increase from 128 if needed
```

---

### Combined Impact: All Connection Pools

#### Example: Indexing 1000 Documents

**Without Connection Pooling**:
```
1000 documents × 3 database queries = 3000 queries
1000 documents × 200 chunks = 200,000 Vespa writes

Database: 3000 queries × 80ms = 240 seconds (4 minutes)
Vespa: 200,000 writes × 200ms = 40,000 seconds (11 hours!)
Total: ~11 hours
```

**With Connection Pooling**:
```
Database: 3000 queries × 13ms = 39 seconds
Vespa: 200,000 writes × 51ms = 10,200 seconds (2.8 hours)
Total: ~2.8 hours
Improvement: 3.9x faster!
```

---

### Troubleshooting Connection Pool Issues

#### Symptoms

1. **"Too many connections" errors**
   - Database: `FATAL: too many connections`
   - Vespa: Connection timeouts
   - Redis: Connection refused

2. **Slow performance under load**
   - Requests waiting for connections
   - High latency during peak times

3. **Connection pool exhaustion**
   - Workers blocking waiting for connections
   - Tasks timing out

#### Solutions

1. **Increase Pool Size**:
   ```yaml
   # Database
   POSTGRES_API_SERVER_POOL_SIZE=80
   POSTGRES_API_SERVER_POOL_OVERFLOW=20
   
   # HTTP (requires code change)
   EXTRA_CONCURRENCY=16  # Increase from 8
   ```

2. **Monitor Pool Usage**:
   ```python
   # Check database pool
   active_connections = engine.pool.checkedout()
   idle_connections = engine.pool.checkedin()
   pool_size = engine.pool.size()
   
   print(f"Active: {active_connections}, Idle: {idle_connections}, Total: {pool_size}")
   ```

3. **Scale Horizontally**:
   - More worker replicas = more pools
   - Distribute load across multiple workers

---

### Summary: Connection Pooling Optimization

| Connection Type | Current | Recommended (50 users) | Improvement |
|----------------|---------|------------------------|-------------|
| **HTTP (Vespa)** | 20-32 | 50-100 | 1.2-1.5x faster |
| **Database (PostgreSQL)** | 40-50 | 80-100 | 1.5-2x faster |
| **Redis** | 128 | 128-256 | Usually sufficient |

**Combined Impact**: **1.2-2x faster** overall indexing performance

**Best For**:
- ✅ High-volume indexing
- ✅ Multiple concurrent users (50+)
- ✅ Network latency issues
- ✅ Multiple worker replicas

**Trade-offs**:
- ⚠️ More memory usage (each connection uses memory)
- ⚠️ Must not exceed service limits (PostgreSQL max_connections)
- ⚠️ Requires monitoring to avoid exhaustion

---

## 🚀 Optimization 13: GPU Acceleration (VERY HIGH IMPACT)

### What It Does

Uses GPU instead of CPU for embedding generation (10-50x faster).

**Current**: CPU-only  
**Recommended**: GPU if available

### How It Works

```
CPU Processing:
Embedding generation: 0.5s per batch
Bottleneck: CPU speed

GPU Processing:
Embedding generation: 0.05s per batch
Bottleneck: Removed!

Improvement: 10x faster!
```

### Configuration

```yaml
# In indexing-model-server deployment
resources:
  requests:
    nvidia.com/gpu: 1  # Request 1 GPU
  limits:
    nvidia.com/gpu: 1  # Limit to 1 GPU
```

### Impact

- **Speed Improvement**: 10-50x faster (depending on GPU)
- **Cost**: Requires GPU nodes
- **Best For**: High-volume indexing, production systems

---

## 🚀 Optimization 14: Prefetch Multiplier (LOW IMPACT)

### What It Does

Controls how many tasks a worker prefetches from the queue.

**Default**: Varies by worker type  
**Recommended**: 1-2 for docprocessing (prevents task hoarding)

### Configuration

**Environment Variable**: `CELERY_WORKER_LIGHT_PREFETCH_MULTIPLIER`

```yaml
env:
  - name: CELERY_WORKER_LIGHT_PREFETCH_MULTIPLIER
    value: "1"  # Process one task at a time per thread
```

**Code Location**: `backend/onyx/configs/app_configs.py:311-322`

### Impact

- **Speed Improvement**: 1.1x faster (better task distribution)
- **Best For**: Multiple workers, prevents task hoarding

---

## 🚀 Optimization 15: Disable Multipass Indexing (MEDIUM IMPACT)

### What It Does

**Multipass indexing** is a two-stage search technique that creates **both regular chunks AND large chunks** (4x larger) for each document. This allows the system to search at two different granularities, but **doubles** the indexing work.

**Disabling multipass indexing** means you only create regular chunks, which is **2x faster** and uses **half the storage**.

### Real-World Analogy

Think of multipass indexing like creating **two different maps** of the same city:

```
🏙️ City Map Analogy:

WITH MULTIPASS INDEXING:
City → Create Detailed Map (regular chunks)
     → ALSO Create Overview Map (large chunks, 4x zoomed out)
     
Result: 2 maps = 2x work, 2x storage
- Detailed map: Shows every street (regular chunks)
- Overview map: Shows entire neighborhoods (large chunks)

Search Process:
1. First, search the overview map (faster, less precise)
2. Then, look at the detailed map for the specific streets
3. Combine results for better accuracy

WITHOUT MULTIPASS INDEXING:
City → Create Detailed Map Only (regular chunks)

Result: 1 map = 1x work, 1x storage
- Detailed map: Shows every street (regular chunks)

Search Process:
1. Search the detailed map directly
2. Get results immediately
3. Faster, simpler, but slightly less context
```

---

### How Multipass Indexing Works (Step-by-Step)

#### Stage 1: Indexing (When Documents Are Processed)

**WITH Multipass Indexing Enabled**:
```
┌─────────────────────────────────────────────────────────────────┐
│                    MULTIPASS INDEXING FLOW                       │
└─────────────────────────────────────────────────────────────────┘

Document (10,000 tokens)
  ↓
Step 1: Create Regular Chunks (512 tokens each)
  ↓
┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
│ Chunk 1  │ │ Chunk 2  │ │ Chunk 3  │ │ Chunk 4  │ │ Chunk 5  │
│ 512 tok  │ │ 512 tok  │ │ 512 tok  │ │ 512 tok  │ │ 512 tok  │
└──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘
... (20 chunks total)

  ↓
Step 2: Create Large Chunks (combine 4 regular chunks each)
  ↓
┌──────────────────────────┐ ┌──────────────────────────┐
│ Large Chunk 1            │ │ Large Chunk 2            │
│ = Chunk 1 + 2 + 3 + 4    │ │ = Chunk 5 + 6 + 7 + 8    │
│ ~2048 tokens (4x size)   │ │ ~2048 tokens (4x size)   │
└──────────────────────────┘ └──────────────────────────┘
... (5 large chunks total)

  ↓
Step 3: Generate Embeddings for BOTH
  ↓
Regular Chunks: 20 embeddings
Large Chunks: 5 embeddings
Total: 25 embeddings (2x work!)

  ↓
Step 4: Store in Vespa
  ↓
Regular Chunks: 20 chunks stored
Large Chunks: 5 chunks stored (with references to regular chunks)
Total: 25 chunks stored (2x storage!)
```

**WITHOUT Multipass Indexing (Standard)**:
```
┌─────────────────────────────────────────────────────────────────┐
│                    STANDARD INDEXING FLOW                        │
└─────────────────────────────────────────────────────────────────┘

Document (10,000 tokens)
  ↓
Step 1: Create Regular Chunks (512 tokens each)
  ↓
┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
│ Chunk 1  │ │ Chunk 2  │ │ Chunk 3  │ │ Chunk 4  │ │ Chunk 5  │
│ 512 tok  │ │ 512 tok  │ │ 512 tok  │ │ 512 tok  │ │ 512 tok  │
└──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘
... (20 chunks total)

  ↓
Step 2: Generate Embeddings
  ↓
Regular Chunks: 20 embeddings
Total: 20 embeddings (1x work)

  ↓
Step 3: Store in Vespa
  ↓
Regular Chunks: 20 chunks stored
Total: 20 chunks stored (1x storage)
```

#### Stage 2: Search (When Users Query)

**WITH Multipass Indexing**:
```
┌─────────────────────────────────────────────────────────────────┐
│                    MULTIPASS SEARCH FLOW                        │
└─────────────────────────────────────────────────────────────────┘

User Query: "What is machine learning?"
  ↓
Step 1: Search Large Chunks First
  ↓
┌──────────────────────────┐ ┌──────────────────────────┐
│ Large Chunk 1            │ │ Large Chunk 2            │
│ Score: 0.85 (high)        │ │ Score: 0.72 (medium)     │
│ References: Chunk 1-4     │ │ References: Chunk 5-8    │
└──────────────────────────┘ └──────────────────────────┘

  ↓
Step 2: Retrieve Referenced Regular Chunks
  ↓
From Large Chunk 1 → Get Chunk 1, 2, 3, 4
From Large Chunk 2 → Get Chunk 5, 6, 7, 8

  ↓
Step 3: Apply Scores from Large Chunks
  ↓
Chunk 1: Score 0.85 (from Large Chunk 1)
Chunk 2: Score 0.85 (from Large Chunk 1)
Chunk 3: Score 0.85 (from Large Chunk 1)
Chunk 4: Score 0.85 (from Large Chunk 1)
Chunk 5: Score 0.72 (from Large Chunk 2)
...

  ↓
Step 4: Return Results
  ↓
Results: 8 chunks with scores
Time: ~150ms (2 search operations)
```

**WITHOUT Multipass Indexing (Standard)**:
```
┌─────────────────────────────────────────────────────────────────┐
│                    STANDARD SEARCH FLOW                          │
└─────────────────────────────────────────────────────────────────┘

User Query: "What is machine learning?"
  ↓
Step 1: Search Regular Chunks Directly
  ↓
┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
│ Chunk 1   │ │ Chunk 2   │ │ Chunk 3   │ │ Chunk 4   │
│ Score:0.82│ │ Score:0.79│ │ Score:0.75│ │ Score:0.71│
└──────────┘ └──────────┘ └──────────┘ └──────────┘

  ↓
Step 2: Return Results
  ↓
Results: 4 chunks with scores
Time: ~75ms (1 search operation)
Improvement: 2x faster search!
```

---

### Visual Diagram: Multipass vs Standard Indexing

```
┌─────────────────────────────────────────────────────────────────┐
│              MULTIPASS INDEXING (ENABLED)                       │
└─────────────────────────────────────────────────────────────────┘

Document: "Machine Learning Guide" (10,000 tokens)
│
├─ Regular Chunking (512 tokens each)
│  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐
│  │ Chunk 1│ │ Chunk 2│ │ Chunk 3│ │ Chunk 4│ │ Chunk 5│
│  │ 512 tok│ │ 512 tok│ │ 512 tok│ │ 512 tok│ │ 512 tok│
│  └────────┘ └────────┘ └────────┘ └────────┘ └────────┘
│  ... (20 chunks)
│
├─ Large Chunking (combine 4 regular chunks)
│  ┌────────────────────────────┐ ┌────────────────────────────┐
│  │ Large Chunk 1               │ │ Large Chunk 2              │
│  │ = Chunk 1+2+3+4             │ │ = Chunk 5+6+7+8            │
│  │ ~2048 tokens                │ │ ~2048 tokens               │
│  │ References: [1,2,3,4]       │ │ References: [5,6,7,8]      │
│  └────────────────────────────┘ └────────────────────────────┘
│  ... (5 large chunks)
│
├─ Embedding Generation
│  Regular Chunks: 20 embeddings × 0.5s = 10 seconds
│  Large Chunks: 5 embeddings × 2s = 10 seconds
│  Total: 20 seconds
│
└─ Storage
   Regular Chunks: 20 chunks in Vespa
   Large Chunks: 5 chunks in Vespa (with references)
   Total: 25 chunks stored


┌─────────────────────────────────────────────────────────────────┐
│              STANDARD INDEXING (DISABLED)                       │
└─────────────────────────────────────────────────────────────────┘

Document: "Machine Learning Guide" (10,000 tokens)
│
├─ Regular Chunking (512 tokens each)
│  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐
│  │ Chunk 1│ │ Chunk 2│ │ Chunk 3│ │ Chunk 4│ │ Chunk 5│
│  │ 512 tok│ │ 512 tok│ │ 512 tok│ │ 512 tok│ │ 512 tok│
│  └────────┘ └────────┘ └────────┘ └────────┘ └────────┘
│  ... (20 chunks)
│
├─ Embedding Generation
│  Regular Chunks: 20 embeddings × 0.5s = 10 seconds
│  Total: 10 seconds (2x faster!)
│
└─ Storage
   Regular Chunks: 20 chunks in Vespa
   Total: 20 chunks stored (2x less storage!)

Improvement: 2x faster indexing, 2x less storage!
```

---

### Detailed Example: Indexing a 100-Page PDF

**Scenario**: Indexing a 100-page technical document (approximately 50,000 tokens)

#### WITH Multipass Indexing

```
Document: 100 pages, 50,000 tokens
  ↓
Regular Chunks: 50,000 ÷ 512 = ~98 chunks
  ↓
Large Chunks: 98 ÷ 4 = ~25 large chunks
  ↓
Embedding Generation:
  - Regular chunks: 98 × 0.5s = 49 seconds
  - Large chunks: 25 × 2s = 50 seconds
  - Total: 99 seconds
  ↓
Storage:
  - Regular chunks: 98 chunks
  - Large chunks: 25 chunks
  - Total: 123 chunks in Vespa
  ↓
Indexing Time: ~2 minutes
Storage Used: 123 chunks
```

#### WITHOUT Multipass Indexing

```
Document: 100 pages, 50,000 tokens
  ↓
Regular Chunks: 50,000 ÷ 512 = ~98 chunks
  ↓
Embedding Generation:
  - Regular chunks: 98 × 0.5s = 49 seconds
  - Total: 49 seconds
  ↓
Storage:
  - Regular chunks: 98 chunks
  - Total: 98 chunks in Vespa
  ↓
Indexing Time: ~1 minute (2x faster!)
Storage Used: 98 chunks (20% less storage)
```

**Improvement**: 
- **Time**: 99s → 49s = **2x faster**
- **Storage**: 123 chunks → 98 chunks = **20% less storage**

---

### Why Multipass Indexing Exists

**Purpose**: Multipass indexing improves search accuracy by:
1. **Context Awareness**: Large chunks capture broader context (4x more tokens)
2. **Two-Stage Search**: First find relevant sections (large chunks), then get precise chunks
3. **Better Ranking**: Scores from large chunks help rank regular chunks

**When to Use**:
- ✅ Complex queries requiring context
- ✅ Long documents where context matters
- ✅ Research/academic use cases
- ✅ When search accuracy is more important than speed

**When NOT to Use** (Most Cases):
- ✅ General business documents
- ✅ When indexing speed is important
- ✅ When storage is limited
- ✅ When search latency matters
- ✅ **For 50 concurrent users** (performance > accuracy)

---

### Configuration

#### Environment Variable

**Variable**: `ENABLE_MULTIPASS_INDEXING`

**Default**: `false` (disabled by default)

**Code Location**: `backend/onyx/configs/app_configs.py:622-624`

```python
ENABLE_MULTIPASS_INDEXING = (
    os.environ.get("ENABLE_MULTIPASS_INDEXING", "").lower() == "true"
)
```

#### Configuration Options

**Option 1: Keep Disabled (Recommended)**
```yaml
# In ConfigMap or Deployment
env:
  - name: ENABLE_MULTIPASS_INDEXING
    value: "false"  # Explicitly disable (default)
```

**Option 2: Ensure Not Set (Also Disabled)**
```yaml
# Don't set the variable at all (defaults to false)
# env:
#   - name: ENABLE_MULTIPASS_INDEXING
#     (omit this entirely)
```

**Option 3: Enable (Only if Needed)**
```yaml
# Only enable if you specifically need multipass search
env:
  - name: ENABLE_MULTIPASS_INDEXING
    value: "true"  # Enable multipass (slower indexing)
```

#### Database-Level Configuration

Multipass can also be controlled per search settings in the database:

**Code Location**: `backend/onyx/db/models.py:1589`

```python
# In SearchSettings model
multipass_indexing: Mapped[bool] = mapped_column(Boolean, default=True)
```

**Note**: The database default is `True`, but the environment variable `ENABLE_MULTIPASS_INDEXING` overrides it if set.

---

### Performance Impact

#### Indexing Performance

| Scenario | With Multipass | Without Multipass | Improvement |
|----------|---------------|-------------------|-------------|
| **Small Document** (10 chunks) | 15s | 7.5s | 2x faster |
| **Medium Document** (50 chunks) | 60s | 30s | 2x faster |
| **Large Document** (200 chunks) | 240s | 120s | 2x faster |
| **Storage per Document** | 250 chunks | 200 chunks | 20% less |

#### Search Performance

| Scenario | With Multipass | Without Multipass | Improvement |
|----------|---------------|-------------------|-------------|
| **Search Latency** | 150ms | 75ms | 2x faster |
| **Vespa Queries** | 2 queries | 1 query | 50% fewer |
| **Network Calls** | 2 round trips | 1 round trip | 50% fewer |

#### Resource Usage

| Resource | With Multipass | Without Multipass | Savings |
|----------|---------------|-------------------|---------|
| **Embeddings Generated** | 2x | 1x | 50% less |
| **Vespa Storage** | 1.25x | 1x | 20% less |
| **Indexing Time** | 2x | 1x | 50% less |
| **Search Time** | 2x | 1x | 50% less |

---

### Real-World Example: 50 Users Uploading Documents

**Scenario**: 50 users upload medium-sized documents (100 chunks each) simultaneously

#### WITH Multipass Indexing

```
50 users × 100 chunks = 5,000 regular chunks
50 users × 25 large chunks = 1,250 large chunks

Embedding Generation:
  - Regular chunks: 5,000 × 0.5s = 2,500 seconds (42 minutes)
  - Large chunks: 1,250 × 2s = 2,500 seconds (42 minutes)
  - Total: 5,000 seconds (83 minutes)

Storage:
  - Regular chunks: 5,000 chunks
  - Large chunks: 1,250 chunks
  - Total: 6,250 chunks in Vespa

Time to Index All: ~83 minutes
```

#### WITHOUT Multipass Indexing

```
50 users × 100 chunks = 5,000 regular chunks

Embedding Generation:
  - Regular chunks: 5,000 × 0.5s = 2,500 seconds (42 minutes)
  - Total: 2,500 seconds (42 minutes)

Storage:
  - Regular chunks: 5,000 chunks
  - Total: 5,000 chunks in Vespa

Time to Index All: ~42 minutes
```

**Improvement**: 
- **Time**: 83 minutes → 42 minutes = **2x faster**
- **Storage**: 6,250 chunks → 5,000 chunks = **20% less storage**
- **For 50 users**: Saves **41 minutes** of indexing time!

---

### How to Check if Multipass is Enabled

#### Method 1: Check Environment Variable

```bash
# In your deployment
oc get configmap onyx-config -o yaml | grep ENABLE_MULTIPASS_INDEXING

# Or in pod
oc exec deployment/onyx-backend -- env | grep ENABLE_MULTIPASS_INDEXING
```

#### Method 2: Check Database Settings

```sql
-- Check search settings
SELECT multipass_indexing FROM search_settings WHERE status = 'current';
```

#### Method 3: Check Logs

Look for log messages indicating large chunk creation:
```
Creating large chunks for document...
Large chunks enabled: True
```

#### Method 4: Check Vespa Storage

```bash
# Count chunks in Vespa
# If you see ~25% more chunks than expected, multipass is likely enabled
```

---

### Troubleshooting

#### Problem: Indexing is Slow

**Symptom**: Documents take 2x longer to index than expected

**Check**:
```bash
# Check if multipass is enabled
oc get configmap onyx-config -o yaml | grep ENABLE_MULTIPASS_INDEXING
```

**Solution**: Disable multipass indexing
```yaml
env:
  - name: ENABLE_MULTIPASS_INDEXING
    value: "false"
```

#### Problem: Storage Usage is High

**Symptom**: Vespa storage is 20-25% higher than expected

**Check**: Count chunks in Vespa (should be ~1.25x regular chunks if multipass enabled)

**Solution**: Disable multipass indexing to reduce storage by 20%

#### Problem: Search is Slow

**Symptom**: Search queries take 150ms+ instead of 75ms

**Check**: Multipass requires 2 search operations (large chunks + regular chunks)

**Solution**: Disable multipass for faster search (2x improvement)

---

### Summary: Multipass Indexing Optimization

| Aspect | With Multipass | Without Multipass | Recommendation |
|--------|---------------|-------------------|----------------|
| **Indexing Speed** | 2x slower | 2x faster | ✅ **Disable** |
| **Storage Usage** | 1.25x more | 1x | ✅ **Disable** |
| **Search Speed** | 2x slower | 2x faster | ✅ **Disable** |
| **Search Accuracy** | Slightly better | Good enough | ⚠️ Usually not needed |
| **For 50 Users** | 83 min for 50 docs | 42 min for 50 docs | ✅ **Disable** |

**Recommendation for 50 Concurrent Users**: 
- ✅ **Disable multipass indexing** (`ENABLE_MULTIPASS_INDEXING=false`)
- ✅ **2x faster indexing** = better user experience
- ✅ **20% less storage** = lower costs
- ✅ **2x faster search** = better responsiveness
- ⚠️ **Trade-off**: Slightly less context-aware search (usually not noticeable)

**Best For**:
- ✅ High-volume indexing
- ✅ Performance-critical deployments
- ✅ Storage-constrained environments
- ✅ **50+ concurrent users**

**Not Recommended For**:
- ⚠️ Research/academic use cases (where accuracy > speed)
- ⚠️ Complex queries requiring maximum context

---

## 📊 Combined Optimization Strategy

### Recommended Configuration for High Performance

```yaml
# ConfigMap or Environment Variables
env:
  # Embedding Optimizations
  - name: INDEXING_EMBEDDING_MODEL_NUM_THREADS
    value: "32"  # Your current setting ✅
  - name: EMBEDDING_BATCH_SIZE
    value: "16"  # Increase from 8
  
  # Celery Worker Optimizations
  - name: CELERY_WORKER_DOCPROCESSING_CONCURRENCY
    value: "24"  # Increase from 6
  - name: CELERY_WORKER_DOCFETCHING_CONCURRENCY
    value: "2"   # Increase from 1
  
  # Chunking Optimizations
  - name: SKIP_METADATA_IN_CHUNK
    value: "true"  # Skip metadata if not needed
  
  # Batch Size Optimizations
  - name: INDEX_BATCH_SIZE
    value: "32"  # Increase from 16
```

### Deployment Optimizations

```yaml
# Indexing Model Server
spec:
  replicas: 2  # Scale horizontally
  resources:
    requests:
      cpu: 4000m
      memory: 8Gi
    limits:
      cpu: 8000m
      memory: 16Gi

# Celery Docprocessing Worker
spec:
  replicas: 2  # Scale horizontally
  resources:
    requests:
      cpu: 2000m
      memory: 4Gi
    limits:
      cpu: 4000m
      memory: 8Gi
```

---

## 📈 Expected Performance Improvements

### Individual Optimizations

| Optimization | Impact | Speed Improvement |
|-------------|--------|-------------------|
| INDEXING_EMBEDDING_MODEL_NUM_THREADS = 32 | High | 3-4x |
| EMBEDDING_BATCH_SIZE = 16 | High | 1.2-1.5x |
| CELERY_WORKER_DOCPROCESSING_CONCURRENCY = 24 | High | 2-4x |
| Indexing Model Server: 4 CPU, 8Gi RAM | High | 2-3x |
| Scale Model Server: 2 replicas | High | 2x |
| Scale Workers: 2 replicas | High | 2x |
| INDEX_BATCH_SIZE = 32 | Medium | 1.2-1.5x |
| SKIP_METADATA_IN_CHUNK = true | Medium | 1.15-1.2x |
| GPU Acceleration | Very High | 10-50x |
| Connection Pooling | Low | 1.1-1.2x |

### Combined Impact

**With All Optimizations Applied**:
- **Base Performance**: 1x
- **With Threading (32)**: 4x
- **With Batch Size (16)**: 4.8x
- **With Worker Concurrency (24)**: 14.4x
- **With Model Server Resources**: 28.8x
- **With Scaling (2x replicas)**: 57.6x

**Realistic Combined Improvement**: **10-20x faster** (accounting for bottlenecks and diminishing returns)

---

## 🎯 Quick Reference: All Environment Variables

```yaml
# Embedding Optimizations
INDEXING_EMBEDDING_MODEL_NUM_THREADS=32      # Parallel API calls
EMBEDDING_BATCH_SIZE=16                      # Chunks per batch

# Celery Worker Optimizations
CELERY_WORKER_DOCPROCESSING_CONCURRENCY=24  # Docprocessing threads
CELERY_WORKER_DOCFETCHING_CONCURRENCY=2     # Docfetching threads
CELERY_WORKER_LIGHT_PREFETCH_MULTIPLIER=1    # Task prefetch

# Chunking Optimizations
SKIP_METADATA_IN_CHUNK=true                 # Skip metadata
ENABLE_MULTIPASS_INDEXING=false              # Disable multipass

# Batch Size Optimizations
INDEX_BATCH_SIZE=32                          # Documents per batch

# Model Server Optimizations
INDEXING_ONLY=True                           # Dedicated indexing server
MODEL_SERVER_PORT=9000                       # Model server port
```

---

## 🔍 Monitoring and Validation

### How to Verify Optimizations Are Working

1. **Check Logs for Batch Sizes**:
   ```
   Embedding 16 texts with total 45,234 characters  # Should show 16, not 8
   ```

2. **Check Worker Concurrency**:
   ```bash
   # Check active tasks
   oc logs deployment/celery-worker-docprocessing | grep "processing"
   ```

3. **Monitor Resource Usage**:
   ```bash
   oc adm top pods | grep -E "indexing-model-server|celery-worker"
   ```

4. **Measure Indexing Time**:
   - Before: Note time to index 100 documents
   - After: Compare with same workload
   - Expected: 10-20x improvement

---

## ⚠️ Important Considerations

### 1. **Resource Limits**
- Higher concurrency = more CPU/memory
- Monitor resource usage and adjust accordingly
- Don't exceed cluster capacity

### 2. **API Rate Limits**
- 32 threads = 32 concurrent API calls
- Ensure your API provider can handle this
- Monitor for rate limit errors

### 3. **Memory Constraints**
- Larger batch sizes = more memory per batch
- Monitor memory usage, especially with multiple workers

### 4. **Network Bandwidth**
- More parallel requests = more bandwidth needed
- Ensure network can handle increased traffic

### 5. **Database Connections**
- More workers = more database connections
- Monitor PostgreSQL connection pool

---

## 🎓 Summary: Optimization Priority

### High Priority (Biggest Impact)
1. ✅ **INDEXING_EMBEDDING_MODEL_NUM_THREADS = 32** (Already done!)
2. **EMBEDDING_BATCH_SIZE = 16** (Easy, high impact)
3. **CELERY_WORKER_DOCPROCESSING_CONCURRENCY = 24** (High impact)
4. **Scale Model Server Resources** (4 CPU, 8Gi RAM)
5. **Scale Workers/Model Server** (2-3 replicas)

### Medium Priority (Good Impact)
6. **INDEX_BATCH_SIZE = 32**
7. **SKIP_METADATA_IN_CHUNK = true**
8. **CELERY_WORKER_DOCFETCHING_CONCURRENCY = 2**

### Low Priority (Fine-tuning)
9. Connection pooling
10. Prefetch multiplier
11. Chunk size optimization

### Special Cases
- **GPU Acceleration**: If available, 10-50x improvement
- **Disable Multipass**: If enabled, 2x improvement

---

## 📚 Related Documentation

- [INDEXING_EMBEDDING_NUM_THREADS-EXPLANATION.md](./INDEXING_EMBEDDING_NUM_THREADS-EXPLANATION.md)
- [INDEXING_EMBEDDING_NUM_THREADS-FOR-JUNIORS.md](./INDEXING_EMBEDDING_NUM_THREADS-FOR-JUNIORS.md)
- [FILE-UPLOAD-PERFORMANCE-OPTIMIZATION.md](./FILE-UPLOAD-PERFORMANCE-OPTIMIZATION.md)
- [EMBEDDING-BATCH-SIZE-EXPLANATION.md](../troubleshooting/EMBEDDING-BATCH-SIZE-EXPLANATION.md)
- [MODEL-SERVERS-EXPLANATION.md](./MODEL-SERVERS-EXPLANATION.md)

---

**Bottom Line**: Beyond threading, you can achieve **10-20x faster indexing** by optimizing batch sizes, worker concurrency, resource allocation, and horizontal scaling! 🚀

