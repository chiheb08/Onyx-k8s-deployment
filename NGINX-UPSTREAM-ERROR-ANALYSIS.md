# NGINX Upstream Error - Deep Investigation & Solution

**Error:** `host not found in upstream "web-server:3000" in /etc/nginx/nginx.conf:7`

---

## 🔍 Root Cause Analysis

### The Error Explained

```
2025/10/16 13:52:59 [emerg] 1#1: host not found in upstream "web-server:3000" in /etc/nginx/nginx.conf:7
nginx: [emerg] host not found in upstream "web-server:3000" in /etc/nginx/nginx.conf:7
```

**What this means:**
- NGINX is trying to start
- It reads the configuration from `/etc/nginx/nginx.conf`
- At line 7, it finds: `server web-server:3000;`
- It tries to resolve the hostname `web-server:3000`
- **DNS resolution fails** - the service doesn't exist yet!

### Why This Happens

**NGINX Configuration (line 21-23):**
```nginx
upstream web_server {
    server web-server:3000;  ← This is line 7 in the error!
}
```

**The Problem:**
1. You deployed NGINX first
2. NGINX tries to resolve `web-server:3000` at startup
3. The `web-server` service doesn't exist yet
4. Kubernetes DNS can't resolve the hostname
5. NGINX fails to start with `[emerg]` error

---

## 🎯 The Real Issue: Deployment Order

### What You Did (Wrong Order)
```
1. Deploy NGINX ✅ (starts first)
2. NGINX tries to resolve web-server:3000 ❌ (doesn't exist!)
3. Deploy web-server (too late - NGINX already failed)
```

### What Should Happen (Correct Order)
```
1. Deploy web-server ✅ (creates web-server service)
2. Deploy api-server ✅ (creates api-server service)  
3. Deploy NGINX ✅ (can now resolve both services)
```

---

## 🔧 Solutions (3 Options)

### Solution 1: Deploy in Correct Order (Recommended)

```bash
# Step 1: Deploy backend services first
kubectl apply -f 08-web-server.yaml
kubectl apply -f 07-api-server.yaml

# Wait for services to be ready
kubectl get services
# Should see: web-server and api-server

# Step 2: Then deploy NGINX
kubectl apply -f 09-nginx.yaml

# Step 3: Verify NGINX starts successfully
kubectl get pods -l app=nginx
kubectl logs deployment/nginx
```

### Solution 2: Use initContainer to Wait for Services

Add this to the NGINX deployment:

```yaml
spec:
  template:
    spec:
      initContainers:
        - name: wait-for-services
          image: busybox:1.35
          command: ['sh', '-c']
          args:
            - |
              echo "Waiting for web-server..."
              until nslookup web-server; do
                echo "web-server not ready, waiting..."
                sleep 2
              done
              echo "Waiting for api-server..."
              until nslookup api-server; do
                echo "api-server not ready, waiting..."
                sleep 2
              done
              echo "All services ready!"
      containers:
        - name: nginx
          # ... rest of nginx config
```

### Solution 3: Use NGINX Dynamic Upstream (Advanced)

Modify the NGINX config to use variables:

```nginx
upstream web_server {
    server web-server:3000 max_fails=3 fail_timeout=30s;
}

upstream api_server {
    server api-server:8080 max_fails=3 fail_timeout=30s;
}
```

---

## 🚀 Quick Fix (Immediate Solution)

### If You're Using kubectl/oc:

```bash
# 1. Delete the failing NGINX deployment
kubectl delete -f 09-nginx.yaml

# 2. Deploy web-server and api-server first
kubectl apply -f 08-web-server.yaml
kubectl apply -f 07-api-server.yaml

# 3. Wait for services to be ready (30 seconds)
sleep 30

# 4. Check services exist
kubectl get services | grep -E "(web-server|api-server)"

# 5. Deploy NGINX again
kubectl apply -f 09-nginx.yaml

# 6. Check NGINX starts successfully
kubectl get pods -l app=nginx
kubectl logs deployment/nginx
```

### If You're Using Docker Compose:

```bash
# 1. Stop everything
docker-compose down

# 2. Start services in correct order
docker-compose up -d web-server api-server

# 3. Wait for services to be ready
sleep 30

# 4. Start NGINX
docker-compose up -d nginx

# 5. Check logs
docker-compose logs nginx
```

---

## 🔍 Verification Steps

