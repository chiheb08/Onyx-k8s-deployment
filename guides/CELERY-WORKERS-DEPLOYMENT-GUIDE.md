# Celery Workers Deployment Guide

## 🎯 Overview

This guide explains how to deploy the 6 critical Celery background workers that were previously missing from your Kubernetes deployment. These workers are essential for document processing, indexing, and all background operations in Onyx.

## 📋 Workers Overview

| Worker | Purpose | Queue | Critical? |
|--------|---------|-------|-----------|
| **Celery Beat** | Task scheduler | N/A | ✅ YES |
| **Primary** | Core background tasks | `celery`, `periodic_tasks` | ✅ YES |
| **Docfetching** | Fetch documents from connectors | `docfetching` | ✅ YES |
| **Docprocessing** | Process & embed documents | `docprocessing` | ✅ **CRITICAL** |
| **Light** | Lightweight operations | Multiple queues | ⚠️ Moderate |
| **Heavy** | Resource-intensive operations | Multiple queues | ⚠️ Moderate |

## 🚀 Quick Deployment

### 1. Deploy All Workers (Recommended)
```bash
# Deploy in order:
oc apply -f manifests/10-celery-beat.yaml
oc apply -f manifests/11-celery-worker-primary.yaml
oc apply -f manifests/12-celery-worker-light.yaml
oc apply -f manifests/13-celery-worker-heavy.yaml
oc apply -f manifests/14-celery-worker-docfetching.yaml
oc apply -f manifests/15-celery-worker-docprocessing.yaml

# Wait for all workers to be ready
oc get pods -l scope=onyx-backend-celery -w
```

### 2. Minimal Deployment (Only Critical Workers)
```bash
# If resource-constrained, deploy only these 3:
oc apply -f manifests/10-celery-beat.yaml
oc apply -f manifests/11-celery-worker-primary.yaml
oc apply -f manifests/15-celery-worker-docprocessing.yaml

# This provides:
# - Task scheduling (Beat)
# - Core tasks (Primary)
# - Document indexing (Docprocessing)
```

## 📊 Resource Requirements

### Full Deployment
| Worker | CPU Request | CPU Limit | Memory Request | Memory Limit |
|--------|-------------|-----------|----------------|--------------|
| Beat | 100m | 500m | 256Mi | 512Mi |
| Primary | 500m | 1000m | 1Gi | 2Gi |
| Light | 500m | 1000m | 1Gi | 2Gi |
| Heavy | 1000m | 2000m | 4Gi | 8Gi |
| Docfetching | 500m | 2000m | 8Gi | 16Gi |
| Docprocessing | 1000m | 4000m | 8Gi | 16Gi |
| **TOTAL** | **3.6 cores** | **10.5 cores** | **22 GB** | **44 GB** |

### Minimal Deployment
| Worker | CPU Request | CPU Limit | Memory Request | Memory Limit |
|--------|-------------|-----------|----------------|--------------|
| Beat | 100m | 500m | 256Mi | 512Mi |
| Primary | 500m | 1000m | 1Gi | 2Gi |
| Docprocessing | 1000m | 4000m | 8Gi | 16Gi |
| **TOTAL** | **1.6 cores** | **5.5 cores** | **9.2 GB** | **18.5 GB** |

## 🔍 Verification Steps

### 1. Check Worker Pods
```bash
# All workers should be Running
oc get pods -l scope=onyx-backend-celery

# Expected output:
# NAME                                         READY   STATUS    RESTARTS   AGE
# celery-beat-xxx                              1/1     Running   0          2m
# celery-worker-primary-xxx                    1/1     Running   0          2m
# celery-worker-light-xxx                      1/1     Running   0          2m
# celery-worker-heavy-xxx                      1/1     Running   0          2m
# celery-worker-docfetching-xxx                1/1     Running   0          2m
# celery-worker-docprocessing-xxx              1/1     Running   0          2m
```

