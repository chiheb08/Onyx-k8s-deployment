# Onyx Kubernetes Infrastructure

Complete Kubernetes/OpenShift deployment manifests and documentation for Onyx AI platform.

---

## 📁 Repository Structure

```
onyx-k8s-infrastructure/
├── manifests/              # Kubernetes YAML manifests
│   ├── 02-postgresql.yaml
│   ├── 03-vespa.yaml
│   ├── 04-redis.yaml
│   ├── 05-configmap.yaml
│   ├── 06-inference-model-server.yaml
│   ├── 06-indexing-model-server.yaml
│   ├── 07-api-server.yaml
│   ├── 07-api-server-service.yaml
│   ├── 08-web-server.yaml
│   ├── 08-web-server-service.yaml
│   ├── 09-nginx.yaml
│   ├── 09-nginx-simple.yaml
│   └── 09-nginx-hardcoded-namespace.yaml
│
├── documentation/          # Architecture & technical docs
│   ├── ARCHITECTURE-FOR-JUNIOR-ENGINEERS.md
│   ├── KUBERNETES-NETWORKING-COMPLETE-GUIDE.md
│   ├── MODEL-SERVERS-EXPLANATION.md
│   ├── MODEL-SERVERS-YAML-EXPLAINED.md
│   ├── HUGGING-FACE-MODELS-FLOW.md
│   ├── END-TO-END-USER-FLOW.md
│   └── AIRGAPPED-MODEL-SERVERS-GUIDE.md
│
├── guides/                 # Getting started guides
│   ├── 00-BEFORE-DEPLOYING.md
│   ├── START-HERE.md
│   ├── QUICK-START.md
│   └── MINIMAL-DEPLOYMENT-GUIDE.md
│
├── troubleshooting/        # Issue resolution guides
│   ├── STEP-BY-STEP-FIX.md
│   ├── NGINX-DNS-TROUBLESHOOTING-GUIDE.md
│   ├── FULL-DNS-RESOLUTION-FIX.md
│   ├── OPENSHIFT-RESOURCE-QUOTA-FIX.md
│   ├── OPENSHIFT-DNS-RESOLUTION-FIX.md
│   ├── MISSING-SERVICES-SOLUTION.md
│   ├── NGINX-UPSTREAM-ERROR-ANALYSIS.md
│   ├── NGINX-CONFIGMAP-ISSUE-ANALYSIS.md
│   └── WEBSERVER-DEPLOYMENT-ANALYSIS.md
│
├── scripts/                # Utility scripts
│   ├── deploy.sh
│   ├── diagnose.sh
│   └── quick-fix.sh
│
├── storage-setup/          # Persistent storage configs
│   ├── 01-pv-huggingface-models.yaml
│   ├── 02-pvc-huggingface-models.yaml
│   ├── PV-PVC-SETUP-GUIDE.md
│   ├── SIMPLE-PV-EXPLANATION.md
│   └── USING-EXISTING-PV-FOR-MODELS.md
│
└── docs/                   # Additional reference docs
    ├── reference/
    └── troubleshooting/
```

---

## 🚀 Quick Start

### 1. Before You Begin

Read these guides in order:

1. **[START-HERE.md](guides/START-HERE.md)** - Overview and prerequisites
2. **[00-BEFORE-DEPLOYING.md](guides/00-BEFORE-DEPLOYING.md)** - Pre-deployment checklist
3. **[QUICK-START.md](guides/QUICK-START.md)** - Fast deployment guide

### 2. Deploy Onyx

```bash
# Deploy infrastructure services
oc apply -f manifests/02-postgresql.yaml
oc apply -f manifests/03-vespa.yaml
oc apply -f manifests/04-redis.yaml

# Deploy model servers
oc apply -f manifests/06-inference-model-server.yaml
oc apply -f manifests/06-indexing-model-server.yaml

# Deploy application services
oc apply -f manifests/07-api-server-service.yaml
oc apply -f manifests/07-api-server.yaml
oc apply -f manifests/08-web-server-service.yaml
oc apply -f manifests/08-web-server.yaml

# Deploy NGINX
oc apply -f manifests/09-nginx-simple.yaml

# Create route for external access
oc expose service nginx --hostname=onyx.company.com
```

### 3. Verify Deployment

```bash
# Check all pods are running
oc get pods

# Check all services
oc get services

# Check route
oc get route

# Access Onyx
curl https://onyx.company.com
```

---

## 📚 Documentation

### Architecture Guides

