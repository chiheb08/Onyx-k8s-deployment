# Webserver Logout Error Analysis - Invalid Connection Header

## 🚨 **Error Analysis from Logs**

Based on your webserver logs, I can see the exact problem with the logout functionality:

```
TypeError: fetch failed
at async (...next/server/chunks/270.js:7:133572)
at async (...next/server/app/auth/logout/route.js:1:2372)
[cause]: [Error [InvalidArgumentError]: invalid connection header]
code: 'UND_ERR_INVALID_ARG'
```

**Root Cause**: The webserver is getting an "invalid connection header" error when trying to make the logout API call to the backend API server.

---

## 🔍 **What This Error Means**

### **The Problem:**
- The **webserver (Next.js)** is trying to call the **API server** logout endpoint
- The HTTP request is failing due to an **invalid connection header**
- This is a **network/HTTP configuration issue**, not a Redis or authentication issue

### **Why This Happens:**
1. **HTTP/1.1 vs HTTP/2 mismatch**
2. **Proxy configuration issues** (NGINX)
3. **Connection header conflicts** between webserver and API server
4. **Keep-alive connection problems**

---

## 🛠️ **Specific Solutions**

### **Solution 1: Fix NGINX Configuration (Most Likely)**

The issue is probably in your NGINX configuration. Check and update your NGINX ConfigMap:

```bash
# Check current NGINX configuration
oc get configmap nginx-config -o yaml
```

**Update your NGINX ConfigMap to include proper headers:**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  default.conf: |
    upstream web-server {
        server web-server:3000;
    }
    
    upstream api-server {
        server api-server:8080;
    }
    
    server {
        listen 80;
        server_name localhost;
        
        # Increase buffer sizes
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
        
        # Fix connection headers
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Web server routes
        location / {
            proxy_pass http://web-server;
            proxy_set_header Connection "";
            proxy_http_version 1.1;
        }
        
        # API server routes
        location /api/ {
            proxy_pass http://api-server;
            proxy_set_header Connection "";
            proxy_http_version 1.1;
            
            # Specific headers for API calls
            proxy_set_header Accept-Encoding "";
            proxy_set_header Content-Type $content_type;
        }
        
        # Health check
        location /health {
            proxy_pass http://api-server/health;
            proxy_set_header Connection "";
            proxy_http_version 1.1;
        }
    }
```

**Apply the fix:**
```bash
# Update the ConfigMap (edit with the above configuration)
oc edit configmap nginx-config

# Restart NGINX to pick up changes
oc rollout restart deployment/nginx

# Wait for NGINX to be ready
oc get pods -l app=nginx -w
```

### **Solution 2: Fix API Server Internal URL**

Check if the `INTERNAL_URL` in your ConfigMap is correct:

```bash
# Check the INTERNAL_URL configuration
oc get configmap onyx-config -o yaml | grep INTERNAL_URL
```

**It should be:**
```yaml
INTERNAL_URL: "http://api-server:8080"
```

**If it's wrong, fix it:**
```bash
# Edit the ConfigMap
oc edit configmap onyx-config

# Find INTERNAL_URL and make sure it's:
# INTERNAL_URL: "http://api-server:8080"

# Restart webserver to pick up changes
oc rollout restart deployment/webserver
```

### **Solution 3: Add Connection Headers to Web Server**

The webserver might need specific connection headers. Check if there's a custom configuration:

```bash
# Check webserver environment variables
oc exec -it deploy/webserver -- env | grep -E "(API|URL|HOST)"

# Check if webserver can reach API server directly
oc exec -it deploy/webserver -- curl -I http://api-server:8080/health
```

### **Solution 4: Test Direct API Connection**

Test if the API server logout endpoint works directly:

```bash
# Test logout endpoint directly from webserver pod
oc exec -it deploy/webserver -- curl -X POST \
  -H "Content-Type: application/json" \
  -H "Connection: close" \
  http://api-server:8080/api/auth/logout

