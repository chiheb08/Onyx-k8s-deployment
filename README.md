# Onyx Kubernetes Infrastructure - Minimal Deployment

Minimal Kubernetes deployment for Onyx on OpenShift, specifically designed for **air-gapped/restricted environments** with existing PersistentVolume for model storage.

---

## 🚀 Quick Start

### Prerequisites

1. **OpenShift cluster** with namespace created (e.g., `onyx-infra`)
2. **Existing PersistentVolume (PV)** with pre-loaded Hugging Face models
3. **Storage class** that supports `ReadWriteMany` (preferred) or `ReadWriteOnce`
4. **No internet access** required in pods (air-gapped ready)

### Deployment Steps

```bash
# 1. Get PV details from your colleague
#    - StorageClass name
#    - Access mode (ReadWriteMany or ReadWriteOnce)
#    - PV size

# 2. Update pvc-shared-models.yaml with your StorageClass
#    Edit: storageClassName: "your-storage-class-name"

# 3. Deploy in order
oc apply -f pvc-shared-models.yaml              # Model cache PVC
oc apply -f 02-postgresql.yaml                  # Database
oc apply -f 03-vespa.yaml                       # Vector search
oc apply -f 04-redis.yaml                       # Cache
oc apply -f 05-configmap.yaml                   # Configuration
oc apply -f 06-inference-model-server.yaml      # Inference model server
oc apply -f 06-indexing-model-server.yaml       # Indexing model server
oc apply -f 07-api-server.yaml                  # API server
oc apply -f 08-web-server.yaml                  # Web UI
oc apply -f 09-nginx.yaml                       # Reverse proxy

# 4. Verify deployment
oc get pods
oc logs deployment/inference-model-server | grep "loaded model"
```

---

## 📁 Essential Files

### Deployment YAMLs (Deploy in Order)

1. **`pvc-shared-models.yaml`** - PVC for Hugging Face models (shared by both model servers)
2. **`02-postgresql.yaml`** - PostgreSQL database with persistent storage
3. **`03-vespa.yaml`** - Vespa vector database (StatefulSet)
4. **`04-redis.yaml`** - Redis cache for sessions and queues
5. **`05-configmap.yaml`** - Environment configuration for all services
6. **`06-inference-model-server.yaml`** - Real-time query embedding (offline mode)
7. **`06-indexing-model-server.yaml`** - Bulk document embedding (offline mode)
8. **`07-api-server.yaml`** - FastAPI backend with Alembic migrations
9. **`08-web-server.yaml`** - Next.js frontend
10. **`09-nginx.yaml`** - NGINX reverse proxy with ConfigMap

### Alternative Files

- **`pvc-separate-models.yaml`** - Use if your storage only supports `ReadWriteOnce`

### Key Documentation

- **`START-HERE.md`** - Quick orientation guide
- **`USING-EXISTING-PV-FOR-MODELS.md`** - **CRITICAL:** How to use existing PV with models
- **`00-BEFORE-DEPLOYING.md`** - Prerequisites and OpenShift setup
- **`QUICK-START.md`** - Fast deployment guide
- **`MINIMAL-DEPLOYMENT-GUIDE.md`** - Comprehensive deployment guide

### Architecture & Concepts

- **`ARCHITECTURE-FOR-JUNIOR-ENGINEERS.md`** - Detailed architecture for beginners
- **`HUGGING-FACE-MODELS-FLOW.md`** - How model servers use Hugging Face models
- **`MODEL-SERVERS-EXPLANATION.md`** - Why two model servers are needed
- **`AIRGAPPED-MODEL-SERVERS-GUIDE.md`** - Complete air-gapped deployment guide

### Additional Documentation

- **`docs/troubleshooting/`** - Troubleshooting guides (PVC, ArgoCD, Redis, SCC)
- **`docs/reference/`** - Reference documentation (DNS, architecture, Vespa)

---

## 🎯 What Gets Deployed

### Core Services (7 components)

