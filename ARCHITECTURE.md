# Kubernetes Minimal Deployment Architecture

Visual architecture diagram for the Onyx Kubernetes minimal deployment.

---

## 🏗️ Kubernetes Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          🌐 EXTERNAL USER                                │
│                      http://<LoadBalancer-IP>:80                         │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 │ Internet/Network
                                 │
        ┌────────────────────────┴────────────────────────┐
        │          Kubernetes Namespace: onyx-infra        │
        │                                                  │
        │                    ┌─────────────┐              │
        │                    │   NGINX     │              │
        │                    │ LoadBalancer│              │
        │                    │  Service    │              │
        │                    │  Port: 80   │              │
        │                    └──────┬──────┘              │
        │                           │                      │
        │              ┌────────────┴──────────┐          │
        │              │                       │          │
        │              ▼                       ▼          │
        │     ┌────────────────┐     ┌────────────────┐  │
        │     │  WEB SERVER    │     │  API SERVER    │◄─┼────┐
        │     │  Deployment    │◄────│  Deployment    │  │    │
        │     │  ClusterIP     │ API │  ClusterIP     │  │    │
        │     │  Port: 3000    │     │  Port: 8080    │  │    │
        │     └────────────────┘     └───────┬────────┘  │    │
        │                                    │           │    │
        │         ┌──────────────────────────┼────┐      │    │
        │         │           │              │    │      │    │
        │         ▼           ▼              ▼    ▼      │    │
        │  ┌───────────┐ ┌────────┐  ┌─────────┐ ┌──────────┐
        │  │PostgreSQL │ │ Vespa  │  │  Redis  │ │  Model   │
        │  │Deployment │ │StatefulSet │Deployment│ │  Server  │
        │  │ClusterIP  │ │Headless│  │ClusterIP│ │Deployment│
        │  │Port: 5432 │ │19071   │  │Port:6379│ │Port: 9000│
        │  │PVC: 10Gi  │ │PVC:30Gi│  │Ephemeral│ │EmptyDir  │
        │  └───────────┘ └────────┘  └─────────┘ └──────────┘
        │                                                  │
        └──────────────────────────────────────────────────┘
```

---

## 🔄 Data Flow in Kubernetes

### User Search Flow

```
1. User → http://<LoadBalancer-IP>
         ↓
2. Kubernetes LoadBalancer → NGINX Service (ClusterIP: None or LoadBalancer)
         ↓
