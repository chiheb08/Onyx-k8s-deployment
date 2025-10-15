# Onyx Kubernetes Infrastructure Components

Simple Kubernetes deployments for Onyx infrastructure services (PostgreSQL, Vespa, Redis).

Created from Onyx Helm charts - simplified for easy deployment.

---

## 📦 What's Included - Complete Minimal Deployment

**All 7 services needed for Onyx UI + Chat:**

| Layer | Service | Purpose | Image | Storage |
|-------|---------|---------|-------|---------|
| **Gateway** | NGINX | Reverse proxy | nginx:1.23.4-alpine | - |
| **Frontend** | Web Server | UI (Next.js) | onyxdotapp/onyx-web-server | - |
| **Backend** | API Server | Backend (FastAPI) | onyxdotapp/onyx-backend | - |
| **AI/ML** | Inference Model Server | Query embeddings | onyxdotapp/onyx-model-server | 2GB cache |
| **Data** | PostgreSQL | Database | postgres:15.2-alpine | 10Gi PVC |
| **Data** | Vespa | Vector search | vespaengine/vespa:8.526.15 | 30Gi PVC |
| **Data** | Redis | Cache & queue | redis:7.4-alpine | Ephemeral |

**Total:** 7 services, ~40Gi storage, ~6-17Gi RAM

---

## 🚀 Quick Deploy - Complete Stack

### Deploy All 7 Services

```bash
cd /Users/chihebmhamdi/Desktop/onyx/onyx-k8s-infrastructure

# Option 1: Automated deployment (Recommended)
./deploy.sh

# Option 2: Manual deployment (all services)
kubectl apply -f 01-namespace.yaml
kubectl apply -f 02-postgresql.yaml
kubectl apply -f 03-vespa.yaml
kubectl apply -f 04-redis.yaml
kubectl apply -f 05-configmap.yaml
kubectl apply -f 06-inference-model-server.yaml
kubectl apply -f 07-api-server.yaml
kubectl apply -f 08-web-server.yaml
kubectl apply -f 09-nginx.yaml

# Check status
kubectl get pods -n onyx-infra
kubectl get svc -n onyx-infra
kubectl get pvc -n onyx-infra
```

### Wait for Ready

```bash
# Watch pods become ready
kubectl get pods -n onyx-infra -w

# Expected output (wait ~10-15 minutes):
# NAME                                      READY   STATUS    RESTARTS   AGE
# postgresql-xxxxxxxxx-xxxxx                1/1     Running   0          10m
# vespa-0                                   1/1     Running   0          10m
# redis-xxxxxxxxx-xxxxx                     1/1     Running   0          10m
# inference-model-server-xxxxxxxxx-xxxxx    1/1     Running   0          7m
# api-server-xxxxxxxxx-xxxxx                1/1     Running   0          5m
# web-server-xxxxxxxxx-xxxxx                1/1     Running   0          3m
# nginx-xxxxxxxxx-xxxxx                     1/1     Running   0          2m
```

### Access Onyx UI

```bash
# Get NGINX LoadBalancer IP
kubectl get svc nginx -n onyx-infra

# If LoadBalancer is available, open browser to:
# http://<EXTERNAL-IP>

# If LoadBalancer is pending, use port-forward:
kubectl port-forward -n onyx-infra svc/nginx 3000:80
# Then open: http://localhost:3000
```

---

## 📊 Service Endpoints

Once deployed, services are accessible within the cluster:

| Service | Endpoint | Port | Usage |
|---------|----------|------|-------|
| **NGINX** | LoadBalancer EXTERNAL-IP or NodePort | 80 | Entry point (external access) |
| **Web Server** | `web-server.onyx-infra.svc.cluster.local` | 3000 | Frontend UI |
| **API Server** | `api-server.onyx-infra.svc.cluster.local` | 8080 | Backend API |
| **Model Server** | `inference-model-server.onyx-infra.svc.cluster.local` | 9000 | AI embeddings |
| **PostgreSQL** | `postgresql.onyx-infra.svc.cluster.local` | 5432 | Database |
| **Vespa** | `vespa-0.vespa-service.onyx-infra.svc.cluster.local` | 19071 (config)<br>8081 (query) | Vector search |
| **Redis** | `redis.onyx-infra.svc.cluster.local` | 6379 | Cache/queue |

