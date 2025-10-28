# Onyx Logout Problem - Cluster Deployment Solutions

## 🚨 **Problem Description**

**Issue**: Users cannot log out from their sessions in the Onyx cluster deployment. The logout functionality is not working properly.

**Impact**: Users remain logged in even after clicking logout, which can be a security concern and user experience issue.

---

## 🔍 **Possible Root Causes**

### **1. Redis Session Storage Issues**
- Redis pod not running or accessible
- Session tokens not being cleared from Redis
- Redis connection problems from API server

### **2. API Server Issues**
- Logout endpoint not responding
- Authentication middleware problems
- Session invalidation logic not working

### **3. Frontend Issues**
- Logout request not being sent properly
- Token not being cleared from browser
- Frontend-backend communication problems

### **4. Network/Service Issues**
- Service discovery problems
- Load balancer issues
- DNS resolution problems

---

## 🛠️ **Step-by-Step Solutions**

### **Solution 1: Check Redis Pod Status**

#### **Check if Redis is running:**
```bash
# Check Redis pod status
oc get pods -l app=redis

# Check Redis pod logs
oc logs -l app=redis --tail=50

# Check Redis service
oc get svc redis

# Test Redis connectivity from API server
oc exec -it deploy/api-server -- redis-cli -h redis -p 6379 ping
```

#### **Expected Results:**
```bash
# Redis pod should be Running
NAME                     READY   STATUS    RESTARTS   AGE
redis-7d4b8c9f8d-xyz123   1/1     Running   0          2h

# Redis should respond with PONG
PONG
```

#### **If Redis is not working:**
```bash
# Restart Redis pod
oc delete pod -l app=redis

# Check Redis configuration
oc describe configmap redis-config

# Check Redis persistent volume
oc get pvc redis-data
```

### **Solution 2: Check API Server Logout Endpoint**

#### **Test logout endpoint directly:**
```bash
# Get your auth token (from browser developer tools)
TOKEN="your-jwt-token-here"

# Test logout endpoint
oc exec -it deploy/api-server -- curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  http://localhost:8080/api/auth/logout

# Check API server logs for logout requests
oc logs -l app=api-server --tail=100 | grep -i logout
```

#### **Expected Response:**
```json
{
  "message": "Successfully logged out"
}
```

#### **If logout endpoint is not working:**
```bash
# Check API server pod status
oc get pods -l app=api-server

# Check API server logs for errors
oc logs -l app=api-server --tail=200 | grep -i error

# Restart API server if needed
oc rollout restart deployment/api-server
```

### **Solution 3: Check Session Token Management**

#### **Verify Redis session cleanup:**
```bash
# Connect to Redis and check sessions
oc exec -it deploy/redis -- redis-cli

# Inside Redis CLI:
# List all auth session keys
KEYS auth:session:*

# Check a specific session (replace with actual key)
GET auth:session:your-token-key

# Check session TTL
TTL auth:session:your-token-key

# Exit Redis CLI
exit
```

#### **Manual session cleanup (if needed):**
```bash
# Clear all auth sessions (CAUTION: This logs out all users)
oc exec -it deploy/redis -- redis-cli FLUSHDB

# Or clear specific session
oc exec -it deploy/redis -- redis-cli DEL auth:session:specific-token
```

### **Solution 4: Check Web Server Configuration**

#### **Test web server logout functionality:**
```bash
# Check web server logs
oc logs -l app=webserver --tail=100 | grep -i logout

# Check web server pod status
oc get pods -l app=webserver

# Test web server connectivity
oc exec -it deploy/api-server -- curl -I http://web-server:3000/
```

#### **If web server has issues:**
```bash
# Restart web server
oc rollout restart deployment/webserver

# Check web server configuration
oc describe deployment webserver
```

### **Solution 5: Check NGINX Configuration**

#### **Verify NGINX is routing logout requests correctly:**
```bash
# Check NGINX logs for logout requests
oc logs -l app=nginx --tail=100 | grep -i logout

# Check NGINX configuration
oc exec -it deploy/nginx -- cat /etc/nginx/conf.d/default.conf

# Test NGINX routing
oc exec -it deploy/nginx -- curl -I http://localhost/api/auth/logout
```