| Service | Purpose | Port | Replicas |
|---------|---------|------|----------|
| **NGINX** | Reverse proxy, SSL termination | 80 (external) | 1 |
| **Web Server** | Next.js frontend UI | 3000 (internal) | 1 |
| **API Server** | FastAPI backend | 8080 (internal) | 1 |
| **Inference Model Server** | Real-time query embeddings | 9000 (internal) | 1 |
| **Indexing Model Server** | Bulk document embeddings | 9000 (internal) | 1 |
| **PostgreSQL** | Primary database | 5432 (internal) | 1 |
| **Vespa** | Vector search engine | 19071, 8081 (internal) | 1 |
| **Redis** | Cache and task queue | 6379 (internal) | 1 |

### Not Included (Optional for Full Features)

- Background workers (Celery) - For document indexing
- MinIO - For file storage (can use external S3)

---

## 🔧 Configuration for Air-Gapped Environments

Both model servers are configured for **offline mode** with existing PV:

### Critical Environment Variables

```yaml
env:
  - name: HF_HUB_OFFLINE
    value: "1"  # Don't download from Hugging Face
  - name: TRANSFORMERS_OFFLINE
    value: "1"  # Force offline mode
  - name: HF_HOME
    value: "/app/.cache/huggingface"
```

### PVC Mount Configuration

```yaml
volumeMounts:
  - name: model-cache
    mountPath: /app/.cache/huggingface
    readOnly: true  # Models are pre-loaded

volumes:
  - name: model-cache
    persistentVolumeClaim:
      claimName: huggingface-models-pvc
```

---

## 📊 Resource Requirements

### Minimum Resources

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage |
|-----------|-------------|-----------|----------------|--------------|---------|
| NGINX | 100m | 500m | 128Mi | 256Mi | - |
| Web Server | 500m | 1000m | 512Mi | 1Gi | - |
| API Server | 1000m | 2000m | 2Gi | 4Gi | - |
| Inference Model Server | 500m | 2000m | 2Gi | 4Gi | - |
| Indexing Model Server | 1000m | 4000m | 2Gi | 8Gi | - |
| PostgreSQL | 500m | 1000m | 1Gi | 2Gi | 10Gi |
| Vespa | 1000m | 2000m | 4Gi | 8Gi | 30Gi |
| Redis | 100m | 500m | 256Mi | 512Mi | - |
| **Total** | **~5 cores** | **~13 cores** | **~12Gi** | **~28Gi** | **~50Gi** |

### Model Cache (Shared PVC)

- **Size:** 10Gi (stores Hugging Face models ~5-6GB)
- **Access Mode:** ReadWriteMany (recommended) or ReadWriteOnce
- **Storage Class:** Your cluster's storage class (e.g., `nfs-example`)

---

## 🔍 Verification & Testing

### Check All Pods are Running

```bash
oc get pods
# All should show: STATUS = Running, READY = 1/1
```

### Verify Models Loaded from PV (No Internet Downloads)

```bash
# Check inference server logs
oc logs deployment/inference-model-server | grep -i "loaded model"
# Should see: "Loaded model from local cache"

# Check indexing server logs
oc logs deployment/indexing-model-server | grep -i "loaded model"
# Should see: "Loaded model from local cache"

# Should NOT see any "Downloading" messages!
```

### Test Health Endpoints

```bash
# Test model servers
oc exec deployment/inference-model-server -- curl -s http://localhost:9000/health
oc exec deployment/indexing-model-server -- curl -s http://localhost:9000/health
# Both should return: {"status":"healthy"}

# Test API server
oc exec deployment/api-server -- curl -s http://localhost:8080/health
```

### Access the UI

```bash
# Get NGINX service endpoint
oc get svc nginx
# Access via LoadBalancer IP or create OpenShift Route

# Create route (OpenShift)
oc expose svc/nginx
oc get route nginx
# Access the URL shown
```

---

## 🐛 Troubleshooting

### PVC Not Binding

```bash
oc describe pvc huggingface-models-pvc
# Check for errors, verify StorageClass name matches
```