### Check Services Exist
```bash
# List all services
kubectl get services

# Should see:
# NAME          TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
# web-server    ClusterIP   10.96.123.45   <none>        3000/TCP   2m
# api-server    ClusterIP   10.96.123.46   <none>        8080/TCP   2m
# nginx         ClusterIP   10.96.123.47   <none>        80/TCP     1m
```

### Check NGINX Can Resolve Services
```bash
# Test DNS resolution from NGINX pod
kubectl exec deployment/nginx -- nslookup web-server
kubectl exec deployment/nginx -- nslookup api-server

# Should return IP addresses, not errors
```

### Check NGINX Configuration
```bash
# View the actual NGINX config
kubectl exec deployment/nginx -- cat /etc/nginx/nginx.conf

# Test configuration
kubectl exec deployment/nginx -- nginx -t
```

---

## 📋 Complete Deployment Order

### For Kubernetes/OpenShift:

```bash
# 1. Storage (if using PVCs)
kubectl apply -f storage-setup/01-pv-huggingface-models.yaml
kubectl apply -f storage-setup/02-pvc-huggingface-models.yaml

# 2. Databases
kubectl apply -f 02-postgresql.yaml
kubectl apply -f 03-vespa.yaml
kubectl apply -f 04-redis.yaml

# 3. Configuration
kubectl apply -f 05-configmap.yaml

# 4. Model servers
kubectl apply -f 06-inference-model-server.yaml
kubectl apply -f 06-indexing-model-server.yaml

# 5. Application services (MUST be before NGINX!)
kubectl apply -f 07-api-server.yaml
kubectl apply -f 08-web-server.yaml

# 6. Wait for services to be ready
kubectl get services
# Verify: web-server and api-server exist

# 7. Finally, deploy NGINX
kubectl apply -f 09-nginx.yaml

# 8. Create external access
kubectl expose svc/nginx
```

### For Docker Compose:

```bash
# Start in dependency order
docker-compose up -d postgresql vespa redis
docker-compose up -d api-server web-server
docker-compose up -d nginx
```

---

## 🐛 Common Mistakes

### Mistake 1: Deploying NGINX First
```bash
# ❌ WRONG - NGINX will fail
kubectl apply -f 09-nginx.yaml
kubectl apply -f 08-web-server.yaml

# ✅ CORRECT - Services first
kubectl apply -f 08-web-server.yaml
kubectl apply -f 09-nginx.yaml
```

### Mistake 2: Not Waiting for Services
```bash
# ❌ WRONG - Services might not be ready
kubectl apply -f 08-web-server.yaml
kubectl apply -f 09-nginx.yaml  # Too fast!

# ✅ CORRECT - Wait for services
kubectl apply -f 08-web-server.yaml
kubectl wait --for=condition=Ready pod -l app=web-server --timeout=60s
kubectl apply -f 09-nginx.yaml
```

### Mistake 3: Wrong Service Names
```bash
# ❌ WRONG - Service doesn't exist
upstream web_server {
    server web-server:3000;  # If service is named differently
}

# ✅ CORRECT - Match actual service name
kubectl get services  # Check actual service names
```

---

## 🎯 Prevention for Future

### Use the Deploy Script
The `deploy.sh` script handles the correct order:

```bash
# This script deploys in the right order
./deploy.sh
```

### Add Health Checks
Add readiness probes to ensure services are truly ready:

```yaml
# In web-server.yaml and api-server.yaml
readinessProbe:
  httpGet:
    path: /health
    port: 3000
  initialDelaySeconds: 10
  periodSeconds: 5
```

### Use initContainers
Add initContainers to wait for dependencies:

```yaml
initContainers:
  - name: wait-for-dependencies
    image: busybox:1.35
    command: ['sh', '-c', 'until nslookup web-server; do sleep 2; done']
```

---

## ✅ Summary

**The Problem:** NGINX tries to resolve `web-server:3000` at startup, but the service doesn't exist yet.

**The Solution:** Deploy services in the correct order:
1. Deploy `web-server` and `api-server` first
2. Wait for them to be ready
3. Then deploy `nginx`

**Quick Fix:**
```bash
kubectl delete -f 09-nginx.yaml
kubectl apply -f 08-web-server.yaml
kubectl apply -f 07-api-server.yaml
sleep 30
kubectl apply -f 09-nginx.yaml
```

This is a **dependency ordering issue**, not a configuration problem! 🎯
