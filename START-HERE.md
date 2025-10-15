# 🚀 START HERE - Onyx Kubernetes Minimal Deployment

**Welcome!** This folder contains everything you need to deploy Onyx on Kubernetes.

---

## 📚 Which File to Read?

**Choose based on what you need:**

| If you want to... | Read this file |
|-------------------|----------------|
| 🚀 **Deploy now (fastest)** | `QUICK-START.md` |
| 🐛 **Fix deployment issues** | `QUICK-FIX-PVC.md` (PVC + SCC issues) |
| 🔒 **Fix OpenShift security issues** | `TROUBLESHOOTING-SCC.md` |
| 📖 **Understand everything first** | `MINIMAL-DEPLOYMENT-GUIDE.md` |
| 🏗️ **See architecture diagrams** | `ARCHITECTURE.md` |
| 🔧 **Configure specific services** | `README.md` |
| 🌐 **Understand DNS naming** | `DNS-NAMING-EXPLAINED.md` |

---

## ⚡ Absolute Fastest Start

```bash
cd /Users/chihebmhamdi/Desktop/onyx/onyx-k8s-infrastructure

# FIRST: Create namespace
kubectl create namespace onyx-infra
# OR in OpenShift: oc new-project onyx-infra

# Deploy
./deploy.sh

# Wait 10-15 minutes

kubectl port-forward -n onyx-infra svc/nginx 3000:80
# Open: http://localhost:3000
```

**Done!** Sign up and start using Onyx.

**⚠️ Using a different namespace?** Read `00-BEFORE-DEPLOYING.md` first!

---

## 📦 What This Deploys

**Complete Onyx Minimal Stack (7 services):**

✅ NGINX - Entry point  
✅ Web Server - UI  
✅ API Server - Backend  
✅ Inference Model Server - AI embeddings  
✅ PostgreSQL - Database  
✅ Vespa - Vector search  
✅ Redis - Cache  

**What it does:**
- ✅ Full Onyx UI
- ✅ Chat functionality (configure your LLM)
- ✅ User authentication
- ✅ Search capability

**What it doesn't do:**
- ❌ Document upload (need Background Workers + MinIO)

---

## 📊 Resources Needed

- **RAM:** 6-17Gi (depending on load)
- **Storage:** 40Gi
- **Time:** 10-15 minutes

---

## 🎯 Quick Reference

```bash
# Deploy
./deploy.sh

# Check status
kubectl get pods -n onyx-infra

# Access UI
kubectl port-forward -n onyx-infra svc/nginx 3000:80

# View logs
kubectl logs -n onyx-infra deployment/api-server -f

# Delete all
kubectl delete namespace onyx-infra
```

---

## 🔗 Based On

This deployment was created by analyzing:

1. `/onyx-deployment-troubleshooting/ARCHITECTURE-DIAGRAM.md` - Service connections
2. `/onyx-repo/deployment/helm/charts/onyx/values.yaml` - Helm chart configuration
3. `/onyx-repo/deployment/docker_compose/docker-compose.yml` - Docker Compose setup

All service connections, dependencies, and configurations match the architecture diagram!

---

## 💡 Tips

- **First time?** Read `QUICK-START.md` (5 minutes)
- **Need details?** Read `MINIMAL-DEPLOYMENT-GUIDE.md` (15 minutes)
- **Troubleshooting?** Check `README.md` troubleshooting section
- **Understand architecture?** Read `ARCHITECTURE.md`

---

**Ready to deploy Onyx on Kubernetes? Run `./deploy.sh`!** 🎉

