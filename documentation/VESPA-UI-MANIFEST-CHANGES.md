# Vespa UI Access - Manifest Changes Guide

## 🎯 Overview

This guide shows **exactly what to modify** in your Kubernetes manifests to access the Vespa admin UI.

---

## 📋 Current Situation

**Current Vespa Service** (`03-vespa.yaml`):
- Type: `ClusterIP` (headless)
- Ports: `19071` (config), `8081` (query)
- **Access**: Only within cluster (internal only)

**Problem**: Cannot access Vespa UI from outside the cluster.

---

## ✅ Solution Options

You have **4 options**. Choose based on your needs:

| Option | Best For | Access Method | Security |
|-------|----------|---------------|----------|
| **1. Port Forward** | Development | `kubectl port-forward` | ✅ Secure |
| **2. NodePort** | Development/Testing | `<node-ip>:<port>` | ⚠️ Less secure |
| **3. LoadBalancer** | Cloud deployments | `<external-ip>:19071` | ⚠️ Less secure |
| **4. Ingress** | Production | `https://vespa-ui.domain.com` | ✅ Most secure |

---

## ✅ Option 1: Port Forward (No Manifest Changes Needed)

**Best for**: Quick access, development, testing

**No manifest changes required!** Just use kubectl:

```bash
# Port forward Vespa service
kubectl port-forward -n onyx-infra svc/vespa-service 19071:19071

# Access in browser
http://localhost:19071
```

**Pros:**
- ✅ No manifest changes
- ✅ Secure (only accessible from your machine)
- ✅ Works immediately

**Cons:**
- ❌ Requires kubectl access
- ❌ Connection drops when terminal closes
- ❌ Only accessible from your machine

---

## ✅ Option 2: NodePort Service (Recommended for Development)

**Best for**: Development, testing, internal access

### Step 1: Create New Service File

**File**: `onyx-k8s-infrastructure/manifests/03-vespa-ui-service.yaml` (already created)

This file contains a NodePort service that exposes Vespa UI.

### Step 2: Apply the Manifest

```bash
cd /Users/chihebmhamdi/Desktop/onyx/onyx-k8s-infrastructure/manifests

# Apply the new service
kubectl apply -f 03-vespa-ui-service.yaml

# Verify service is created
kubectl get svc -n onyx-infra vespa-ui-service
```

### Step 3: Find Node IP and Access

```bash
# Get node IP
kubectl get nodes -o wide

# Access Vespa UI
http://<node-ip>:30190
```

**Example:**
```bash
# If node IP is 192.168.1.100
http://192.168.1.100:30190
```

### What Changed

**Added**: New `vespa-ui-service` with:
- Type: `NodePort`
- Port `19071` → NodePort `30190`
- Port `8081` → NodePort `30191`

**Original service** (`vespa-service`) remains unchanged (still headless for internal use).

---

## ✅ Option 3: LoadBalancer Service (Cloud Deployments)

**Best for**: AWS, GCP, Azure, cloud deployments

### Step 1: Modify Service File

**File**: `onyx-k8s-infrastructure/manifests/03-vespa-ui-service.yaml`

**Change**:
```yaml
# Comment out NodePort section
# ---
# apiVersion: v1
# kind: Service
# metadata:
#   name: vespa-ui-service
#   ...
# spec:
#   type: NodePort  # <-- Comment this out
#   ...

# Uncomment LoadBalancer section
---
apiVersion: v1
kind: Service
metadata:
  name: vespa-ui-service
  namespace: onyx-infra
  labels:
    app: vespa
    component: ui
spec:
  type: LoadBalancer  # <-- Use this
  ports:
    - name: config-ui
      port: 19071
      targetPort: 19071
      protocol: TCP
    - name: query-ui
      port: 8081
      targetPort: 8081
      protocol: TCP
  selector:
    app: vespa
```

### Step 2: Apply and Get External IP

```bash
# Apply manifest
kubectl apply -f 03-vespa-ui-service.yaml

# Wait for LoadBalancer to get external IP (may take 1-2 minutes)
kubectl get svc -n onyx-infra vespa-ui-service -w

# Access Vespa UI
http://<external-ip>:19071
```

**Example Output:**
```
NAME                TYPE           EXTERNAL-IP      PORT(S)
vespa-ui-service    LoadBalancer   35.123.45.67    19071:30190/TCP
```

Access: `http://35.123.45.67:19071`

---

## ✅ Option 4: Ingress (Production - Most Secure)

**Best for**: Production deployments with domain names

### Prerequisites

- Ingress controller installed (NGINX, Traefik, etc.)
- Domain name configured
- SSL certificate (optional but recommended)

### Step 1: Create NodePort or LoadBalancer Service First

You still need the service from Option 2 or 3.

### Step 2: Create Ingress Manifest