| Document | Description |
|----------|-------------|
| [ARCHITECTURE-FOR-JUNIOR-ENGINEERS.md](documentation/ARCHITECTURE-FOR-JUNIOR-ENGINEERS.md) | Complete architecture explanation with diagrams |
| [KUBERNETES-NETWORKING-COMPLETE-GUIDE.md](documentation/KUBERNETES-NETWORKING-COMPLETE-GUIDE.md) | Networking, Routes, Network Policies guide |
| [MODEL-SERVERS-EXPLANATION.md](documentation/MODEL-SERVERS-EXPLANATION.md) | Understanding Inference & Indexing model servers |
| [END-TO-END-USER-FLOW.md](documentation/END-TO-END-USER-FLOW.md) | User request flow from UI to response |

### Getting Started Guides

| Document | Description |
|----------|-------------|
| [START-HERE.md](guides/START-HERE.md) | Start here for overview |
| [00-BEFORE-DEPLOYING.md](guides/00-BEFORE-DEPLOYING.md) | Pre-deployment checklist |
| [QUICK-START.md](guides/QUICK-START.md) | Fast deployment guide |
| [MINIMAL-DEPLOYMENT-GUIDE.md](guides/MINIMAL-DEPLOYMENT-GUIDE.md) | Minimal setup for testing |

### Troubleshooting Guides

| Document | Description |
|----------|-------------|
| [STEP-BY-STEP-FIX.md](troubleshooting/STEP-BY-STEP-FIX.md) | Manual troubleshooting steps |
| [NGINX-DNS-TROUBLESHOOTING-GUIDE.md](troubleshooting/NGINX-DNS-TROUBLESHOOTING-GUIDE.md) | DNS resolution issues |
| [OPENSHIFT-RESOURCE-QUOTA-FIX.md](troubleshooting/OPENSHIFT-RESOURCE-QUOTA-FIX.md) | Resource quota errors |
| [MISSING-SERVICES-SOLUTION.md](troubleshooting/MISSING-SERVICES-SOLUTION.md) | Service connection issues |

---

## 🔧 Manifest Files

### Infrastructure Services

| File | Component | Description |
|------|-----------|-------------|
| `02-postgresql.yaml` | PostgreSQL | Database for metadata and users |
| `03-vespa.yaml` | Vespa | Vector search engine |
| `04-redis.yaml` | Redis | Cache and task queue |

### Model Servers

| File | Component | Description |
|------|-----------|-------------|
| `06-inference-model-server.yaml` | Inference Server | Real-time query embeddings |
| `06-indexing-model-server.yaml` | Indexing Server | Bulk document embeddings |

### Application Services

| File | Component | Description |
|------|-----------|-------------|
| `07-api-server.yaml` | API Server | Backend FastAPI application |
| `07-api-server-service.yaml` | API Service | Service for API server |
| `08-web-server.yaml` | Web Server | Frontend Next.js application |
| `08-web-server-service.yaml` | Web Service | Service for web server |

### Gateway

| File | Component | Description |
|------|-----------|-------------|
| `09-nginx.yaml` | NGINX | Reverse proxy with initContainer |
| `09-nginx-simple.yaml` | NGINX Simple | Simplified without initContainer |
| `09-nginx-hardcoded-namespace.yaml` | NGINX Hardcoded | For namespace issues |

---

## 🛠️ Common Tasks

### Scale Services

```bash
# Scale web server
oc scale deployment/web-server --replicas=3

# Scale API server
oc scale deployment/api-server --replicas=2
```

### Check Logs

```bash
# Check API server logs
oc logs deployment/api-server -f

# Check NGINX logs
oc logs deployment/nginx -f

# Check initContainer logs
oc logs deployment/nginx -c wait-for-services
```

### Update Configuration

```bash
# Update ConfigMap
oc edit configmap nginx-config

# Restart NGINX to apply changes
oc rollout restart deployment/nginx
```

### Access Services

```bash
# Port forward to web server
oc port-forward service/web-server 3000:3000

# Port forward to API server
oc port-forward service/api-server 8080:8080

# Access in browser
open http://localhost:3000
```

---

## 🔐 Security

### Network Policies

Apply network policies for security:

```bash
# See KUBERNETES-NETWORKING-COMPLETE-GUIDE.md for complete policies
oc apply -f network-policies.yaml
```

### Company-Only Access

Restrict access to company network:

```bash
# Create route with IP whitelist
oc create route edge onyx-route \
  --service=nginx \
  --hostname=onyx.company.com \
  --insecure-policy=Redirect

# Add IP whitelist annotation
oc annotate route onyx-route \
  haproxy.router.openshift.io/ip_whitelist="192.168.1.0/24 10.0.0.0/8"
```