---

## 🔧 Configuration

### Important: Namespace Configuration & DNS Naming

**✅ No hardcoded namespaces in YAML files!**

All resources will deploy to your **current namespace/project**.

**Before deploying, set your namespace:**

```bash
# Kubernetes
kubectl config set-context --current --namespace=your-namespace

# OpenShift
oc project your-namespace

# Verify
kubectl config view --minify | grep namespace:
# OR
oc project
```

**Example for OpenShift:**
```bash
# Create project
oc new-project onyx-production

# Set as current
oc project onyx-production

# Deploy
./deploy.sh
# → All resources created in onyx-production
```

---

### 🌐 Kubernetes DNS Naming Explained

**You might see references to `web-server.onyx-infra.svc.cluster.local` in documentation.**

**Understanding the format:**
```
service-name.namespace.svc.cluster.local:port

Example:
web-server.onyx-infra.svc.cluster.local:3000
│         │          │   │            │
│         │          │   │            └─ Port number
│         │          │   └─ Kubernetes domain (always same)
│         │          └─ "svc" means Service
│         └─ Namespace name (changes per deployment)
└─ Service name
```

**Important: Our YAML files use SHORT names!**

```yaml
# In 05-configmap.yaml:
POSTGRES_HOST: "postgresql"              # Not postgresql.onyx-infra...
VESPA_HOST: "vespa-0.vespa-service"      # Not vespa-0.vespa-service.onyx-infra...

# In 09-nginx.yaml:
upstream web_server {
    server web-server:3000;              # Not web-server.onyx-infra...
}
```

**Why this works:**

When you deploy to namespace `my-custom-namespace`:
- Service `postgresql` is created in `my-custom-namespace`
- API Server looks up `postgresql`
- Kubernetes automatically resolves to: `postgresql.my-custom-namespace.svc.cluster.local`
- Connection works! ✅

**You DON'T need to change anything!**

The namespace is automatically added by Kubernetes DNS based on where you deploy.

**For cross-namespace access (like external vLLM):**
```yaml
# If vLLM is in namespace "ai-services":
VLLM_URL: "http://vllm-service.ai-services:8001"
                           └─ Must specify namespace
```

**See `DNS-NAMING-EXPLAINED.md` for complete details.**

---

## 📡 NGINX ConfigMap Explained (For Junior Engineers)

### What is NGINX Doing?

NGINX acts as a **reverse proxy** - it sits in front of your application and routes traffic to the right service based on the URL path.

**Think of NGINX like a receptionist at a company:**
- Visitors (users) come to the front desk (NGINX)
- The receptionist looks at where they want to go (URL path)
- Then directs them to the right department (Web Server or API Server)

### The ConfigMap

In `09-nginx.yaml`, we have a ConfigMap called `nginx-config` that contains the NGINX configuration file.

#### Why Use a ConfigMap?

Instead of building a custom NGINX Docker image with our config file baked in, we:
1. Use the standard NGINX image (nginx:1.23.4-alpine)
2. Store our configuration in a ConfigMap (Kubernetes resource)
3. Mount the ConfigMap into the NGINX container as a file

**Benefits:**
- ✅ Can update configuration without rebuilding image
- ✅ Configuration is versioned with Kubernetes
- ✅ Easy to see and modify
- ✅ Standard practice in Kubernetes

#### How It Works:

```yaml
# Step 1: Define the ConfigMap (stores the nginx.conf file)
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  nginx.conf: |
    # This entire block is the NGINX configuration file
    # It will be created as /etc/nginx/nginx.conf inside the container
```

```yaml
# Step 2: Mount the ConfigMap into the NGINX container
spec:
  containers:
    - name: nginx
      volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/nginx.conf  # Where NGINX reads config
          subPath: nginx.conf               # Which key from ConfigMap to use
  volumes:
    - name: nginx-config
      configMap:
        name: nginx-config  # Reference to the ConfigMap above
```