See: `docs/troubleshooting/TROUBLESHOOTING-PVC.md`

### Models Not Found in PV

```bash
# Create debug pod to check PV contents
oc run debug-pv --image=registry.access.redhat.com/ubi8/ubi:latest --command -- sleep infinity
oc set volume pod/debug-pv --add --name=models --type=pvc --claim-name=huggingface-models-pvc --mount-path=/models
oc exec debug-pv -- ls -lh /models/
# Should show model directories
```

See: `USING-EXISTING-PV-FOR-MODELS.md`

### Pods Try to Download from Internet

Check if offline mode is enabled:

```bash
oc exec deployment/inference-model-server -- env | grep HF_
# Must show: HF_HUB_OFFLINE=1, TRANSFORMERS_OFFLINE=1
```

### OpenShift Security Context Issues

```bash
# Grant anyuid SCC if needed
oc adm policy add-scc-to-user anyuid -z default
```

See: `docs/troubleshooting/TROUBLESHOOTING-SCC.md`

---

## 📖 Documentation Guide

### Getting Started (Read First)

1. **`START-HERE.md`** - Orientation and next steps
2. **`USING-EXISTING-PV-FOR-MODELS.md`** - Critical for air-gapped setup
3. **`00-BEFORE-DEPLOYING.md`** - Prerequisites checklist
4. **`QUICK-START.md`** - Fast deployment

### Understanding the System

- **`ARCHITECTURE-FOR-JUNIOR-ENGINEERS.md`** - Complete architecture
- **`HUGGING-FACE-MODELS-FLOW.md`** - Model download and caching
- **`MODEL-SERVERS-EXPLANATION.md`** - Why two servers

### Advanced Topics

- **`AIRGAPPED-MODEL-SERVERS-GUIDE.md`** - Complete air-gapped guide
- **`docs/reference/DNS-NAMING-EXPLAINED.md`** - Kubernetes DNS
- **`docs/reference/VESPA-STATEFULSET-EXPLANATION.md`** - Why Vespa uses StatefulSet

---

## 🔗 Related Resources

- **Main Onyx Repo:** https://github.com/onyx-dot-app/onyx
- **Docker Compose Deployment:** `../onyx-repo/deployment/docker_compose/`
- **Helm Charts:** `../onyx-repo/deployment/helm/`

---

## 📝 Key Design Decisions

1. **Two Model Servers:** Separate inference (real-time) and indexing (bulk) for performance
2. **Offline Mode:** `HF_HUB_OFFLINE=1` prevents internet access for air-gapped environments
3. **Shared PVC:** Both model servers use same PVC (if ReadWriteMany supported)
4. **StatefulSet for Vespa:** Ensures stable network identity and persistent storage
5. **No Background Workers:** Minimal deployment for UI and chat only
6. **Pinned Image Versions:** No `:latest` tags for production stability

---

## ✅ What Works

- ✅ Web UI accessible
- ✅ User authentication (basic)
- ✅ Chat functionality (with external LLM)
- ✅ Document search (if documents indexed)
- ✅ Real-time query embeddings
- ✅ Offline operation (no internet needed)

## ❌ What Doesn't Work (Minimal Setup)

- ❌ Document indexing (needs background workers)
- ❌ Connector sync (needs background workers)
- ❌ File uploads (needs MinIO or S3)
- ❌ Scheduled tasks (needs Celery beat)

---

## 🚀 Upgrade Path

To add missing features:

1. **Add Background Workers:** Deploy Celery workers for document processing
2. **Add MinIO:** Deploy object storage for file uploads
3. **Scale Services:** Increase replicas for high availability
4. **Add Monitoring:** Deploy Prometheus/Grafana for observability

---

## 🆘 Support

**Issues or questions?**

- Check `docs/troubleshooting/` for common issues
- Review `USING-EXISTING-PV-FOR-MODELS.md` for PV setup
- See `START-HERE.md` for quick orientation

---

**This is a production-ready minimal deployment for air-gapped OpenShift environments!** 🎉
