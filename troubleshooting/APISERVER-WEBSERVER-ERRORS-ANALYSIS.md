# API Server & Web Server Errors Analysis

## Summary of Errors

You're experiencing **4 related issues** that are all connected to **service communication problems** in your Kubernetes cluster.

---

## Error 1: "Could not trace chat message history"

### Where It Appears
```
File "/app/onyx/chat/chat_utils.py", line 260, in create_chat_chain
RuntimeError: Could not trace chat message history
```

### What It Means

This error occurs in the API server when trying to continue a chat conversation. The function `create_chat_chain` is trying to rebuild the message history for a chat session.

### Why It Happens

```python
# File: backend/onyx/chat/chat_utils.py, line 259-260
if not mainline_messages:
    raise RuntimeError("Could not trace chat message history")
```

This error is thrown when:
1. The chat session exists but has **no valid message chain**
2. The message chain is **broken** (messages reference non-existent parents)
3. There's a **database inconsistency** - messages were partially deleted

### Root Cause

This is likely a **symptom** of Error 2 (connection refused). When the web server can't reach the API server:
1. Some requests succeed, some fail
2. Chat sessions get created but messages don't get properly saved
3. Next request tries to continue a broken conversation

---

## Error 2: "ECONNREFUSED 172.30.154.48:8080"

### Where It Appears
```
Error: connect ECONNREFUSED 172.30.154.48:8080
code: 'ECONNREFUSED',
syscall: 'connect',
address: '172.30.154.48',
port: 8080
```

### What It Means

The **Web Server** (Next.js) is trying to connect to the **API Server** (FastAPI) at IP `172.30.154.48:8080`, but the connection is being **refused**.

### Why It Happens

The web server uses `INTERNAL_URL` to connect to the API server:

```typescript
// File: web/src/lib/constants.ts, line 13
export const INTERNAL_URL = process.env.INTERNAL_URL || "http://127.0.0.1:8080";
```

Then all server-side fetches use this URL:

```typescript
// File: web/src/lib/utilsSS.ts, line 59-71
export async function fetchSS(url: string, options?: RequestInit) {
  return fetch(buildUrl(url), init);  // buildUrl uses INTERNAL_URL
}
```

### Possible Causes

| Cause | Likelihood | How to Check |
|-------|------------|--------------|
| API Server pod is down/restarting | High | `kubectl get pods -l app=api-server` |
| Wrong `INTERNAL_URL` configuration | High | Check web server ConfigMap |
| Kubernetes Service not found | Medium | `kubectl get svc api-server` |
| Network Policy blocking traffic | Medium | Check NetworkPolicies |
| API Server overloaded | Low | Check API server logs for errors |

---

## Error 3: "404: Not Found" for MCP Servers

### Where It Appears
```
ERROR: main.py 319: [API:YCrqgDXa] 404: Not Found
GET /mcp/servers/persona/...
raise HTTPException(status_code=404)
```

### What It Means

The web server is requesting MCP (Model Context Protocol) server configurations for a persona/assistant, but the API server returns 404.

### Why It Happens

This is a **minor issue** that occurs when:
1. A persona is configured to use MCP servers
2. But those MCP servers don't exist or aren't configured

This error is **not critical** - it's a feature that's not set up, not a system failure.

---

## Error 4: "User is not authenticated" + "User is logged in"

### Where It Appears
```
Failed to fetch assistants - Access denied. User is not authenticated.
Login page: User is logged in, redirecting to chat {
  userId: '755033c6-4661-4be5-9622-c6d51f5d1533',
  is_active: true,
  is_anonymous: null
}
```

### What It Means

This is a **contradictory state**:
- One message says "User is not authenticated"
- Next message says "User is logged in" with a valid user ID

### Why It Happens

This is caused by **Error 2** (ECONNREFUSED):

```
1. User logs in successfully
2. Web server stores session cookie
3. Web server tries to fetch assistants from API server
4. API server connection fails (ECONNREFUSED)
5. Fetch fails with network error
6. Web server interprets failure as "not authenticated"
7. But the user's session cookie is still valid
8. So it says "User is logged in" when checking locally
```

### Visual Flow

```
User Browser                   Web Server                    API Server
     |                              |                             |
     |-- Login Request ------------>|                             |
     |                              |-- Verify credentials ------>|
     |                              |<-- Success, create session -|
     |<-- Set session cookie -------|                             |
     |                              |                             |
     |-- Load Chat Page ----------->|                             |
     |                              |-- Fetch assistants -------->|
     |                              |       X ECONNREFUSED X      |
     |                              |                             |
     |                              |-- Check local session       |
     |                              |   "User is logged in"       |
     |                              |                             |
     |<-- Error: Not authenticated -|                             |
```

---

## The Root Cause: Service Communication

All 4 errors stem from **one root cause**: The **Web Server cannot reliably reach the API Server**.

### Diagram: Current (Broken) State

