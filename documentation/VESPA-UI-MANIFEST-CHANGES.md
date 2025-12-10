# Vespa UI Access - Manifest Changes Guide

## 🎯 Overview

This guide shows **exactly what to modify** in your Kubernetes manifests **and Docker Compose** to access the Vespa admin UI.

---

## 📋 Current Situation

**Current Vespa Service** (`03-vespa.yaml`):
- Type: `ClusterIP` (headless)
- Ports: `19071` (config), `8081` (query)
- **Access**: Only within cluster (internal only)

**Problem**: Cannot access Vespa UI from outside the cluster.

---

## ✅ Solution Options

You have **4 options**. Choose based on your needs:

| Option | Best For | Access Method | Security |
|-------|----------|---------------|----------|
| **1. Port Forward** | Development | `kubectl port-forward` | ✅ Secure |
| **2. NodePort** | Development/Testing | `<node-ip>:<port>` | ⚠️ Less secure |
| **3. LoadBalancer** | Cloud deployments | `<external-ip>:19071` | ⚠️ Less secure |
| **4. Ingress** | Production | `https://vespa-ui.domain.com` | ✅ Most secure |

---

## ✅ Option 1: Port Forward (No Manifest Changes Needed)

**Best for**: Quick access, development, testing

**No manifest changes required!** Just use kubectl:

```bash
# Port forward Vespa service
kubectl port-forward -n onyx-infra svc/vespa-service 19071:19071

# Access in browser
http://localhost:19071
```

**Pros:**
- ✅ No manifest changes
- ✅ Secure (only accessible from your machine)
- ✅ Works immediately

**Cons:**
- ❌ Requires kubectl access
- ❌ Connection drops when terminal closes
- ❌ Only accessible from your machine

---

## ✅ Option 2: NodePort Service (Recommended for Development)

**Best for**: Development, testing, internal access

### Step 1: Create New Service File

**File**: `onyx-k8s-infrastructure/manifests/03-vespa-ui-service.yaml` (already created)

This file contains a NodePort service that exposes Vespa UI.

### Step 2: Apply the Manifest

```bash
cd /Users/chihebmhamdi/Desktop/onyx/onyx-k8s-infrastructure/manifests

# Apply the new service
kubectl apply -f 03-vespa-ui-service.yaml

# Verify service is created
kubectl get svc -n onyx-infra vespa-ui-service
```

### Step 3: Find Node IP and Access

```bash
# Get node IP
kubectl get nodes -o wide

# Access Vespa UI
http://<node-ip>:30190
```

**Example:**
```bash
# If node IP is 192.168.1.100
http://192.168.1.100:30190
```

### What Changed

**Added**: New `vespa-ui-service` with:
- Type: `NodePort`
- Port `19071` → NodePort `30190`
- Port `8081` → NodePort `30191`

**Original service** (`vespa-service`) remains unchanged (still headless for internal use).

---

## ✅ Option 3: LoadBalancer Service (Cloud Deployments)

**Best for**: AWS, GCP, Azure, cloud deployments

### Step 1: Modify Service File

**File**: `onyx-k8s-infrastructure/manifests/03-vespa-ui-service.yaml`

**Change**:
```yaml
# Comment out NodePort section
# ---
# apiVersion: v1
# kind: Service
# metadata:
#   name: vespa-ui-service
#   ...
# spec:
#   type: NodePort  # <-- Comment this out
#   ...

# Uncomment LoadBalancer section
---
apiVersion: v1
kind: Service
metadata:
  name: vespa-ui-service
  namespace: onyx-infra
  labels:
    app: vespa
    component: ui
spec:
  type: LoadBalancer  # <-- Use this
  ports:
    - name: config-ui
      port: 19071
      targetPort: 19071
      protocol: TCP
    - name: query-ui
      port: 8081
      targetPort: 8081
      protocol: TCP
  selector:
    app: vespa
```

### Step 2: Apply and Get External IP

```bash
# Apply manifest
kubectl apply -f 03-vespa-ui-service.yaml

# Wait for LoadBalancer to get external IP (may take 1-2 minutes)
kubectl get svc -n onyx-infra vespa-ui-service -w

# Access Vespa UI
http://<external-ip>:19071
```

