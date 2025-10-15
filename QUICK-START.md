# Onyx Kubernetes Minimal Deployment - Quick Start

**One-page guide to deploy Onyx on Kubernetes in 5 minutes.**

---

## ⚡ TL;DR (Copy-Paste Commands)

```bash
cd /Users/chihebmhamdi/Desktop/onyx/onyx-k8s-infrastructure

# FIRST: Create namespace (or use existing OpenShift project)
kubectl create namespace onyx-infra
# OR in OpenShift: oc new-project onyx-infra

# Deploy everything
./deploy.sh

# Wait 10-15 minutes, then access UI:
kubectl port-forward -n onyx-infra svc/nginx 3000:80

# Open: http://localhost:3000
```

**Done!** 🎉

**Note:** If using a different namespace, read `00-BEFORE-DEPLOYING.md` first!

---

## 📦 What Gets Deployed

**7 Services (complete minimal stack):**

1. **NGINX** - Entry point (Port 80)
2. **Web Server** - UI (Port 3000)
3. **API Server** - Backend (Port 8080)
4. **Inference Model Server** - AI embeddings (Port 9000)
5. **PostgreSQL** - Database (Port 5432, 10Gi storage)
6. **Vespa** - Vector search (Port 19071, 30Gi storage)
7. **Redis** - Cache (Port 6379)

---

## 🎯 Architecture Flow

```
User
  ↓
NGINX (LoadBalancer)
  ├─→ Web Server → UI
  └─→ API Server → Backend
        ├─→ PostgreSQL (data)
        ├─→ Vespa (search)
        ├─→ Redis (cache)
        └─→ Model Server (AI)
```

---

## ✅ Prerequisites

- Kubernetes cluster running (Minikube, kind, GKE, EKS, OpenShift, etc.)
- `kubectl` (or `oc` for OpenShift) installed and configured
- **Namespace created:** `kubectl create namespace onyx-infra` (or use existing)
- 8GB+ RAM available in cluster
- 50Gi storage available

**⚠️ Important:** If using a different namespace, read `00-BEFORE-DEPLOYING.md` first!

---

## 🚀 Deployment Steps

### 1. Deploy

```bash
cd /Users/chihebmhamdi/Desktop/onyx/onyx-k8s-infrastructure
./deploy.sh
```

### 2. Wait for Ready (~10-15 minutes)

```bash
# Watch pods
kubectl get pods -n onyx-infra -w

# Wait for all to show "1/1 Running"
```

### 3. Access UI

```bash
# Get LoadBalancer IP
kubectl get svc nginx -n onyx-infra

# If LoadBalancer works:
# Open: http://<EXTERNAL-IP>

# If LoadBalancer is pending (Minikube, kind):
kubectl port-forward -n onyx-infra svc/nginx 3000:80
# Open: http://localhost:3000
```

### 4. Create Account

- Click "Sign Up"
- Email: `admin@example.com`
- Password: `admin123`

### 5. Configure LLM

- Go to Settings → LLM Configuration
- Add your vLLM or cloud LLM provider

**Done!** Chat is now working! 🎉

---

## 🔧 Useful Commands

```bash
# Check status
kubectl get pods -n onyx-infra
kubectl get svc -n onyx-infra

# View logs
kubectl logs -n onyx-infra deployment/api-server -f
kubectl logs -n onyx-infra deployment/web-server -f

# Restart service
kubectl rollout restart deployment/api-server -n onyx-infra

# Delete everything
kubectl delete namespace onyx-infra
```

---

## 🐛 Troubleshooting

### Issue: Pods stuck in Pending

**Check:**
```bash
kubectl describe pod <pod-name> -n onyx-infra
```

**Common causes:**
- Not enough resources
- PVC not binding (check storage class)

### Issue: Can't access UI

**Solution:**
```bash
# Use port-forward
kubectl port-forward -n onyx-infra svc/nginx 3000:80
# Open: http://localhost:3000
```

### Issue: API Server CrashLoopBackOff

**Check:**
```bash
kubectl logs -n onyx-infra deployment/api-server
kubectl logs -n onyx-infra deployment/postgresql
```

**Usually:** Database connection issue or migrations failed

---

## 📊 Files Overview

| File | Purpose |
|------|---------|
| `01-namespace.yaml` | Creates onyx-infra namespace |
| `02-postgresql.yaml` | Database (10Gi PVC) |
| `03-vespa.yaml` | Vector search (30Gi PVC) |
| `04-redis.yaml` | Cache/queue |
| `05-configmap.yaml` | Environment config |
| `06-inference-model-server.yaml` | AI embeddings |
| `07-api-server.yaml` | Backend API |
| `08-web-server.yaml` | Frontend UI |
| `09-nginx.yaml` | Reverse proxy |
| `deploy.sh` | One-command deployment |

---

## 💡 Next Steps

After deployment:

1. ✅ Access UI at http://localhost:3000
2. ✅ Create admin account
3. ✅ Configure LLM provider (vLLM or cloud)
4. ✅ Test chat functionality
5. ✅ (Optional) Add document upload later

---

## 📚 More Documentation

- `MINIMAL-DEPLOYMENT-GUIDE.md` - Detailed deployment guide
- `ARCHITECTURE.md` - Architecture diagrams
- `README.md` - Complete infrastructure docs

---

**Everything you need to get Onyx running on Kubernetes!** 🚀