**What happens:**
1. Kubernetes creates the ConfigMap as a resource in the cluster
2. When NGINX pod starts, Kubernetes mounts the ConfigMap as a file
3. The `nginx.conf` content from ConfigMap → appears as `/etc/nginx/nginx.conf` in container
4. NGINX reads this file and applies the routing rules

### The Configuration Breakdown

Let's break down what's in the `nginx.conf`:

```nginx
events {
    worker_connections 1024;
}
```
**Explanation:** Basic NGINX setting. Allows 1024 concurrent connections per worker process.

```nginx
http {
    upstream web_server {
        server web-server.onyx-infra.svc.cluster.local:3000;
    }

    upstream api_server {
        server api-server.onyx-infra.svc.cluster.local:8080;
    }
```
**Explanation:**
- **upstream** = Define backend servers that NGINX will forward traffic to
- `web_server` is a **name** (we can use it later)
- Points to the Kubernetes service: `web-server.onyx-infra.svc.cluster.local:3000`
- Same for `api_server` pointing to API service on port 8080

**Real-world analogy:**
```
upstream = "Department contact list"
web_server = "Frontend Department, extension 3000"
api_server = "Backend Department, extension 8080"
```

```nginx
    server {
        listen 80;
        server_name _;
```
**Explanation:**
- NGINX listens on port 80 (HTTP)
- `server_name _` = Accept requests for any domain/hostname

