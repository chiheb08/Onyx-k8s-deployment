# CRITICAL: Missing Celery Background Workers

## 🚨 **Issue Summary**

**Your Kubernetes deployment is missing ALL Celery background workers!**

This is a **critical omission** that explains why:
- ❌ API server can't fully communicate with model servers (workers do the bulk processing)
- ❌ Documents are not being indexed
- ❌ Connectors are not syncing
- ❌ Background tasks are not running
- ❌ The system appears to "work" but many features are broken

## 📊 What's Missing

According to the Docker Compose architecture diagram you provided, Onyx requires **8 types of Celery workers**:

### Current State (Your Deployment)
```
✅ PostgreSQL        - Deployed
✅ Redis             - Deployed  
✅ Vespa             - Deployed
✅ API Server        - Deployed
✅ Web Server        - Deployed
✅ NGINX             - Deployed
✅ Inference Model Server - Deployed
✅ Indexing Model Server  - Deployed

❌ Celery Worker - Primary         - MISSING
❌ Celery Worker - Docfetching     - MISSING
❌ Celery Worker - Docprocessing   - MISSING
❌ Celery Worker - Light           - MISSING
❌ Celery Worker - Heavy           - MISSING
❌ Celery Beat (Scheduler)         - MISSING
```

## 🔍 Why This Breaks Model Server Communication

### API Server vs Background Workers

```
┌─────────────────────────────────────────────────────────────┐
│  API SERVER (What You Have)                                 │
│  - Handles user requests                                    │
│  - Uses INFERENCE Model Server for real-time queries        │
│  - Does NOT use INDEXING Model Server                       │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  BACKGROUND WORKERS (What's Missing)                        │
│  - Processes documents in background                        │
│  - Uses INDEXING Model Server for bulk embedding           │
│  - Writes vectors to Vespa                                  │
│  - Updates PostgreSQL metadata                              │
└─────────────────────────────────────────────────────────────┘
```

**The Problem:**
- Your **Indexing Model Server** is deployed but **nothing is using it**
- The **Inference Model Server** is only used by API server for queries
- **Document indexing never happens** without background workers
- **Celery tasks pile up in Redis** but no workers pick them up

## 📋 Complete Worker Breakdown

### 1. **Primary Worker**
- **Queue**: `celery`, `periodic_tasks`
- **Purpose**: Core background tasks, connector management
- **Used by**: System coordination, LLM model updates
- **Critical**: Yes

### 2. **Docfetching Worker**
- **Queue**: `docfetching`
- **Purpose**: Fetch documents from connectors (Google Drive, Confluence, etc.)
- **Used by**: All connector sync operations
- **Critical**: Yes (for document ingestion)

### 3. **Docprocessing Worker**
- **Queue**: `docprocessing`
- **Purpose**: Process and embed documents, write to Vespa
- **Calls**: Indexing Model Server → Generates embeddings → Vespa
- **Critical**: **YES - THIS IS WHY MODEL SERVER COMMUNICATION IS BROKEN**

### 4. **Light Worker**
- **Queue**: `vespa_metadata_sync`, `connector_deletion`, `doc_permissions_upsert`, etc.
- **Purpose**: Lightweight tasks (metadata sync, permissions)
- **Critical**: Moderate

### 5. **Heavy Worker**
- **Queue**: `connector_pruning`, `connector_doc_permissions_sync`, etc.
- **Purpose**: Resource-intensive operations (pruning, bulk sync)
- **Critical**: Moderate

### 6. **Celery Beat (Scheduler)**
- **Purpose**: Schedule periodic tasks (every 15s-5min)
- **Examples**: Check for new docs, sync connectors, cleanup
- **Critical**: **YES - Without this, NOTHING runs automatically**

## 🔗 Model Server Communication Flow

### What SHOULD Happen (With Workers):

```
1. User uploads document
        ↓
2. API Server stores in MinIO
        ↓
3. API Server creates Celery task in Redis
        ↓
4. Docprocessing Worker picks up task
        ↓
5. Worker calls Indexing Model Server
        ↓
6. Model Server returns embeddings
        ↓
7. Worker writes to Vespa
        ↓
8. Document ready for search!
```

### What ACTUALLY Happens (Without Workers):

```
1. User uploads document
        ↓
2. API Server stores in MinIO
        ↓
3. API Server creates Celery task in Redis
        ↓
4. Task sits in Redis forever ⚠️
        ↓
5. Indexing Model Server never called ⚠️
        ↓
6. Document never indexed ⚠️
        ↓
7. Search returns nothing! ❌
```

## 📊 Comparison: Docker Compose vs Your K8s Deployment

### Docker Compose (ARCHITECTURE-DIAGRAM.md)
```yaml
services:
  # ... infrastructure ...
  
  background:  # ← THIS IS MISSING FROM YOUR K8s!
    image: onyxdotapp/onyx-backend:latest
    command: ["/usr/bin/supervisord"]  # Runs all workers
    depends_on:
      - relational_db
      - index
      - cache
      - inference_model_server
      - indexing_model_server  # ← CRITICAL!
```

### Your Kubernetes Deployment
```yaml
# Only has:
- API Server
- Web Server
- Model Servers
- Infrastructure

# Missing:
- Background workers (all 6 types)
- Celery Beat scheduler
```

## 🚀 What You Need to Deploy

Based on Helm charts, you need these 6 deployments:

