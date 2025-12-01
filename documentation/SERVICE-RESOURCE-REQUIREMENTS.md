# Service Resource Requirements: File Upload & All Services

## 🎯 File Upload Service

### Service Responsible for File Upload

**Service Name**: **API Server** (`api-server`)

**Endpoint**: `POST /api/user/projects/file/upload`

**File Location**: `backend/onyx/server/features/projects/api.py:75-113`

**What it does**:
1. Receives file uploads from frontend
2. Validates file types and sizes
3. Stores files in MinIO (S3-compatible storage)
4. Creates `UserFile` records in PostgreSQL
5. Enqueues Celery tasks for background processing

**Important**: The API Server **receives** the upload, but **processing** (indexing, embedding) is done by **Celery Workers**.

---

## 📊 Resource Requirements Comparison

### Docker Compose (Official onyxdotapp/onyx-backend:latest)

**File**: `deployment/docker_compose/docker-compose.resources.yml`

**Note**: Docker Compose has **NO resource limits by default** in `docker-compose.yml`. Resource limits are optional and defined in `docker-compose.resources.yml`.

#### API Server (File Upload Service)

**File**: `deployment/docker_compose/docker-compose.resources.yml:28-36`

**Default Resources** (when using resources file):
```yaml
api_server:
  deploy:
    resources:
      limits:
        cpus: ${API_SERVER_CPU_LIMIT:-2}      # Default: 2 CPUs
        memory: ${API_SERVER_MEM_LIMIT:-4g}   # Default: 4GB memory
```

**Without resources file** (default docker-compose.yml):
- **CPU**: Unlimited (uses all available host CPU)
- **Memory**: Unlimited (uses all available host memory)

#### Background Worker (Processes File Uploads)

**File**: `deployment/docker_compose/docker-compose.resources.yml:7-16`

**Default Resources** (when using resources file):
```yaml
background:
  deploy:
    resources:
      limits:
        cpus: ${BACKGROUND_CPU_LIMIT:-6}      # Default: 6 CPUs
        memory: ${BACKGROUND_MEM_LIMIT:-10g}  # Default: 10GB memory
```

**Note**: In Docker Compose, user file processing is handled by the **consolidated background worker** which processes the `user_file_processing` queue along with other queues.

**Without resources file**:
- **CPU**: Unlimited
- **Memory**: Unlimited

#### Other Services (Docker Compose Defaults)

| Service | CPU Limit | Memory Limit | File Location |
|---------|-----------|--------------|---------------|
| **API Server** | 2 CPUs | 4GB | `docker-compose.resources.yml:32-33` |
| **Background Worker** | 6 CPUs | 10GB | `docker-compose.resources.yml:12-13` |
| **Inference Model Server** | Unlimited* | 5GB | `docker-compose.resources.yml:53` |
| **Indexing Model Server** | Unlimited* | 5GB | `docker-compose.resources.yml:63` |
| **PostgreSQL** | 2 CPUs | 4GB | `docker-compose.resources.yml:72-73` |
| **NGINX** | 1 CPU | 1GB | `docker-compose.resources.yml:22-23` |
| **Redis** | Not specified | Not specified | Not in resources file |
| **MinIO** | Not specified | Not specified | Not in resources file |
| **Vespa** | Not specified | Not specified | Not in resources file |

*CPU limits commented out in resources file

---

## 📋 Your OpenShift Manifests: Current Resource Requirements

Based on your manifests in `onyx-k8s-infrastructure/manifests/`:

### 1. API Server (File Upload Service)

**File**: `manifests/07-api-server.yaml`

**Current Resources** (lines 148-154):
```yaml
resources:
  requests:
    cpu: 500m          # 0.5 CPU cores
    memory: 1Gi        # 1GB memory
  limits:
    cpu: 2000m         # 2 CPU cores
    memory: 2Gi        # 2GB memory
```

**Minimum Requirements** (based on Docker Compose defaults):
- **CPU Request**: 500m (current) ✅
- **CPU Limit**: 2000m (current) ✅
- **Memory Request**: 1Gi (current) ✅
- **Memory Limit**: 2Gi (current) ⚠️ **Consider increasing to 4Gi** (Docker Compose uses 4GB)

