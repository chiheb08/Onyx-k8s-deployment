# Hugging Face Models Flow in Onyx Model Servers

Complete visual explanation of how model servers download, cache, and use Hugging Face models.

---

## 🏗️ High-Level Architecture: Model Servers & Hugging Face

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        🌐 HUGGING FACE HUB                              │
│                     https://huggingface.co/                             │
│                                                                         │
│  📦 Models Repository:                                                  │
│  ├─ nomic-ai/nomic-embed-text-v1 (~1.5GB)                             │
│  ├─ mixedbread-ai/mxbai-rerank-xsmall-v1 (~200MB)                     │
│  ├─ onyx-dot-app/hybrid-intent-token-classifier (~100MB)              │
│  ├─ onyx-dot-app/information-content-model (~100MB)                   │
│  ├─ distilbert-base-uncased (tokenizer)                               │
│  └─ intfloat/e5-base-v2, intfloat/e5-small-v2, etc.                  │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ (Download during Docker build
                                    │  + runtime on first use)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│               🐳 DOCKER IMAGE BUILD (Dockerfile.model_server)           │
│                                                                         │
│  Pre-download Models:                                                  │
│  ┌───────────────────────────────────────────────────────────┐        │
│  │ RUN python -c "                                            │        │
│  │   from huggingface_hub import snapshot_download;          │        │
│  │   snapshot_download('nomic-ai/nomic-embed-text-v1');     │        │
│  │   snapshot_download('mixedbread-ai/mxbai-rerank-xsmall-v1');│     │
│  │   snapshot_download('onyx-dot-app/hybrid-intent-...');    │        │
│  │   snapshot_download('onyx-dot-app/information-content-...');│      │
│  │   ...                                                      │        │
│  │ "                                                          │        │
│  └───────────────────────────────────────────────────────────┘        │
│                                                                         │
│  Result: Models stored in /app/.cache/temp_huggingface/                │
│  Image Size: ~3GB per model server image                              │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ (Deploy image)
                                    ▼
         ┌──────────────────────────────────────────────────┐
         │                                                  │
         ▼                                                  ▼
┌────────────────────────┐                    ┌────────────────────────┐
│  🤖 INFERENCE MODEL    │                    │  🤖 INDEXING MODEL     │
│     SERVER             │                    │     SERVER             │
│                        │                    │                        │
│  Container 1           │                    │  Container 2           │
│  Port: 9000            │                    │  Port: 9000            │
│  Env: (none)           │                    │  Env: INDEXING_ONLY=True│
└────────────────────────┘                    └────────────────────────┘
         │                                                  │
         │                                                  │
         ▼                                                  ▼
┌────────────────────────┐                    ┌────────────────────────┐
│  💾 MODEL CACHE        │                    │  💾 MODEL CACHE        │
│  VOLUME                │                    │  VOLUME                │
│                        │                    │                        │
│  /app/.cache/          │                    │  /app/.cache/          │
│  huggingface/          │                    │  huggingface/          │
│                        │                    │                        │
│  📁 models--nomic-ai-- │                    │  📁 models--nomic-ai-- │
│     nomic-embed-text-v1│                    │     nomic-embed-text-v1│
│  📁 models--mixedbread-│                    │  📁 models--mixedbread-│
│     ai--mxbai-rerank-  │                    │     ai--mxbai-rerank-  │
│     xsmall-v1          │                    │     xsmall-v1          │
│  📁 models--onyx-dot-  │                    │  📁 models--onyx-dot-  │
│     app--hybrid-intent-│                    │     app--information-  │
│     token-classifier   │                    │     content-model      │
│                        │                    │                        │
│  Size: ~2-3GB          │                    │  Size: ~2-3GB          │
└────────────────────────┘                    └────────────────────────┘
         │                                                  │
         │ (Models loaded into memory)                     │
         │                                                  │
         ▼                                                  ▼