### 1. Celery Beat (Scheduler)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: celery-beat
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: celery-beat
          image: onyxdotapp/onyx-backend:nightly-20241004
          command:
            - celery
            - -A
            - onyx.background.celery.versioned_apps.beat
            - beat
            - --loglevel=INFO
```

### 2. Celery Worker - Primary
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: celery-worker-primary
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: celery-worker-primary
          image: onyxdotapp/onyx-backend:nightly-20241004
          command:
            - celery
            - -A
            - onyx.background.celery.versioned_apps.primary
            - worker
            - --loglevel=INFO
            - --hostname=primary@%n
            - -Q
            - celery,periodic_tasks
```

### 3. Celery Worker - Docfetching
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: celery-worker-docfetching
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: celery-worker-docfetching
          image: onyxdotapp/onyx-backend:nightly-20241004
          command:
            - celery
            - -A
            - onyx.background.celery.versioned_apps.docfetching
            - worker
            - --pool=threads
            - --concurrency=4
            - --loglevel=INFO
            - --hostname=docfetching@%n
            - -Q
            - docfetching
```

### 4. Celery Worker - Docprocessing (CRITICAL!)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: celery-worker-docprocessing
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: celery-worker-docprocessing
          image: onyxdotapp/onyx-backend:nightly-20241004
          command:
            - celery
            - -A
            - onyx.background.celery.versioned_apps.docprocessing
            - worker
            - --pool=threads
            - --concurrency=6
            - --prefetch-multiplier=1
            - --loglevel=INFO
            - --hostname=docprocessing@%n
            - -Q
            - docprocessing
```

### 5. Celery Worker - Light
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: celery-worker-light
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: celery-worker-light
          image: onyxdotapp/onyx-backend:nightly-20241004
          command:
            - celery
            - -A
            - onyx.background.celery.versioned_apps.light
            - worker
            - --loglevel=INFO
            - --hostname=light@%n
            - -Q
            - vespa_metadata_sync,connector_deletion,doc_permissions_upsert,checkpoint_cleanup,index_attempt_cleanup
```

### 6. Celery Worker - Heavy
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: celery-worker-heavy
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: celery-worker-heavy
          image: onyxdotapp/onyx-backend:nightly-20241004
          command:
            - celery
            - -A
            - onyx.background.celery.versioned_apps.heavy
            - worker
            - --loglevel=INFO
            - --hostname=heavy@%n
            - -Q
            - connector_pruning,connector_doc_permissions_sync,connector_external_group_sync,csv_generation
```

## 📈 Resource Requirements

Based on Helm charts:

| Worker | CPU Request | CPU Limit | Memory Request | Memory Limit |
|--------|-------------|-----------|----------------|--------------|
| Beat | 100m | 500m | 256Mi | 512Mi |
| Primary | 500m | 1000m | 1Gi | 2Gi |
| Docfetching | 500m | 2000m | 8Gi | 16Gi |
| Docprocessing | 1000m | 4000m | 8Gi | 16Gi |
| Light | 500m | 1000m | 1Gi | 2Gi |
| Heavy | 1000m | 2000m | 4Gi | 8Gi |

**Total Additional Resources Needed:**
- CPU: ~3.6 cores (requests), ~10.5 cores (limits)
- Memory: ~22 GB (requests), ~44 GB (limits)

## 🔧 Immediate Actions

### 1. **Verify Redis Queue**
```bash
# Check if tasks are piling up in Redis
oc exec -it deploy/redis -- redis-cli

# In Redis CLI:
KEYS celery*
LLEN celery  # Check celery queue length
LLEN docprocessing  # Check docprocessing queue
```

If you see tasks piling up, it confirms workers are missing.

### 2. **Check API Server Logs**
```bash
# Look for Celery task creation
oc logs deploy/api-server | grep -i celery

# You should see:
# "Created task for document processing..."
# But no "Task completed" messages (because no workers!)
```

### 3. **Deploy Workers**
I'll create complete worker manifests in the next step.

## 🎯 Why This Wasn't Obvious

1. **API Server starts fine** - It doesn't need workers to run
2. **UI loads** - Web server works independently
3. **Search works (partially)** - Uses inference model server
4. **No obvious errors** - Tasks just queue silently in Redis

## 📚 References

- Docker Compose: `/onyx-deployment-troubleshooting/ARCHITECTURE-DIAGRAM.md`
- Helm Charts: `onyx-repo/deployment/helm/charts/onyx/templates/celery-*.yaml`
- Celery Apps: `onyx-repo/backend/onyx/background/celery/versioned_apps/`

## 🚨 Impact Assessment

### Without Workers:
- ❌ Document indexing broken
- ❌ Connector sync broken
- ❌ Scheduled tasks not running
- ❌ Indexing Model Server unused
- ❌ Permissions sync broken
- ❌ Cleanup tasks not running
- ⚠️ Search works (but only for manually indexed docs)
- ⚠️ Chat works (if using external LLM)

### With Workers:
- ✅ Full document processing pipeline
- ✅ Automatic connector sync
- ✅ Background indexing
- ✅ Periodic cleanup
- ✅ Complete system functionality

## ⏭️ Next Steps

1. Create complete Celery worker manifests
2. Deploy all 6 workers
3. Verify workers connect to Redis
4. Test document upload → indexing → search flow
5. Monitor worker logs for model server communication