---

## 📊 Resource Requirements

### Minimum Requirements

| Component | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| PostgreSQL | 200m | 256Mi | 5Gi |
| Redis | 100m | 128Mi | 1Gi |
| Vespa | 500m | 1Gi | 10Gi |
| Model Servers (each) | 500m | 2Gi | 5Gi |
| API Server | 500m | 1Gi | - |
| Web Server | 200m | 512Mi | - |
| NGINX | 100m | 128Mi | - |
| **Total** | **~2.6 cores** | **~7.1 Gi** | **~26 Gi** |

### Production Requirements

| Component | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| PostgreSQL | 1000m | 1Gi | 50Gi |
| Redis | 500m | 256Mi | 5Gi |
| Vespa | 2000m | 2Gi | 100Gi |
| Model Servers (each) | 2000m | 4Gi | 10Gi |
| API Server | 2000m | 2Gi | - |
| Web Server | 1000m | 1Gi | - |
| NGINX | 500m | 256Mi | - |
| **Total** | **~11 cores** | **~14.5 Gi** | **~175 Gi** |

---

## 🐛 Troubleshooting

### NGINX Connection Timeout

See [STEP-BY-STEP-FIX.md](troubleshooting/STEP-BY-STEP-FIX.md)

**Quick fix:**
```bash
# Check if services exist
oc get service web-server
oc get service api-server

# Check if services have endpoints
oc get endpoints web-server
oc get endpoints api-server

# If missing, create services
oc apply -f manifests/07-api-server-service.yaml
oc apply -f manifests/08-web-server-service.yaml
```

### DNS Resolution Issues

See [NGINX-DNS-TROUBLESHOOTING-GUIDE.md](troubleshooting/NGINX-DNS-TROUBLESHOOTING-GUIDE.md)

**Quick test:**
```bash
# Test DNS from NGINX pod
oc exec deployment/nginx -- nslookup web-server
oc exec deployment/nginx -- nslookup api-server
```

### Resource Quota Errors

See [OPENSHIFT-RESOURCE-QUOTA-FIX.md](troubleshooting/OPENSHIFT-RESOURCE-QUOTA-FIX.md)

**Quick fix:** Add resource limits to all containers

### Pod Not Starting

```bash
# Check pod status
oc get pods

# Describe pod to see events
oc describe pod <pod-name>

# Check logs
oc logs <pod-name>

# Check previous logs (if crashed)
oc logs <pod-name> --previous
```

---

## 🔄 Updates and Maintenance

### Update Onyx Images

```bash
# Set new image
oc set image deployment/api-server api-server=onyxdotapp/onyx-backend:latest
oc set image deployment/web-server web-server=onyxdotapp/onyx-web-server:latest

# Check rollout status
oc rollout status deployment/api-server
oc rollout status deployment/web-server
```

### Backup Data

```bash
# Backup PostgreSQL
oc exec deployment/postgresql -- pg_dump -U postgres onyx > backup.sql

# Backup Vespa (if needed)
oc exec deployment/vespa -- vespa-visit > vespa-backup.json
```

### Restore Data

```bash
# Restore PostgreSQL
cat backup.sql | oc exec -i deployment/postgresql -- psql -U postgres onyx
```

---

## 📞 Support

### Useful Commands

```bash
# Get all resources
oc get all

# Check events
oc get events --sort-by='.lastTimestamp'

# Check resource usage
oc adm top pods
oc adm top nodes

# Debug pod
oc debug deployment/api-server
```

### Documentation Links

- **Architecture:** [documentation/ARCHITECTURE-FOR-JUNIOR-ENGINEERS.md](documentation/ARCHITECTURE-FOR-JUNIOR-ENGINEERS.md)
- **Networking:** [documentation/KUBERNETES-NETWORKING-COMPLETE-GUIDE.md](documentation/KUBERNETES-NETWORKING-COMPLETE-GUIDE.md)
- **Troubleshooting:** [troubleshooting/](troubleshooting/)
- **Guides:** [guides/](guides/)

---

## 🤝 Contributing

When adding new manifests or documentation:

1. **Manifests** → `manifests/` directory
2. **Architecture docs** → `documentation/` directory
3. **How-to guides** → `guides/` directory
4. **Troubleshooting** → `troubleshooting/` directory
5. **Scripts** → `scripts/` directory

---

## 📄 License

This deployment configuration is based on the Onyx open-source project.

---

**Repository:** https://github.com/chiheb08/Onyx-k8s-deployment

**Onyx Project:** https://github.com/onyx-dot-app/onyx