```nginx
        location /api/ {
            proxy_pass http://api_server;
```
**Explanation:**
- **location /api/** = "If URL starts with /api/"
- **proxy_pass http://api_server** = Forward to the api_server upstream (port 8080)

**Example:**
```
User requests: http://your-site.com/api/chat/send
                                     ^^^^^^^^
                                     Matches /api/

NGINX forwards to: http://api-server.onyx-infra.svc.cluster.local:8080/api/chat/send
```

```nginx
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
```
**Explanation:**
- **proxy_set_header** = Add HTTP headers when forwarding
- `Host` = Original hostname user requested
- `X-Real-IP` = User's actual IP address
- `X-Forwarded-For` = Chain of proxies (for logging)

**Why needed:**
The backend API server needs to know who the original user was, not just that NGINX made the request.

```nginx
        location /api/stream {
            proxy_pass http://api_server;
            proxy_buffering off;
            proxy_cache off;
```
**Explanation:**
- Special handling for **streaming** responses (like chat)
- `proxy_buffering off` = Don't buffer the response (send immediately)
- `proxy_cache off` = Don't cache (each message is unique)

**Why needed:**
When Onyx streams chat responses word-by-word, we want them to appear immediately, not after buffering.

```nginx
        location / {
            proxy_pass http://web_server;
```
**Explanation:**
- **location /** = "For everything else not matched above"
- Forward to Web Server (Next.js frontend)

**Example:**
```
User requests: http://your-site.com/
User requests: http://your-site.com/chat
User requests: http://your-site.com/settings

All go to: http://web-server.onyx-infra.svc.cluster.local:3000/
```

### Complete Request Flow Example

**Scenario 1: User loads homepage**

```
1. User browser → http://your-site.com/
2. Request hits NGINX (port 80)
3. NGINX checks: Does URL start with /api/? NO
4. NGINX forwards to: http://web_server (web-server:3000)
5. Web Server returns HTML/CSS/JS
6. NGINX forwards response to user
7. User sees homepage!
```

**Scenario 2: User sends chat message (API call)**

```
1. User browser → http://your-site.com/api/chat/send-message
2. Request hits NGINX (port 80)
3. NGINX checks: Does URL start with /api/? YES!
4. NGINX forwards to: http://api_server (api-server:8080)
5. API Server processes (queries DB, calls LLM)
6. API Server returns JSON response
7. NGINX forwards response to user
8. User sees chat response!
```

**Scenario 3: Streaming chat (real-time)**

```
1. User browser → http://your-site.com/api/stream/chat
2. Request hits NGINX (port 80)
3. NGINX checks: Does URL match /api/stream? YES!
4. NGINX forwards to: http://api_server
   - WITH buffering OFF (immediate streaming)
5. API Server streams words one by one
6. Each word immediately forwarded to user
7. User sees typing effect in real-time!
```

### Why Do We Need This?

**Without NGINX:**
- Users would need to know two different URLs:
  - http://web-server:3000 for UI
  - http://api-server:8080 for API
- Can't expose multiple ports externally
- No SSL termination point
- No load balancing capability

**With NGINX:**
- ✅ Single entry point: http://your-site.com
- ✅ NGINX automatically routes to the right service
- ✅ Can add SSL/HTTPS easily
- ✅ Can add authentication
- ✅ Can add rate limiting
- ✅ Can scale backend services behind NGINX

### How to Modify the Configuration

**Example: Change API path from `/api/` to `/backend/`**

Edit the ConfigMap in `09-nginx.yaml`:
```nginx
# Change this:
location /api/ {
    proxy_pass http://api_server;

# To this:
location /backend/ {
    proxy_pass http://api_server;
```

Then apply:
```bash
kubectl apply -f 09-nginx.yaml
kubectl rollout restart deployment/nginx -n onyx-infra
```

**Example: Add a new backend service**

```nginx
# Add upstream
upstream new_service {
    server new-service.onyx-infra.svc.cluster.local:5000;
}

# Add location
location /newapi/ {
    proxy_pass http://new_service;
    # ... other proxy settings
}
```

### Common Issues

**Issue: "502 Bad Gateway"**

**Cause:** NGINX can't reach the backend service

**Debug:**
```bash
# Check if services exist
kubectl get svc -n onyx-infra web-server
kubectl get svc -n onyx-infra api-server

# Check if DNS works from NGINX pod
kubectl exec -it -n onyx-infra deployment/nginx -- \
  nslookup web-server.onyx-infra.svc.cluster.local

# Check if backend is listening
kubectl exec -it -n onyx-infra deployment/nginx -- \
  wget -O- http://web-server.onyx-infra.svc.cluster.local:3000
```

**Issue: "504 Gateway Timeout"**

**Cause:** Backend is too slow to respond

**Solution:** Increase timeouts in ConfigMap:
```nginx
proxy_read_timeout 120s;  # Increase from 60s
```

---

## 🎓 Summary for Junior Engineers

**NGINX ConfigMap:**
- **What:** Configuration file stored in Kubernetes
- **Why:** Separates config from image, easy to update
- **How:** Mounted as a file into NGINX container
- **Does:** Routes traffic based on URL path
  - `/` → Web Server (UI)
  - `/api/*` → API Server (Backend)
  - `/api/stream` → API Server (with streaming)

**Key Concept:** One entry point (NGINX) routes to multiple backend services based on URL patterns!

---

### PostgreSQL

**Credentials:**
- User: `postgres`
- Password: `postgres`  
- Database: `postgres`

**Change password:**
```bash
# Edit secret
kubectl edit secret postgresql-secret -n onyx-infra

# Or delete and recreate
kubectl delete secret postgresql-secret -n onyx-infra
kubectl create secret generic postgresql-secret -n onyx-infra \
  --from-literal=POSTGRES_USER=postgres \
  --from-literal=POSTGRES_PASSWORD=your-secure-password \
  --from-literal=POSTGRES_DB=postgres
```

**Storage:**
- PVC: `postgresql-pvc`
- Size: 10Gi
- Path: `/var/lib/postgresql/data`

### Vespa

**Configuration:**
- Runs as StatefulSet (requires stable network identity)
- Hostname: `vespa-0`
- Subdomain: `vespa-service`

**Storage:**
- PVC: `vespa-storage-vespa-0` (auto-created by StatefulSet)
- Size: 30Gi
- Path: `/opt/vespa/var`

**Ports:**
- 19071: Config/health endpoint
- 8081: Query API

**Resource Requirements:**
- Minimum: 1 CPU, 2Gi RAM
- Recommended: 4 CPU, 8Gi RAM
- For large scale: Increase to 8 CPU, 32Gi RAM

### Redis

**Credentials:**
- Password: `password`

**Change password:**
```bash
kubectl delete secret redis-secret -n onyx-infra
kubectl create secret generic redis-secret -n onyx-infra \
  --from-literal=REDIS_PASSWORD=your-secure-password
```

**Mode:**
- Ephemeral (no persistence)
- In-memory only
- Data lost on pod restart (intentional for Onyx)

---

## 🧪 Testing

### Test PostgreSQL

```bash
# Connect to PostgreSQL
kubectl exec -it -n onyx-infra deployment/postgresql -- psql -U postgres

# In psql:
\l                    # List databases
\dt                   # List tables (after Onyx creates them)
SELECT version();     # Check version
\q                    # Exit
```

### Test Vespa

```bash
# Check Vespa health
kubectl exec -it -n onyx-infra vespa-0 -- \
  curl -s http://localhost:19071/state/v1/health

# Expected output: {"status":{"code":"up"}}
```

### Test Redis

```bash
# Test Redis connection
kubectl exec -it -n onyx-infra deployment/redis -- \
  redis-cli -a password ping

# Expected output: PONG

# Check Redis info
kubectl exec -it -n onyx-infra deployment/redis -- \
  redis-cli -a password INFO server
```

---

## 🔍 Monitoring

### Check Logs

```bash
# PostgreSQL logs
kubectl logs -n onyx-infra deployment/postgresql -f

# Vespa logs
kubectl logs -n onyx-infra vespa-0 -f

# Redis logs
kubectl logs -n onyx-infra deployment/redis -f
```

### Check Resources

```bash
# Resource usage
kubectl top pods -n onyx-infra

# Describe pods
kubectl describe pod -n onyx-infra <pod-name>

# Check events
kubectl get events -n onyx-infra --sort-by='.lastTimestamp'
```

### Check Storage

```bash
# List PVCs
kubectl get pvc -n onyx-infra

# Describe PVC
kubectl describe pvc postgresql-pvc -n onyx-infra
kubectl describe pvc vespa-storage-vespa-0 -n onyx-infra
```

---

## 🔄 Management

### Restart Services

```bash
# Restart PostgreSQL
kubectl rollout restart deployment/postgresql -n onyx-infra

# Restart Vespa
kubectl delete pod vespa-0 -n onyx-infra

# Restart Redis
kubectl rollout restart deployment/redis -n onyx-infra
```

### Scale (if needed)

```bash
# Note: PostgreSQL and Vespa should stay at 1 replica
# Only Redis can be scaled (but not recommended for Onyx)

# Scale Redis (not recommended)
kubectl scale deployment/redis -n onyx-infra --replicas=1
```

### Backup PostgreSQL

```bash
# Create backup
kubectl exec -n onyx-infra deployment/postgresql -- \
  pg_dump -U postgres postgres > onyx-backup-$(date +%Y%m%d).sql

# Restore from backup
kubectl exec -i -n onyx-infra deployment/postgresql -- \
  psql -U postgres postgres < onyx-backup-20241014.sql
```

---

## 🧹 Cleanup

### Delete Everything

```bash
# Delete all resources
kubectl delete -f 04-redis.yaml
kubectl delete -f 03-vespa.yaml
kubectl delete -f 02-postgresql.yaml
kubectl delete -f 01-namespace.yaml

# This will delete the namespace and all resources in it
# PVCs and PVs might need manual deletion depending on reclaim policy
```

### Delete Just One Service

```bash
# Delete specific service
kubectl delete -f 02-postgresql.yaml
kubectl delete -f 03-vespa.yaml
kubectl delete -f 04-redis.yaml
```

---

## ⚠️ Production Considerations

Before using in production:

### Security

- [ ] **Change all default passwords**
  - PostgreSQL: postgres/postgres
  - Redis: password
  
- [ ] **Use stronger secrets**
  ```bash
  # Generate random password
  openssl rand -base64 32
  ```

- [ ] **Enable network policies**
  - Restrict access between namespaces
  - Only allow Onyx pods to access these services

- [ ] **Use TLS for connections**
  - PostgreSQL: Enable SSL
  - Redis: Use stunnel or Redis TLS
  
### Storage

- [ ] **Set storage class**
  - Uncomment and set `storageClassName` in PVCs
  - Use fast SSD storage for best performance
  
- [ ] **Configure backup strategy**
  - PostgreSQL: Regular pg_dump or continuous archiving
  - Vespa: Volume snapshots
  
- [ ] **Set reclaim policy**
  ```bash
  # Prevent accidental data loss
  kubectl patch pv <pv-name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
  ```

### High Availability

- [ ] **PostgreSQL HA**
  - Consider using PostgreSQL operator (Zalando, CloudNativePG)
  - Or external managed service (AWS RDS, Google Cloud SQL)
  
- [ ] **Vespa Clustering**
  - For large scale, use Vespa Cloud or multi-node cluster
  
- [ ] **Redis HA**
  - Use Redis Sentinel or Redis Cluster
  - Or Redis operator (Bitnami, Spotahome)

### Resource Limits

- [ ] **Adjust resource requests/limits**
  - Based on your workload
  - Monitor actual usage with `kubectl top`
  
- [ ] **Set Pod Disruption Budgets**
  ```yaml
  apiVersion: policy/v1
  kind: PodDisruptionBudget
  metadata:
    name: postgresql-pdb
  spec:
    minAvailable: 1
    selector:
      matchLabels:
        app: postgresql
  ```

---

## 📝 Environment Variables for Onyx

When deploying Onyx services, use these connection strings:

```yaml
# In your Onyx ConfigMap or environment variables:

POSTGRES_HOST: postgresql.onyx-infra.svc.cluster.local
POSTGRES_PORT: "5432"
POSTGRES_USER: postgres
POSTGRES_PASSWORD: postgres  # From secret

VESPA_HOST: vespa-0.vespa-service.onyx-infra.svc.cluster.local
VESPA_PORT: "19071"

REDIS_HOST: redis.onyx-infra.svc.cluster.local
REDIS_PORT: "6379"
REDIS_PASSWORD: password  # From secret
```

---

## 🐛 Troubleshooting

### PostgreSQL Not Starting

**Check logs:**
```bash
kubectl logs -n onyx-infra deployment/postgresql
```

**Common issues:**
- PVC not bound: Check storage class exists
- Permissions: Check PV permissions
- Out of memory: Increase memory limits

### Vespa Taking Long to Start

**Vespa needs time:**
- First start: 2-5 minutes
- Downloading data: Can take longer
- Check readiness probe

**If stuck:**
```bash
# Check logs
kubectl logs -n onyx-infra vespa-0

# Check health
kubectl exec -n onyx-infra vespa-0 -- \
  curl http://localhost:19071/state/v1/health
```

### Redis Connection Refused

**Check password:**
```bash
# Verify secret
kubectl get secret redis-secret -n onyx-infra -o yaml

# Test connection
kubectl exec -it -n onyx-infra deployment/redis -- \
  redis-cli -a password ping
```

### Storage Issues

**PVC pending:**
```bash
# Check PVC status
kubectl describe pvc <pvc-name> -n onyx-infra

# Check if storage class exists
kubectl get storageclass

# Check PV
kubectl get pv
```

---

## 📚 References

- **Original Helm Chart:** `/onyx-repo/deployment/helm/charts/onyx/values.yaml`
- **Docker Compose:** `/onyx-repo/deployment/docker_compose/docker-compose.yml`
- **PostgreSQL Docs:** https://www.postgresql.org/docs/15/
- **Vespa Docs:** https://docs.vespa.ai/
- **Redis Docs:** https://redis.io/docs/

---

## 💡 Next Steps

After deploying these infrastructure components:

1. **Deploy Onyx Application Services:**
   - API Server
   - Web Server
   - Model Servers
   - (Optional) Background Workers

2. **Configure Networking:**
   - Set up Ingress for external access
   - Configure DNS
   - Enable SSL/TLS

3. **Set up Monitoring:**
   - Prometheus metrics
   - Grafana dashboards
   - Logging (EFK/Loki)

4. **Configure Backups:**
   - Automated PostgreSQL backups
   - Volume snapshots
   - Disaster recovery plan

---

**🎯 These infrastructure components are ready to support your Onyx deployment!**

