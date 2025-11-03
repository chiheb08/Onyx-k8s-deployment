# Why Embedding Batch Size is Always 8

## What You're Seeing

When reading Indexing Model Server logs, you see messages like:

```
Embedding 8 texts with total 45,234 characters with local model: nomic-ai/nomic-embed-text-v1
Successfully embedded 8 texts with total 45,234 characters with local model nomic-ai/nomic-embed-text-v1 in 0.23s
```

## Why Always 8?

The batch size of **8 is the default configuration** for local embedding models (your Indexing Model Server).

### Configuration Source

**File:** `onyx-repo/backend/onyx/configs/model_configs.py`

```python
# Line 43-46
# User's set embedding batch size overrides the default encoding batch sizes
EMBEDDING_BATCH_SIZE = int(os.environ.get("EMBEDDING_BATCH_SIZE") or 0) or None

BATCH_SIZE_ENCODE_CHUNKS = EMBEDDING_BATCH_SIZE or 8
```

**Code comment says:**
```python
# Purely an optimization, memory limitation consideration
```

### How It Works

1. **Default Value**: `BATCH_SIZE_ENCODE_CHUNKS = 8` (if `EMBEDDING_BATCH_SIZE` is not set)
2. **Used for Local Models**: When using your local Indexing Model Server (not API-based services)
3. **Batch Processing**: Documents are chunked, then embeddings are generated in batches of 8 chunks at a time

### Example Flow

```
Large Document (200 chunks)
  ↓
Chunk 1-8   → Batch 1 → Indexing Model Server → "Embedding 8 texts..."
Chunk 9-16  → Batch 2 → Indexing Model Server → "Embedding 8 texts..."
Chunk 17-24 → Batch 3 → Indexing Model Server → "Embedding 8 texts..."
...and so on (25 batches total)
```

## Why 8 and Not More?

### 1. **Memory Constraints**
- Each text chunk is tokenized and processed through the embedding model
- Larger batches = more GPU/CPU memory required
- Default of 8 balances throughput vs memory usage

### 2. **Processing Efficiency**
- Smaller batches = faster individual processing
- Better for real-time indexing
- Reduces risk of timeouts

### 3. **Model Server Capacity**
- Local model servers (using CPU or limited GPU) have memory limits
- Processing 8 chunks at a time prevents OOM (Out of Memory) errors

### 4. **Different for API Services**
Note: For **API-based embedding services** (OpenAI, Azure, etc.), the batch size is much larger:

```python
# Line 48
BATCH_SIZE_ENCODE_CHUNKS_FOR_API_EMBEDDING_SERVICES = EMBEDDING_BATCH_SIZE or 512
```

This is because:
- API services handle batching on their end
- No local memory constraints
- Sending larger batches reduces API calls

## Where the Batch Size is Used

**File:** `onyx-repo/backend/onyx/natural_language_processing/search_nlp_models.py`

```python
# Line 675-685
def _batch_encode_texts(
    self,
    texts: list[str],
    text_type: EmbedTextType,
    batch_size: int,  # ← This is 8 for local models
    max_seq_length: int,
    ...
) -> list[Embedding]:
    text_batches = batch_list(texts, batch_size)  # ← Splits into batches of 8
    
    # Then processes each batch
    for idx, text_batch in enumerate(text_batches, start=1):
        # Sends batch to model server
        response = self._make_model_server_request(...)
```

**Model Server logs the batch:**
```python
# File: onyx-repo/backend/model_server/encoders.py
# Line 151-152
logger.info(
    f"Embedding {len(texts)} texts with {total_chars} total characters with local model: {model_name}"
)
```

## Can You Change It?

### Yes! Set Environment Variable

**In your ConfigMap or Deployment YAML:**

```yaml
env:
  - name: EMBEDDING_BATCH_SIZE
    value: "16"  # or 32, 64, etc.
```

**Or via command line:**
```bash
export EMBEDDING_BATCH_SIZE=16
```

### Considerations When Changing

**Increasing Batch Size (e.g., 8 → 16 or 32):**

✅ **Pros:**
- Faster overall processing (fewer API calls to model server)
- Better GPU utilization (if using GPU)
- Reduced overhead

❌ **Cons:**
- Higher memory usage (may cause OOM errors)
- Longer processing time per batch
- Higher risk of timeouts

**Decreasing Batch Size (e.g., 8 → 4):**

✅ **Pros:**
- Lower memory usage
- Faster per-batch processing
- More frequent progress updates

❌ **Cons:**
- More API calls to model server (overhead)
- Slower overall indexing
- Less efficient

### Recommended Values

| Resource Available | Recommended Batch Size | Reason |
|-------------------|----------------------|---------|
| Low memory (< 4GB) | 4-8 | Prevent OOM errors |
| Medium memory (4-8GB) | 8-16 | Good balance |
| High memory (8GB+) | 16-32 | Better throughput |
| GPU available | 32-64 | GPU can handle larger batches |

## Current Configuration Check

To see what batch size is currently configured:

```bash
# Check environment variable
kubectl get configmap <configmap-name> -n onyx -o yaml | grep EMBEDDING_BATCH_SIZE

# Or check in pod
kubectl exec deployment/indexing-model-server -n onyx -- env | grep EMBEDDING_BATCH_SIZE
```

If nothing is set, it defaults to **8**.

## Summary

- **8 is the default batch size** for local embedding models
- It's optimized for **memory efficiency** and **processing speed**
- Designed to prevent OOM errors on resource-constrained systems
- Can be changed via `EMBEDDING_BATCH_SIZE` environment variable
- For API-based services, the batch size is much larger (512) because they handle batching differently

**The logs showing "Embedding 8 texts" are normal behavior** - it means your document chunks are being processed efficiently in batches of 8!