┌────────────────────────┐                    ┌────────────────────────┐
│  🧠 IN-MEMORY MODELS   │                    │  🧠 IN-MEMORY MODELS   │
│                        │                    │                        │
│  • Embedding Model     │                    │  • Embedding Model     │
│    (nomic-embed-text)  │                    │    (nomic-embed-text)  │
│  • Reranking Model     │                    │  • Reranking Model     │
│    (mxbai-rerank)      │                    │    (mxbai-rerank)      │
│  • Intent Classifier   │                    │  • Content Classifier  │
│    (hybrid-intent)     │                    │    (info-content)      │
│                        │                    │                        │
│  RAM Usage: ~2GB       │                    │  RAM Usage: ~2GB       │
└────────────────────────┘                    └────────────────────────┘
         │                                                  │
         │                                                  │
         ▼                                                  ▼
┌────────────────────────┐                    ┌────────────────────────┐
│  🔄 PROCESSES REQUESTS │                    │  🔄 PROCESSES REQUESTS │
│                        │                    │                        │
│  Used by:              │                    │  Used by:              │
│  • API Server          │                    │  • Background Workers  │
│                        │                    │                        │
│  Purpose:              │                    │  Purpose:              │
│  • User query →        │                    │  • Document chunks →   │
│    embeddings          │                    │    embeddings          │
│  • Real-time search    │                    │  • Bulk indexing       │
│                        │                    │                        │
│  Workload:             │                    │  Workload:             │
│  • Single queries      │                    │  • Batch processing    │
│  • Low latency         │                    │  • High throughput     │
└────────────────────────┘                    └────────────────────────┘
```

---

## 📥 Download & Caching Flow

```
╔═══════════════════════════════════════════════════════════════════════╗
║                     FIRST TIME STARTUP (NO CACHE)                     ║
╚═══════════════════════════════════════════════════════════════════════╝

Step 1: Container Starts
┌─────────────────────────────────────────────────────────────────────┐
│  Container: inference-model-server                                  │
│  Status: Starting...                                                │
│  Volume: Empty (or contains pre-downloaded models from image)       │
└─────────────────────────────────────────────────────────────────────┘
                              ▼
Step 2: Check Cache Directory
┌─────────────────────────────────────────────────────────────────────┐
│  Path: /app/.cache/huggingface/                                     │
│  Status: Empty (if using emptyDir) OR Has pre-built models          │
│                                                                     │
│  IF pre-built models exist:                                         │
│    Move from /app/.cache/temp_huggingface/ → /app/.cache/huggingface/│
└─────────────────────────────────────────────────────────────────────┘
                              ▼
Step 3: Model Loading (SentenceTransformer)
┌─────────────────────────────────────────────────────────────────────┐
│  Code: model = SentenceTransformer('nomic-ai/nomic-embed-text-v1') │
│                                                                     │
│  Check 1: Local cache exists?                                       │
│  ├─ YES → Load from /app/.cache/huggingface/                       │
│  └─ NO  → Download from Hugging Face Hub                           │
│                                                                     │
│  Download Process (if needed):                                      │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │ 1. Connect to https://huggingface.co/                         │ │
│  │ 2. Download model files:                                      │ │
│  │    • config.json                                              │ │
│  │    • model.safetensors (or pytorch_model.bin)                 │ │
│  │    • tokenizer_config.json                                    │ │
│  │    • special_tokens_map.json                                  │ │
│  │    • vocab.txt                                                │ │
│  │ 3. Save to: /app/.cache/huggingface/models--nomic-ai--nomic-...│ │
│  │ 4. Total size: ~1.5GB                                         │ │
│  │ 5. Time: 2-10 minutes (depends on internet speed)             │ │
│  └───────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                              ▼
Step 4: Model Warmup
┌─────────────────────────────────────────────────────────────────────┐
│  Pre-warm RoPE caches:                                              │
│  • Generate dummy text                                              │
│  • Process through model                                            │
│  • Cache rotary position embeddings                                 │
│  • Result: Faster inference on real queries                         │
└─────────────────────────────────────────────────────────────────────┘
                              ▼
Step 5: Ready to Serve
┌─────────────────────────────────────────────────────────────────────┐
│  Status: READY ✅                                                   │
│  Endpoints:                                                         │
│  • POST /embed - Generate embeddings                                │
│  • POST /rerank - Rerank search results                             │
│  • GET /health - Health check                                       │
└─────────────────────────────────────────────────────────────────────┘


═════════════════════════════════════════════════════════════════════

