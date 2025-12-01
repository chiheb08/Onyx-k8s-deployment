# Docker Compose Default Values for Backend Optimization

## Current Default Values in Latest Onyx Docker Compose

This document shows the **current default values** used in Docker Compose deployments, which explain why local deployments are faster than OpenShift.

---

## 🏗️ Architecture: Docker Compose vs OpenShift

### Docker Compose (Local)
- **Single "background" service**: Runs all Celery workers in one container
- **Shared resources**: All workers share the host's CPU/memory
- **Localhost communication**: Services communicate via Docker network (very fast)
- **No resource limits**: Can use all available host resources

### OpenShift (Cluster)
- **Separate deployments**: Each worker type has its own pod
- **Resource isolation**: Each pod has limited CPU/memory
- **Network communication**: Services communicate over cluster network (5-20ms latency)
- **Resource limits**: Strict CPU/memory limits per pod

---

## 📊 Current Default Values

### 1. Celery Worker Configuration

#### User File Processing Worker

**Environment Variable**: `CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY`

**Docker Compose Default**: **2** (from code, not set in env.template)

**Code Location**: `backend/onyx/configs/app_configs.py:400-402`
```python
CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY = int(
    os.environ.get("CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY") or 2
)
```

**Docker Compose Setup**:
- Uses **consolidated background worker** by default (`USE_LIGHTWEIGHT_BACKGROUND_WORKER=true`)
- Background worker has **total concurrency of 20** (shared across all worker types)
- User file processing gets a **portion of this 20**, but defaults to **2** when running as separate worker

**To Check in Your Docker Compose**:
```bash
# Check if using lightweight worker (default)
docker exec onyx-backend-1 env | grep USE_LIGHTWEIGHT_BACKGROUND_WORKER
# Output: USE_LIGHTWEIGHT_BACKGROUND_WORKER=true

# Check actual concurrency
docker exec onyx-backend-1 env | grep CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY
# Output: (empty, using default 2)
```

---

### 2. Embedding Batch Size

**Environment Variable**: `EMBEDDING_BATCH_SIZE`

**Docker Compose Default**: **8** (from code, not set in env.template)

**Code Location**: `backend/onyx/configs/model_configs.py:44-46`
```python
EMBEDDING_BATCH_SIZE = int(os.environ.get("EMBEDDING_BATCH_SIZE") or 0) or None
BATCH_SIZE_ENCODE_CHUNKS = EMBEDDING_BATCH_SIZE or 8
```

**env.template** (commented out, so uses code default):
```bash
# EMBEDDING_BATCH_SIZE=
```

**To Check in Your Docker Compose**:
```bash
docker exec onyx-backend-1 env | grep EMBEDDING_BATCH_SIZE
# Output: (empty, using default 8)
```

---

### 3. Worker Replicas

**Docker Compose**: **1 replica** (single "background" service)

**docker-compose.yml**:
```yaml
background:
  image: onyxdotapp/onyx-backend:${IMAGE_TAG:-latest}
  # No replicas specified = 1 container
```

**Why it's still fast locally**:
- Single container can use **all available CPU/memory** from host
- No resource limits = can scale up dynamically
- Localhost communication = minimal latency

---

### 4. Resource Limits

**Docker Compose**: **No limits** (can use all host resources)

**docker-compose.yml**: No `resources` section specified

**Why it's fast**:
- Can use all CPU cores available
- Can use all memory available
- No throttling from Kubernetes/OpenShift

---

### 5. Background Worker Concurrency

**Environment Variable**: `CELERY_WORKER_BACKGROUND_CONCURRENCY`

**Docker Compose Default**: **20** (when using lightweight worker)

**Code Location**: `backend/onyx/configs/app_configs.py:383-385`
```python
CELERY_WORKER_BACKGROUND_CONCURRENCY = int(
    os.environ.get("CELERY_WORKER_BACKGROUND_CONCURRENCY") or 20
)
```

**Note**: This is the **total concurrency** for the consolidated background worker, which handles:
- Light tasks
- Docprocessing
- Docfetching
- Heavy tasks
- KG processing
- Monitoring
- **User file processing** (shares this pool)

---

## 📋 Complete Default Values Table

| Setting | Docker Compose Default | OpenShift Default | Code Default |
|---------|----------------------|-------------------|--------------|
| **User File Processing Concurrency** | 2 | 2 | 2 (app_configs.py:401) |
| **Embedding Batch Size** | 8 | 8 | 8 (model_configs.py:46) |
| **Background Worker Concurrency** | 20 | N/A (separate workers) | 20 (app_configs.py:384) |
| **Worker Replicas** | 1 (consolidated) | 1 (separate) | 1 |
| **CPU Request** | Unlimited | 500m | N/A |
| **CPU Limit** | Unlimited | 2000m | N/A |
| **Memory Request** | Unlimited | 512Mi | N/A |
| **Memory Limit** | Unlimited | 2Gi | N/A |
| **USE_LIGHTWEIGHT_BACKGROUND_WORKER** | true | false (Kubernetes) | true |

---

## 🔍 Why Docker Compose is Faster

### 1. Resource Availability
- **Docker Compose**: Can use all host resources (no limits)
- **OpenShift**: Limited to 500m CPU / 512Mi memory per worker

