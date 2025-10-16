# Model Servers YAML Files - Complete Explanation

**A detailed, beginner-friendly guide to understanding `06-inference-model-server.yaml` and `06-indexing-model-server.yaml`**

---

## 📋 Table of Contents

1. [Overview: What Are These Files?](#overview)
2. [The Big Picture: Why Two Model Servers?](#big-picture)
3. [Architecture Diagram](#architecture-diagram)
4. [Inference Model Server - Line by Line](#inference-yaml)
5. [Indexing Model Server - Line by Line](#indexing-yaml)
6. [Key Differences Between Them](#key-differences)
7. [Environment Variables Explained](#environment-variables)
8. [Volume Mounts Explained](#volume-mounts)
9. [How They Work Together](#how-they-work)
10. [Common Questions](#faq)

---

## 🎯 Overview: What Are These Files? {#overview}

These two YAML files define **Kubernetes Deployments** for running AI model servers that convert text into numbers (embeddings) for semantic search.

**Simple analogy:** Think of them as recipe cards that tell Kubernetes how to cook two different types of AI services.

### What's in Each File?

Each YAML file contains **TWO** Kubernetes resources:

1. **Service** - A network address so other pods can talk to this server
2. **Deployment** - Instructions for running the actual container

```
┌─────────────────────────────────────────┐
│  06-inference-model-server.yaml         │
├─────────────────────────────────────────┤
│  1. Service (network endpoint)          │
│  2. Deployment (running container)      │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│  06-indexing-model-server.yaml          │
├─────────────────────────────────────────┤
│  1. Service (network endpoint)          │
│  2. Deployment (running container)      │
└─────────────────────────────────────────┘
```

---

## 🌟 The Big Picture: Why Two Model Servers? {#big-picture}

### The Problem

Onyx needs to convert text into "embeddings" (vectors of numbers) so it can do semantic search. But there are TWO different situations:

1. **Real-time queries** - When a user types a question (needs to be FAST!)
2. **Bulk indexing** - When processing thousands of documents (can be SLOWER, but handles volume)

### The Solution

Instead of one server doing both jobs (which could make user queries slow), we split into TWO servers:

```
┌─────────────────────────────────────────────────────────────────┐
│                         THE PROBLEM                             │
└─────────────────────────────────────────────────────────────────┘

Scenario 1: User asks "What is our vacation policy?"
           ↓
Need: Fast embedding (100ms) ⚡

Scenario 2: System processes 10,000 document chunks
           ↓
Need: Bulk processing (can take minutes) 📦

If ONE server does both:
❌ User query gets stuck waiting for bulk processing
❌ Poor user experience (slow responses)


┌─────────────────────────────────────────────────────────────────┐
│                         THE SOLUTION                            │
└─────────────────────────────────────────────────────────────────┘

TWO separate servers:

Server 1: Inference Model Server (Real-time)
  ✅ Handles user queries ONLY
  ✅ Fast response (100ms)
  ✅ Never blocked by bulk processing

Server 2: Indexing Model Server (Bulk)
  ✅ Handles document processing ONLY
  ✅ Can take its time
  ✅ Doesn't slow down user queries
```

---

## 🏗️ Architecture Diagram {#architecture-diagram}

### Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        ONYX SYSTEM ARCHITECTURE                         │
└─────────────────────────────────────────────────────────────────────────┘


USER QUERY FLOW (Real-time):
═════════════════════════════

👤 User types: "What is our vacation policy?"
      ↓
┌─────────────────┐
│   Web Server    │ (Next.js UI)
│   Port: 3000    │
└────────┬────────┘
         ↓
┌─────────────────┐
│   API Server    │ (FastAPI backend)
│   Port: 8080    │
└────────┬────────┘
         ↓
         ↓ HTTP POST http://inference-model-server:9000/embed
         ↓ Body: {"texts": ["What is our vacation policy?"]}
         ↓
┌─────────────────────────────────────────────────────────────────┐
│  🤖 INFERENCE MODEL SERVER                                      │
│  ════════════════════════════════════════════════════════════   │
│                                                                 │
│  Service: inference-model-server                                │
│  Port: 9000                                                     │
│  Purpose: Real-time query embedding                             │
│                                                                 │
│  What it does:                                                  │
│  1. Receives text: "What is our vacation policy?"               │
│  2. Loads model: nomic-ai/nomic-embed-text-v1                  │
│  3. Converts to embedding: [0.123, -0.456, ..., 0.789]        │
│     (768 numbers representing the meaning)                      │
│  4. Returns in ~100ms ⚡                                        │
│                                                                 │
│  Models loaded from:                                            │
│  📁 /app/.cache/huggingface/ (mounted PVC)                     │
│                                                                 │
│  Environment:                                                   │
│  • HF_HUB_OFFLINE=1 (no internet downloads)                    │
│  • TRANSFORMERS_OFFLINE=1 (force offline)                      │
└─────────────────────────────────────────────────────────────────┘
         ↓
         ↓ Returns: [0.123, -0.456, ..., 0.789]
         ↓
┌─────────────────┐
│   API Server    │ Uses embedding for vector search
└────────┬────────┘
         ↓
┌─────────────────┐
│     Vespa       │ Searches for similar document chunks
│  Vector Search  │
└────────┬────────┘
         ↓
👤 User gets answer!


═══════════════════════════════════════════════════════════════════════════

DOCUMENT INDEXING FLOW (Bulk processing):
══════════════════════════════════════════

📄 System needs to index "HR_Policy_2025.pdf" (50 pages)
      ↓
┌─────────────────┐
│ Background      │ (Celery worker - not in minimal deployment)
│ Worker          │ Processes document, creates 200 chunks
└────────┬────────┘
         ↓
         ↓ HTTP POST http://indexing-model-server:9000/embed
         ↓ Body: {"texts": ["chunk1...", "chunk2...", ... "chunk200..."]}
         ↓
┌─────────────────────────────────────────────────────────────────┐
│  🤖 INDEXING MODEL SERVER                                       │
│  ═══════════════════════════════════════════════════════════    │
│                                                                 │
│  Service: indexing-model-server                                 │
│  Port: 9000 (same port, different pod!)                        │
│  Purpose: Bulk document embedding                               │
│                                                                 │
│  What it does:                                                  │
│  1. Receives 200 chunks of text                                 │
│  2. Loads model: nomic-ai/nomic-embed-text-v1                  │
│     (SAME model as inference server!)                           │
│  3. Processes in batches (8 chunks at a time)                   │
│  4. Converts all to embeddings:                                 │
│     [[0.111, 0.222, ...], [0.333, 0.444, ...], ...]           │
│  5. Returns in ~30-60 seconds 📦                                │
│                                                                 │
│  Models loaded from:                                            │
│  📁 /app/.cache/huggingface/ (SAME PVC as inference!)          │
│                                                                 │
│  Environment:                                                   │
│  • INDEXING_ONLY=True ← KEY DIFFERENCE!                        │
│  • HF_HUB_OFFLINE=1 (no internet downloads)                    │
│  • TRANSFORMERS_OFFLINE=1 (force offline)                      │
└─────────────────────────────────────────────────────────────────┘
         ↓
         ↓ Returns: 200 embeddings
         ↓
┌─────────────────┐
│ Background      │ Stores embeddings in Vespa
│ Worker          │
└────────┬────────┘
         ↓
┌─────────────────┐
│     Vespa       │ Document indexed and searchable!
└─────────────────┘
```

### Side-by-Side Comparison

```
┌──────────────────────────────┬──────────────────────────────┐
│   INFERENCE MODEL SERVER     │   INDEXING MODEL SERVER      │
├──────────────────────────────┼──────────────────────────────┤
│  Purpose: Real-time queries  │  Purpose: Bulk indexing      │
│  Speed: Fast (100ms)         │  Speed: Slower (30-60s)      │
│  Who uses it: API Server     │  Who uses it: Background     │
│  Input: 1 query at a time    │  Input: 100s of chunks       │
│  Priority: Low latency       │  Priority: High throughput   │
│  Model: nomic-embed-text-v1  │  Model: nomic-embed-text-v1  │
│  Port: 9000                  │  Port: 9000 (different pod)  │
│  INDEXING_ONLY: (not set)    │  INDEXING_ONLY: True         │
│  CPU: 500m-2000m             │  CPU: 1000m-4000m (higher)   │
│  Memory: 2Gi-4Gi             │  Memory: 2Gi-8Gi             │
└──────────────────────────────┴──────────────────────────────┘
```

---

## 📝 Inference Model Server - Line by Line Explanation {#inference-yaml}

Let's break down **`06-inference-model-server.yaml`** section by section:

### Part 1: Service (Network Endpoint)

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: inference-model-server
  labels:
    app: inference-model-server
```

**What this means:**
- `apiVersion: v1` - Using Kubernetes API version 1
- `kind: Service` - This creates a network endpoint
- `name: inference-model-server` - The DNS name (other pods use this to connect)
- `labels: app: inference-model-server` - A tag to identify this resource

**Think of it as:** A phone number in a phonebook. When API Server wants to call the inference model server, it looks up `inference-model-server` in the cluster's "phonebook" (DNS) and gets the IP address.

```yaml
spec:
  type: ClusterIP
  ports:
    - name: modelserver
      port: 9000
      targetPort: 9000
      protocol: TCP
  selector:
    app: inference-model-server
```

**What this means:**
- `type: ClusterIP` - Only accessible from inside the cluster (not from internet)
- `port: 9000` - The port that clients connect to
- `targetPort: 9000` - The port the container is listening on
- `selector: app: inference-model-server` - Routes traffic to pods with this label

**Think of it as:** A receptionist that forwards calls. When someone calls port 9000, it forwards to the pod running on port 9000.

### Part 2: Deployment (Running Container)

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inference-model-server
  labels:
    app: inference-model-server
```

**What this means:**
- `kind: Deployment` - Manages a set of identical pods
- `name: inference-model-server` - The name of this deployment
- `labels` - Tags for organizing resources

**Think of it as:** A manager that makes sure one copy of the inference model server is always running.

```yaml
spec:
  replicas: 1
  selector:
    matchLabels:
      app: inference-model-server
```

**What this means:**
- `replicas: 1` - Keep exactly 1 pod running
- `selector: matchLabels` - Which pods this deployment manages

**Think of it as:** "I'm responsible for keeping 1 copy of the inference model server alive."

```yaml
  template:
    metadata:
      labels:
        app: inference-model-server
```

**What this means:**
- `template` - The blueprint for creating pods
- `labels` - Must match the selector above

**Think of it as:** "Here's the recipe for creating a new pod if needed."

```yaml
    spec:
      containers:
        - name: model-server
          image: onyxdotapp/onyx-model-server:nightly-20241004
          imagePullPolicy: IfNotPresent
```

**What this means:**
- `containers` - List of containers in this pod (just one)
- `name: model-server` - Container name
- `image: onyxdotapp/onyx-model-server:nightly-20241004` - Docker image to use
- `imagePullPolicy: IfNotPresent` - Only download image if not already cached

**Think of it as:** "Run this Docker image from Docker Hub (or your registry)."

```yaml
          ports:
            - name: modelserver
              containerPort: 9000
              protocol: TCP
```

**What this means:**
- `containerPort: 9000` - The port the container listens on
- `protocol: TCP` - Use TCP protocol

**Think of it as:** "The app inside listens on port 9000 for incoming requests."

```yaml
          env:
            - name: HF_HOME
              value: "/app/.cache/huggingface"
            - name: HF_HUB_OFFLINE
              value: "1"
            - name: TRANSFORMERS_OFFLINE
              value: "1"
            - name: MODEL_SERVER_PORT
              value: "9000"
```

**What this means:**
- `env` - Environment variables passed to the container
- `HF_HOME` - Where Hugging Face models are stored
- `HF_HUB_OFFLINE=1` - **CRITICAL:** Don't download from internet!
- `TRANSFORMERS_OFFLINE=1` - **CRITICAL:** Force offline mode!
- `MODEL_SERVER_PORT=9000` - Port to listen on

**Think of it as:** Configuration settings for the app. Like telling it "your files are here, don't go online, listen on port 9000."

```yaml
          command:
            - uvicorn
            - model_server.main:app
            - --host
            - "0.0.0.0"
            - --port
            - "9000"
```

**What this means:**
- `command` - The startup command to run
- `uvicorn` - Python web server
- `model_server.main:app` - The Python application
- `--host 0.0.0.0` - Listen on all network interfaces
- `--port 9000` - Listen on port 9000

**Think of it as:** "Start the web server and make it listen for requests."

```yaml
          resources:
            requests:
              cpu: 500m
              memory: 2Gi
            limits:
              cpu: 2000m
              memory: 4Gi
```

**What this means:**
- `requests` - Minimum resources guaranteed
  - `cpu: 500m` - 0.5 CPU cores minimum
  - `memory: 2Gi` - 2 gigabytes RAM minimum
- `limits` - Maximum resources allowed
  - `cpu: 2000m` - 2 CPU cores maximum
  - `memory: 4Gi` - 4 gigabytes RAM maximum

**Think of it as:** "Reserve at least 0.5 CPU and 2GB RAM, but don't let it use more than 2 CPUs and 4GB RAM."

```yaml
          livenessProbe:
            httpGet:
              path: /health
              port: 9000
            initialDelaySeconds: 120
            periodSeconds: 30
            timeoutSeconds: 10
            failureThreshold: 3
```

**What this means:**
- `livenessProbe` - Check if container is alive (restart if not)
- `httpGet: /health` - Check by calling HTTP GET /health
- `initialDelaySeconds: 120` - Wait 2 minutes before first check (models need time to load)
- `periodSeconds: 30` - Check every 30 seconds
- `timeoutSeconds: 10` - Wait 10 seconds for response
- `failureThreshold: 3` - Restart after 3 failed checks

**Think of it as:** "Every 30 seconds, ask 'are you alive?' If no response 3 times in a row, restart the container."

```yaml
          readinessProbe:
            httpGet:
              path: /health
              port: 9000
            initialDelaySeconds: 60
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 5
```

**What this means:**
- `readinessProbe` - Check if container is ready to receive traffic
- Similar to liveness probe but determines if traffic should be sent
- `initialDelaySeconds: 60` - Start checking after 1 minute
- `periodSeconds: 10` - Check every 10 seconds
- `failureThreshold: 5` - Mark as "not ready" after 5 failures

**Think of it as:** "Don't send traffic until the /health endpoint responds successfully. If it starts failing, stop sending traffic but don't restart."

```yaml
          volumeMounts:
            - name: model-cache
              mountPath: /app/.cache/huggingface
              readOnly: true
```

**What this means:**
- `volumeMounts` - Attach storage to the container
- `name: model-cache` - Reference to volume defined below
- `mountPath: /app/.cache/huggingface` - Where to mount in the container
- `readOnly: true` - Don't allow writes (models are pre-loaded)

**Think of it as:** "Plug in an external hard drive at /app/.cache/huggingface. But make it read-only since we're not modifying files."

```yaml
      volumes:
        - name: model-cache
          persistentVolumeClaim:
            claimName: huggingface-models-pvc
```

**What this means:**
- `volumes` - Define the storage volumes
- `name: model-cache` - Name referenced by volumeMounts above
- `persistentVolumeClaim` - Use a PVC (persistent storage)
- `claimName: huggingface-models-pvc` - The PVC created earlier

**Think of it as:** "The external hard drive is actually a PVC named 'huggingface-models-pvc' that contains our pre-loaded models."

```yaml
      restartPolicy: Always
```

**What this means:**
- `restartPolicy: Always` - Always restart the pod if it crashes

**Think of it as:** "If this crashes, automatically restart it. Keep trying forever."

---

## 📝 Indexing Model Server - Line by Line Explanation {#indexing-yaml}

Now let's look at **`06-indexing-model-server.yaml`**. It's VERY similar to the inference server with a few key differences.

### The Same Parts (I'll highlight what's identical)

✅ **Service definition** - Almost identical (just different name)
✅ **Deployment structure** - Same structure
✅ **Container image** - Same Docker image!
✅ **Ports** - Same port 9000 (but different pod)
✅ **Volume mounts** - Same PVC mount
✅ **Health checks** - Similar probes

### The KEY Differences

#### Difference 1: Environment Variables

```yaml
          env:
            - name: INDEXING_ONLY
              value: "True"        # ← THIS IS THE KEY DIFFERENCE!
            - name: HF_HOME
              value: "/app/.cache/huggingface"
            - name: HF_HUB_OFFLINE
              value: "1"
            - name: TRANSFORMERS_OFFLINE
              value: "1"
            - name: MODEL_SERVER_PORT
              value: "9000"
```

**What `INDEXING_ONLY=True` means:**

When the model server starts, it checks this environment variable:

```python
# Inside the model server code (simplified):
if os.environ.get("INDEXING_ONLY") == "True":
    print("I'm the INDEXING server - optimized for bulk processing")
    # Load models optimized for batch processing
    # Different warmup strategy
    # Load information-content-model instead of intent-model
else:
    print("I'm the INFERENCE server - optimized for real-time queries")
    # Load models optimized for single queries
    # Different warmup strategy
    # Load intent-model for query classification
```

**Think of it as:** A switch that tells the same app to behave differently. Like telling a restaurant "you're the takeout counter" vs "you're the dine-in restaurant."

#### Difference 2: Resource Allocation

```yaml
          resources:
            requests:
              cpu: 1000m      # ← HIGHER than inference (500m)
              memory: 2Gi     # ← Same as inference
            limits:
              cpu: 4000m      # ← HIGHER than inference (2000m)
              memory: 8Gi     # ← HIGHER than inference (4Gi)
```

**Why higher resources?**

- **Bulk processing needs more CPU** - Processing 100s of chunks at once
- **More memory for batching** - Loading multiple chunks into memory

**Think of it as:** Giving a cargo truck more engine power than a taxi. Both do transport, but cargo needs more power.

#### Difference 3: Service Name

```yaml
metadata:
  name: indexing-model-server   # ← Different DNS name
```

**Why different name?**

So API Server can call `http://inference-model-server:9000` and Background Workers can call `http://indexing-model-server:9000`. They're different endpoints!

**Think of it as:** Two phone numbers for two different departments in the same company.

---

## 🔍 Key Differences Between Them {#key-differences}

### Summary Table

| Aspect | Inference Model Server | Indexing Model Server |
|--------|----------------------|---------------------|
| **Environment Variable** | `INDEXING_ONLY` not set | `INDEXING_ONLY=True` ✅ |
| **Purpose** | Real-time user queries | Bulk document processing |
| **Who calls it** | API Server | Background Workers |
| **Input** | 1 query at a time | 100s of chunks in batches |
| **Speed priority** | Fast (100ms) | Throughput (can take minutes) |
| **CPU Request** | 500m (0.5 cores) | 1000m (1 core) ⬆️ |
| **CPU Limit** | 2000m (2 cores) | 4000m (4 cores) ⬆️ |
| **Memory Limit** | 4Gi | 8Gi ⬆️ |
| **Model loaded** | Intent classifier | Information content model |
| **Optimization** | Low latency | High throughput |

### Visual Comparison

```
┌─────────────────────────────────────────────────────────────────┐
│                     SHARED CHARACTERISTICS                      │
└─────────────────────────────────────────────────────────────────┘

Both servers:
✅ Use SAME Docker image (onyxdotapp/onyx-model-server)
✅ Use SAME embedding model (nomic-ai/nomic-embed-text-v1)
✅ Mount SAME PVC (huggingface-models-pvc)
✅ Run on port 9000 (but different pods!)
✅ Use offline mode (HF_HUB_OFFLINE=1)
✅ Load models from /app/.cache/huggingface


┌─────────────────────────────────────────────────────────────────┐
│                        KEY DIFFERENCES                          │
└─────────────────────────────────────────────────────────────────┘

Inference Server:
├─ INDEXING_ONLY: (not set)
├─ Purpose: Real-time queries
├─ CPU: 0.5-2 cores
├─ Memory: 2-4GB
└─ Loads: Intent classification model

Indexing Server:
├─ INDEXING_ONLY: True ← THE KEY DIFFERENCE!
├─ Purpose: Bulk processing
├─ CPU: 1-4 cores (higher)
├─ Memory: 2-8GB (higher)
└─ Loads: Information content model
```

---

## 🔧 Environment Variables Explained {#environment-variables}

Let's understand each environment variable:

### 1. `HF_HOME=/app/.cache/huggingface`

```yaml
- name: HF_HOME
  value: "/app/.cache/huggingface"
```

**What it does:**
- Tells Hugging Face library where to look for cached models
- Without this, it would use default location (~/.cache/huggingface)

**Why we need it:**
- We're mounting our PVC at `/app/.cache/huggingface`
- Models are pre-loaded there
- The library needs to know where to look

**Real-world example:**
```python
# Inside the container, when code runs:
from transformers import AutoModel

# This tries to load model:
model = AutoModel.from_pretrained("nomic-ai/nomic-embed-text-v1")

# Hugging Face looks in: HF_HOME + "/models--nomic-ai--nomic-embed-text-v1/"
# Which is: /app/.cache/huggingface/models--nomic-ai--nomic-embed-text-v1/
```

### 2. `HF_HUB_OFFLINE=1`

```yaml
- name: HF_HUB_OFFLINE
  value: "1"
```

**What it does:**
- Forces Hugging Face to NEVER try to download from the internet
- If model not found locally, it will error instead of downloading

**Why we need it:**
- Your pods don't have internet access (air-gapped)
- We want it to FAIL FAST if model is missing (not hang trying to download)

**What happens without it:**
```
❌ Without HF_HUB_OFFLINE=1:
Pod starts → Tries to load model → Not in cache → Tries to download
→ Network blocked → Hangs for 60+ seconds → Eventually fails

✅ With HF_HUB_OFFLINE=1:
Pod starts → Tries to load model → Not in cache → Immediately fails
→ Clear error message → Easier to debug
```

### 3. `TRANSFORMERS_OFFLINE=1`

```yaml
- name: TRANSFORMERS_OFFLINE
  value: "1"
```

**What it does:**
- Similar to HF_HUB_OFFLINE but for the Transformers library specifically
- Prevents any network calls during model loading

**Why we need it:**
- Extra safety layer
- Some Transformers functions check online for updates - this disables that

### 4. `MODEL_SERVER_PORT=9000`

```yaml
- name: MODEL_SERVER_PORT
  value: "9000"
```

**What it does:**
- Tells the model server application which port to listen on

**Why we need it:**
- The app needs to know what port to bind to
- Must match the `containerPort` in the YAML

### 5. `INDEXING_ONLY=True` (Indexing Server Only)

```yaml
- name: INDEXING_ONLY
  value: "True"
```

**What it does:**
- Tells the model server to optimize for bulk processing
- Loads different auxiliary models
- Uses different warmup strategy

**Why we need it:**
- Makes the same Docker image behave differently
- No need for two different images

---

## 💾 Volume Mounts Explained {#volume-mounts}

### The Volume Mount Configuration

```yaml
volumeMounts:
  - name: model-cache
    mountPath: /app/.cache/huggingface
    readOnly: true

volumes:
  - name: model-cache
    persistentVolumeClaim:
      claimName: huggingface-models-pvc
```

### Visual Explanation

```
┌─────────────────────────────────────────────────────────────────┐
│                    VOLUME MOUNT FLOW                            │
└─────────────────────────────────────────────────────────────────┘

Step 1: Your colleague has a PersistentVolume with models
        └─ Contains: nomic-ai/nomic-embed-text-v1 (~1.5GB)
        └─ Contains: mixedbread-ai/mxbai-rerank-xsmall-v1 (~200MB)
        └─ Contains: Onyx custom models (~200MB)

Step 2: You create PVC (pvc-shared-models.yaml)
        └─ Claims: "I need access to that PV!"
        └─ Gets bound to the PV
        └─ Name: huggingface-models-pvc

Step 3: In model server YAMLs:
        ┌──────────────────────────────────────────────┐
        │  volumes:                                    │
        │    - name: model-cache                       │
        │      persistentVolumeClaim:                  │
        │        claimName: huggingface-models-pvc     │
        │                                              │
        │  "Mount that PVC into my pod"                │
        └──────────────────────────────────────────────┘
                      ↓
        ┌──────────────────────────────────────────────┐
        │  volumeMounts:                               │
        │    - name: model-cache                       │
        │      mountPath: /app/.cache/huggingface      │
        │      readOnly: true                          │
        │                                              │
        │  "Put it at this path inside container"      │
        └──────────────────────────────────────────────┘

Step 4: Inside the running container:
        
        Container filesystem:
        /
        ├── app/
        │   └── .cache/
        │       └── huggingface/  ← MOUNTED HERE!
        │           ├── models--nomic-ai--nomic-embed-text-v1/
        │           ├── models--mixedbread-ai--mxbai-rerank-xsmall-v1/
        │           └── models--onyx-dot-app--hybrid-intent.../
        ├── bin/
        ├── etc/
        └── ...

Step 5: When Python code runs:
        
        from transformers import AutoModel
        model = AutoModel.from_pretrained("nomic-ai/nomic-embed-text-v1")
        
        # Library checks: /app/.cache/huggingface/models--nomic-ai...
        # Files are there! ✅
        # Loads model into memory
        # No internet needed! ✅
```

### Why `readOnly: true`?

```yaml
readOnly: true
```

**Reasons:**

1. **Models are pre-loaded** - We're not downloading or modifying
2. **Security** - Prevents accidental writes
3. **Shared PVC** - Both servers can read from same PVC safely
4. **Faster** - Some storage systems optimize for read-only access

**Think of it as:** Like a CD-ROM drive. You can read the data, but can't write to it.

---

## 🤝 How They Work Together {#how-they-work}

### Complete System Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                   COMPLETE ONYX SYSTEM WITH MODEL SERVERS               │
└─────────────────────────────────────────────────────────────────────────┘


STARTUP SEQUENCE:
═════════════════

1. PVC created:
   └─ huggingface-models-pvc binds to existing PV

2. Inference Model Server starts:
   ├─ Mounts PVC at /app/.cache/huggingface (read-only)
   ├─ Reads models from mounted directory
   ├─ Loads nomic-embed-text-v1 (~1.5GB) into memory
   ├─ Loads intent classification model
   ├─ Warms up (pre-computes some caches)
   ├─ Starts listening on port 9000
   └─ Health check returns 200 OK → READY ✅

3. Indexing Model Server starts:
   ├─ Mounts SAME PVC at /app/.cache/huggingface (read-only)
   ├─ Reads SAME models from mounted directory
   ├─ Loads nomic-embed-text-v1 (~1.5GB) into memory
   ├─ Loads information content model (DIFFERENT from inference)
   ├─ Warms up for batch processing
   ├─ Starts listening on port 9000 (different pod!)
   └─ Health check returns 200 OK → READY ✅

4. Both servers are now ready to handle requests!


RUNTIME FLOW - USER QUERY:
═══════════════════════════

[User] "What is our vacation policy?"
   ↓
[Web Server] → [API Server]
   ↓
[API Server] needs to search for this query
   ↓
[API Server] → POST http://inference-model-server:9000/embed
                Body: {"texts": ["What is our vacation policy?"]}
   ↓
[Inference Server] receives request:
   ├─ Loads model from memory (already loaded!)
   ├─ Tokenizes text: ["What", "is", "our", "vacation", "policy", "?"]
   ├─ Runs through neural network
   ├─ Generates 768-dimensional vector
   ├─ Normalizes the vector
   └─ Returns: [0.123, -0.456, 0.789, ..., 0.321]
   
Time: ~100ms ⚡
   ↓
[API Server] receives embedding → searches Vespa → returns results
   ↓
[User] sees search results!


RUNTIME FLOW - DOCUMENT INDEXING:
══════════════════════════════════

[Admin] uploads "HR_Policy.pdf"
   ↓
[API Server] stores file in MinIO
   ↓
[API Server] creates background task
   ↓
[Background Worker] picks up task:
   ├─ Downloads PDF from MinIO
   ├─ Extracts text (50 pages)
   ├─ Chunks into paragraphs (200 chunks)
   └─ Needs to generate embeddings for all chunks
   ↓
[Background Worker] → POST http://indexing-model-server:9000/embed
                      Body: {"texts": ["chunk1", "chunk2", ..., "chunk200"]}
   ↓
[Indexing Server] receives request:
   ├─ Loads model from memory (already loaded!)
   ├─ Processes in batches (8 chunks at a time):
   │  ├─ Batch 1: Chunks 1-8 → 8 embeddings
   │  ├─ Batch 2: Chunks 9-16 → 8 embeddings
   │  ├─ ...
   │  └─ Batch 25: Chunks 193-200 → 8 embeddings
   └─ Returns: [[emb1], [emb2], ..., [emb200]]

Time: ~30-60 seconds 📦
   ↓
[Background Worker] receives all embeddings
   ↓
[Background Worker] → stores in Vespa
   ↓
Document is now searchable! ✅


ISOLATION BENEFIT:
══════════════════

❌ Without separate servers:
   User query arrives → waits for bulk indexing to finish → slow!

✅ With separate servers:
   User query → goes to Inference Server → fast! ⚡
   Bulk indexing → goes to Indexing Server → doesn't affect queries! ✅
```

### Network Communication

```
┌─────────────────────────────────────────────────────────────────┐
│               KUBERNETES NETWORK ARCHITECTURE                   │
└─────────────────────────────────────────────────────────────────┘

All pods are in the same namespace (e.g., "onyx-infra")

API Server Pod (api-server-xxx)
    ↓ HTTP
    ↓ URL: http://inference-model-server:9000/embed
    ↓
Service: inference-model-server (ClusterIP)
    ↓ routes to:
    ↓
Pod: inference-model-server-xxx-yyy
    ├─ Container: model-server
    ├─ Port: 9000
    └─ PVC mount: huggingface-models-pvc (read-only)


Background Worker Pod (background-xxx)
    ↓ HTTP
    ↓ URL: http://indexing-model-server:9000/embed
    ↓
Service: indexing-model-server (ClusterIP)
    ↓ routes to:
    ↓
Pod: indexing-model-server-xxx-yyy
    ├─ Container: indexing-model-server
    ├─ Port: 9000 (same port, different pod!)
    └─ PVC mount: huggingface-models-pvc (read-only, SHARED!)
```

### Shared Storage Benefit

```
┌─────────────────────────────────────────────────────────────────┐
│                     SHARED PVC BENEFIT                          │
└─────────────────────────────────────────────────────────────────┘

PersistentVolume (managed by your infrastructure team)
├─ Storage: 10Gi
├─ Type: NFS (or similar)
└─ Contains models: ~5-6GB used

        ↓ (bound via PVC)
        ↓
PersistentVolumeClaim: huggingface-models-pvc
├─ Access Mode: ReadWriteMany
└─ Status: Bound

        ↓ (mounted by both pods)
        ├────────────────┬────────────────┐
        ↓                ↓                ↓
Inference Server   Indexing Server
├─ Reads models    ├─ Reads models (SAME files!)
├─ No writes       ├─ No writes
└─ readOnly:true   └─ readOnly:true

Benefits:
✅ Only one copy of models (save 5-6GB storage!)
✅ Both servers always use same model version
✅ Easy to update (just replace PVC contents)
✅ Cost effective
```

---

## ❓ Common Questions (FAQ) {#faq}

### Q1: Why do both servers use the same Docker image?

**A:** Because they run the same code! The `INDEXING_ONLY=True` environment variable is like a switch that changes the behavior. This is simpler than maintaining two different Docker images.

**Think of it as:** A car that can be a taxi (inference) or a cargo truck (indexing) depending on configuration.

### Q2: Why do both use port 9000?

**A:** Each container can use port 9000 because they're in different pods (separate network namespaces). It's like two houses both having a door at the front - they don't conflict because they're separate buildings.

### Q3: Can they share the same PVC?

**A:** Yes! As long as your storage supports `ReadWriteMany` access mode. Both pods mount it as `readOnly: true`, so there's no conflict.

**Analogy:** Like two people reading from the same library book. As long as nobody is writing/erasing, multiple readers are fine.

### Q4: What happens if models are not in the PVC?

**A:** The pod will crash during startup with an error like:
```
OSError: Can't load model nomic-ai/nomic-embed-text-v1
```

Check logs: `oc logs deployment/inference-model-server`

**Solution:** Make sure your PVC is properly bound to a PV that contains the models.

### Q5: Why `readOnly: true`?

**A:** Because:
1. Models are pre-loaded (not downloading)
2. Prevents accidental writes
3. Allows sharing PVC between both servers
4. Better security

### Q6: Can I scale to multiple replicas?

**A:** Yes for Inference Server (to handle more user queries). Maybe for Indexing Server (depending on your workload).

```yaml
replicas: 3  # Run 3 copies of inference server
```

If using `ReadWriteMany`, all replicas can share the same PVC!

### Q7: How much memory do they actually use?

**A:**
- **Model files on disk:** ~5-6GB (in PVC)
- **Models loaded in RAM:** ~2-3GB per server
- **Total RAM with buffer:** 4-8GB per server (configured limits)

### Q8: What if I don't have ReadWriteMany storage?

**A:** Use `pvc-separate-models.yaml` to create two separate PVCs:
- `inference-model-cache-pvc` (5Gi)
- `indexing-model-cache-pvc` (5Gi)

Models need to be copied to both PVCs. Total storage: ~10-12GB.

### Q9: Why are startup times slow (2 minutes)?

**A:** Models are large (~1.5GB) and need to be:
1. Read from disk
2. Loaded into memory
3. Compiled/optimized
4. Warmed up (pre-compute caches)

This is why `initialDelaySeconds: 120` for health checks.

### Q10: Can I use a different embedding model?

**A:** Yes, but you'd need to:
1. Download the new model
2. Put it in the PVC at the correct path
3. Configure Onyx to use the new model (in Onyx UI settings)

The model server will automatically use whatever model Onyx requests.

---

## 🎓 Summary

### Key Takeaways

1. **Two servers, same image** - Different behavior via `INDEXING_ONLY=True`
2. **Same embedding model** - Both use `nomic-ai/nomic-embed-text-v1`
3. **Shared PVC** - Both mount `huggingface-models-pvc` read-only
4. **Offline mode** - `HF_HUB_OFFLINE=1` prevents internet access
5. **Different workloads** - Inference (real-time) vs Indexing (bulk)
6. **Resource allocation** - Indexing gets more CPU/memory
7. **Network isolation** - Different Service names, same port (different pods)

### The Critical Parts You Must Get Right

✅ **PVC must exist** - `huggingface-models-pvc` created before deploying
✅ **PVC must have models** - Pre-loaded with Hugging Face models
✅ **Offline env vars** - `HF_HUB_OFFLINE=1` and `TRANSFORMERS_OFFLINE=1`
✅ **StorageClass correct** - Must match your cluster's available storage
✅ **Access mode** - `ReadWriteMany` preferred, or use separate PVCs
✅ **INDEXING_ONLY=True** - Only for indexing server, not inference!

### Quick Reference

```bash
# Deploy order:
1. oc apply -f pvc-shared-models.yaml
2. oc apply -f 06-inference-model-server.yaml
3. oc apply -f 06-indexing-model-server.yaml

# Verify:
oc get pods | grep model-server
oc logs deployment/inference-model-server | grep "loaded model"
oc logs deployment/indexing-model-server | grep "loaded model"

# Test:
oc exec deployment/inference-model-server -- curl http://localhost:9000/health
oc exec deployment/indexing-model-server -- curl http://localhost:9000/health
```

---

**You now understand the model servers! They're the AI "brain" of Onyx, converting text to numbers for semantic search.** 🧠✨

