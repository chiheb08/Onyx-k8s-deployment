# WebServer Deployment Analysis - DNS Resolution Issues

**Issue:** Still getting "host not found in upstream web-server:3000" error

**Analysis of your webserver deployment YAML:**

---

## 🔍 Issues Identified in Your WebServer Deployment

### Issue 1: Missing Service Definition
Your YAML shows a `Deployment` but **no corresponding `Service`**!

```yaml
# You have this (Deployment):
kind: Deployment
metadata:
  name: webserver  ← This is the deployment name
```

**But NGINX is looking for:**
```nginx
upstream web_server {
    server web-server:3000;  ← Looking for service named "web-server"
}
```

**The Problem:** 
- Your deployment is named `webserver`
- But NGINX is looking for service `web-server`
- **No service exists to resolve the DNS name!**

### Issue 2: Service Name Mismatch
- **Deployment name:** `webserver`
- **NGINX expects:** `web-server`
- **Missing:** Service definition entirely

### Issue 3: Image Version Mismatch
Your deployment uses:
```yaml
image: 'onyxdotapp/onyx-web-server:v2.0.0-beta.2'
```

But our NGINX config expects the service to be available on port 3000.

---

## 🔧 Solutions

### Solution 1: Create Missing Service (Recommended)

Create a service that matches what NGINX expects:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-server  ← This matches NGINX expectation
  labels:
    app: webserver
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 3000
      targetPort: 3000
      protocol: TCP
  selector:
    io.kompose.service: webserver  ← Matches your deployment selector
```

### Solution 2: Update NGINX Config to Match Your Deployment

If you want to keep your current deployment name, update NGINX config:

```nginx
upstream web_server {
    server webserver:3000;  ← Change to match your deployment name
}
```

### Solution 3: Complete WebServer YAML with Service

Here's the complete YAML you need:

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: web-server
  labels:
    app: webserver
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 3000
      targetPort: 3000
      protocol: TCP
  selector:
    io.kompose.service: webserver

---
kind: Deployment
apiVersion: apps/v1
metadata:
  name: webserver
spec:
  replicas: 1
  selector:
    matchLabels:
      io.kompose.service: webserver
  strategy:
    type: Recreate
    revisionHistoryLimit: 3
  template:
    metadata:
      labels:
        io.kompose.service: webserver
    spec:
      containers:
        - resources:
            limits:
              cpu: 1000m
              memory: 1Gi
            requests:
              cpu: 200m
              memory: 512Mi
          name: webserver
          ports:
            - containerPort: 3000
              protocol: TCP
          imagePullPolicy: IfNotPresent
          image: 'onyxdotapp/onyx-web-server:v2.0.0-beta.2'
```

---

## 🚀 Quick Fix Commands

### Option 1: Create the Missing Service
```bash
# Create service for your existing deployment
oc apply -f - << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: web-server
  labels:
    app: webserver
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 3000
      targetPort: 3000
      protocol: TCP
  selector:
    io.kompose.service: webserver
EOF
```

### Option 2: Update NGINX ConfigMap
```bash
# Update NGINX to use your deployment name
oc patch configmap nginx-config --patch '{
  "data": {
    "default.conf": "upstream web_server {\n    server webserver:3000;\n}\n\nupstream api_server {\n    server api-server:8080;\n}\n\nserver {\n    listen 80;\n    server_name _;\n    \n    location /api/ {\n        proxy_pass http://api_server;\n        proxy_set_header Host $host;\n        proxy_set_header X-Real-IP $remote_addr;\n        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n        proxy_set_header X-Forwarded-Proto $scheme;\n    }\n    \n    location / {\n        proxy_pass http://web_server;\n        proxy_set_header Host $host;\n        proxy_set_header X-Real-IP $remote_addr;\n        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n        proxy_set_header X-Forwarded-Proto $scheme;\n    }\n}"
  }
}'

# Restart NGINX
oc rollout restart deployment/nginx
```

---

## 🔍 Verification Steps

### Check if Service Exists
```bash
# Check for web-server service
oc get service web-server

# Check for webserver service
oc get service webserver

# List all services
oc get services
```

### Check Deployment Status
```bash
# Check if webserver deployment is running
oc get deployment webserver
oc get pods -l io.kompose.service=webserver
```

### Test DNS Resolution
```bash
# Test from NGINX pod
oc exec deployment/nginx -c nginx -- nslookup web-server
oc exec deployment/nginx -c nginx -- nslookup webserver
```

---

## ✅ Summary

**The Root Cause:** Your webserver deployment exists, but there's **no corresponding service** for NGINX to connect to!

**The Solution:** Create a service named `web-server` that points to your `webserver` deployment.

**Quick Fix:** Apply the service YAML above, then restart NGINX.

This should resolve the DNS resolution issue! 🎯