╔═══════════════════════════════════════════════════════════════════════╗
║                    SUBSEQUENT STARTUPS (WITH CACHE)                   ║
╚═══════════════════════════════════════════════════════════════════════╝

Step 1: Container Starts
┌─────────────────────────────────────────────────────────────────────┐
│  Container: inference-model-server                                  │
│  Status: Starting...                                                │
│  Volume: Contains cached models ✅                                  │
└─────────────────────────────────────────────────────────────────────┘
                              ▼
Step 2: Check Cache Directory
┌─────────────────────────────────────────────────────────────────────┐
│  Path: /app/.cache/huggingface/                                     │
│  Status: Models found! ✅                                           │
│  • models--nomic-ai--nomic-embed-text-v1/                           │
│  • models--mixedbread-ai--mxbai-rerank-xsmall-v1/                   │
│  • models--onyx-dot-app--hybrid-intent-token-classifier/            │
└─────────────────────────────────────────────────────────────────────┘
                              ▼
Step 3: Model Loading (Fast!)
┌─────────────────────────────────────────────────────────────────────┐
│  Code: model = SentenceTransformer('nomic-ai/nomic-embed-text-v1') │
│                                                                     │
│  Check: Local cache exists? ✅ YES                                  │
│  Action: Load from /app/.cache/huggingface/ (no download!)         │
│                                                                     │
│  Time: ~30-60 seconds (just loading into memory)                    │
│  No internet required! ✅                                           │
└─────────────────────────────────────────────────────────────────────┘
                              ▼
Step 4: Model Warmup
┌─────────────────────────────────────────────────────────────────────┐
│  Pre-warm RoPE caches: ~10-20 seconds                               │
└─────────────────────────────────────────────────────────────────────┘
                              ▼
Step 5: Ready to Serve
┌─────────────────────────────────────────────────────────────────────┐
│  Status: READY ✅                                                   │
│  Total Time: ~1-2 minutes (vs 5-15 minutes first time)              │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Request Processing Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                     USER SEARCH QUERY EXAMPLE                       │
└─────────────────────────────────────────────────────────────────────┘

User types: "What is our vacation policy?"
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  API Server receives query                                          │
│  Needs to convert text → embedding vector                           │
└─────────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  API Server → Inference Model Server                                │
│  POST http://inference-model-server:9000/embed                      │
│  Body: {                                                            │
│    "texts": ["What is our vacation policy?"],                       │
│    "model_name": "nomic-ai/nomic-embed-text-v1",                   │
│    "max_context_length": 512                                        │
│  }                                                                  │
└─────────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Inference Model Server processes:                                  │
│                                                                     │
│  1. Load model from memory (already loaded)                         │
│     ├─ Model: nomic-ai/nomic-embed-text-v1                         │
│     └─ Status: Cached in RAM ✅                                     │
│                                                                     │
│  2. Tokenize text                                                   │
│     ├─ Input: "What is our vacation policy?"                        │
│     └─ Output: [101, 2054, 2003, 2256, 5840, 3343, 1029, 102]      │
│                                                                     │
│  3. Run through neural network (Hugging Face model)                 │
│     ├─ Input tokens → Transformer layers                            │
│     ├─ Process with nomic-embed-text-v1 weights                     │
│     └─ Output: 768-dimensional vector                               │
│                                                                     │
│  4. Normalize embeddings                                            │
│     ├─ Apply L2 normalization                                       │
│     └─ Result: Unit vector for cosine similarity                    │
│                                                                     │
│  Time: ~100ms                                                       │
└─────────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Return embedding vector:                                           │
│  [0.123, -0.456, 0.789, ..., 0.321] (768 values)                   │
└─────────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  API Server uses embedding for:                                     │
│  • Vector search in Vespa                                           │
│  • Find similar document chunks                                     │
│  • Retrieve relevant context                                        │
└─────────────────────────────────────────────────────────────────────┘


═════════════════════════════════════════════════════════════════════

┌─────────────────────────────────────────────────────────────────────┐
│                   DOCUMENT INDEXING EXAMPLE                         │
└─────────────────────────────────────────────────────────────────────┘

