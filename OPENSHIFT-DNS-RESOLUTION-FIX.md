# OpenShift DNS Resolution Issue - Complete Solution

**Error:** `host not found in upstream "web-server:3000" in /etc/nginx/conf.d/default.conf:2`

**Status:** ConfigMap mounting fixed ✅, but DNS resolution still failing ❌

---

## 🔍 Current Status Analysis

### What's Working
✅ ConfigMap mounting fix worked - NGINX now reads from `/etc/nginx/conf.d/default.conf:2`
✅ NGINX configuration structure is correct
✅ Services are deployed in correct order

### What's Still Failing
❌ DNS resolution of `web-server:3000` in OpenShift cluster
❌ NGINX can't find the upstream service

---

## 🎯 Root Cause: OpenShift DNS Resolution

### The Problem
In OpenShift, service DNS resolution can be more restrictive than standard Kubernetes:

1. **Namespace Isolation:** Services might not be resolvable across namespaces
2. **DNS Policy:** OpenShift might have stricter DNS resolution policies
3. **Service Discovery:** The service might not be properly registered in DNS
4. **Timing:** Services might not be fully ready when NGINX starts

---

## 🔧 Solutions (Try in Order)

### Solution 1: Use Full DNS Names (Recommended)

Update the NGINX ConfigMap to use full DNS names:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  default.conf: |
    upstream web_server {
        server web-server.onyx-infra.svc.cluster.local:3000;
    }

    upstream api_server {
        server api-server.onyx-infra.svc.cluster.local:8080;
    }

    server {
        listen 80;
        server_name _;
        
        # ... rest of configuration
    }
```

### Solution 2: Add initContainer to Wait for Services

Add an initContainer to the NGINX deployment to wait for services:

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
              echo "web-server is ready!"
              
              echo "Waiting for api-server..."
              until nslookup api-server; do
                echo "api-server not ready, waiting..."
                sleep 2
              done
              echo "api-server is ready!"
              
              echo "All services are ready!"
      containers:
        - name: nginx
          # ... rest of nginx config
```

### Solution 3: Use IP Addresses (Temporary)

Get the actual IP addresses of services and use them directly:

```bash
# Get service IPs
oc get services -o wide

# Use IPs in ConfigMap (temporary solution)
upstream web_server {
    server 10.96.123.45:3000;  # Replace with actual IP
}
```

### Solution 4: Add DNS Configuration

Add DNS configuration to the NGINX deployment:

```yaml
spec:
  template:
    spec:
      dnsPolicy: ClusterFirst
      dnsConfig:
        options:
          - name: ndots
            value: "2"
          - name: edns0
      containers:
        - name: nginx
          # ... rest of config
```

---

## 🚀 Recommended Fix (Solution 1 + 2)