**Example Output:**
```
NAME                TYPE           EXTERNAL-IP      PORT(S)
vespa-ui-service    LoadBalancer   35.123.45.67    19071:30190/TCP
```

Access: `http://35.123.45.67:19071`

---

## ✅ Option 4: Ingress (Production - Most Secure)

**Best for**: Production deployments with domain names

### Prerequisites

- Ingress controller installed (NGINX, Traefik, etc.)
- Domain name configured
- SSL certificate (optional but recommended)

### Step 1: Create NodePort or LoadBalancer Service First

You still need the service from Option 2 or 3.

### Step 2: Create Ingress Manifest

**File**: `onyx-k8s-infrastructure/manifests/03-vespa-ui-ingress.yaml` (new file)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vespa-ui-ingress
  namespace: onyx-infra
  annotations:
    # For NGINX Ingress Controller
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    # Optional: Add authentication
    # nginx.ingress.kubernetes.io/auth-type: basic
    # nginx.ingress.kubernetes.io/auth-secret: vespa-ui-auth
spec:
  ingressClassName: nginx  # Change to your ingress class
  rules:
    - host: vespa-ui.yourdomain.com  # CHANGE THIS to your domain
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: vespa-ui-service
                port:
                  number: 19071
```

### Step 3: Apply and Access

```bash
# Apply ingress
kubectl apply -f 03-vespa-ui-ingress.yaml

# Access via domain
http://vespa-ui.yourdomain.com
```

---

## 🔧 Complete Example: NodePort Setup

### Files to Create/Modify

**1. New File**: `onyx-k8s-infrastructure/manifests/03-vespa-ui-service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: vespa-ui-service
  namespace: onyx-infra
  labels:
    app: vespa
    component: ui
spec:
  type: NodePort
  ports:
    - name: config-ui
      port: 19071
      targetPort: 19071
      nodePort: 30190
      protocol: TCP
    - name: query-ui
      port: 8081
      targetPort: 8081
      nodePort: 30191
      protocol: TCP
  selector:
    app: vespa
```

**2. No changes needed** to existing `03-vespa.yaml` (keep it as is)

### Apply Changes

```bash
cd /Users/chihebmhamdi/Desktop/onyx/onyx-k8s-infrastructure/manifests

# Apply new service
kubectl apply -f 03-vespa-ui-service.yaml

# Verify
kubectl get svc -n onyx-infra | grep vespa
```

**Expected Output:**
```
NAME                TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)
vespa-service       ClusterIP   None          <none>        19071/TCP,8081/TCP
vespa-ui-service    NodePort    10.96.1.23    <none>        19071:30190/TCP,8081:30191/TCP
```

### Access Vespa UI

```bash
# Get node IP
kubectl get nodes -o wide

# Access (replace <node-ip> with actual IP)
http://<node-ip>:30190
```

---

## 🔒 Security Considerations

### Option 1: Port Forward (Most Secure)
- ✅ Only accessible from your machine
- ✅ No external exposure
- ✅ No firewall rules needed

### Option 2: NodePort
- ⚠️ Exposes port on all nodes
- ⚠️ Accessible from anywhere that can reach node IP
- ✅ Can restrict with firewall rules
- ✅ Can use NetworkPolicy

### Option 3: LoadBalancer
- ⚠️ Publicly accessible (unless using private LoadBalancer)
- ⚠️ Exposes service to internet
- ✅ Can restrict with security groups (cloud)
- ✅ Can use NetworkPolicy

### Option 4: Ingress
- ✅ Can add authentication
- ✅ Can use SSL/TLS
- ✅ Can restrict by IP
- ✅ Most production-ready

---

## 🚀 Quick Start (Recommended)

**For immediate access (development):**

```bash
# Option 1: Port forward (no changes needed)
kubectl port-forward -n onyx-infra svc/vespa-service 19071:19071
# Then open: http://localhost:19071
```

**For persistent access (testing):**

```bash
# Option 2: Apply NodePort service
kubectl apply -f onyx-k8s-infrastructure/manifests/03-vespa-ui-service.yaml