User uploads: "HR_Policy_2025.pdf"
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Background Worker receives task:                                   │
│  • Extract text from PDF                                            │
│  • Result: 50 pages of text                                         │
└─────────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Chunk document:                                                    │
│  • Split into 200 chunks (~512 tokens each)                         │
│  • Each chunk needs embedding                                       │
└─────────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Background Worker → Indexing Model Server                          │
│  POST http://indexing-model-server:9000/embed                       │
│  Body: {                                                            │
│    "texts": ["Chunk 1...", "Chunk 2...", ... "Chunk 200..."],      │
│    "model_name": "nomic-ai/nomic-embed-text-v1",                   │
│    "max_context_length": 512,                                       │
│    "batch_size": 8                                                  │
│  }                                                                  │
└─────────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Indexing Model Server processes (BATCH):                           │
│                                                                     │
│  1. Load model from memory (already loaded)                         │
│     ├─ Model: nomic-ai/nomic-embed-text-v1                         │
│     ├─ Same model as Inference Server!                              │
│     └─ But dedicated for bulk processing                            │
│                                                                     │
│  2. Process in batches (8 chunks at a time)                         │
│     ├─ Batch 1: Chunks 1-8                                          │
│     ├─ Batch 2: Chunks 9-16                                         │
│     ├─ ...                                                          │
│     └─ Batch 25: Chunks 193-200                                     │
│                                                                     │
│  3. For each batch:                                                 │
│     ├─ Tokenize all texts                                           │
│     ├─ Run through Hugging Face model                               │
│     ├─ Generate 768-dim vectors                                     │
│     └─ Normalize embeddings                                         │
│                                                                     │
│  Time: ~30-60 seconds for 200 chunks                                │
└─────────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Return 200 embedding vectors:                                      │
│  [                                                                  │
│    [0.123, -0.456, ...], // Chunk 1                                │
│    [0.789, 0.321, ...],  // Chunk 2                                │
│    ...                                                              │
│    [0.654, -0.987, ...]  // Chunk 200                              │
│  ]                                                                  │
└─────────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Background Worker stores in Vespa:                                 │
│  • Each chunk + embedding → Vespa document                          │
│  • Document ready for search!                                       │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 🗂️ File System Layout

```
Container: inference-model-server
═════════════════════════════════

/app/
├── .cache/
│   ├── temp_huggingface/  (moved to huggingface/ on startup)
│   │   ├── models--nomic-ai--nomic-embed-text-v1/
│   │   ├── models--mixedbread-ai--mxbai-rerank-xsmall-v1/
│   │   └── models--onyx-dot-app--hybrid-intent-token-classifier/
│   │
│   └── huggingface/  (active cache, mounted volume)
│       ├── models--nomic-ai--nomic-embed-text-v1/
│       │   ├── snapshots/
│       │   │   └── abc123def456.../
│       │   │       ├── config.json
│       │   │       ├── model.safetensors (1.2GB)
│       │   │       ├── tokenizer_config.json
│       │   │       ├── special_tokens_map.json
│       │   │       ├── vocab.txt
│       │   │       └── tokenizer.json
│       │   └── refs/
│       │       └── main → abc123def456...
│       │
│       ├── models--mixedbread-ai--mxbai-rerank-xsmall-v1/
│       │   └── snapshots/
│       │       └── xyz789ghi012.../
│       │           ├── config.json
│       │           ├── model.safetensors (180MB)
│       │           └── ...
│       │
│       └── models--onyx-dot-app--hybrid-intent-token-classifier/
│           └── snapshots/
│               └── def456abc789.../
│                   ├── config.json
│                   ├── pytorch_model.bin (95MB)
│                   └── ...
│
├── model_server/
│   ├── main.py
│   ├── encoders.py
│   ├── custom_models.py
│   └── ...
│
└── shared_configs/
    └── configs.py

Volume Mount:
═════════════
Docker Compose: model_cache_huggingface → /app/.cache/huggingface/
Kubernetes: emptyDir → /app/.cache/huggingface/ (or persistent PVC)
```

---

## 💾 Storage Comparison: Docker vs Kubernetes

