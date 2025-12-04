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

Optimizes HTTP connection reuse to reduce connection overhead.

**Current**: Default httpx connection pool (20 connections)  
**Recommended**: Increase pool size for high-volume indexing

### How It Works

```
Without Connection Pooling:
Request 1 → New connection → Process → Close
Request 2 → New connection → Process → Close
Overhead: Connection setup time

With Connection Pooling:
Request 1 → Reuse connection → Process → Keep alive
Request 2 → Reuse connection → Process → Keep alive
Overhead: Minimal
```

### Configuration

**Code Location**: `backend/onyx/background/celery/celery_utils.py`

```python
# Current (for Vespa)
httpx_init_vespa_pool(20)  # 20 keepalive connections

# Optimized (if code supports)
httpx_init_vespa_pool(50)  # More connections for high volume
```

### Impact

- **Speed Improvement**: 1.1-1.2x faster
- **Best For**: High-volume indexing, network latency issues

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

Disables the creation of additional "large chunks" for multipass indexing, reducing processing time.

**Default**: Disabled (if not explicitly enabled)  
**Recommended**: Keep disabled unless you need multipass indexing

### How It Works

```
With Multipass Indexing (ENABLE_MULTIPASS_INDEXING = true):
Document → Chunks → Large Chunks (4x size)
  ↓
2x more embeddings to generate
2x more storage
2x more processing time

Without Multipass Indexing (default):
Document → Chunks
  ↓
Standard processing
Faster indexing
```

### Configuration

**Environment Variable**: `ENABLE_MULTIPASS_INDEXING`

```yaml
# Keep it disabled (default) or explicitly set to false
env:
  - name: ENABLE_MULTIPASS_INDEXING
    value: "false"  # Disable for faster indexing
```

**Code Location**: `backend/onyx/configs/app_configs.py:594-596`

### Impact

- **Speed Improvement**: 2x faster (if currently enabled)
- **Trade-off**: Less accurate results (but usually not needed)

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