# Get node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# Access
echo "Vespa UI: http://${NODE_IP}:30190"
```

---

## 📝 Summary

### What You Need to Do

1. **Choose an option** (recommended: NodePort for dev, Ingress for prod)

2. **Create/Modify files**:
   - ✅ `03-vespa-ui-service.yaml` (already created)
   - ✅ `03-vespa-ui-ingress.yaml` (if using Ingress)

3. **Apply manifests**:
   ```bash
   kubectl apply -f 03-vespa-ui-service.yaml
   ```

4. **Access UI**:
   - Port Forward: `http://localhost:19071`
   - NodePort: `http://<node-ip>:30190`
   - LoadBalancer: `http://<external-ip>:19071`
   - Ingress: `http://vespa-ui.yourdomain.com`

### What You DON'T Need to Change

- ❌ **Don't modify** `03-vespa.yaml` (keep it as is)
- ❌ **Don't delete** existing `vespa-service` (it's needed for internal access)
- ❌ **Don't change** StatefulSet configuration

---

## 🎯 Recommended Approach

**For Development:**
- Use **Port Forward** (no changes needed)

**For Testing/Staging:**
- Use **NodePort** service (apply `03-vespa-ui-service.yaml`)

**For Production:**
- Use **Ingress** with authentication and SSL

---

## 🐳 Docker Compose - Local Deployment

### Current Situation

**In `docker-compose.yml`:**
- Vespa ports are **commented out** (not exposed)
- Service name: `index`
- Ports: `19071` (config), `8081` (query)

**Problem**: Cannot access Vespa UI from host machine.

---

## ✅ Docker Compose Solutions

### Option 1: Use Development Override File (Easiest)

**File**: `onyx-repo/deployment/docker_compose/docker-compose.dev.yml` (already exists!)

This file already exposes Vespa ports for development.

**Step 1: Start with dev override**

```bash
cd /Users/chihebmhamdi/Desktop/onyx/onyx-repo/deployment/docker_compose

# Start with dev override (exposes ports)
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d

# Or set environment variable
export COMPOSE_FILE=docker-compose.yml:docker-compose.dev.yml
docker compose up -d
```

**Step 2: Access Vespa UI**

```bash
# Vespa Admin UI
http://localhost:19071

# Vespa Query API
http://localhost:8081
```

**What's in `docker-compose.dev.yml`:**
```yaml
services:
  index:
    ports:
      - "19071:19071"  # Admin UI
      - "8081:8081"    # Query API
```

**Pros:**
- ✅ No changes to main compose file
- ✅ Already configured
- ✅ Easy to enable/disable

**Cons:**
- ❌ Need to remember to use both files

---

### Option 2: Uncomment Ports in Main Compose File

**File**: `onyx-repo/deployment/docker_compose/docker-compose.yml`

**Step 1: Edit the file**

Find the `index` service (around line 263) and uncomment the ports:

```yaml
  index:
    image: vespaengine/vespa:8.526.15
    restart: unless-stopped
    environment:
      - VESPA_SKIP_UPGRADE_CHECK=${VESPA_SKIP_UPGRADE_CHECK:-true}
    # Uncomment these lines:
    ports:
      - "19071:19071"
      - "8081:8081"
    volumes:
      - vespa_volume:/opt/vespa/var
```

**Step 2: Restart services**

```bash
cd /Users/chihebmhamdi/Desktop/onyx/onyx-repo/deployment/docker_compose

# Restart Vespa container
docker compose restart index

# Or restart all
docker compose down
docker compose up -d
```

**Step 3: Access Vespa UI**

```bash
# Vespa Admin UI
http://localhost:19071

# Vespa Query API
http://localhost:8081
```

**Pros:**
- ✅ Simple - just uncomment
- ✅ Works with standard `docker compose up`

**Cons:**
- ❌ Modifies main compose file
- ❌ Ports always exposed (even in production)

---

### Option 3: Create Custom Override File

**File**: `onyx-repo/deployment/docker_compose/docker-compose.vespa-ui.yml` (new file)

**Step 1: Create override file**