**Recommendation**: Increase memory limit to 4Gi to match Docker Compose:
```yaml
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi  # ← Increase from 2Gi to 4Gi
```

---

### 2. User File Processing Worker ⚠️ **MISSING**

**Status**: **NOT FOUND in your manifests!**

**Problem**: Your manifests don't include a dedicated `celery-worker-user-file-processing` deployment.

**What this means**:
- User file uploads are **received** by API Server ✅
- But file **processing** (indexing, embedding) may not be happening ❌
- Or it's being handled by another worker (unlikely)

**Solution**: You need to create a user file processing worker. See below.

**Docker Compose Equivalent**: Handled by `background` service with:
- CPU: 6 cores (shared with other workers)
- Memory: 10GB (shared with other workers)
- Queue: `user_file_processing`

**Recommended Resources** (for dedicated worker):
```yaml
resources:
  requests:
    cpu: 2000m         # 2 CPU cores
    memory: 2Gi        # 2GB memory
  limits:
    cpu: 4000m         # 4 CPU cores
    memory: 4Gi        # 4GB memory
```

---

### 3. Indexing Model Server (Used for File Processing)

**File**: `manifests/06-indexing-model-server.yaml`

**Current Resources** (lines 88-94):
```yaml
resources:
  requests:
    cpu: 1000m         # 1 CPU core
    memory: 2Gi        # 2GB memory
  limits:
    cpu: 4000m         # 4 CPU cores
    memory: 8Gi        # 8GB memory
```

**Docker Compose Default**: 5GB memory (no CPU limit specified)

**Minimum Requirements**:
- **CPU Request**: 1000m (current) ✅
- **CPU Limit**: 4000m (current) ✅
- **Memory Request**: 2Gi (current) ✅
- **Memory Limit**: 8Gi (current) ✅ **Good!**

---

### 4. Inference Model Server

**File**: `manifests/06-inference-model-server.yaml`

**Current Resources** (lines 80-86):
```yaml
resources:
  requests:
    cpu: 500m          # 0.5 CPU cores
    memory: 2Gi        # 2GB memory
  limits:
    cpu: 2000m         # 2 CPU cores
    memory: 4Gi        # 4GB memory
```

**Docker Compose Default**: 5GB memory (no CPU limit specified)

**Minimum Requirements**:
- **CPU Request**: 500m (current) ✅
- **CPU Limit**: 2000m (current) ✅
- **Memory Request**: 2Gi (current) ✅
- **Memory Limit**: 4Gi (current) ⚠️ **Consider increasing to 5Gi** to match Docker Compose

---

### 5. PostgreSQL

**File**: `manifests/02-postgresql.yaml`

**Current Resources** (lines 102-108):
```yaml
resources:
  requests:
    cpu: 100m          # 0.1 CPU cores
    memory: 256Mi      # 256MB memory
  limits:
    cpu: 1000m         # 1 CPU core
    memory: 1Gi        # 1GB memory
```

**Docker Compose Default**: 2 CPUs, 4GB memory

**Minimum Requirements**:
- **CPU Request**: 100m (current) ⚠️ **Very low, consider 500m**
- **CPU Limit**: 1000m (current) ⚠️ **Consider 2000m** to match Docker Compose
- **Memory Request**: 256Mi (current) ⚠️ **Very low, consider 1Gi**
- **Memory Limit**: 1Gi (current) ⚠️ **Consider 4Gi** to match Docker Compose

**Recommendation**:
```yaml
resources:
  requests:
    cpu: 500m          # Increase from 100m
    memory: 1Gi        # Increase from 256Mi
  limits:
    cpu: 2000m         # Increase from 1000m
    memory: 4Gi        # Increase from 1Gi
```

---

### 6. Redis

**File**: `manifests/04-redis.yaml`

**Current Resources** (lines 75-81):
```yaml
resources:
  requests:
    cpu: 100m          # 0.1 CPU cores
    memory: 128Mi      # 128MB memory
  limits:
    cpu: 500m          # 0.5 CPU cores
    memory: 512Mi      # 512MB memory
```

