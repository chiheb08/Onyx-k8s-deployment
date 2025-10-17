# Onyx Minimal Kubernetes Deployment Guide

**Complete 7-service minimal deployment** based on the architecture diagram.

---

## 🎯 What's Included

Based on `/onyx-deployment-troubleshooting/ARCHITECTURE-DIAGRAM.md`

### **7 Mandatory Services:**

| Layer | Service | Image | Port | Purpose |
|-------|---------|-------|------|---------|
| **Gateway** | NGINX | nginx:1.23.4-alpine | 80 | Reverse proxy, entry point |
| **Frontend** | Web Server | onyxdotapp/onyx-web-server | 3000 | Next.js UI |
| **Backend** | API Server | onyxdotapp/onyx-backend | 8080 | FastAPI backend |
| **AI/ML** | Inference Model Server | onyxdotapp/onyx-model-server | 9000 | Query embeddings |
| **Data** | PostgreSQL | postgres:15.2-alpine | 5432 | Database |
| **Data** | Vespa | vespaengine/vespa:8.526.15 | 19071 | Vector search |
| **Data** | Redis | redis:7.4-alpine | 6379 | Cache & queue |

---

## 🔗 Service Dependencies (From Architecture Diagram)

```
Startup Order (Critical for Success):

1. Infrastructure Layer (No Dependencies)
   ├─ PostgreSQL      (Database)
   ├─ Vespa           (Search)
   └─ Redis           (Cache)
        ↓
2. AI/ML Layer (Depends on Infrastructure)
   └─ Inference Model Server
        ↓
3. Application Layer (Depends on All Above)
   └─ API Server  → needs: PostgreSQL, Vespa, Redis, Model Server
        ↓
4. Frontend Layer (Depends on API)
   └─ Web Server  → needs: API Server
        ↓
5. Gateway Layer (Depends on Frontend + Backend)
   └─ NGINX  → needs: Web Server, API Server
```

### **Communication Matrix:**

| From | To | Protocol | Purpose |
|------|--------|----------|---------|
| NGINX | Web Server | HTTP:3000 | Serve UI |
| NGINX | API Server | HTTP:8080 | Proxy API calls |
| Web Server | API Server | HTTP:8080 | Fetch data |
| API Server | PostgreSQL | TCP:5432 | Query data |
| API Server | Vespa | HTTP:19071 | Vector search |
| API Server | Redis | TCP:6379 | Cache operations |
| API Server | Model Server | HTTP:9000 | Generate embeddings |

---

## 🚀 Quick Deploy

### Prerequisites

```bash
# Check kubectl (or oc for OpenShift)
kubectl version

# Check cluster connection
kubectl cluster-info

# Create namespace (IMPORTANT!)
kubectl create namespace onyx-infra
# OR in OpenShift:
oc new-project onyx-infra

# Verify namespace
kubectl get namespace onyx-infra

# Verify you have sufficient resources
kubectl top nodes  # Need ~6-10GB RAM available
```

**⚠️ Important for OpenShift or Custom Namespace:**
- If using a different namespace, read `00-BEFORE-DEPLOYING.md` first
- You'll need to update all YAML files with your namespace name

### Deploy All Services

```bash
cd /Users/chihebmhamdi/Desktop/onyx/onyx-k8s-infrastructure

# Option 1: Automated (Recommended)
./deploy.sh

# Option 2: Manual (step by step)
kubectl apply -f 01-namespace.yaml
kubectl apply -f 02-postgresql.yaml
kubectl apply -f 03-vespa.yaml
kubectl apply -f 04-redis.yaml
kubectl apply -f 05-configmap.yaml
kubectl apply -f 06-inference-model-server.yaml
kubectl apply -f 07-api-server.yaml
kubectl apply -f 08-web-server.yaml
kubectl apply -f 09-nginx.yaml
```

### Wait for Ready

```bash
# Watch all pods
kubectl get pods -n onyx-infra -w

# Expected (after 5-10 minutes):
# NAME                                      READY   STATUS    RESTARTS   AGE
# postgresql-xxx                            1/1     Running   0          5m
# vespa-0                                   1/1     Running   0          5m
# redis-xxx                                 1/1     Running   0          5m
# inference-model-server-xxx                1/1     Running   0          3m
# api-server-xxx                            1/1     Running   0          2m
# web-server-xxx                            1/1     Running   0          1m
# nginx-xxx                                 1/1     Running   0          1m
```

---

## 🌐 Access Onyx UI

### Method 1: LoadBalancer (if available)

```bash
# Get external IP
kubectl get svc nginx -n onyx-infra

# Output:
# NAME    TYPE           EXTERNAL-IP      PORT(S)        AGE
# nginx   LoadBalancer   35.123.45.67     80:30080/TCP   5m

# Open browser to:
http://<EXTERNAL-IP>
```

### Method 2: Port Forward (always works)

```bash
# Forward port 3000 to nginx
kubectl port-forward -n onyx-infra svc/nginx 3000:80

# Open browser to:
http://localhost:3000
```

