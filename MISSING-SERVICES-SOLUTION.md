# Missing Services Solution - Complete Fix

**Problem:** NGINX can't resolve `web-server:3000` and `api-server:8080` because the services don't exist!

**Root Cause:** You have deployments but no corresponding services for NGINX to connect to.

---

## 🔍 The Complete Problem

### What NGINX Expects
```nginx
upstream web_server {
    server web-server:3000;  ← Needs SERVICE named "web-server"
}

upstream api_server {
    server api-server:8080;  ← Needs SERVICE named "api-server"
}
```

### What You Have
- ✅ `webserver` deployment (but no service)
- ✅ `api-server` deployment (but no service)
- ❌ No `web-server` service
- ❌ No `api-server` service

---

## 🔧 Complete Solution

### Step 1: Create Web Server Service

**File:** `08-web-server-service.yaml`
```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-server  ← Matches NGINX expectation
  labels:
    app: web-server
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 3000
      targetPort: 3000
      protocol: TCP
  selector:
    app: web-server  ← Points to your web-server deployment
```

### Step 2: Create API Server Service

**File:** `07-api-server-service.yaml`
```yaml
apiVersion: v1
kind: Service
metadata:
  name: api-server  ← Matches NGINX expectation
  labels:
    app: api-server
spec:
  type: ClusterIP
  ports:
    - name: api-server-port
      port: 8080
      targetPort: 8080
      protocol: TCP
  selector:
    app: api-server  ← Points to your api-server deployment
```

---

## 🚀 Deployment Commands

### Deploy the Missing Services
```bash
# Deploy web-server service
oc apply -f 08-web-server-service.yaml

# Deploy api-server service
oc apply -f 07-api-server-service.yaml

# Verify services exist
oc get services | grep -E "(web-server|api-server)"

# Check service endpoints
oc get endpoints web-server
oc get endpoints api-server
```

### Restart NGINX
```bash
# Restart NGINX to pick up the new services
oc rollout restart deployment/nginx

# Check NGINX logs
oc logs deployment/nginx -c nginx

# Test DNS resolution from NGINX pod
oc exec deployment/nginx -c nginx -- nslookup web-server
oc exec deployment/nginx -c nginx -- nslookup api-server
```

---

## 🔍 Verification Steps

### Check Services Are Created
```bash
# List all services
oc get services

# Should see:
# NAME          TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
# web-server    ClusterIP   10.96.123.45   <none>        3000/TCP   1m
# api-server    ClusterIP   10.96.123.46   <none>        8080/TCP   1m
```

### Check Service Endpoints
```bash
# Check if services have endpoints (pods backing them)
oc get endpoints web-server
oc get endpoints api-server

# Should show pods as endpoints
```

### Test DNS Resolution
```bash
# Test from NGINX pod
oc exec deployment/nginx -c nginx -- nslookup web-server
oc exec deployment/nginx -c nginx -- nslookup api-server

# Should return IP addresses, not errors
```

### Check NGINX Configuration
```bash
# Test NGINX configuration
oc exec deployment/nginx -c nginx -- nginx -t

# Should return: "nginx: configuration file /etc/nginx/nginx.conf test is successful"
```

---

## 🎯 Complete Deployment Order

### Correct Order for All Components
```bash
# 1. Deploy services first
oc apply -f 08-web-server-service.yaml
oc apply -f 07-api-server-service.yaml

# 2. Deploy applications
oc apply -f 08-web-server.yaml
oc apply -f 07-api-server.yaml

# 3. Wait for applications to be ready
oc wait --for=condition=Ready pod -l app=web-server --timeout=60s
oc wait --for=condition=Ready pod -l app=api-server --timeout=60s

# 4. Deploy NGINX
oc apply -f 09-nginx.yaml

# 5. Verify everything works
oc get pods
oc get services
oc logs deployment/nginx -c nginx
```

---

## 🐛 Troubleshooting

### If Services Still Don't Work
```bash
# Check if deployments exist
oc get deployments

# Check if pods are running
oc get pods -l app=web-server
oc get pods -l app=api-server

# Check service selectors match deployment labels
oc describe service web-server
oc describe service api-server
```

### If DNS Resolution Still Fails
```bash
# Check if services have endpoints
oc get endpoints

# Test DNS from a debug pod
oc run debug --image=busybox:1.35 --rm -it -- nslookup web-server
oc run debug --image=busybox:1.35 --rm -it -- nslookup api-server
```

---

## ✅ Summary

**The Problem:** Missing services that NGINX needs to connect to your deployments.

**The Solution:** Create services that match what NGINX expects:
- `web-server` service → `web-server:3000`
- `api-server` service → `api-server:8080`

**The Result:** NGINX can now resolve both services and proxy traffic correctly! 🎯

---

## 📋 Quick Checklist

- [ ] Deploy `08-web-server-service.yaml`
- [ ] Deploy `07-api-server-service.yaml`
- [ ] Verify services exist: `oc get services`
- [ ] Verify endpoints exist: `oc get endpoints`
- [ ] Restart NGINX: `oc rollout restart deployment/nginx`
- [ ] Test DNS resolution: `oc exec deployment/nginx -c nginx -- nslookup web-server`
- [ ] Check NGINX logs: `oc logs deployment/nginx -c nginx`

All done! The DNS resolution error should be completely resolved! ✅