**File**: `onyx-k8s-infrastructure/manifests/03-vespa-ui-ingress.yaml` (new file)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vespa-ui-ingress
  namespace: onyx-infra
  annotations:
    # For NGINX Ingress Controller
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    # Optional: Add authentication
    # nginx.ingress.kubernetes.io/auth-type: basic
    # nginx.ingress.kubernetes.io/auth-secret: vespa-ui-auth
spec:
  ingressClassName: nginx  # Change to your ingress class
  rules:
    - host: vespa-ui.yourdomain.com  # CHANGE THIS to your domain
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: vespa-ui-service
                port:
                  number: 19071
```

### Step 3: Apply and Access

```bash
# Apply ingress
kubectl apply -f 03-vespa-ui-ingress.yaml

# Access via domain
http://vespa-ui.yourdomain.com
```

---

## 🔧 Complete Example: NodePort Setup

### Files to Create/Modify

**1. New File**: `onyx-k8s-infrastructure/manifests/03-vespa-ui-service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: vespa-ui-service
  namespace: onyx-infra
  labels:
    app: vespa
    component: ui
spec:
  type: NodePort
  ports:
    - name: config-ui
      port: 19071
      targetPort: 19071
      nodePort: 30190
      protocol: TCP
    - name: query-ui
      port: 8081
      targetPort: 8081
      nodePort: 30191
      protocol: TCP
  selector:
    app: vespa
```

**2. No changes needed** to existing `03-vespa.yaml` (keep it as is)

### Apply Changes

```bash
cd /Users/chihebmhamdi/Desktop/onyx/onyx-k8s-infrastructure/manifests

# Apply new service
kubectl apply -f 03-vespa-ui-service.yaml

# Verify
kubectl get svc -n onyx-infra | grep vespa
```

**Expected Output:**
```
NAME                TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)
vespa-service       ClusterIP   None          <none>        19071/TCP,8081/TCP
vespa-ui-service    NodePort    10.96.1.23    <none>        19071:30190/TCP,8081:30191/TCP
```

### Access Vespa UI

```bash
# Get node IP
kubectl get nodes -o wide

# Access (replace <node-ip> with actual IP)
http://<node-ip>:30190
```

---

## 🔒 Security Considerations

### Option 1: Port Forward (Most Secure)
- ✅ Only accessible from your machine
- ✅ No external exposure
- ✅ No firewall rules needed

### Option 2: NodePort
- ⚠️ Exposes port on all nodes
- ⚠️ Accessible from anywhere that can reach node IP
- ✅ Can restrict with firewall rules
- ✅ Can use NetworkPolicy

### Option 3: LoadBalancer
- ⚠️ Publicly accessible (unless using private LoadBalancer)
- ⚠️ Exposes service to internet
- ✅ Can restrict with security groups (cloud)
- ✅ Can use NetworkPolicy

### Option 4: Ingress
- ✅ Can add authentication
- ✅ Can use SSL/TLS
- ✅ Can restrict by IP
- ✅ Most production-ready

---

## 🚀 Quick Start (Recommended)

**For immediate access (development):**

```bash
# Option 1: Port forward (no changes needed)
kubectl port-forward -n onyx-infra svc/vespa-service 19071:19071
# Then open: http://localhost:19071
```

**For persistent access (testing):**

```bash
# Option 2: Apply NodePort service
kubectl apply -f onyx-k8s-infrastructure/manifests/03-vespa-ui-service.yaml

# Get node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# Access
echo "Vespa UI: http://${NODE_IP}:30190"
```

---

## 📝 Summary

### What You Need to Do

1. **Choose an option** (recommended: NodePort for dev, Ingress for prod)

2. **Create/Modify files**:
   - ✅ `03-vespa-ui-service.yaml` (already created)
   - ✅ `03-vespa-ui-ingress.yaml` (if using Ingress)

3. **Apply manifests**:
   ```bash
   kubectl apply -f 03-vespa-ui-service.yaml
   ```

4. **Access UI**:
   - Port Forward: `http://localhost:19071`
   - NodePort: `http://<node-ip>:30190`
   - LoadBalancer: `http://<external-ip>:19071`
   - Ingress: `http://vespa-ui.yourdomain.com`

### What You DON'T Need to Change

- ❌ **Don't modify** `03-vespa.yaml` (keep it as is)
- ❌ **Don't delete** existing `vespa-service` (it's needed for internal access)
- ❌ **Don't change** StatefulSet configuration

---

## 🎯 Recommended Approach

**For Development:**
- Use **Port Forward** (no changes needed)

**For Testing/Staging:**
- Use **NodePort** service (apply `03-vespa-ui-service.yaml`)

**For Production:**
- Use **Ingress** with authentication and SSL

---

**Last Updated**: 2024  
**Version**: 1.0

