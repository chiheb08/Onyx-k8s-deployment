# NGINX ConfigMap Mounting Issue - Deep Analysis

**Problem:** NGINX can't resolve `web-server:3000` even though services are deployed

---

## 🔍 Root Cause Analysis

### The Issue: ConfigMap Mounting Problem

Looking at the NGINX deployment YAML:

```yaml
volumeMounts:
  - name: nginx-config
    mountPath: /etc/nginx/nginx.conf  ← PROBLEM HERE!
    subPath: nginx.conf
```

**What's happening:**
1. The ConfigMap contains the nginx.conf content
2. It's being mounted to `/etc/nginx/nginx.conf`
3. But NGINX expects the main config file to be `/etc/nginx/nginx.conf`
4. The ConfigMap content is **replacing** the entire nginx.conf file
5. This breaks NGINX's default configuration structure

### The NGINX ConfigMap Content Issue

```yaml
data:
  nginx.conf: |
    events {
        worker_connections 1024;
    }
    http {
        upstream web_server {
            server web-server:3000;  ← This is correct
        }
        # ... rest of config
    }
```

**The problem:** This is a **complete nginx.conf replacement**, not just the server block.

---

## 🎯 The Real Issues

### Issue 1: ConfigMap Mounting Path
```yaml
# ❌ WRONG - Replaces entire nginx.conf
mountPath: /etc/nginx/nginx.conf
subPath: nginx.conf

# ✅ CORRECT - Mount as separate config file
mountPath: /etc/nginx/conf.d/
subPath: nginx.conf
```

### Issue 2: Missing Default NGINX Configuration
The current ConfigMap **replaces** the entire nginx.conf, but NGINX needs:
- Default modules
- Default error handling
- Default MIME types
- Default log formats

### Issue 3: OpenShift DNS Resolution
In OpenShift, service resolution might need:
- Full DNS names: `web-server.namespace.svc.cluster.local`
- Or proper namespace context

---

## 🔧 Solutions

### Solution 1: Fix ConfigMap Mounting (Recommended)

Change the NGINX deployment to mount the config in the correct location:

```yaml
volumeMounts:
  - name: nginx-config
    mountPath: /etc/nginx/conf.d/default.conf  ← Mount as server config
    subPath: nginx.conf
```

And update the ConfigMap to contain only the server block:

```yaml
data:
  nginx.conf: |
    upstream web_server {
        server web-server:3000;
    }

    upstream api_server {
        server api-server:8080;
    }

    server {
        listen 80;
        server_name _;
        
        # ... rest of server configuration
    }
```

### Solution 2: Complete nginx.conf (Alternative)

Keep the current mounting but provide a complete nginx.conf:

```yaml
data:
  nginx.conf: |
    user nginx;
    worker_processes auto;
    error_log /var/log/nginx/error.log notice;
    pid /var/run/nginx.pid;

    events {
        worker_connections 1024;
    }

    http {
        include /etc/nginx/mime.types;
        default_type application/octet-stream;
        
        log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                        '$status $body_bytes_sent "$http_referer" '
                        '"$http_user_agent" "$http_x_forwarded_for"';

        access_log /var/log/nginx/access.log main;

        sendfile on;
        tcp_nopush on;
        keepalive_timeout 65;
        types_hash_max_size 4096;

        # Include default server configs
        include /etc/nginx/conf.d/*.conf;

        upstream web_server {
            server web-server:3000;
        }

        upstream api_server {
            server api-server:8080;
        }

        server {
            listen 80;
            server_name _;
            
            # ... rest of configuration
        }
    }
```

### Solution 3: Use Full DNS Names (OpenShift Specific)

For OpenShift, use full DNS names:

```yaml
upstream web_server {
    server web-server.onyx-infra.svc.cluster.local:3000;
}

upstream api_server {
    server api-server.onyx-infra.svc.cluster.local:8080;
}
```

---

## 🚀 Recommended Fix

### Step 1: Update NGINX ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  default.conf: |  ← Change key name
    upstream web_server {
        server web-server:3000;
    }

    upstream api_server {
        server api-server:8080;
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

### Step 2: Update NGINX Deployment

```yaml
volumeMounts:
  - name: nginx-config
    mountPath: /etc/nginx/conf.d/default.conf  ← Mount as server config
    subPath: default.conf  ← Match the key name
```

---

## 🔍 Verification Steps

### Check Current ConfigMap
```bash
oc get configmap nginx-config -o yaml
```

### Check NGINX Pod Logs
```bash
oc logs deployment/nginx
```

### Test DNS Resolution from NGINX Pod
```bash
oc exec deployment/nginx -- nslookup web-server
oc exec deployment/nginx -- nslookup api-server
```

### Check NGINX Configuration
```bash
oc exec deployment/nginx -- nginx -t
oc exec deployment/nginx -- cat /etc/nginx/nginx.conf
oc exec deployment/nginx -- cat /etc/nginx/conf.d/default.conf
```

---

## 🎯 Why This Happens in OpenShift

### OpenShift DNS Resolution
- Services are resolved within the same namespace by default
- If NGINX is in a different namespace, it needs full DNS names
- OpenShift might have stricter DNS resolution policies

### ConfigMap Mounting
- OpenShift might handle ConfigMap mounting differently
- The default nginx.conf structure is important for proper startup
- Mounting to `/etc/nginx/nginx.conf` replaces critical default configuration

---

## ✅ Summary

**The Problem:** ConfigMap is mounted incorrectly, replacing the entire nginx.conf instead of adding server configuration.

**The Solution:** Mount the ConfigMap as `/etc/nginx/conf.d/default.conf` instead of `/etc/nginx/nginx.conf`.

**Quick Fix:**
1. Change ConfigMap key from `nginx.conf` to `default.conf`
2. Change mountPath from `/etc/nginx/nginx.conf` to `/etc/nginx/conf.d/default.conf`
3. Update subPath to match the new key name

This preserves NGINX's default configuration while adding your custom server blocks! 🎯
