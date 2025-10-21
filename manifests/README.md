# Kubernetes Manifests

All Kubernetes/OpenShift YAML deployment files for Onyx.

---

## 📁 Files Overview

### Infrastructure Services (Deploy First)

| File | Component | Port | Description |
|------|-----------|------|-------------|
| `02-postgresql.yaml` | PostgreSQL | 5432 | Relational database for metadata |
| `03-vespa.yaml` | Vespa | 19071, 8081 | Vector search engine |
| `04-redis.yaml` | Redis | 6379 | Cache and task queue |
| `05-configmap.yaml` | ConfigMaps | - | Configuration files |

### Model Servers (Deploy Second)

| File | Component | Port | Description |
|------|-----------|------|-------------|
| `06-inference-model-server.yaml` | Inference Server | 9000 | Real-time query embeddings |
| `06-indexing-model-server.yaml` | Indexing Server | 9000 | Bulk document embeddings |

### Application Services (Deploy Third)

| File | Component | Port | Description |
|------|-----------|------|-------------|
| `07-api-server.yaml` | API Server Deployment | 8080 | Backend FastAPI application |
| `07-api-server-service.yaml` | API Server Service | 8080 | Service for API server |
| `08-web-server.yaml` | Web Server Deployment | 3000 | Frontend Next.js application |
| `08-web-server-service.yaml` | Web Server Service | 3000 | Service for web server |

### Background Workers (Deploy Fourth - CRITICAL!)

| File | Component | Queues | Description |
|------|-----------|--------|-------------|
| `10-celery-beat.yaml` | Celery Beat | N/A | Task scheduler (periodic tasks) |
| `11-celery-worker-primary.yaml` | Primary Worker | celery, periodic_tasks | Core background tasks |
| `12-celery-worker-light.yaml` | Light Worker | Multiple | Lightweight operations |
| `13-celery-worker-heavy.yaml` | Heavy Worker | Multiple | Resource-intensive operations |
| `14-celery-worker-docfetching.yaml` | Docfetching Worker | docfetching | Fetch documents from connectors |
| `15-celery-worker-docprocessing.yaml` | Docprocessing Worker | docprocessing | **Process & embed documents (CRITICAL!)** |

### Gateway (Deploy Last)

| File | Component | Port | Description |
|------|-----------|------|-------------|
| `09-nginx.yaml` | NGINX with initContainer | 80 | Reverse proxy with DNS wait |
| `09-nginx-simple.yaml` | NGINX Simple | 80 | Simplified without initContainer |
| `09-nginx-hardcoded-namespace.yaml` | NGINX Hardcoded | 80 | For namespace resolution issues |

---

## 🚀 Deployment Order

```bash
# 1. Infrastructure
oc apply -f 02-postgresql.yaml
oc apply -f 03-vespa.yaml
oc apply -f 04-redis.yaml
oc apply -f 05-configmap.yaml

# 2. Model Servers
oc apply -f 06-inference-model-server.yaml
oc apply -f 06-indexing-model-server.yaml

# 3. Application
oc apply -f 07-api-server.yaml
oc apply -f 08-web-server.yaml

# 4. Background Workers (CRITICAL!)
oc apply -f 10-celery-beat.yaml
oc apply -f 11-celery-worker-primary.yaml
oc apply -f 12-celery-worker-light.yaml
oc apply -f 13-celery-worker-heavy.yaml
oc apply -f 14-celery-worker-docfetching.yaml
oc apply -f 15-celery-worker-docprocessing.yaml  # CRITICAL for document indexing

# Wait for workers to be ready
oc get pods -l scope=onyx-backend-celery -w

# 5. Gateway (Deploy Last)
oc apply -f 09-nginx.yaml

# 4. Gateway
oc apply -f 09-nginx-simple.yaml

# 5. Expose externally
oc expose service nginx --hostname=onyx.company.com
```

---

## 🔍 Which NGINX to Use?

### Use `09-nginx-simple.yaml` (Recommended)
- ✅ No initContainer complexity
- ✅ Simpler debugging
- ✅ Faster startup
- ✅ Works in most environments

### Use `09-nginx.yaml` (Advanced)
- ✅ Waits for services to be ready
- ✅ Includes debugging output
- ⚠️ May have DNS resolution issues in OpenShift

### Use `09-nginx-hardcoded-namespace.yaml` (Troubleshooting)
- ✅ For namespace-specific DNS issues
- ⚠️ Requires replacing `YOUR_NAMESPACE` with actual namespace
- ⚠️ Only use if other versions fail

---

## ✅ Verification

```bash
# Check all pods are running
oc get pods

# Check all services exist
oc get services

# Check service endpoints
oc get endpoints

# Test connectivity
oc exec deployment/nginx -- curl http://web-server:3000
oc exec deployment/nginx -- curl http://api-server:8080
```

---

## 📝 Notes

- All services use `ClusterIP` type (internal only)
- External access is via OpenShift Route
- Resource requests/limits are configured for OpenShift resource quotas
- Services must exist before NGINX can route to them