### 2. Worker Architecture
- **Docker Compose**: Consolidated worker with 20 total concurrency (shared pool)
- **OpenShift**: Separate worker with only 2 concurrency (dedicated but limited)

### 3. Network Latency
- **Docker Compose**: Localhost/Docker network (<1ms)
- **OpenShift**: Cluster network (5-20ms per call)

### 4. Resource Sharing
- **Docker Compose**: All services share host resources
- **OpenShift**: Each pod isolated with strict limits

---

## 🎯 Recommended Values for OpenShift (To Match Docker Compose Performance)

To get similar performance to Docker Compose, you need to **exceed** Docker Compose defaults because of network overhead:

| Setting | Docker Compose | OpenShift (Recommended) | Reason |
|---------|----------------|-------------------------|--------|
| **User File Processing Concurrency** | 2 | **8** | Compensate for network latency |
| **Embedding Batch Size** | 8 | **16** | Reduce HTTP calls |
| **Worker Replicas** | 1 | **3** | Horizontal scaling |
| **CPU Request** | Unlimited | **2000m** | More processing power |
| **CPU Limit** | Unlimited | **4000m** | Allow bursts |
| **Memory Request** | Unlimited | **2Gi** | Handle larger batches |
| **Memory Limit** | Unlimited | **4Gi** | Prevent OOM |

---

## 📝 How to Check Your Current Values

### In Docker Compose

```bash
# Check worker concurrency
docker exec onyx-backend-1 env | grep CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY

# Check embedding batch size
docker exec onyx-backend-1 env | grep EMBEDDING_BATCH_SIZE

# Check if using lightweight worker
docker exec onyx-backend-1 env | grep USE_LIGHTWEIGHT_BACKGROUND_WORKER

# Check background worker concurrency
docker exec onyx-backend-1 env | grep CELERY_WORKER_BACKGROUND_CONCURRENCY

# Check actual running workers
docker exec onyx-backend-1 ps aux | grep celery
```

### In OpenShift

```bash
# Check ConfigMap values
oc get configmap onyx-config -o yaml | grep CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY
oc get configmap onyx-config -o yaml | grep EMBEDDING_BATCH_SIZE

# Check deployment replicas
oc get deployment celery-worker-user-file-processing -o jsonpath='{.spec.replicas}'

# Check resource limits
oc get deployment celery-worker-user-file-processing -o jsonpath='{.spec.template.spec.containers[0].resources}'

# Check running pods
oc get pods -l app=celery-worker-user-file-processing
```

---

## 🔄 Comparison: Docker Compose vs OpenShift

### Docker Compose (Current - Fast)

```yaml
background:
  # Single service, no resource limits
  # Uses consolidated worker with 20 total concurrency
  # User file processing gets portion of 20, defaults to 2
  # Can use all host CPU/memory
  # Localhost communication (<1ms)
```

**Effective Performance**:
- Concurrency: 2 (or portion of 20 in consolidated mode)
- Resources: Unlimited
- Network: <1ms latency
- **Result**: Fast processing (10-40 seconds)

### OpenShift (Current - Slow)

```yaml
celery_worker_user_file_processing:
  replicas: 1
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 2000m
      memory: 2Gi
  # Concurrency: 2 (default)
  # Network: 5-20ms latency
```

**Effective Performance**:
- Concurrency: 2
- Resources: Limited (500m CPU, 512Mi memory)
- Network: 5-20ms latency
- **Result**: Slow processing (60-120 seconds)

### OpenShift (Optimized - Fast)

```yaml
celery_worker_user_file_processing:
  replicas: 3
  resources:
    requests:
      cpu: 2000m
      memory: 2Gi
    limits:
      cpu: 4000m
      memory: 4Gi
  # Concurrency: 8 (via ConfigMap)
  # Network: 5-20ms latency (optimized with larger batches)
```

**Effective Performance**:
- Concurrency: 8 × 3 replicas = 24 total
- Resources: 2000m CPU, 2Gi memory per pod
- Network: 5-20ms latency (but fewer calls with batch size 16)
- **Result**: Fast processing (15-30 seconds)

---

## 💡 Key Insights

1. **Docker Compose defaults are conservative** (concurrency: 2, batch: 8)
2. **But it's still fast** because:
   - No resource limits
   - Localhost communication
   - Can use all host resources
3. **OpenShift needs higher values** to compensate for:
   - Network latency
   - Resource limits
   - Pod isolation

---

## 📚 References

- **Code Defaults**: `backend/onyx/configs/app_configs.py`
- **Model Configs**: `backend/onyx/configs/model_configs.py`
- **Docker Compose**: `deployment/docker_compose/docker-compose.yml`
- **Env Template**: `deployment/docker_compose/env.template`

---

## ✅ Summary

**Docker Compose Current Values**:
- User File Processing Concurrency: **2**
- Embedding Batch Size: **8**
- Worker Replicas: **1** (consolidated)
- Resources: **Unlimited**
- Network: **Localhost** (<1ms)

**Why It's Fast**: Unlimited resources + localhost communication

**OpenShift Needs**: Higher values (8 concurrency, 16 batch, 3 replicas) to match performance due to network overhead and resource limits.