**Docker Compose Default**: Not specified (no limits)

**Minimum Requirements**:
- **CPU Request**: 100m (current) ✅
- **CPU Limit**: 500m (current) ✅
- **Memory Request**: 128Mi (current) ✅
- **Memory Limit**: 512Mi (current) ✅

**Note**: Redis is lightweight, current settings are adequate.

---

### 7. Web Server (Frontend)

**File**: `manifests/08-web-server.yaml`

**Current Resources** (lines 58-64):
```yaml
resources:
  requests:
    cpu: 200m          # 0.2 CPU cores
    memory: 512Mi      # 512MB memory
  limits:
    cpu: 1000m         # 1 CPU core
    memory: 1Gi        # 1GB memory
```

**Docker Compose Default**: 1 CPU, 1GB memory

**Minimum Requirements**:
- **CPU Request**: 200m (current) ✅
- **CPU Limit**: 1000m (current) ✅
- **Memory Request**: 512Mi (current) ✅
- **Memory Limit**: 1Gi (current) ✅

---

### 8. Celery Workers

#### Primary Worker

**File**: `manifests/11-celery-worker-primary.yaml`

**Current Resources** (lines 63-69):
```yaml
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 1000m
    memory: 2Gi
```

**Minimum Requirements**: ✅ Current settings are adequate

---

#### Light Worker

**File**: `manifests/12-celery-worker-light.yaml`

**Current Resources** (lines 63-69):
```yaml
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 1000m
    memory: 2Gi
```

**Minimum Requirements**: ✅ Current settings are adequate

---

#### Heavy Worker

**File**: `manifests/13-celery-worker-heavy.yaml`

**Current Resources** (lines 63-69):
```yaml
resources:
  requests:
    cpu: 1000m
    memory: 4Gi
  limits:
    cpu: 2000m
    memory: 8Gi
```

**Minimum Requirements**: ✅ Current settings are adequate

---

#### Docfetching Worker

**File**: `manifests/14-celery-worker-docfetching.yaml`

**Current Resources** (lines 65-71):
```yaml
resources:
  requests:
    cpu: 500m
    memory: 8Gi
  limits:
    cpu: 2000m
    memory: 16Gi
```

**Minimum Requirements**: ✅ Current settings are adequate

---

#### Docprocessing Worker

**File**: `manifests/15-celery-worker-docprocessing.yaml`

**Current Resources** (lines 74-80):
```yaml
resources:
  requests:
    cpu: 1000m
    memory: 8Gi
  limits:
    cpu: 4000m
    memory: 16Gi
```

**Minimum Requirements**: ✅ Current settings are adequate

**Note**: This worker processes documents, but **NOT user file uploads**. User files need a separate worker.

---

## ⚠️ Critical Issue: Missing User File Processing Worker

### Problem

Your manifests **DO NOT include** a `celery-worker-user-file-processing` deployment.

**What this means**:
- Files can be **uploaded** (API Server works)
- But files **cannot be processed** (no worker to handle the queue)
- Files will remain in `PROCESSING` status forever

### Solution: Create User File Processing Worker

**Create File**: `manifests/16-celery-worker-user-file-processing.yaml`

