# Model Servers: Two Separate Services Explained

**Question:** Why are there TWO model servers in Docker Compose but only ONE in Kubernetes?

**Answer:** You're absolutely right! There should be TWO model servers in Kubernetes too. I missed creating the second one.

---

## 🔍 The Two Model Servers

### 1. Inference Model Server (`inference_model_server`)

**Purpose:** Real-time query embedding for user searches

**Used by:**
- API Server (for user queries)
- Real-time search requests

**Workload:**
- Low latency requirements
- Single query at a time
- Fast response needed

**Configuration:**
```yaml
# No special environment variables
# Standard model server behavior
```

**Docker Compose:**
```yaml
inference_model_server:
  image: onyxdotapp/onyx-model-server:latest
  ports: 9000
  volumes:
    - model_cache_huggingface:/app/.cache/huggingface/
```

**Kubernetes:**
```yaml
# 06-inference-model-server.yaml
name: inference-model-server
port: 9000
# Used by: API Server
```

---

### 2. Indexing Model Server (`indexing_model_server`)

**Purpose:** Bulk document embedding for background processing

**Used by:**
- Background Workers (Celery)
- Document indexing tasks
- Bulk processing

**Workload:**
- High throughput requirements
- Batch processing
- Can handle longer processing times

**Configuration:**
```yaml
environment:
  - INDEXING_ONLY=True  # Key difference!
```

**Docker Compose:**
```yaml
indexing_model_server:
  image: onyxdotapp/onyx-model-server:latest
  ports: 9000
  environment:
    - INDEXING_ONLY=True
  volumes:
    - indexing_huggingface_model_cache:/app/.cache/huggingface/
```

**Kubernetes:**
```yaml
# 06-indexing-model-server.yaml (NEW!)
name: indexing-model-server
port: 9000
environment:
  - INDEXING_ONLY=True
# Used by: Background Workers
```

---

## 🎯 Why Two Separate Servers?

### 1. **Separation of Concerns**

**Inference Server:**
- Handles user queries (real-time)
- Must be fast and responsive
- Single queries at a time

**Indexing Server:**
- Handles document processing (batch)
- Can be slower but more thorough
- Bulk operations

### 2. **Resource Isolation**

**Inference Server:**
- Optimized for low latency
- Reserved for user interactions
- Can't be blocked by heavy indexing

**Indexing Server:**
- Optimized for throughput
- Can use more resources
- Won't slow down user searches

### 3. **Different Model Configurations**

**Inference Server:**
- Standard model configuration
- Optimized for single queries

**Indexing Server:**
- `INDEXING_ONLY=True` flag
- May use different model settings
- Optimized for batch processing

### 4. **Independent Scaling**

**Inference Server:**
- Scale based on user load
- More replicas during peak hours

**Indexing Server:**
- Scale based on document volume
- More replicas during bulk imports

---

## 🔄 How They Work Together

### User Search Flow (Inference Server)

```
1. User types query → API Server
2. API Server → inference-model-server:9000
3. Inference Server generates embedding
4. API Server searches Vespa
5. Results returned to user
```

### Document Indexing Flow (Indexing Server)

```
1. User uploads document → API Server
2. API Server creates background task
3. Background Worker → indexing-model-server:9000
4. Indexing Server processes document in bulk
5. Embeddings stored in Vespa
```

---

## 📊 Resource Allocation

### Inference Model Server
- **CPU:** 1000m-4000m (moderate)
- **Memory:** 2Gi-8Gi (standard)
- **Usage:** Real-time, low latency

### Indexing Model Server
- **CPU:** 1000m-4000m (higher for bulk)
- **Memory:** 2Gi-8Gi (same as inference)
- **Usage:** Batch processing, high throughput

---

## 🚀 Updated Kubernetes Deployment

### New Files Created

**1. `06-indexing-model-server.yaml`**
- Dedicated indexing model server
- `INDEXING_ONLY=True` environment variable
- Same image but different purpose

**2. Updated `05-configmap.yaml`**
- Added `INDEXING_MODEL_SERVER_HOST`
- Added `INDEXING_MODEL_SERVER_PORT`

**3. Updated `07-api-server.yaml`**
- Added indexing model server environment variables
- API Server can now use both servers

### Deployment Order

```bash
# 1. Deploy infrastructure
kubectl apply -f 02-postgresql.yaml
kubectl apply -f 03-vespa.yaml
kubectl apply -f 04-redis.yaml

# 2. Deploy both model servers
kubectl apply -f 06-inference-model-server.yaml
kubectl apply -f 06-indexing-model-server.yaml

# 3. Deploy configuration
kubectl apply -f 05-configmap.yaml

# 4. Deploy applications
kubectl apply -f 07-api-server.yaml
kubectl apply -f 08-web-server.yaml
kubectl apply -f 09-nginx.yaml
```

---

## 🔍 Verification

### Check Both Model Servers

```bash
# Check both deployments
kubectl get deployments -l app=inference-model-server
kubectl get deployments -l app=indexing-model-server

# Check both services
kubectl get services inference-model-server
kubectl get services indexing-model-server

# Check pods
kubectl get pods -l app=inference-model-server
kubectl get pods -l app=indexing-model-server
```

### Expected Output

```bash
# Deployments
NAME                     READY   UP-TO-DATE   AVAILABLE   AGE
inference-model-server   1/1     1            1           2m
indexing-model-server    1/1     1            1           2m

# Services
NAME                     TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
inference-model-server   ClusterIP   10.96.123.45   <none>        9000/TCP   2m
indexing-model-server    ClusterIP   10.96.123.46   <none>        9000/TCP   2m

# Pods
NAME                                      READY   STATUS    RESTARTS   AGE
inference-model-server-xxxxxxxxx-xxxxx    1/1     Running   0          2m
indexing-model-server-xxxxxxxxx-xxxxx     1/1     Running   0          2m
```

---

## 📝 Summary

**You were absolutely correct!** 

**Docker Compose has:**
- ✅ `inference_model_server` (real-time queries)
- ✅ `indexing_model_server` (bulk processing)

**Kubernetes now has:**
- ✅ `06-inference-model-server.yaml` (real-time queries)
- ✅ `06-indexing-model-server.yaml` (bulk processing) **NEW!**

**Key Differences:**
- **Same image:** `onyxdotapp/onyx-model-server:nightly-20241004`
- **Same port:** `9000` (different containers)
- **Different purpose:** Real-time vs batch processing
- **Different environment:** `INDEXING_ONLY=True` for indexing server

**This matches the Docker Compose architecture exactly!** 🎉