### Method 3: NodePort (alternative)

Edit `09-nginx.yaml`, change service type:
```yaml
spec:
  type: NodePort
  ports:
    - name: http
      port: 80
      targetPort: 80
      nodePort: 30080  # Uncomment this
```

Then access via: `http://<node-ip>:30080`

---

## 📊 Resource Requirements

| Service | CPU | RAM | Disk |
|---------|-----|-----|------|
| NGINX | 100m-500m | 128Mi-256Mi | - |
| Web Server | 200m-1000m | 512Mi-1Gi | - |
| API Server | 500m-2000m | 1Gi-2Gi | - |
| Model Server | 500m-2000m | 2Gi-4Gi | 2GB cache |
| PostgreSQL | 100m-1000m | 256Mi-1Gi | 10Gi PVC |
| Vespa | 1000m-4000m | 2Gi-8Gi | 30Gi PVC |
| Redis | 100m-500m | 128Mi-512Mi | - |
| **TOTAL** | **~2.5-9.5 CPU** | **~6-17Gi RAM** | **~40Gi storage** |

**Minimum Cluster:** 3 nodes with 4GB RAM each, or 2 nodes with 8GB RAM each

---

## 🧪 Verification

### Check All Services

```bash
# All pods
kubectl get pods -n onyx-infra

# All services
kubectl get svc -n onyx-infra

# Storage
kubectl get pvc -n onyx-infra

# ConfigMap
kubectl get configmap -n onyx-infra
```

### Test Each Service

```bash
# Test PostgreSQL
kubectl exec -it -n onyx-infra deployment/postgresql -- psql -U postgres -c "SELECT version();"

# Test Vespa
kubectl exec -it -n onyx-infra vespa-0 -- curl -s http://localhost:19071/state/v1/health

# Test Redis
kubectl exec -it -n onyx-infra deployment/redis -- redis-cli -a password ping

# Test Model Server
kubectl exec -it -n onyx-infra deployment/inference-model-server -- curl -s http://localhost:9000/health

# Test API Server
kubectl exec -it -n onyx-infra deployment/api-server -- curl -s http://localhost:8080/health

# Test Web Server
kubectl exec -it -n onyx-infra deployment/web-server -- curl -s -I http://localhost:3000

# Test NGINX
kubectl exec -it -n onyx-infra deployment/nginx -- curl -s http://localhost:80/nginx-health
```

---

## 📝 Configuration

### Environment Variables

All environment variables are in `05-configmap.yaml`:

```yaml
POSTGRES_HOST: postgresql.onyx-infra.svc.cluster.local
VESPA_HOST: vespa-0.vespa-service.onyx-infra.svc.cluster.local
REDIS_HOST: redis.onyx-infra.svc.cluster.local
MODEL_SERVER_HOST: inference-model-server.onyx-infra.svc.cluster.local
INTERNAL_URL: http://api-server.onyx-infra.svc.cluster.local:8080
```

### Secrets

Change default passwords before production:

```bash
# PostgreSQL
kubectl create secret generic postgresql-secret -n onyx-infra \
  --from-literal=POSTGRES_USER=postgres \
  --from-literal=POSTGRES_PASSWORD=your-secure-password \
  --from-literal=POSTGRES_DB=postgres \
  --dry-run=client -o yaml | kubectl apply -f -

# Redis
kubectl create secret generic redis-secret -n onyx-infra \
  --from-literal=REDIS_PASSWORD=your-secure-password \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart affected pods
kubectl rollout restart deployment/postgresql -n onyx-infra
kubectl rollout restart deployment/redis -n onyx-infra
kubectl rollout restart deployment/api-server -n onyx-infra
```

---

## 🔍 Monitoring & Logs

### View Logs

```bash
# All services
kubectl logs -n onyx-infra -l app=<service-name> -f

# Specific services
kubectl logs -n onyx-infra deployment/api-server -f
kubectl logs -n onyx-infra deployment/web-server -f
kubectl logs -n onyx-infra deployment/nginx -f
kubectl logs -n onyx-infra vespa-0 -f

# Previous logs (if pod restarted)
kubectl logs -n onyx-infra deployment/api-server -f --previous
```

### Resource Usage

```bash
# Pod resources
kubectl top pods -n onyx-infra

# Node resources
kubectl top nodes
```

### Events

```bash
# Recent events
kubectl get events -n onyx-infra --sort-by='.lastTimestamp'

# Watch events
kubectl get events -n onyx-infra -w
```

---

## 🐛 Troubleshooting

### Common Issues

#### 1. Pods Stuck in Pending

**Cause:** Insufficient resources or PVC not bound

```bash
# Check pod details
kubectl describe pod <pod-name> -n onyx-infra

# Check PVC
kubectl get pvc -n onyx-infra
kubectl describe pvc <pvc-name> -n onyx-infra

# Solution: Check if storage class exists
kubectl get storageclass

# If no storage class, you may need to provision one
```

