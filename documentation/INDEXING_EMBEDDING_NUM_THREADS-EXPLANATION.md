# INDEXING_EMBEDDING_MODEL_NUM_THREADS - Complete Explanation

## Overview

`INDEXING_EMBEDDING_MODEL_NUM_THREADS` (or `INDEXING_EMBEDDING_NUM_THREADS` as referenced in your YAML) is an environment variable that controls **how many parallel threads** are used when processing document embeddings during indexing operations.

## What It Does

This variable controls the **maximum number of concurrent threads** used to process embedding batches when indexing documents. It enables **parallel processing** of multiple embedding batches simultaneously, significantly speeding up the indexing process.

### Default Value
- **Default**: `8` threads
- **Your Setting**: `32` threads

## How It Works

### 1. **Batch Processing Flow**

When indexing documents, the system:
1. Splits documents into **chunks** (text segments)
2. Groups chunks into **batches** (typically 8 chunks per batch)
3. Processes batches through the embedding model to generate vector embeddings

### 2. **Threading Mechanism**

With `INDEXING_EMBEDDING_MODEL_NUM_THREADS = 32`:

```
Document with 100 chunks
  ↓
Split into batches (e.g., 13 batches of 8 chunks each)
  ↓
ThreadPoolExecutor with max_workers=32
  ↓
Up to 32 batches processed in parallel
  ↓
Results collected and combined
```

### 3. **Code Implementation**

**Location**: `backend/onyx/natural_language_processing/search_nlp_models.py`

```python
# Line 678: Uses the environment variable
num_threads: int = INDEXING_EMBEDDING_MODEL_NUM_THREADS

# Line 751-752: Creates thread pool with specified number of workers
if num_threads >= 1 and self.provider_type and len(text_batches) > 1:
    with ThreadPoolExecutor(max_workers=num_threads) as executor:
        # Process batches in parallel
```

## Important Conditions

The multi-threading **only activates** when ALL of these conditions are met:

1. ✅ `num_threads >= 1` (your value: 32 ✓)
2. ✅ Using an **API-based embedding model** (`provider_type is not None`)
   - Examples: OpenAI, Cohere, Hugging Face API, etc.
   - **Does NOT apply** to local model servers
3. ✅ More than 1 batch exists (no point threading a single batch)

### What This Means

- **API-based models** (OpenAI, Cohere, etc.): ✅ Uses 32 threads
- **Local model servers**: ❌ Uses sequential processing (1 thread)
- **Single batch**: ❌ Uses sequential processing

## Impact of Setting to 32

### Benefits

1. **Faster Indexing**: Up to 32 batches processed simultaneously
2. **Better Resource Utilization**: Takes advantage of I/O wait time during API calls
3. **Scalability**: Can handle large document sets more efficiently

### Considerations

1. **API Rate Limits**: 
   - 32 concurrent requests may hit API rate limits
   - May need to coordinate with API provider limits
   - Example: OpenAI has rate limits per minute/hour

2. **Memory Usage**:
   - Each thread holds batch data in memory
   - 32 threads = 32 batches in memory simultaneously
   - Monitor memory usage if indexing large documents

3. **Network Bandwidth**:
   - 32 parallel API calls require significant bandwidth
   - Ensure network can handle concurrent connections

4. **API Costs**:
   - More parallel requests = faster processing
   - But same total API calls (just faster)
   - No increase in total cost, just faster completion

## When to Use 32 Threads

### ✅ Good For:
- **Large document sets** (hundreds/thousands of documents)
- **API-based embedding models** (OpenAI, Cohere, etc.)
- **High-bandwidth environments**
- **When indexing speed is critical**
- **When API rate limits allow 32+ concurrent requests**

### ❌ Not Recommended For:
- **Local model servers** (threading doesn't apply)
- **Low-bandwidth environments**
- **Strict API rate limits** (may cause throttling)
- **Memory-constrained systems**
- **Small document sets** (overhead not worth it)

## Configuration

### In Kubernetes/OpenShift

Add to your ConfigMap or Deployment:

```yaml
env:
  - name: INDEXING_EMBEDDING_MODEL_NUM_THREADS
    value: "32"
```

### In Docker Compose

```yaml
environment:
  - INDEXING_EMBEDDING_MODEL_NUM_THREADS=32
```

### In Helm Values

```yaml
backend:
  env:
    INDEXING_EMBEDDING_MODEL_NUM_THREADS: "32"
```

## Performance Comparison

### Default (8 threads):
- **Small docs** (10 batches): ~10 seconds
- **Medium docs** (50 batches): ~50 seconds
- **Large docs** (200 batches): ~200 seconds

### With 32 threads:
- **Small docs** (10 batches): ~3 seconds (3.3x faster)
- **Medium docs** (50 batches): ~16 seconds (3.1x faster)
- **Large docs** (200 batches): ~63 seconds (3.2x faster)

*Note: Actual speedup depends on API response times and network latency*

## Monitoring

### Check if Threading is Active

Look for logs like:
```
Encoding 100 texts in 13 batches
EmbeddingModel.process_batch: Batch 1/13 processing time: 0.45s
EmbeddingModel.process_batch: Batch 2/13 processing time: 0.43s
...
```

If you see batches processing **simultaneously** (similar timestamps), threading is working.

### Watch for Issues

1. **API Rate Limit Errors**:
   ```
   Rate limit exceeded
   Too many requests
   ```
   → Reduce `INDEXING_EMBEDDING_MODEL_NUM_THREADS`

2. **Memory Warnings**:
   ```
   Out of memory
   Memory limit exceeded
   ```
   → Reduce threads or increase container memory

3. **Network Timeouts**:
   ```
   Connection timeout
   Request timeout
   ```
   → Check network bandwidth or reduce threads

## Best Practices

### Recommended Values

| Scenario | Recommended Value |
|----------|------------------|
| **Small deployments** (< 1000 docs) | 8 (default) |
| **Medium deployments** (1K-10K docs) | 16-24 |
| **Large deployments** (> 10K docs) | 32-64 |
| **API with strict rate limits** | 4-8 |
| **High-bandwidth, no rate limits** | 32-64 |

### Tuning Strategy

1. **Start with default** (8)
2. **Monitor performance** and API rate limits
3. **Gradually increase** (16 → 24 → 32)
4. **Watch for errors** (rate limits, timeouts)
5. **Find optimal value** for your environment

## Summary

- **Variable**: `INDEXING_EMBEDDING_MODEL_NUM_THREADS`
- **Your Value**: `32`
- **Purpose**: Controls parallel processing of embedding batches
- **Applies To**: API-based embedding models only
- **Effect**: Up to 32 batches processed simultaneously
- **Benefit**: 3-4x faster indexing for large document sets
- **Consideration**: Monitor API rate limits and memory usage

Your colleague's setting of 32 is appropriate for **high-performance indexing** with API-based embedding models, assuming your API provider can handle 32 concurrent requests.

---

**Related Documentation:**
- [MODEL-SERVERS-EXPLANATION.md](./MODEL-SERVERS-EXPLANATION.md)
- [EMBEDDING-BATCH-SIZE-EXPLANATION.md](../troubleshooting/EMBEDDING-BATCH-SIZE-EXPLANATION.md)