```
+-------------+                    +-------------+
|   Browser   |                    |   Browser   |
+------+------+                    +------+------+
       |                                  |
       | (works)                          | (works)
       v                                  v
+------+------+                    +------+------+
| NGINX/Route |                    | NGINX/Route |
+------+------+                    +------+------+
       |                                  |
       | (works)                          | (works)
       v                                  v
+------+------+                    +------+------+
| Web Server  |                    | API Server  |
| (Next.js)   |                    | (FastAPI)   |
+------+------+                    +------+------+
       |                                  ^
       |          ECONNREFUSED            |
       +------------------X---------------+
              Can't reach API Server!
```

---

## Solutions

### Solution 1: Check API Server Status

```bash
# Check if API server pod is running
kubectl get pods -l app=api-server -o wide

# Expected output:
# NAME                          READY   STATUS    RESTARTS   AGE
# api-server-xxx                1/1     Running   0          1h

# If not running, check why:
kubectl describe pod -l app=api-server

# Check API server logs
kubectl logs -l app=api-server --tail=100
```

### Solution 2: Verify INTERNAL_URL Configuration

```bash
# Check web server's environment variables
kubectl exec -it deployment/web-server -- env | grep INTERNAL_URL

# Should output something like:
# INTERNAL_URL=http://api-server:8080
```

**If missing or wrong**, update the web server ConfigMap:

```yaml
# In your ConfigMap for web-server
apiVersion: v1
kind: ConfigMap
metadata:
  name: web-server-config
data:
  INTERNAL_URL: "http://api-server:8080"  # Use Kubernetes service name!
```

### Solution 3: Verify Kubernetes Service

```bash
# Check if api-server service exists
kubectl get svc api-server

# Expected output:
# NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
# api-server   ClusterIP   10.x.x.x        <none>        8080/TCP   1h

# Test connectivity from web-server pod
kubectl exec -it deployment/web-server -- curl -v http://api-server:8080/health
```

### Solution 4: Check Network Policies

```bash
# List network policies
kubectl get networkpolicies

# If you have network policies, ensure web-server can reach api-server
```

### Solution 5: Check Resource Limits

```bash
# Check if API server is being OOMKilled or throttled
kubectl describe pod -l app=api-server | grep -A5 "Limits\|Requests\|State"

# If the pod keeps restarting, increase resources:
kubectl patch deployment api-server -p '{"spec":{"template":{"spec":{"containers":[{"name":"api-server","resources":{"limits":{"memory":"4Gi"},"requests":{"memory":"2Gi"}}}]}}}}'
```

---

## Quick Fix Checklist

| Step | Command | Expected Result |
|------|---------|-----------------|
| 1. Check API pod | `kubectl get pods -l app=api-server` | STATUS: Running |
| 2. Check API logs | `kubectl logs -l app=api-server --tail=50` | No crash errors |
| 3. Check Service | `kubectl get svc api-server` | Service exists |
| 4. Test connection | `kubectl exec deployment/web-server -- curl http://api-server:8080/health` | `{"status": "ok"}` |
| 5. Check INTERNAL_URL | `kubectl exec deployment/web-server -- env \| grep INTERNAL` | `INTERNAL_URL=http://api-server:8080` |

---

## Understanding the IP Address

The error shows:
```
address: '172.30.154.48'
```

This is an **OpenShift/Kubernetes Service IP**. This means:
- The web server IS configured to use the correct service
- But the service endpoint (API server pod) is not responding

Check the endpoint:
```bash
kubectl get endpoints api-server

# Expected:
# NAME         ENDPOINTS           AGE
# api-server   10.x.x.x:8080       1h
#              ^^^^^^^^^^
#              Should have at least one endpoint

# If ENDPOINTS is empty, the API server pod isn't ready!
```

---

## Most Likely Fix

Based on the errors, the **most likely issue** is:

**The API Server pod is down, restarting, or not ready.**

Run these commands in order:

```bash
# 1. Check pod status
kubectl get pods -l app=api-server -w

# 2. If not running, check events
kubectl describe pod -l app=api-server

# 3. Check logs for startup errors
kubectl logs -l app=api-server --previous

# 4. Restart the API server
kubectl rollout restart deployment/api-server

# 5. Wait for it to be ready
kubectl rollout status deployment/api-server
```

---

## Long-term Fixes

### 1. Add Health Checks

Ensure your API server deployment has proper health checks:

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  
readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

### 2. Add Retry Logic in Web Server

The web server should retry failed API calls. This is a code change in the Onyx codebase.

### 3. Monitor Service Endpoints

Set up alerts when `api-server` service has 0 endpoints.

---

## Summary

| Error | Cause | Fix |
|-------|-------|-----|
| "Could not trace chat message history" | Database inconsistency from failed requests | Will resolve when connectivity is fixed |
| "ECONNREFUSED 172.30.154.48:8080" | API server not reachable | Check pod status, restart if needed |
| "404: Not Found" for MCP | Feature not configured | Ignore or configure MCP servers |
| "User not authenticated" + "logged in" | Auth check failed due to connection error | Will resolve when connectivity is fixed |

**Primary action**: Ensure the API server pod is running and the service endpoint is healthy.