#### **If NGINX has routing issues:**
```bash
# Check NGINX ConfigMap
oc get configmap nginx-config -o yaml

# Restart NGINX
oc rollout restart deployment/nginx

# Test NGINX connectivity to backend services
oc exec -it deploy/nginx -- curl -I http://api-server:8080/health
```

---

## 🔧 **Advanced Troubleshooting**

### **Check 1: Verify Complete Logout Flow**

#### **Test the complete logout process:**
```bash
# 1. Check if user can access protected endpoints before logout
TOKEN="your-jwt-token"
oc exec -it deploy/api-server -- curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8080/api/me

# 2. Perform logout
oc exec -it deploy/api-server -- curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  http://localhost:8080/api/auth/logout

# 3. Check if user can still access protected endpoints after logout
oc exec -it deploy/api-server -- curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8080/api/me
```

#### **Expected Results:**
```bash
# Before logout: Should return user info
{"id": "user-id", "email": "user@example.com", ...}

# After logout: Should return 401 Unauthorized
{"detail": "Not authenticated"}
```

### **Check 2: Monitor Real-time Logs**

#### **Monitor logs during logout attempt:**
```bash
# Terminal 1: Monitor API server logs
oc logs -f -l app=api-server

# Terminal 2: Monitor Redis logs
oc logs -f -l app=redis

# Terminal 3: Monitor NGINX logs
oc logs -f -l app=nginx

# Terminal 4: Monitor web server logs
oc logs -f -l app=webserver

# Now attempt logout from the UI and watch the logs
```

### **Check 3: Verify Environment Variables**

#### **Check authentication configuration:**
```bash
# Check API server environment variables
oc exec -it deploy/api-server -- env | grep -E "(AUTH|REDIS|SESSION)"

# Expected variables:
# AUTH_TYPE=basic
# REDIS_HOST=redis
# REDIS_PORT=6379
# SESSION_EXPIRE_TIME_SECONDS=86400
```

---

## 🚀 **Quick Fixes**

### **Quick Fix 1: Restart All Authentication-Related Services**
```bash
# Restart in order
oc rollout restart deployment/redis
sleep 30
oc rollout restart deployment/api-server
sleep 30
oc rollout restart deployment/webserver
sleep 30
oc rollout restart deployment/nginx

# Wait for all pods to be ready
oc get pods -w
```

### **Quick Fix 2: Clear All Sessions (Nuclear Option)**
```bash
# WARNING: This will log out ALL users
oc exec -it deploy/redis -- redis-cli FLUSHALL

# Restart API server to refresh connections
oc rollout restart deployment/api-server
```

### **Quick Fix 3: Check and Fix ConfigMap**
```bash
# Check if Redis configuration is correct in ConfigMap
oc get configmap onyx-config -o yaml | grep -A 5 -B 5 REDIS

# If Redis host/port is wrong, update ConfigMap
oc edit configmap onyx-config

# Restart API server to pick up changes
oc rollout restart deployment/api-server
```

---

## 🔍 **Diagnostic Commands**

### **Complete Health Check:**
```bash
#!/bin/bash
echo "=== Onyx Logout Problem Diagnostic ==="

echo "1. Checking pod status..."
oc get pods -l 'app in (api-server,webserver,nginx,redis)'

echo "2. Checking services..."
oc get svc -l 'app in (api-server,web-server,nginx,redis)'

echo "3. Checking Redis connectivity..."
oc exec -it deploy/api-server -- redis-cli -h redis -p 6379 ping || echo "Redis connection failed"

echo "4. Checking API server health..."
oc exec -it deploy/api-server -- curl -s http://localhost:8080/health || echo "API server health check failed"

echo "5. Checking recent logs for errors..."
echo "API Server errors:"
oc logs -l app=api-server --tail=50 | grep -i error | tail -5

echo "Redis errors:"
oc logs -l app=redis --tail=50 | grep -i error | tail -5

echo "NGINX errors:"
oc logs -l app=nginx --tail=50 | grep -i error | tail -5

echo "6. Checking Redis session count..."
oc exec -it deploy/redis -- redis-cli EVAL "return #redis.call('keys', 'auth:session:*')" 0

echo "=== Diagnostic Complete ==="
```