```bash
cd /Users/chihebmhamdi/Desktop/onyx/onyx-repo/deployment/docker_compose

cat > docker-compose.vespa-ui.yml << 'EOF'
# Vespa UI Override
# Usage: docker compose -f docker-compose.yml -f docker-compose.vespa-ui.yml up -d

services:
  index:
    ports:
      - "19071:19071"  # Vespa Admin UI
      - "8081:8081"    # Vespa Query API
EOF
```

**Step 2: Start with override**

```bash
# Start with Vespa UI override
docker compose -f docker-compose.yml -f docker-compose.vespa-ui.yml up -d

# Access UI
http://localhost:19071
```

**Pros:**
- ✅ Doesn't modify existing files
- ✅ Can be version controlled
- ✅ Easy to enable/disable

**Cons:**
- ❌ Need to remember to use both files

---

### Option 4: Use Docker Port Forward (No Changes)

**No compose file changes needed!**

**Step 1: Find container name**

```bash
# Get Vespa container name
docker ps | grep vespa

# Or
docker compose ps | grep index
```

**Step 2: Port forward**

```bash
# Port forward (replace <container-name> with actual name)
docker port <container-name> 19071

# Or use docker exec to access directly
docker exec -it <container-name> curl http://localhost:19071
```

**Step 3: Access via port forward**

```bash
# If you need external access, use socat or similar
# Or just access from within container
docker exec -it <container-name> bash
# Then: curl http://localhost:19071
```

**Pros:**
- ✅ No compose file changes
- ✅ Secure (container-only access)

**Cons:**
- ❌ Not ideal for browser access
- ❌ Requires additional tools

---

## 🚀 Quick Start: Docker Compose

### Recommended: Use Dev Override

```bash
cd /Users/chihebmhamdi/Desktop/onyx/onyx-repo/deployment/docker_compose

# Start with dev override (exposes Vespa ports)
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d

# Wait for Vespa to be ready (may take 1-2 minutes)
docker compose logs -f index

# Access Vespa UI
open http://localhost:19071
# Or
curl http://localhost:19071
```

### Verify Vespa is Running

```bash
# Check container status
docker compose ps index

# Check logs
docker compose logs index | tail -20

# Test health endpoint
curl http://localhost:19071/state/v1/health
```

**Expected Response:**
```json
{
  "status": {
    "code": "up"
  }
}
```

---

## 📋 Docker Compose Summary

### What You Need to Do

**Option 1 (Recommended): Use existing dev override**
```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
# Access: http://localhost:19071
```

**Option 2: Uncomment ports in main file**
- Edit `docker-compose.yml`
- Uncomment ports section for `index` service
- Restart: `docker compose restart index`
- Access: `http://localhost:19071`

**Option 3: Create custom override**
- Create `docker-compose.vespa-ui.yml`
- Start: `docker compose -f docker-compose.yml -f docker-compose.vespa-ui.yml up -d`
- Access: `http://localhost:19071`

### Ports Exposed

| Port | Service | Access URL |
|------|---------|------------|
| `19071` | Vespa Admin UI | `http://localhost:19071` |
| `8081` | Vespa Query API | `http://localhost:8081` |

---

## 🔍 Troubleshooting Docker Compose

### Port Already in Use

**Error**: `Bind for 0.0.0.0:19071 failed: port is already allocated`

**Solution**:
```bash
# Find what's using the port
lsof -i :19071
# Or
netstat -an | grep 19071

# Kill the process or change port in compose file
# Change to: "19072:19071" (host:container)
```

### Vespa Not Starting

**Check logs**:
```bash
docker compose logs index
```

**Common issues**:
- Insufficient memory (Vespa needs at least 2GB)
- Port conflicts
- Volume permissions

**Fix**:
```bash
# Restart Vespa
docker compose restart index

# Or recreate
docker compose up -d --force-recreate index
```

### Can't Access UI

**Verify ports are exposed**:
```bash
# Check if ports are mapped
docker compose ps index

# Should show: 0.0.0.0:19071->19071/tcp
```

**Test from container**:
```bash
# Access container
docker compose exec index bash

# Test from inside
curl http://localhost:19071/state/v1/health
```

---

**Last Updated**: 2024  
**Version**: 1.1 (Added Docker Compose section)