### Step 1: Update NGINX ConfigMap with Full DNS Names

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  default.conf: |
    upstream web_server {
        server web-server.onyx-infra.svc.cluster.local:3000;
    }

    upstream api_server {
        server api-server.onyx-infra.svc.cluster.local:8080;
    }

    server {
        listen 80;
        server_name _;

        # Increase buffer sizes for large headers
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
        large_client_header_buffers 4 16k;

        # API requests
        location /api/ {
            proxy_pass http://api_server;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_cache_bypass $http_upgrade;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Timeouts
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }

        # WebSocket support for API
        location /api/stream {
            proxy_pass http://api_server;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Disable buffering for streaming
            proxy_buffering off;
            proxy_cache off;
            
            # Long timeout for streaming
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
        }

        # All other requests go to web server (Next.js)
        location / {
            proxy_pass http://web_server;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_cache_bypass $http_upgrade;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Timeouts
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }

        # Health check endpoint
        location /nginx-health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
```

### Step 2: Add initContainer to NGINX Deployment

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
              until nslookup web-server.onyx-infra.svc.cluster.local; do
                echo "web-server not ready, waiting..."
                sleep 2
              done
              echo "web-server is ready!"
              
              echo "Waiting for api-server..."
              until nslookup api-server.onyx-infra.svc.cluster.local; do
                echo "api-server not ready, waiting..."
                sleep 2
              done
              echo "api-server is ready!"
              
              echo "All services are ready!"
      containers:
        - name: nginx
          image: nginx:1.23.4-alpine
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 80
              protocol: TCP
          volumeMounts:
            - name: nginx-config
              mountPath: /etc/nginx/conf.d/default.conf
              subPath: default.conf
          # ... rest of config
```

---

## 🔍 Verification Steps

### Check Services Exist and Are Running
```bash
# Check all services
oc get services

# Check service endpoints
oc get endpoints

# Check pods are running
oc get pods
```

### Test DNS Resolution
```bash
# Test from a debug pod
oc run debug --image=busybox:1.35 --rm -it -- nslookup web-server.onyx-infra.svc.cluster.local

# Test from NGINX pod (after it starts)
oc exec deployment/nginx -- nslookup web-server.onyx-infra.svc.cluster.local
```

### Check NGINX Configuration
```bash
# Test NGINX configuration
oc exec deployment/nginx -- nginx -t

# View the actual config
oc exec deployment/nginx -- cat /etc/nginx/conf.d/default.conf
```

---

## 🐛 Troubleshooting Commands

### If Services Don't Exist
```bash
# Check if services are deployed
oc get services | grep -E "(web-server|api-server)"

# If missing, redeploy them
oc apply -f 08-web-server.yaml
oc apply -f 07-api-server.yaml
```

### If DNS Resolution Fails
```bash
# Check DNS configuration
oc get pods -o yaml | grep -A 5 dnsConfig

# Check CoreDNS
oc get pods -n kube-system | grep dns
```

### If Services Are in Different Namespace
```bash
# Check current namespace
oc project

# List all namespaces
oc get namespaces

# Check services in other namespaces
oc get services --all-namespaces | grep -E "(web-server|api-server)"
```

---

## 🎯 Quick Fix Commands

### Option 1: Use Full DNS Names
```bash
# Update ConfigMap with full DNS names
oc patch configmap nginx-config --patch '{
  "data": {
    "default.conf": "upstream web_server {\n    server web-server.onyx-infra.svc.cluster.local:3000;\n}\n\nupstream api_server {\n    server api-server.onyx-infra.svc.cluster.local:8080;\n}\n\nserver {\n    listen 80;\n    server_name _;\n    \n    location /api/ {\n        proxy_pass http://api_server;\n        proxy_set_header Host $host;\n        proxy_set_header X-Real-IP $remote_addr;\n        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n        proxy_set_header X-Forwarded-Proto $scheme;\n    }\n    \n    location / {\n        proxy_pass http://web_server;\n        proxy_set_header Host $host;\n        proxy_set_header X-Real-IP $remote_addr;\n        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n        proxy_set_header X-Forwarded-Proto $scheme;\n    }\n}"
  }
}'

# Restart NGINX
oc rollout restart deployment/nginx
```

### Option 2: Add initContainer
```bash
# Add initContainer to wait for services
oc patch deployment nginx --patch '{
  "spec": {
    "template": {
      "spec": {
        "initContainers": [
          {
            "name": "wait-for-services",
            "image": "busybox:1.35",
            "command": ["sh", "-c"],
            "args": [
              "until nslookup web-server.onyx-infra.svc.cluster.local; do sleep 2; done; until nslookup api-server.onyx-infra.svc.cluster.local; do sleep 2; done; echo \"All services ready!\""
            ]
          }
        ]
      }
    }
  }
}'
```

---

## ✅ Summary

**The Issue:** OpenShift DNS resolution is more restrictive than standard Kubernetes.

**The Solution:** Use full DNS names (`service.namespace.svc.cluster.local`) instead of short names.

**Quick Fix:**
1. Update ConfigMap to use full DNS names
2. Add initContainer to wait for services
3. Restart NGINX deployment

This should resolve the DNS resolution issue in OpenShift! 🎯