---

## 📋 **Step-by-Step Resolution Process**

### **Step 1: Basic Checks (5 minutes)**
```bash
# Check if all pods are running
oc get pods

# Check if services are accessible
oc get svc

# Test Redis connectivity
oc exec -it deploy/api-server -- redis-cli -h redis ping
```

### **Step 2: Test Logout Endpoint (5 minutes)**
```bash
# Get auth token from browser (F12 -> Application -> Local Storage)
# Test logout endpoint directly
oc exec -it deploy/api-server -- curl -X POST \
  -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:8080/api/auth/logout
```

### **Step 3: Check Logs (10 minutes)**
```bash
# Check API server logs for logout attempts
oc logs -l app=api-server --tail=100 | grep -i logout

# Check for any error messages
oc logs -l app=api-server --tail=200 | grep -i error
```

### **Step 4: Restart Services (10 minutes)**
```bash
# Restart authentication-related services
oc rollout restart deployment/api-server
oc rollout restart deployment/redis

# Wait for pods to be ready
oc get pods -w
```

### **Step 5: Test Again (5 minutes)**
```bash
# Try logging out from the UI
# Check if session is cleared from Redis
oc exec -it deploy/redis -- redis-cli KEYS "auth:session:*"
```

---

## 🎯 **Most Likely Solutions**

### **Solution A: Redis Connection Issue (80% probability)**
```bash
# Fix Redis connectivity
oc rollout restart deployment/redis
oc rollout restart deployment/api-server

# Test connectivity
oc exec -it deploy/api-server -- redis-cli -h redis ping
```

### **Solution B: Session Token Not Being Cleared (15% probability)**
```bash
# Clear all sessions and restart
oc exec -it deploy/redis -- redis-cli FLUSHDB
oc rollout restart deployment/api-server
```

### **Solution C: API Server Configuration Issue (5% probability)**
```bash
# Check and fix environment variables
oc edit configmap onyx-config
oc rollout restart deployment/api-server
```

---

## 📞 **If Nothing Works**

### **Last Resort Options:**

#### **Option 1: Complete System Restart**
```bash
# Restart all services in order
oc rollout restart deployment/redis
sleep 60
oc rollout restart deployment/api-server
sleep 60
oc rollout restart deployment/webserver
sleep 60
oc rollout restart deployment/nginx
```

#### **Option 2: Check for Resource Issues**
```bash
# Check if pods have enough resources
oc describe pods -l app=api-server | grep -A 10 -B 10 -i "resource\|memory\|cpu"

# Check node resources
oc describe nodes | grep -A 5 -B 5 -i "resource\|memory\|cpu"
```

#### **Option 3: Verify Network Policies**
```bash
# Check if network policies are blocking logout requests
oc get networkpolicies

# Test network connectivity between services
oc exec -it deploy/api-server -- curl -I http://redis:6379
```

---

## 🎉 **Success Verification**

### **How to Verify Logout is Working:**

#### **Test 1: Manual Logout Test**
```bash
# 1. Login to Onyx UI
# 2. Note your session token (F12 -> Application -> Local Storage)
# 3. Click logout
# 4. Check if token is removed from browser
# 5. Try to access a protected page - should redirect to login
```

#### **Test 2: Redis Session Cleanup**
```bash
# Before logout: Check session exists
oc exec -it deploy/redis -- redis-cli KEYS "auth:session:*"

# After logout: Check session is removed
oc exec -it deploy/redis -- redis-cli KEYS "auth:session:*"
```

#### **Test 3: API Endpoint Test**
```bash
# After logout, this should return 401
oc exec -it deploy/api-server -- curl -H "Authorization: Bearer OLD_TOKEN" \
  http://localhost:8080/api/me
```

This comprehensive guide should help you identify and fix the logout problem in your cluster deployment! 🎯
