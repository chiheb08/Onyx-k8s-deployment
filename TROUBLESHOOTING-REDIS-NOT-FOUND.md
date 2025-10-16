# Troubleshooting: Redis Deployment Not Found

**Error:** `Resource not found in cluster: apps/v1/Deployment:redis`

This error means the Redis deployment doesn't exist in your cluster yet.

---

## 🔍 Understanding the Error

### What the Error Means

```
Resource not found in cluster: apps/v1/Deployment:redis
│                    │        │              │
│                    │        │              └─ Resource name
│                    │        └─ Resource type
│                    └─ Location (your cluster)
└─ Problem: Resource doesn't exist
```

**Translation:** 
- Your dashboard/UI is looking for a Redis deployment
- The deployment named "redis" doesn't exist in your cluster
- You need to create it first

---

## 🔧 Solutions

### Solution 1: Deploy Redis (Most Common)

**The Redis deployment hasn't been created yet. Deploy it:**

```bash
# Deploy Redis
kubectl apply -f 04-redis.yaml

# Check if it was created
kubectl get deployment redis

# Check pod status
kubectl get pods -l app=redis
```

**Expected output:**
```bash
# After deployment:
NAME    READY   UP-TO-DATE   AVAILABLE   AGE
redis   1/1     1            1           30s

# Pod status:
NAME                    READY   STATUS    RESTARTS   AGE
redis-xxxxxxxxx-xxxxx   1/1     Running   0          30s
```

---

### Solution 2: Check Current Namespace

**Make sure you're in the right namespace:**

```bash
# Check current namespace
kubectl config get-contexts

# Check if Redis exists in current namespace
kubectl get deployment redis

# If not found, check all namespaces
kubectl get deployment redis --all-namespaces

# Switch to correct namespace if needed
kubectl config set-context --current --namespace=your-namespace
```

---

### Solution 3: Verify YAML File

**Check if the Redis YAML file exists and is correct:**

```bash
# Check if file exists
ls -la 04-redis.yaml

# View the file content
cat 04-redis.yaml

# Validate YAML syntax
kubectl apply --dry-run=client -f 04-redis.yaml
```

**Expected output:**
```bash
# File should exist and be valid:
deployment.apps/redis created (dry run)
service/redis created (dry run)
secret/redis-secret created (dry run)
```

---

### Solution 4: Deploy All Services in Order

**Deploy services in the correct order:**

```bash
# 1. Deploy infrastructure first
kubectl apply -f 02-postgresql.yaml
kubectl apply -f 03-vespa.yaml
kubectl apply -f 04-redis.yaml

# 2. Wait for them to be ready
kubectl get pods -w

# 3. Deploy configuration
kubectl apply -f 05-configmap.yaml

# 4. Deploy applications
kubectl apply -f 06-inference-model-server.yaml
kubectl apply -f 07-api-server.yaml
kubectl apply -f 08-web-server.yaml
kubectl apply -f 09-nginx.yaml
```

**Or use the automated script:**
```bash
# Deploy everything in order
./deploy.sh
```

---

## 🔍 Diagnosis Commands

### Check What Exists

```bash
# Check all deployments in current namespace
kubectl get deployments

# Check all pods
kubectl get pods

# Check all services
kubectl get services

# Check if Redis exists anywhere
kubectl get deployment redis --all-namespaces
```

### Check Namespace

```bash
# Check current namespace
kubectl config get-contexts

# List all namespaces
kubectl get namespaces

# Check resources in specific namespace
kubectl get deployments -n your-namespace
```

### Check YAML Files

```bash
# List all YAML files
ls -la *.yaml

# Check Redis YAML specifically
cat 04-redis.yaml | head -20

# Validate YAML syntax
kubectl apply --dry-run=client -f 04-redis.yaml
```

---

## 🎯 Common Scenarios

### Scenario 1: Haven't Deployed Yet

**Problem:** You're looking at a dashboard but haven't deployed Redis yet.

**Solution:**
```bash
kubectl apply -f 04-redis.yaml
kubectl get deployment redis
```

### Scenario 2: Wrong Namespace

**Problem:** Redis exists but in a different namespace.

**Solution:**
```bash
# Find Redis
kubectl get deployment redis --all-namespaces

# Switch to correct namespace
kubectl config set-context --current --namespace=redis-namespace
```

### Scenario 3: Deployment Failed

**Problem:** You tried to deploy but it failed.

**Solution:**
```bash
# Check for errors
kubectl get events --sort-by=.metadata.creationTimestamp

# Check pod status
kubectl get pods -l app=redis

# Check pod logs
kubectl logs -l app=redis
```

### Scenario 4: YAML File Issues

**Problem:** The YAML file has syntax errors.

**Solution:**
```bash
# Validate YAML
kubectl apply --dry-run=client -f 04-redis.yaml

# Check file permissions
ls -la 04-redis.yaml

# Re-download if needed
git pull origin main
```

---

## 🚀 Quick Fix Workflow

```bash
# 1. Check if Redis exists
kubectl get deployment redis

# 2. If not found, deploy it
kubectl apply -f 04-redis.yaml

# 3. Verify deployment
kubectl get deployment redis
kubectl get pods -l app=redis

# 4. Check if it's running
kubectl get pods -l app=redis
# Should show: Running ✅

# 5. If still issues, check logs
kubectl logs -l app=redis
```

---

## 📊 Expected Redis Configuration

**Your Redis deployment should have:**

```yaml
# From 04-redis.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  labels:
    app: redis
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7.4-alpine
        ports:
        - containerPort: 6379
        env:
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: redis-secret
              key: REDIS_PASSWORD
```

**Resources created:**
- ✅ Deployment: `redis`
- ✅ Service: `redis`
- ✅ Secret: `redis-secret`

---

## ⚠️ Troubleshooting Tips

### If Deployment Still Fails

```bash
# Check for resource conflicts
kubectl get all -l app=redis

# Check for storage issues
kubectl get pvc

# Check for SCC issues (OpenShift)
kubectl describe pod -l app=redis

# Check events
kubectl get events --sort-by=.metadata.creationTimestamp
```

### If Pod Won't Start

```bash
# Check pod status
kubectl get pods -l app=redis

# Check pod details
kubectl describe pod -l app=redis

# Check logs
kubectl logs -l app=redis

# Check if image can be pulled
kubectl describe pod -l app=redis | grep -i image
```

---

## 📝 Summary

**Root cause:** Redis deployment doesn't exist in your cluster

**Quick fix:**
```bash
kubectl apply -f 04-redis.yaml
kubectl get deployment redis
```

**Verify:**
```bash
kubectl get pods -l app=redis
# Should show: Running ✅
```

**If still failing:**
```bash
kubectl logs -l app=redis
kubectl describe pod -l app=redis
```

---

**This is a simple "resource not found" error - just deploy Redis and it will work!**
