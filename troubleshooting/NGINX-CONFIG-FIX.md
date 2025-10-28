# NGINX Configuration Fix for Logout Problem

## 🚨 **The Problem in Your Current Config**

Looking at your NGINX configuration, I can see the exact issue causing the logout error:

### **What's Missing:**
1. **`proxy_set_header Connection "";`** - This is the KEY fix for the "invalid connection header" error
2. **Connection header is set to "upgrade"** instead of being cleared
3. **Missing proper connection handling** for regular HTTP requests

### **Current Problematic Lines:**
```nginx
# In your /api/ location block:
proxy_set_header Connection 'upgrade';  # ← THIS IS THE PROBLEM!

# In your /api/stream location block:
proxy_set_header Connection "upgrade";  # ← This is OK for WebSocket, but conflicts with regular API calls
```

---

## 🛠️ **The Exact Fix**

Here's your corrected NGINX configuration:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  default.conf: |
    upstream web_server {
        server web-server.bai32-onyx-deployment-onyx-dev-01.svc.cluster.local:3000;
    }
    
    upstream api_server {
        server api-server.bai32-onyx-deployment-onyx-dev-01.svc.cluster.local:8080;
    }
    
    server {
        listen 8000;
        server_name _;
        
        # Increase buffer sizes for large headers
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
        large_client_header_buffers 4 16k;
        client_max_body_size 10M;
        
        # API requests - FIXED VERSION
        location /api/ {
            proxy_pass http://api_server/;
            proxy_http_version 1.1;
            
            # FIX: Clear the Connection header for regular API calls
            proxy_set_header Connection "";
            
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
        
        # WebSocket support for API - SEPARATE LOCATION
        location /api/stream {
            proxy_pass http://api_server/api/stream;
            proxy_http_version 1.1;
            
            # For WebSocket, we DO want upgrade headers
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Long timeout for streaming
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
            
            # Disable buffering for streaming
            proxy_buffering off;
            proxy_cache off;
        }
        
        # All other requests go to web server (Next.js) - FIXED VERSION
        location / {
            proxy_pass http://web_server;
            proxy_http_version 1.1;
            
            # FIX: Clear the Connection header
            proxy_set_header Connection "";
            
            proxy_set_header Upgrade $http_upgrade;
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

---

## 🔧 **Apply the Fix**

### **Method 1: Edit the ConfigMap Directly**
```bash
# Edit your NGINX ConfigMap
oc edit configmap nginx-config

# Replace the content with the fixed version above
# Save and exit
```

### **Method 2: Apply via File**
```bash
# Create the fixed config file
cat > /tmp/nginx-config-fixed.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  default.conf: |
    upstream web_server {
        server web-server.bai32-onyx-deployment-onyx-dev-01.svc.cluster.local:3000;
    }
    
    upstream api_server {
        server api-server.bai32-onyx-deployment-onyx-dev-01.svc.cluster.local:8080;
    }
    
    server {
        listen 8000;
        server_name _;
        
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
        large_client_header_buffers 4 16k;
        client_max_body_size 10M;
        
        location /api/ {
            proxy_pass http://api_server/;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_set_header Host $host;
            proxy_cache_bypass $http_upgrade;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }
        
        location /api/stream {
            proxy_pass http://api_server/api/stream;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
            proxy_buffering off;
            proxy_cache off;
        }
        
        location / {
            proxy_pass http://web_server;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Host $host;
            proxy_cache_bypass $http_upgrade;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }
        
        location /nginx-health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
EOF

# Apply the fixed configuration
oc apply -f /tmp/nginx-config-fixed.yaml
```

### **Step 3: Restart NGINX**
```bash
# Restart NGINX to pick up the new configuration
oc rollout restart deployment/nginx

# Wait for NGINX to be ready
oc get pods -l app=nginx -w
```

---

## 🎯 **Key Changes Made**

### **1. Fixed Connection Header for API Calls:**
```nginx
# BEFORE (causing the error):
proxy_set_header Connection 'upgrade';

# AFTER (fixes the error):
proxy_set_header Connection "";
```

### **2. Separated WebSocket and Regular API Handling:**
```nginx
# Regular API calls (including logout):
location /api/ {
    proxy_set_header Connection "";  # ← This fixes logout
}

# WebSocket streaming (separate location):
location /api/stream {
    proxy_set_header Connection "upgrade";  # ← This is OK for WebSocket
}
```

### **3. Fixed Web Server Connection:**
```nginx
# Web server requests:
location / {
    proxy_set_header Connection "";  # ← This prevents conflicts
}
```

---

## 🔍 **Why This Fixes the Logout Problem**

### **The Root Cause:**
1. Your current config sets `Connection: 'upgrade'` for ALL `/api/` requests
2. The **logout API call** is a regular HTTP POST, NOT a WebSocket upgrade
3. Setting `Connection: 'upgrade'` for regular HTTP requests causes the "invalid connection header" error
4. The webserver gets confused and throws the `TypeError: fetch failed` error

### **The Solution:**
1. **Regular API calls** (like logout) get `Connection: ""` (empty/cleared)
2. **WebSocket calls** (like streaming) get `Connection: "upgrade"`
3. **Separate locations** handle different types of requests properly

---

## ✅ **Test the Fix**

After applying the configuration:

```bash
# 1. Check NGINX is running with new config
oc get pods -l app=nginx

# 2. Test the logout functionality from UI
# 3. Check webserver logs - should NOT see TypeError anymore
oc logs -l app=webserver --tail=10

# 4. Verify NGINX config is loaded correctly
oc exec -it deploy/nginx -- nginx -t
```

---

## 🎉 **Expected Result**

After this fix:
- ✅ **No more "TypeError: fetch failed"** in webserver logs
- ✅ **No more "invalid connection header"** errors
- ✅ **Logout works properly** - user gets logged out and redirected
- ✅ **WebSocket streaming still works** for chat functionality

**The key fix is changing `proxy_set_header Connection 'upgrade';` to `proxy_set_header Connection "";` for regular API calls!** 🎯
