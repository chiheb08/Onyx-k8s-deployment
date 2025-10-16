# NGINX DNS Troubleshooting Guide - Complete Solution

**Problem:** InitContainer still can't resolve services even with full DNS names

**Solution:** Multiple approaches with debugging and fallback options

---

## 🔍 Debugging Steps

### Step 1: Check Current Namespace
```bash
# Get your current namespace
oc project

# Or get namespace programmatically
oc project -q
```

### Step 2: Deploy with Debugging
```bash
# Deploy the updated NGINX with debugging
oc apply -f 09-nginx.yaml

# Watch the initContainer logs to see debugging information
oc logs deployment/nginx -c wait-for-services -f
```

### Step 3: Analyze Debug Output
The initContainer will now show:
- NAMESPACE environment variable value
- Available environment variables
- DNS resolution test results for different formats
- Which DNS resolution method works

---

## 🔧 Solution Options

### Option 1: Use Hardcoded Namespace (Recommended)

If environment variable substitution doesn't work, use the hardcoded version:

```bash
# Step 1: Get your namespace
NAMESPACE=$(oc project -q)
echo "Your namespace is: $NAMESPACE"

# Step 2: Replace YOUR_NAMESPACE in the hardcoded file
sed "s/YOUR_NAMESPACE/$NAMESPACE/g" 09-nginx-hardcoded-namespace.yaml > 09-nginx-fixed.yaml

# Step 3: Deploy the fixed version
oc apply -f 09-nginx-fixed.yaml
```

### Option 2: Use Short Names (Fallback)

If full DNS names don't work, try short names:

```bash
# Patch the ConfigMap to use short names
oc patch configmap nginx-config --patch '{
  "data": {
    "default.conf": "upstream web_server {\n    server web-server:3000;\n}\n\nupstream api_server {\n    server api-server:8080;\n}\n\nserver {\n    listen 80;\n    server_name _;\n    \n    location /api/ {\n        proxy_pass http://api_server;\n        proxy_set_header Host $host;\n        proxy_set_header X-Real-IP $remote_addr;\n        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n        proxy_set_header X-Forwarded-Proto $scheme;\n    }\n    \n    location / {\n        proxy_pass http://web_server;\n        proxy_set_header Host $host;\n        proxy_set_header X-Real-IP $remote_addr;\n        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n        proxy_set_header X-Forwarded-Proto $scheme;\n    }\n}"
  }
}'

# Restart NGINX
oc rollout restart deployment/nginx
```

### Option 3: Use IP Addresses (Last Resort)

Get the actual IP addresses of services:

```bash
# Get service IPs
oc get services -o wide

# Example output:
# NAME          TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
# web-server    ClusterIP   10.96.123.45   <none>        3000/TCP   1m
# api-server    ClusterIP   10.96.123.46   <none>        8080/TCP   1m

# Patch ConfigMap with IP addresses
oc patch configmap nginx-config --patch '{
  "data": {
    "default.conf": "upstream web_server {\n    server 10.96.123.45:3000;\n}\n\nupstream api_server {\n    server 10.96.123.46:8080;\n}\n\nserver {\n    listen 80;\n    server_name _;\n    \n    location /api/ {\n        proxy_pass http://api_server;\n        proxy_set_header Host $host;\n        proxy_set_header X-Real-IP $remote_addr;\n        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n        proxy_set_header X-Forwarded-Proto $scheme;\n    }\n    \n    location / {\n        proxy_pass http://web_server;\n        proxy_set_header Host $host;\n        proxy_set_header X-Real-IP $remote_addr;\n        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n        proxy_set_header X-Forwarded-Proto $scheme;\n    }\n}"
  }
}'
```

---

## 🔍 Verification Commands

### Check Services Exist
```bash
# List all services
oc get services

# Check specific services
oc get service web-server
oc get service api-server

# Check service endpoints
oc get endpoints web-server
oc get endpoints api-server
```

### Test DNS Resolution Manually
```bash
# Test from a debug pod
oc run debug --image=busybox:1.35 --rm -it -- nslookup web-server
oc run debug --image=busybox:1.35 --rm -it -- nslookup api-server

# Test with full DNS names
NAMESPACE=$(oc project -q)
oc run debug --image=busybox:1.35 --rm -it -- nslookup web-server.${NAMESPACE}.svc.cluster.local
oc run debug --image=busybox:1.35 --rm -it -- nslookup api-server.${NAMESPACE}.svc.cluster.local
```

### Check NGINX Configuration
```bash
# View the actual NGINX config
oc exec deployment/nginx -c nginx -- cat /etc/nginx/conf.d/default.conf

# Test NGINX configuration
oc exec deployment/nginx -c nginx -- nginx -t
```

---

## 🐛 Common Issues and Solutions

### Issue 1: Services Don't Exist
```bash
# Check if services are deployed
oc get services | grep -E "(web-server|api-server)"

# If missing, deploy them
oc apply -f 08-web-server-service.yaml
oc apply -f 07-api-server-service.yaml
```

### Issue 2: Services Have No Endpoints
```bash
# Check if deployments are running
oc get deployments
oc get pods -l app=web-server
oc get pods -l app=api-server

# If pods are not running, check their logs
oc logs deployment/web-server
oc logs deployment/api-server
```

### Issue 3: DNS Resolution Fails
```bash
# Check CoreDNS
oc get pods -n kube-system | grep dns

# Check DNS configuration
oc get configmap -n kube-system coredns -o yaml
```

### Issue 4: Environment Variable Not Set
```bash
# Check environment variables in pod
oc exec deployment/nginx -c wait-for-services -- env | grep NAMESPACE

# If not set, check pod spec
oc get pod -l app=nginx -o yaml | grep -A 5 -B 5 NAMESPACE
```

---

## 🚀 Quick Fix Commands

### Complete Troubleshooting Sequence
```bash
# 1. Get namespace
NAMESPACE=$(oc project -q)
echo "Namespace: $NAMESPACE"

# 2. Check services exist
oc get services | grep -E "(web-server|api-server)"

# 3. Test DNS resolution
oc run debug --image=busybox:1.35 --rm -it -- nslookup web-server.${NAMESPACE}.svc.cluster.local

# 4. If DNS works, use hardcoded namespace
sed "s/YOUR_NAMESPACE/$NAMESPACE/g" 09-nginx-hardcoded-namespace.yaml > 09-nginx-fixed.yaml
oc apply -f 09-nginx-fixed.yaml

# 5. Check logs
oc logs deployment/nginx -c wait-for-services -f
```

---

## ✅ Summary

**The Problem:** DNS resolution still failing despite full DNS names.

**The Solutions:**
1. **Debug first:** Use the updated NGINX with debugging to see what's happening
2. **Hardcoded namespace:** Use `09-nginx-hardcoded-namespace.yaml` with your actual namespace
3. **Short names fallback:** If full DNS doesn't work, try short names
4. **IP addresses:** Last resort - use actual service IP addresses

**Next Steps:**
1. Deploy the updated NGINX with debugging
2. Check the initContainer logs to see the namespace value
3. Use the appropriate solution based on what works in your environment

The debugging output will tell us exactly what's happening! 🎯