3. NGINX Pod → Routes request:
   ├─→ / (root) → web-server.onyx-infra.svc.cluster.local:3000
   └─→ /api/* → api-server.onyx-infra.svc.cluster.local:8080
         ↓
4. API Server Pod:
   ├─→ Query embedding: inference-model-server.onyx-infra:9000/embed
   ├─→ Vector search: vespa-0.vespa-service.onyx-infra:19071/search
   ├─→ Cache check: redis.onyx-infra:6379
   ├─→ Metadata query: postgresql.onyx-infra:5432
   └─→ (Optional) LLM call: <external-vllm-endpoint>/v1/chat/completions
         ↓
5. Response → NGINX → LoadBalancer → User
```

---

## 🌐 Kubernetes Networking

### Internal DNS Resolution

All services communicate via Kubernetes DNS:

```
Service FQDN Format:
<service-name>.<namespace>.svc.cluster.local

Examples:
- api-server.onyx-infra.svc.cluster.local:8080
- postgresql.onyx-infra.svc.cluster.local:5432
- vespa-0.vespa-service.onyx-infra.svc.cluster.local:19071
- redis.onyx-infra.svc.cluster.local:6379
- inference-model-server.onyx-infra.svc.cluster.local:9000
- web-server.onyx-infra.svc.cluster.local:3000
```

### Service Types

| Service | Type | Why |
|---------|------|-----|
| NGINX | LoadBalancer | External access (or NodePort/port-forward) |
| All Others | ClusterIP | Internal only |
| Vespa | Headless (ClusterIP: None) | StatefulSet requires stable DNS |

### Network Policies (Optional)

For production, restrict network access:

```yaml
# Example: Only allow API Server to access PostgreSQL
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: postgresql-network-policy
  namespace: onyx-infra
spec:
  podSelector:
    matchLabels:
      app: postgresql
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api-server
      ports:
        - protocol: TCP
          port: 5432
```

---

## 📦 Kubernetes Resources

### Deployments

| Deployment | Replicas | Strategy | Notes |
|------------|----------|----------|-------|
| nginx | 1 | RollingUpdate | Can scale if needed |
| web-server | 1 | RollingUpdate | Can scale if needed |
| api-server | 1 | RollingUpdate | Can scale if needed |
| inference-model-server | 1 | RollingUpdate | Can scale if needed |
| postgresql | 1 | Recreate | DO NOT scale (single instance) |
| redis | 1 | RollingUpdate | Can scale with Redis Cluster |

### StatefulSets

| StatefulSet | Replicas | volumeClaimTemplates | Notes |
|-------------|----------|----------------------|-------|
| vespa | 1 | vespa-storage (30Gi) | DO NOT scale (needs clustering config) |

### Services

All services use ClusterIP except NGINX (LoadBalancer).

### ConfigMaps

- `onyx-config`: Environment variables for all Onyx services
- `nginx-config`: NGINX routing configuration

### Secrets

- `postgresql-secret`: Database credentials
- `redis-secret`: Redis password

---

## 🔗 Service Communication Matrix

```
┌──────────┬─────────────┬──────────┬─────────────┬──────────┬────────┬────────┐
│   From   │     To      │ Protocol │  Endpoint   │   Port   │ Purpose│ Example│
├──────────┼─────────────┼──────────┼─────────────┼──────────┼────────┼────────┤
│ User     │ NGINX       │ HTTP     │ External IP │ 80       │ Access │ GET /  │
│ NGINX    │ Web Server  │ HTTP     │ ClusterIP   │ 3000     │ Serve  │ GET /  │
│ NGINX    │ API Server  │ HTTP     │ ClusterIP   │ 8080     │ Proxy  │ /api/* │
│ Web      │ API Server  │ HTTP     │ ClusterIP   │ 8080     │ Data   │ /api/  │
│ API      │ PostgreSQL  │ PostgreSQL│ClusterIP   │ 5432     │ Query  │ SELECT │
│ API      │ Vespa       │ HTTP     │ Headless    │ 19071    │ Search │ POST   │
│ API      │ Redis       │ Redis    │ ClusterIP   │ 6379     │ Cache  │ GET    │
│ API      │ Model       │ HTTP     │ ClusterIP   │ 9000     │ Embed  │ POST   │
│ API      │ vLLM (ext)  │ HTTP     │ External    │ Custom   │ Chat   │ POST   │
└──────────┴─────────────┴──────────┴─────────────┴──────────┴────────┴────────┘
```

---

## 📊 Resource Allocation

### CPU Requests/Limits

| Service | Request | Limit |
|---------|---------|-------|
| NGINX | 100m | 500m |
| Web Server | 200m | 1000m |
| API Server | 500m | 2000m |
| Model Server | 500m | 2000m |
| PostgreSQL | 100m | 1000m |
| Vespa | 1000m | 4000m |
| Redis | 100m | 500m |
| **TOTAL** | **2.5 CPU** | **9.5 CPU** |

### Memory Requests/Limits

| Service | Request | Limit |
|---------|---------|-------|
| NGINX | 128Mi | 256Mi |
| Web Server | 512Mi | 1Gi |
| API Server | 1Gi | 2Gi |
| Model Server | 2Gi | 4Gi |
| PostgreSQL | 256Mi | 1Gi |
| Vespa | 2Gi | 8Gi |
| Redis | 128Mi | 512Mi |
| **TOTAL** | **~6Gi** | **~17Gi** |

---

## 🚀 Startup Sequence

**Correct order (handled by deploy.sh):**

```
1. Namespace
   ↓
2. Infrastructure Layer (parallel)
   ├─ PostgreSQL
   ├─ Vespa
   └─ Redis
   ↓ (wait for ready)
   
3. ConfigMap
   ↓
   
4. AI/ML Layer
   └─ Inference Model Server
   ↓ (wait for ready)
   
5. Application Layer
   └─ API Server (runs DB migrations in init container)
   ↓ (wait for ready)
   
6. Frontend Layer
   └─ Web Server
   ↓ (wait for ready)
   
7. Gateway Layer
   └─ NGINX
   ↓
   
✅ Onyx is ready!
```

**Total Time:** 10-15 minutes (first deployment with model downloads)

---

## 💡 Key Design Decisions

### Why These Configurations?

**1. PostgreSQL as Deployment (not StatefulSet)**
- Single instance is fine for minimal deployment
- Easier to manage
- Can upgrade to StatefulSet or operator for HA later

**2. Vespa as StatefulSet**
- Requires stable hostname (`vespa-0.vespa-service...`)
- Needs persistent storage with stable identity
- Vespa expects consistent network identity

**3. Redis as Deployment (ephemeral)**
- Onyx uses Redis as cache (ephemeral is intentional)
- Data loss on restart is acceptable
- Faster than persistent Redis

**4. Model Server with emptyDir**
- Models download on first start (~2GB)
- Can use PVC for faster subsequent starts
- emptyDir = simpler for minimal deployment

**5. API Server Init Container**
- Runs Alembic migrations before main container
- Ensures database schema is up to date
- Prevents race conditions

**6. NGINX with Custom ConfigMap**
- Full routing configuration embedded
- Routes `/api/*` to API Server
- Routes `/` to Web Server
- WebSocket support for streaming

---

## 🔧 Customization

### Change Resource Limits

Edit the respective YAML files:

```yaml
# In 07-api-server.yaml
resources:
  requests:
    cpu: 1000m      # Increase for better performance
    memory: 2Gi
  limits:
    cpu: 4000m
    memory: 4Gi
```

### Change Storage Sizes

```yaml
# In 02-postgresql.yaml
resources:
  requests:
    storage: 20Gi  # Increase if storing lots of data

# In 03-vespa.yaml
resources:
  requests:
    storage: 50Gi  # Increase for more documents
```

### Add Storage Class

```yaml
# In PVC specs
storageClassName: "fast-ssd"  # or your storage class name
```

---

## 📝 Next Steps

1. **Deploy Infrastructure:** Run `./deploy.sh`
2. **Access UI:** Get LoadBalancer IP or use port-forward
3. **Create Account:** Sign up in Onyx UI
4. **Configure LLM:** Add your vLLM or cloud LLM provider
5. **Test Chat:** Ask questions and verify it works

**For document upload capability:** Deploy Background Workers, Indexing Model Server, and MinIO (see full Helm chart).

---

**This deployment provides everything you need for Onyx UI and chat functionality!** 🚀