### 2. Check Worker Logs
```bash
# Check Beat scheduler
oc logs -l app=celery-beat --tail=20

# Should see:
# "LocalTime -> 2025-10-21 ..."
# "celery beat v5.x.x is starting."

# Check Primary worker
oc logs -l app=celery-worker-primary --tail=20

# Should see:
# "celery@primary-xxx v5.x.x"
# "Connected to redis://redis..."
# "[queues] .> celery, periodic_tasks"

# Check Docprocessing worker (CRITICAL)
oc logs -l app=celery-worker-docprocessing --tail=20

# Should see:
# "celery@docprocessing-xxx v5.x.x"
# "Connected to redis://redis..."
# "[queues] .> docprocessing"
```

### 3. Verify Redis Connection
```bash
# Check if workers are registered in Redis
oc exec -it deploy/redis -- redis-cli

# In Redis CLI:
KEYS celery-task-meta*  # Should show task metadata
LLEN docprocessing      # Check docprocessing queue length
LLEN celery             # Check celery queue length
```

### 4. Test Document Upload
```bash
# Upload a test document via Onyx UI
# Then check docprocessing worker logs

oc logs -l app=celery-worker-docprocessing --tail=50 -f

# Should see:
# "Task onyx.background.celery.tasks.indexing.upsert_documents[xxx] received"
# "Calling indexing model server..."
# "Writing to Vespa..."
# "Task onyx.background.celery.tasks.indexing.upsert_documents[xxx] succeeded"
```

## 🔧 Detailed Worker Configurations

### 1. Celery Beat (Scheduler)

**Purpose:** Schedules periodic tasks

**File:** `manifests/10-celery-beat.yaml`

**Command:**
```bash
celery -A onyx.background.celery.versioned_apps.beat beat --loglevel=INFO
```

**Important:** 
- **MUST** have exactly **1 replica** (to avoid duplicate scheduled tasks)
- No queues (scheduler only)
- Uses exec probe (no HTTP endpoint)

### 2. Celery Worker - Primary

**Purpose:** Core background tasks, connector management

**File:** `manifests/11-celery-worker-primary.yaml`

**Command:**
```bash
celery -A onyx.background.celery.versioned_apps.primary worker \
  --loglevel=INFO --hostname=primary@%n -Q celery,periodic_tasks
```

**Queues:**
- `celery` - Default queue for general tasks
- `periodic_tasks` - Tasks scheduled by Beat

### 3. Celery Worker - Light

**Purpose:** Lightweight, fast operations

**File:** `manifests/12-celery-worker-light.yaml`

**Command:**
```bash
celery -A onyx.background.celery.versioned_apps.light worker \
  --loglevel=INFO --hostname=light@%n \
  -Q vespa_metadata_sync,connector_deletion,doc_permissions_upsert,checkpoint_cleanup,index_attempt_cleanup
```

**Queues:**
- `vespa_metadata_sync` - Vespa metadata synchronization
- `connector_deletion` - Delete connectors
- `doc_permissions_upsert` - Update document permissions
- `checkpoint_cleanup` - Clean up indexing checkpoints
- `index_attempt_cleanup` - Clean up failed indexing attempts

### 4. Celery Worker - Heavy

**Purpose:** Resource-intensive operations

**File:** `manifests/13-celery-worker-heavy.yaml`

**Command:**
```bash
celery -A onyx.background.celery.versioned_apps.heavy worker \
  --loglevel=INFO --hostname=heavy@%n \
  -Q connector_pruning,connector_doc_permissions_sync,connector_external_group_sync,csv_generation
```

**Queues:**
- `connector_pruning` - Prune deleted documents
- `connector_doc_permissions_sync` - Sync document permissions
- `connector_external_group_sync` - Sync external groups
- `csv_generation` - Generate CSV exports

### 5. Celery Worker - Docfetching

**Purpose:** Fetch documents from external connectors

**File:** `manifests/14-celery-worker-docfetching.yaml`

**Command:**
```bash
celery -A onyx.background.celery.versioned_apps.docfetching worker \
  --pool=threads --concurrency=4 \
  --loglevel=INFO --hostname=docfetching@%n -Q docfetching
```

**Special Config:**
- `--pool=threads` - Uses thread pool for I/O-bound operations
- `--concurrency=4` - 4 concurrent threads