```
┌─────────────────────────────────────────────────────────────────────┐
│                         DOCKER COMPOSE                              │
└─────────────────────────────────────────────────────────────────────┘

volumes:
  model_cache_huggingface:           # Named volume (persistent)
  indexing_huggingface_model_cache:  # Named volume (persistent)

Behavior:
─────────
• Models downloaded once
• Cached across container restarts ✅
• Shared between container recreations ✅
• Persists even if container deleted ✅
• Only deleted if volume explicitly removed

Location on host:
─────────────────
/var/lib/docker/volumes/onyx_model_cache_huggingface/_data/


═════════════════════════════════════════════════════════════════════

┌─────────────────────────────────────────────────────────────────────┐
│                      KUBERNETES (CURRENT)                           │
└─────────────────────────────────────────────────────────────────────┘

volumes:
  - name: inference-model-cache
    emptyDir: {}                     # Temporary volume

  - name: indexing-model-cache
    emptyDir: {}                     # Temporary volume

Behavior:
─────────
• Models downloaded on every pod start ❌
• Lost when pod deleted/restarted ❌
• Not shared between pods ❌
• Wastes bandwidth and time ❌

⚠️  PROBLEM: Re-downloads ~2-3GB on every restart!


═════════════════════════════════════════════════════════════════════

┌─────────────────────────────────────────────────────────────────────┐
│                KUBERNETES (RECOMMENDED FOR PRODUCTION)              │
└─────────────────────────────────────────────────────────────────────┘

volumes:
  - name: inference-model-cache
    persistentVolumeClaim:
      claimName: inference-model-cache-pvc

  - name: indexing-model-cache
    persistentVolumeClaim:
      claimName: indexing-model-cache-pvc

PVC Configuration:
──────────────────
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: inference-model-cache-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: "nfs-example"
  volumeMode: "Filesystem"
  resources:
    requests:
      storage: 5Gi

Behavior:
─────────
• Models downloaded once ✅
• Cached across pod restarts ✅
• Persists when pod deleted ✅
• Saves bandwidth and time ✅
• Can be shared (with ReadWriteMany) ✅
```

---

## 📊 Model Size & Resource Summary

```
╔═══════════════════════════════════════════════════════════════════════╗
║                        MODEL SIZES & RESOURCES                        ║
╚═══════════════════════════════════════════════════════════════════════╝

┌───────────────────────────────────────────────────────────────────────┐
│  Model: nomic-ai/nomic-embed-text-v1 (DEFAULT EMBEDDING MODEL)        │
├───────────────────────────────────────────────────────────────────────┤
│  Disk Size:        ~1.5 GB                                            │
│  RAM (loaded):     ~2.0 GB                                            │
│  Dimensions:       768                                                │
│  Max Context:      512 tokens                                         │
│  License:          Apache 2.0                                         │
│  Purpose:          Convert text → embeddings                          │
│  Used by:          Both servers (inference + indexing)                │
└───────────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────────┐
│  Model: mixedbread-ai/mxbai-rerank-xsmall-v1 (RERANKING MODEL)       │
├───────────────────────────────────────────────────────────────────────┤
│  Disk Size:        ~200 MB                                            │
│  RAM (loaded):     ~300 MB                                            │
│  Purpose:          Rerank search results by relevance                 │
│  Used by:          Both servers                                       │
└───────────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────────┐
│  Model: onyx-dot-app/hybrid-intent-token-classifier                   │
├───────────────────────────────────────────────────────────────────────┤
│  Disk Size:        ~100 MB                                            │
│  RAM (loaded):     ~150 MB                                            │
│  Purpose:          Classify user intent (search vs chat)              │
│  Used by:          Inference server only                              │
└───────────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────────┐
│  Model: onyx-dot-app/information-content-model                        │
├───────────────────────────────────────────────────────────────────────┤
│  Disk Size:        ~100 MB                                            │
│  RAM (loaded):     ~150 MB                                            │
│  Purpose:          Score information density of text chunks           │
│  Used by:          Indexing server only                               │
└───────────────────────────────────────────────────────────────────────┘

═════════════════════════════════════════════════════════════════════

TOTAL RESOURCES PER SERVER:
───────────────────────────

Inference Model Server:
• Disk: ~2.0 GB
• RAM:  ~2.5 GB
• CPU:  1-4 cores (depending on load)

Indexing Model Server:
• Disk: ~2.0 GB
• RAM:  ~2.5 GB
• CPU:  1-4 cores (depending on load)

TOTAL FOR BOTH:
• Disk: ~4.0 GB
• RAM:  ~5.0 GB
• CPU:  2-8 cores
```