# Test with keep-alive disabled
oc exec -it deploy/webserver -- curl -X POST \
  -H "Content-Type: application/json" \
  -H "Connection: close" \
  -H "Accept-Encoding: identity" \
  http://api-server:8080/api/auth/logout
```

---

## 🔧 **Quick Fix Commands**

### **Quick Fix 1: Update NGINX Configuration**
```bash
# Create a temporary file with the correct NGINX config
cat > /tmp/nginx-fix.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  default.conf: |
    upstream web-server {
        server web-server:3000;
    }
    
    upstream api-server {
        server api-server:8080;
    }
    
    server {
        listen 80;
        server_name localhost;
        
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        location / {
            proxy_pass http://web-server;
            proxy_set_header Connection "";
            proxy_http_version 1.1;
        }
        
        location /api/ {
            proxy_pass http://api-server;
            proxy_set_header Connection "";
            proxy_http_version 1.1;
        }
    }
EOF

# Apply the fix
oc apply -f /tmp/nginx-fix.yaml

# Restart NGINX
oc rollout restart deployment/nginx
```

### **Quick Fix 2: Verify and Fix INTERNAL_URL**
```bash
# Check current INTERNAL_URL
oc get configmap onyx-config -o jsonpath='{.data.INTERNAL_URL}'

# If it's not "http://api-server:8080", fix it:
oc patch configmap onyx-config --type merge -p '{"data":{"INTERNAL_URL":"http://api-server:8080"}}'

# Restart webserver
oc rollout restart deployment/webserver
```

### **Quick Fix 3: Test the Fix**
```bash
# Wait for pods to be ready
oc get pods -l 'app in (nginx,webserver)' -w

# Test logout from webserver pod
oc exec -it deploy/webserver -- curl -X POST \
  -H "Content-Type: application/json" \
  -H "Connection: close" \
  http://api-server:8080/api/auth/logout

# Check webserver logs for errors
oc logs -l app=webserver --tail=20
```

---

## 🎯 **Root Cause Summary**

**The issue is NOT with Redis or authentication logic.** The problem is:

1. **HTTP connection header mismatch** between webserver and API server
2. **NGINX proxy configuration** not handling connection headers properly
3. **Possible HTTP version conflicts** (HTTP/1.1 vs HTTP/2)

**The fix is to:**
1. **Update NGINX configuration** to properly handle connection headers
2. **Ensure INTERNAL_URL** points to the correct API server endpoint
3. **Add proper HTTP headers** to prevent connection conflicts

---

## 📋 **Step-by-Step Resolution**

### **Step 1: Apply NGINX Fix (5 minutes)**
```bash
# Update NGINX ConfigMap with proper connection headers
oc edit configmap nginx-config
# Add: proxy_set_header Connection "";
# Add: proxy_http_version 1.1;

# Restart NGINX
oc rollout restart deployment/nginx
```

### **Step 2: Verify INTERNAL_URL (2 minutes)**
```bash
# Check INTERNAL_URL
oc get configmap onyx-config -o jsonpath='{.data.INTERNAL_URL}'

# Should be: http://api-server:8080
```

### **Step 3: Test the Fix (3 minutes)**
```bash
# Try logging out from the UI
# Check webserver logs for the error
oc logs -l app=webserver --tail=10
```

### **Step 4: Verify Success (2 minutes)**
```bash
# Should see successful logout without TypeError
# User should be redirected to login page
```

---

## 🎉 **Expected Result After Fix**

After applying the NGINX configuration fix, you should see:

1. **No more "TypeError: fetch failed" errors** in webserver logs
2. **No more "invalid connection header" errors**
3. **Successful logout functionality** in the UI
4. **Proper redirection** to login page after logout

The key fix is updating the NGINX configuration to properly handle HTTP connection headers between the webserver and API server! 🎯