**Queues:**
- `docfetching` - Fetch documents from connectors

### 6. Celery Worker - Docprocessing (CRITICAL!)

**Purpose:** Process documents and generate embeddings

**File:** `manifests/15-celery-worker-docprocessing.yaml`

**Command:**
```bash
celery -A onyx.background.celery.versioned_apps.docprocessing worker \
  --pool=threads --concurrency=6 --prefetch-multiplier=1 \
  --loglevel=INFO --hostname=docprocessing@%n -Q docprocessing
```

**Special Config:**
- `--pool=threads` - Uses thread pool for embedding operations
- `--concurrency=6` - 6 concurrent threads
- `--prefetch-multiplier=1` - Process one task at a time per thread

**Queues:**
- `docprocessing` - Process and embed documents

**Critical Operations:**
1. Chunk documents
2. **Call Indexing Model Server** for embeddings
3. Write chunks and embeddings to Vespa
4. Update PostgreSQL metadata

**This is the worker that communicates with your Indexing Model Server!**

## 🎯 Communication Flow (With Workers Deployed)

```
1. User uploads document via UI
        ↓
2. API Server stores in MinIO
        ↓
3. API Server creates Celery task in Redis queue
        ↓
4. Docfetching Worker picks up task
        ↓
5. Docfetching Worker creates docprocessing task
        ↓
6. Docprocessing Worker picks up task
        ↓
7. Docprocessing Worker calls Indexing Model Server
        ↓
8. Model Server returns embeddings
        ↓
9. Docprocessing Worker writes to Vespa
        ↓
10. Document ready for search!
```

## 🐛 Troubleshooting

### Workers Not Starting

**Symptom:** Pods in CrashLoopBackOff or Error state

**Diagnosis:**
```bash
# Check pod logs
oc logs -l app=celery-worker-primary --tail=50

# Check pod events
oc describe pod -l app=celery-worker-primary
```

**Common Causes:**
1. **Redis connection failed**
   - Check: `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` in ConfigMap
   - Fix: Update ConfigMap with correct Redis service name

2. **PostgreSQL connection failed**
   - Check: `POSTGRES_HOST`, `POSTGRES_PORT`, credentials
   - Fix: Ensure PostgreSQL is running and accessible

3. **Resource constraints**
   - Check: Resource quotas in namespace
   - Fix: Reduce resource requests or increase namespace quota

### Workers Running But No Tasks Processing

**Symptom:** Documents uploaded but not indexed

**Diagnosis:**
```bash
# Check Redis queues
oc exec -it deploy/redis -- redis-cli

# In Redis:
LLEN docprocessing  # Should be 0 if processing
LLEN celery         # Should be 0 if processing

# If queues are growing, workers aren't picking up tasks
```

**Fixes:**
1. Check worker logs for errors
2. Verify ConfigMap environment variables
3. Ensure all workers are connected to Redis

### Indexing Model Server Not Being Called

**Symptom:** Docprocessing worker running but no embeddings generated

**Diagnosis:**
```bash
# Check docprocessing worker logs
oc logs -l app=celery-worker-docprocessing --tail=100 -f

# Check indexing model server logs
oc logs -l app=indexing-model-server --tail=100 -f
```

**Fixes:**
1. Verify `INDEXING_MODEL_SERVER_HOST` in ConfigMap
2. Ensure indexing model server is running and accessible
3. Check network policies allow communication

## 📚 Additional Resources

- **Architecture Diagram:** `onyx-deployment-troubleshooting/ARCHITECTURE-DIAGRAM.md`
- **Missing Workers Analysis:** `troubleshooting/CRITICAL-MISSING-CELERY-WORKERS.md`
- **Helm Charts Reference:** `onyx-repo/deployment/helm/charts/onyx/templates/celery-*.yaml`
- **Celery Source Code:** `onyx-repo/backend/onyx/background/celery/`

## ⏭️ Next Steps

1. **Deploy workers** using commands above
2. **Verify deployment** using verification steps
3. **Test document upload** and indexing flow
4. **Monitor resource usage** and adjust limits if needed
5. **Scale workers** if needed (increase replicas for heavy load)