**Template**:
```yaml
# ============================================================================
# Celery Worker - User File Processing for Onyx
# ============================================================================
# CRITICAL: Processes user-uploaded files
# - Extracts text from files
# - Chunks documents
# - Generates embeddings via INDEXING MODEL SERVER
# - Stores in Vespa vector database
# 
# Image: onyxdotapp/onyx-backend
# Queues: user_file_processing, user_file_project_sync, user_file_delete
# ============================================================================

apiVersion: apps/v1
kind: Deployment
metadata:
  name: celery-worker-user-file-processing
  labels:
    app: celery-worker-user-file-processing
spec:
  replicas: 1  # Increase to 3 for better performance
  selector:
    matchLabels:
      app: celery-worker-user-file-processing
  template:
    metadata:
      labels:
        app: celery-worker-user-file-processing
        scope: onyx-backend-celery
    spec:
      containers:
        - name: celery-worker-user-file-processing
          image: onyxdotapp/onyx-backend:nightly-20241004
          imagePullPolicy: IfNotPresent
          command:
            - celery
            - -A
            - onyx.background.celery.versioned_apps.user_file_processing
            - worker
            - --pool=threads
            - --concurrency=${CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY:-2}
            - --prefetch-multiplier=1
            - --loglevel=INFO
            - --hostname=user_file_processing@%n
            - -Q
            - user_file_processing,user_file_project_sync,user_file_delete
          envFrom:
            - configMapRef:
                name: onyx-config
          env:
            # Database credentials from secret
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: postgresql-secret
                  key: POSTGRES_USER
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgresql-secret
                  key: POSTGRES_PASSWORD
            # Redis password from secret
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: redis-secret
                  key: REDIS_PASSWORD
            # NLTK data path (for air-gapped environments)
            - name: NLTK_DATA
              value: "/usr/local/share/nltk_data"
          resources:
            requests:
              cpu: 2000m         # 2 CPU cores (for file processing)
              memory: 2Gi        # 2GB memory
            limits:
              cpu: 4000m         # 4 CPU cores
              memory: 4Gi        # 4GB memory
          startupProbe:
            exec:
              command:
                - /bin/sh
                - -c
                - celery -A onyx.background.celery.versioned_apps.user_file_processing inspect ping -d user_file_processing@$HOSTNAME
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 30
          readinessProbe:
            exec:
              command:
                - /bin/sh
                - -c
                - celery -A onyx.background.celery.versioned_apps.user_file_processing inspect ping -d user_file_processing@$HOSTNAME
            initialDelaySeconds: 10
            periodSeconds: 10
            failureThreshold: 3
      restartPolicy: Always
```

**Apply**:
```bash
oc apply -f manifests/16-celery-worker-user-file-processing.yaml
```

---

## 📊 Complete Resource Requirements Summary

### Minimum Requirements (Based on Docker Compose Defaults)

| Service | CPU Request | CPU Limit | Memory Request | Memory Limit | Status |
|---------|-------------|-----------|----------------|--------------|--------|
| **API Server** (File Upload) | 500m | 2000m | 1Gi | **4Gi** ⚠️ | Increase memory |
| **User File Processing Worker** | **2000m** ⚠️ | **4000m** ⚠️ | **2Gi** ⚠️ | **4Gi** ⚠️ | **MISSING - CREATE** |
| **Indexing Model Server** | 1000m | 4000m | 2Gi | 8Gi | ✅ OK |
| **Inference Model Server** | 500m | 2000m | 2Gi | **5Gi** ⚠️ | Increase memory |
| **PostgreSQL** | **500m** ⚠️ | **2000m** ⚠️ | **1Gi** ⚠️ | **4Gi** ⚠️ | Increase all |
| **Redis** | 100m | 500m | 128Mi | 512Mi | ✅ OK |
| **Web Server** | 200m | 1000m | 512Mi | 1Gi | ✅ OK |
| **Primary Worker** | 500m | 1000m | 1Gi | 2Gi | ✅ OK |
| **Light Worker** | 500m | 1000m | 1Gi | 2Gi | ✅ OK |
| **Heavy Worker** | 1000m | 2000m | 4Gi | 8Gi | ✅ OK |
| **Docfetching Worker** | 500m | 2000m | 8Gi | 16Gi | ✅ OK |
| **Docprocessing Worker** | 1000m | 4000m | 8Gi | 16Gi | ✅ OK |

**⚠️ = Needs adjustment**  
**✅ = Adequate**

---

## 🔧 Recommended Changes to Your Manifests

### 1. API Server (`07-api-server.yaml`)

**File**: `manifests/07-api-server.yaml`  
**Line**: 154

**Change**:
```yaml
# BEFORE:
limits:
  cpu: 2000m
  memory: 2Gi

# AFTER:
limits:
  cpu: 2000m
  memory: 4Gi  # Increase from 2Gi to match Docker Compose
```