---

## 🔄 Timeline: First Startup vs Cached Startup

```
╔═══════════════════════════════════════════════════════════════════════╗
║                       FIRST STARTUP (NO CACHE)                        ║
╚═══════════════════════════════════════════════════════════════════════╝

00:00 │ Container starts
      │ └─ Check HF_CACHE_PATH
      │
00:10 │ Move temp_huggingface → huggingface cache
      │ └─ Pre-downloaded models from Docker image
      │
00:30 │ Loading nomic-ai/nomic-embed-text-v1
      ├─ IF in cache: Load from disk (~30s)
      │  └─ ✅ Pre-downloaded in Docker image
      │
      ├─ IF NOT in cache: Download from Hugging Face (~5-10 min)
      │  ├─ Download model.safetensors (1.2GB)
      │  ├─ Download config files
      │  └─ Save to cache
      │
01:30 │ Loading mixedbread-ai/mxbai-rerank-xsmall-v1
      ├─ IF in cache: Load from disk (~10s)
      │  └─ ✅ Pre-downloaded in Docker image
      │
02:00 │ Loading intent/content classifier
      ├─ IF in cache: Load from disk (~10s)
      │  └─ ✅ Pre-downloaded in Docker image
      │
02:30 │ Model warmup
      ├─ Pre-warm RoPE caches
      └─ Test with dummy data
      │
03:00 │ ✅ READY TO SERVE

Total Time: ~3 minutes (with pre-downloaded models in image)
         OR ~10-15 minutes (if downloading from Hugging Face)


═════════════════════════════════════════════════════════════════════

╔═══════════════════════════════════════════════════════════════════════╗
║                    SUBSEQUENT STARTUPS (WITH CACHE)                   ║
╚═══════════════════════════════════════════════════════════════════════╝

00:00 │ Container starts
      │ └─ Check HF_CACHE_PATH
      │
00:05 │ Models found in cache! ✅
      │ └─ /app/.cache/huggingface/models--nomic-ai--nomic-embed-text-v1/
      │
00:10 │ Loading nomic-ai/nomic-embed-text-v1
      └─ Load from cache (no download needed!)
      │
00:40 │ Loading mixedbread-ai/mxbai-rerank-xsmall-v1
      └─ Load from cache
      │
00:50 │ Loading intent/content classifier
      └─ Load from cache
      │
01:00 │ Model warmup
      └─ Pre-warm RoPE caches
      │
01:30 │ ✅ READY TO SERVE

Total Time: ~1.5 minutes ✅
Internet: NOT REQUIRED ✅
```

---

## 🎯 Key Takeaways

### ✅ What You Need to Know:

1. **Both model servers use Hugging Face models** - they are essentially Hugging Face model runners
2. **Default embedding model**: `nomic-ai/nomic-embed-text-v1` (1.5GB)
3. **Models are downloaded** from Hugging Face Hub on first use (or pre-downloaded in Docker image)
4. **Models are cached** in `/app/.cache/huggingface/` volume
5. **Same embedding model** used by both servers, different workloads
6. **Inference server**: Real-time queries (single requests)
7. **Indexing server**: Bulk processing (batch requests)
8. **Total size**: ~2-3GB per server, ~4-6GB for both
9. **Startup time**: 1-2 minutes (cached) vs 5-15 minutes (first time with download)
10. **Internet required**: Only for first-time model download

### ⚠️ Important for Kubernetes:

- **Current setup uses `emptyDir`** - models re-downloaded on every pod restart
- **Recommendation**: Use PersistentVolumeClaims for production
- **Save bandwidth**: Cache models persistently to avoid re-downloading 2-3GB
- **Faster restarts**: Cached models load in 1-2 minutes vs 5-15 minutes

### 🔧 The model servers are:

- **NOT custom AI models** - they use open-source Hugging Face models
- **NOT just API proxies** - they run actual inference (PyTorch/Transformers)
- **Local processing** - embeddings generated on your infrastructure
- **Privacy-focused** - no external API calls after models are downloaded
- **Production-ready** - used by thousands of Onyx deployments

---

**The model servers are the "brain" of Onyx's semantic search, powered by Hugging Face!** 🧠✨