#### 2. API Server CrashLoopBackOff

**Cause:** Usually database connection issues

```bash
# Check logs
kubectl logs -n onyx-infra deployment/api-server

# Check if PostgreSQL is ready
kubectl get pods -n onyx-infra -l app=postgresql

# Check if migrations ran
kubectl logs -n onyx-infra deployment/api-server -c migration
```

#### 3. NGINX 502 Bad Gateway

**Cause:** Backend services not ready

```bash
# Check API and Web Server
kubectl get pods -n onyx-infra -l app=api-server
kubectl get pods -n onyx-infra -l app=web-server

# Check logs
kubectl logs -n onyx-infra deployment/nginx
```

#### 4. Model Server Taking Long Time

**Cause:** Downloading ML models (2-3GB)

```bash
# Check logs to see download progress
kubectl logs -n onyx-infra deployment/inference-model-server -f

# This is normal on first start, wait 5-10 minutes
```

#### 5. Cannot Access UI

**Symptoms:** LoadBalancer stuck in Pending

```bash
# Check service
kubectl get svc nginx -n onyx-infra

# If EXTERNAL-IP shows <pending>, your cluster doesn't support LoadBalancer
# Solution: Use port-forward instead
kubectl port-forward -n onyx-infra svc/nginx 3000:80
```

---

## 🔄 Management

### Restart Services

```bash
# Restart specific service
kubectl rollout restart deployment/<name> -n onyx-infra

# Restart API Server
kubectl rollout restart deployment/api-server -n onyx-infra

# Restart all deployments
kubectl rollout restart deployment -n onyx-infra
```

### Scale Services

```bash
# Scale Web Server (safe to scale)
kubectl scale deployment/web-server -n onyx-infra --replicas=2

# Scale API Server (safe to scale)
kubectl scale deployment/api-server -n onyx-infra --replicas=2

# DON'T scale PostgreSQL, Vespa, or Redis (single instance only)
```

### Update Images

```bash
# Update to specific version
kubectl set image deployment/api-server api-server=onyxdotapp/onyx-backend:v1.2.3 -n onyx-infra

# Update to latest
kubectl set image deployment/api-server api-server=onyxdotapp/onyx-backend:latest -n onyx-infra
kubectl rollout restart deployment/api-server -n onyx-infra
```

---

## 🧹 Cleanup

### Delete Everything

```bash
# Delete all resources
kubectl delete namespace onyx-infra

# This deletes:
# - All deployments
# - All services
# - All pods
# - ConfigMaps and Secrets
# - PVCs (depending on reclaim policy)

# Check PVs (may need manual cleanup)
kubectl get pv
```

### Delete Specific Service

```bash
# Delete just one service
kubectl delete -f 09-nginx.yaml
kubectl delete -f 08-web-server.yaml
# etc.
```

---

## 📚 Files Overview

| File | Purpose | Components |
|------|---------|------------|
| `01-namespace.yaml` | Namespace | onyx-infra |
| `02-postgresql.yaml` | Database | Deployment, Service, PVC, Secret |
| `03-vespa.yaml` | Vector Search | StatefulSet, Service, PVC |
| `04-redis.yaml` | Cache/Queue | Deployment, Service, Secret |
| `05-configmap.yaml` | Configuration | Environment variables |
| `06-inference-model-server.yaml` | AI Embeddings | Deployment, Service |
| `07-api-server.yaml` | Backend API | Deployment, Service, Init Container |
| `08-web-server.yaml` | Frontend UI | Deployment, Service |
| `09-nginx.yaml` | Reverse Proxy | Deployment, Service, ConfigMap |
| `deploy.sh` | Automation | Deployment script |

---

## ⚠️ Production Checklist

Before using in production:

- [ ] **Change all default passwords** (PostgreSQL, Redis)
- [ ] **Set resource limits** based on your workload
- [ ] **Configure persistent storage** with proper storage class
- [ ] **Enable TLS/SSL** in NGINX
- [ ] **Set up monitoring** (Prometheus, Grafana)
- [ ] **Configure backups** (PostgreSQL, Vespa volumes)
- [ ] **Enable authentication** (OAuth, SAML) in Onyx
- [ ] **Set up ingress** with proper domain
- [ ] **Configure network policies** for security
- [ ] **Set up logging** (EFK, Loki)
- [ ] **Plan for high availability** (multiple replicas, anti-affinity)
- [ ] **Test disaster recovery** procedures

---

## 🎯 Next Steps

After successful deployment:

1. **Access UI:** Open Onyx in browser
2. **Create Admin Account:** Sign up via UI
3. **Configure LLM Provider:** Add vLLM or cloud LLM
4. **Test Chat:** Ask a question
5. **(Optional) Add Document Upload:** Deploy Background Workers, Indexing Model Server, MinIO

---

**This minimal deployment includes everything needed to run Onyx UI and chat functionality!** 🚀