---

### 2. PostgreSQL (`02-postgresql.yaml`)

**File**: `manifests/02-postgresql.yaml`  
**Lines**: 102-108

**Change**:
```yaml
# BEFORE:
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 1Gi

# AFTER:
resources:
  requests:
    cpu: 500m      # Increase from 100m
    memory: 1Gi    # Increase from 256Mi
  limits:
    cpu: 2000m     # Increase from 1000m
    memory: 4Gi    # Increase from 1Gi
```

---

### 3. Inference Model Server (`06-inference-model-server.yaml`)

**File**: `manifests/06-inference-model-server.yaml`  
**Line**: 86

**Change**:
```yaml
# BEFORE:
limits:
  cpu: 2000m
  memory: 4Gi

# AFTER:
limits:
  cpu: 2000m
  memory: 5Gi  # Increase from 4Gi to match Docker Compose
```

---

### 4. Create User File Processing Worker

**Action**: Create new file `manifests/16-celery-worker-user-file-processing.yaml`

**Use the template provided above** in the "Critical Issue" section.

---

## 📈 Total Resource Requirements

### Current (Your Manifests)

| Resource | Total Request | Total Limit |
|----------|---------------|-------------|
| **CPU** | ~8.4 cores | ~20.5 cores |
| **Memory** | ~30Gi | ~60Gi |

### Recommended (After Changes)

| Resource | Total Request | Total Limit |
|----------|---------------|-------------|
| **CPU** | ~12.4 cores | ~28.5 cores |
| **Memory** | ~40Gi | ~80Gi |

**Increase**: +4 CPU cores, +10Gi memory (requests) and +8 CPU cores, +20Gi memory (limits)

---

## ✅ Action Items

1. **CRITICAL**: Create `16-celery-worker-user-file-processing.yaml` (file uploads won't work without it!)
2. **IMPORTANT**: Increase API Server memory limit to 4Gi
3. **IMPORTANT**: Increase PostgreSQL resources (CPU: 500m/2000m, Memory: 1Gi/4Gi)
4. **OPTIONAL**: Increase Inference Model Server memory to 5Gi
5. **OPTIONAL**: Add `CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY: "8"` to ConfigMap
6. **OPTIONAL**: Scale user file processing worker to 3 replicas

---

## 📚 File Reference Summary

| Service | Manifest File | Resource Section |
|---------|---------------|-----------------|
| API Server | `07-api-server.yaml` | Lines 148-154 |
| User File Processing Worker | **MISSING** | **CREATE FILE** |
| Indexing Model Server | `06-indexing-model-server.yaml` | Lines 88-94 |
| Inference Model Server | `06-inference-model-server.yaml` | Lines 80-86 |
| PostgreSQL | `02-postgresql.yaml` | Lines 102-108 |
| Redis | `04-redis.yaml` | Lines 75-81 |
| Web Server | `08-web-server.yaml` | Lines 58-64 |
| Primary Worker | `11-celery-worker-primary.yaml` | Lines 63-69 |
| Light Worker | `12-celery-worker-light.yaml` | Lines 63-69 |
| Heavy Worker | `13-celery-worker-heavy.yaml` | Lines 63-69 |
| Docfetching Worker | `14-celery-worker-docfetching.yaml` | Lines 65-71 |
| Docprocessing Worker | `15-celery-worker-docprocessing.yaml` | Lines 74-80 |

---

## 🎯 Summary

**File Upload Service**: API Server (`api-server`)

**Docker Compose Resources**:
- API Server: 2 CPUs, 4GB memory (when using resources file)
- Background Worker: 6 CPUs, 10GB memory (handles user file processing)

**Your OpenShift Manifests**:
- API Server: 500m/2000m CPU, 1Gi/2Gi memory ✅ (consider increasing memory to 4Gi)
- **User File Processing Worker**: **MISSING** ⚠️ **CRITICAL - MUST CREATE**
- PostgreSQL: Very low resources ⚠️ (should increase)

**Key Finding**: Your deployment is **missing the user file processing worker**, which explains why file uploads may not be completing!

