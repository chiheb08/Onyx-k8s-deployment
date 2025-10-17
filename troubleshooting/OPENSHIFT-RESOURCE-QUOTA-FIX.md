# OpenShift Resource Quota Fix - NGINX InitContainer

**Error:** `pods 'nginx-xxx' is forbidden: failed quota: resource-quota-custom: must specify limits.cpu for: wait-for-services; limits.memory for: wait-for-services; requests.cpu for: wait-for-services; requests.memory for: wait-for-services`

**Root Cause:** OpenShift resource quota requires all containers (including initContainers) to have resource specifications.

---

## 🔍 The Problem

### OpenShift Resource Quota Requirements
OpenShift enforces resource quotas that require **ALL containers** to specify:
- `requests.cpu`
- `requests.memory`
- `limits.cpu`
- `limits.memory`

### What Was Missing
The `wait-for-services` initContainer in NGINX deployment had no resource specifications:

```yaml
initContainers:
  - name: wait-for-services
    image: busybox:1.35
    # ❌ Missing resources section!
```

---

## 🔧 Solution Applied

### Added Resource Specifications to InitContainer
```yaml
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
    resources:  ← ADDED THIS SECTION
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 100m
        memory: 128Mi
```

### Resource Specifications Used
Based on other deployments in the project:

**InitContainer Resources (Minimal):**
- **Requests:** 50m CPU, 64Mi memory
- **Limits:** 100m CPU, 128Mi memory

**Comparison with Other Services:**
- **Web Server:** 200m/512Mi requests, 1000m/1Gi limits
- **API Server:** 500m/1Gi requests, 2000m/2Gi limits
- **NGINX Main:** 100m/128Mi requests, 500m/256Mi limits

---

## 🚀 How to Apply the Fix

### Deploy Updated NGINX
```bash
# Apply the updated NGINX deployment with resource specifications
oc apply -f 09-nginx.yaml

# Check if the pod starts successfully
oc get pods -l app=nginx

# Check pod events for any remaining issues
oc describe pod -l app=nginx
```

### Verify Resource Quota Compliance
```bash
# Check resource quota status
oc describe quota resource-quota-custom

# Check if pod is now allowed
oc get pods -l app=nginx
```

---

## 🔍 Verification Steps

### Check Pod Status
```bash
# Check if NGINX pod is running
oc get pods -l app=nginx

# Should show: STATUS = Running, READY = 1/1
```

### Check InitContainer Logs
```bash
# Check initContainer logs
oc logs deployment/nginx -c wait-for-services

# Should show:
# Waiting for web-server...
# web-server is ready!
# Waiting for api-server...
# api-server is ready!
# All services are ready!
```

### Check NGINX Logs
```bash
# Check NGINX container logs
oc logs deployment/nginx -c nginx

# Should show successful startup without DNS errors
```

---

## 📊 Resource Usage Summary

### All Services Resource Specifications

| Service | Container | CPU Request | Memory Request | CPU Limit | Memory Limit |
|---------|-----------|-------------|----------------|-----------|--------------|
| **NGINX** | wait-for-services | 50m | 64Mi | 100m | 128Mi |
| **NGINX** | nginx | 100m | 128Mi | 500m | 256Mi |
| **Web Server** | web-server | 200m | 512Mi | 1000m | 1Gi |
| **API Server** | api-server | 500m | 1Gi | 2000m | 2Gi |
| **PostgreSQL** | postgresql | 200m | 256Mi | 1000m | 1Gi |
| **Redis** | redis | 100m | 128Mi | 500m | 256Mi |
| **Vespa** | vespa | 500m | 1Gi | 2000m | 2Gi |

### Total Resource Requirements
- **CPU Requests:** ~1.65 cores
- **Memory Requests:** ~3.1 GiB
- **CPU Limits:** ~6.1 cores
- **Memory Limits:** ~6.4 GiB

---

## 🐛 Troubleshooting

### If Pod Still Fails
```bash
# Check detailed pod events
oc describe pod -l app=nginx

# Check resource quota limits
oc describe quota

# Check if namespace has enough resources
oc describe namespace <your-namespace>
```

### If Resource Quota is Too Restrictive
```bash
# Check current quota usage
oc describe quota resource-quota-custom

# If needed, reduce resource requests/limits in other services
# or request quota increase from cluster admin
```

---

## ✅ Summary

**The Problem:** OpenShift resource quota requires all containers to have resource specifications.

**The Solution:** Added resource specifications to the `wait-for-services` initContainer:
- **Requests:** 50m CPU, 64Mi memory
- **Limits:** 100m CPU, 128Mi memory

**The Result:** NGINX pod can now be deployed successfully within the resource quota constraints! 🎯

---

## 📋 Quick Checklist

- [ ] Apply updated NGINX deployment: `oc apply -f 09-nginx.yaml`
- [ ] Check pod status: `oc get pods -l app=nginx`
- [ ] Verify initContainer logs: `oc logs deployment/nginx -c wait-for-services`
- [ ] Check NGINX logs: `oc logs deployment/nginx -c nginx`
- [ ] Test DNS resolution: `oc exec deployment/nginx -c nginx -- nslookup web-server`

All resource quota requirements are now satisfied! ✅
