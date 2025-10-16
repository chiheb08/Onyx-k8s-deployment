# Air-Gapped Model Servers Deployment Guide for OpenShift

**Complete guide for deploying Onyx model servers in restricted OpenShift environments without internet access.**

---

## 🚨 The Problem

Your OpenShift cluster has **network restrictions** which means:
- ❌ Pods cannot access internet
- ❌ Cannot download models from Hugging Face Hub
- ❌ Model servers will fail to start if models not cached
- ❌ `emptyDir` volumes lose models on pod restart

**Current Issue:**
```
Pod starts → Tries to download models from huggingface.co → Network blocked → Pod fails
```

---

## ✅ The Solution: Pre-loaded Persistent Volumes

We need to:
1. **Pre-download models** on a machine WITH internet access
2. **Upload models** to a PersistentVolume (PV) in OpenShift
3. **Mount the PV** to model server pods
4. **Models are available offline** - no internet needed!

---

## 📋 Complete Deployment Strategy

```
┌─────────────────────────────────────────────────────────────────────┐
│                     DEPLOYMENT ARCHITECTURE                         │
└─────────────────────────────────────────────────────────────────────┘

STEP 1: Pre-download Models (On Machine with Internet)
═══════════════════════════════════════════════════════
┌──────────────────┐
│  Your Laptop     │  Internet ✅
│  (or Jump Host)  │
│                  │  1. Download models from Hugging Face
│                  │  2. Package into tar.gz
│                  │  3. Transfer to OpenShift environment
└──────────────────┘
        │
        │ (scp/transfer)
        ▼
┌──────────────────┐
│  Bastion/Jump    │  Internet ❌ (but can transfer files)
│  Host            │
│                  │  4. Upload models to PV
└──────────────────┘
        │
        │ (oc rsync or mount PV)
        ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    OPENSHIFT CLUSTER                                │
│                                                                     │
│  ┌─────────────────────────────────────────────────────┐           │
│  │  PersistentVolume (PV)                              │           │
│  │  Type: NFS / Ceph / GlusterFS / etc.               │           │
│  │  Size: 10Gi                                         │           │
│  │  StorageClass: nfs-example                          │           │
│  │                                                     │           │
│  │  Contents:                                          │           │
│  │  /huggingface-models/                               │           │
│  │  ├── models--nomic-ai--nomic-embed-text-v1/        │           │
│  │  ├── models--mixedbread-ai--mxbai-rerank-xsmall-v1/│           │
│  │  ├── models--onyx-dot-app--hybrid-intent-.../      │           │
│  │  └── models--onyx-dot-app--information-content-.../ │           │
│  └─────────────────────────────────────────────────────┘           │
│                          │                                          │
│                          │ (Mount as ReadOnlyMany)                 │
│           ┌──────────────┴───────────────┐                         │
│           ▼                              ▼                         │
│  ┌────────────────────┐       ┌────────────────────┐              │
│  │ Inference Server   │       │ Indexing Server    │              │
│  │ Pod                │       │ Pod                │              │
│  │                    │       │                    │              │
│  │ Volume Mount:      │       │ Volume Mount:      │              │
│  │ /app/.cache/       │       │ /app/.cache/       │              │
│  │ huggingface/       │       │ huggingface/       │              │
│  │ (from PV)          │       │ (from PV)          │              │
│  └────────────────────┘       └────────────────────┘              │
│                                                                     │
│  ✅ Models loaded from PV (no internet needed!)                    │
│  ✅ Fast startup (~1-2 minutes)                                    │
│  ✅ Shared across both servers                                     │
│  ✅ Persists across pod restarts                                   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 🔧 Step-by-Step Implementation

### STEP 1: Download Models (On Machine with Internet)

**Option A: Using Docker (Recommended)**

```bash
#!/bin/bash
# Run this on a machine with internet access (your laptop, jump host, etc.)

# Create a directory for models
mkdir -p huggingface-models
cd huggingface-models

# Pull the Onyx model server image (it has models pre-downloaded!)
docker pull onyxdotapp/onyx-model-server:nightly-20241004

# Run the container and copy out the models
docker run -d --name temp-model-server onyxdotapp/onyx-model-server:nightly-20241004 sleep infinity

# Copy models from container
docker cp temp-model-server:/app/.cache/huggingface/. ./

# Or copy from temp location if they're there
docker cp temp-model-server:/app/.cache/temp_huggingface/. ./

# Stop and remove container
docker stop temp-model-server
docker rm temp-model-server

# Check what you have
ls -lh
# You should see directories like:
# models--nomic-ai--nomic-embed-text-v1/
# models--mixedbread-ai--mxbai-rerank-xsmall-v1/
# models--onyx-dot-app--hybrid-intent-token-classifier/
# models--onyx-dot-app--information-content-model/

# Create a tarball for easy transfer
cd ..
tar -czf huggingface-models.tar.gz huggingface-models/

# Size should be ~2-3GB
ls -lh huggingface-models.tar.gz
```

**Option B: Using Python Script (If Docker not available)**

```bash
#!/bin/bash
# Run this on a machine with internet access

mkdir -p huggingface-models
cd huggingface-models

# Create a Python script to download models
cat > download_models.py << 'EOF'
#!/usr/bin/env python3
import os
os.environ['HF_HOME'] = os.getcwd()

from huggingface_hub import snapshot_download
from sentence_transformers import SentenceTransformer

print("Downloading models to:", os.getcwd())

# Download embedding model
print("\n1. Downloading nomic-ai/nomic-embed-text-v1...")
snapshot_download(repo_id='nomic-ai/nomic-embed-text-v1')
SentenceTransformer('nomic-ai/nomic-embed-text-v1', trust_remote_code=True)

# Download reranking model
print("\n2. Downloading mixedbread-ai/mxbai-rerank-xsmall-v1...")
snapshot_download(repo_id='mixedbread-ai/mxbai-rerank-xsmall-v1')

# Download Onyx custom models
print("\n3. Downloading onyx-dot-app/hybrid-intent-token-classifier...")
snapshot_download(repo_id='onyx-dot-app/hybrid-intent-token-classifier')

print("\n4. Downloading onyx-dot-app/information-content-model...")
snapshot_download(repo_id='onyx-dot-app/information-content-model')

print("\n✅ All models downloaded successfully!")
print("Models are in:", os.getcwd())
EOF

# Install dependencies
pip install huggingface_hub sentence-transformers torch transformers

# Run the download script
python3 download_models.py

# Create tarball
cd ..
tar -czf huggingface-models.tar.gz huggingface-models/
```

---

### STEP 2: Transfer Models to OpenShift Environment

**Transfer the tarball to your OpenShift environment:**

```bash
# From your laptop/machine with internet
scp huggingface-models.tar.gz user@bastion-host:/tmp/

# Or if you have direct access
scp huggingface-models.tar.gz user@openshift-node:/path/to/storage/
```

---

### STEP 3: Create PersistentVolumeClaim for Models

**File: `model-cache-pvc.yaml`**

```yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: huggingface-models-pvc
  labels:
    app: onyx-model-servers
spec:
  accessModes:
    - ReadWriteMany  # IMPORTANT: Allow multiple pods to read
  storageClassName: "nfs-example"  # Your colleague's storage class
  volumeMode: "Filesystem"
  resources:
    requests:
      storage: 10Gi  # Need ~5-6GB, request 10Gi for safety

---
# Optional: Separate PVCs for inference and indexing (if ReadWriteMany not supported)
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: inference-model-cache-pvc
  labels:
    app: inference-model-server
spec:
  accessModes:
    - ReadWriteOnce  # If ReadWriteMany not available
  storageClassName: "nfs-example"
  volumeMode: "Filesystem"
  resources:
    requests:
      storage: 5Gi

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: indexing-model-cache-pvc
  labels:
    app: indexing-model-server
spec:
  accessModes:
    - ReadWriteOnce  # If ReadWriteMany not available
  storageClassName: "nfs-example"
  volumeMode: "Filesystem"
  resources:
    requests:
      storage: 5Gi
```

**Deploy the PVC:**

```bash
oc apply -f model-cache-pvc.yaml

# Check PVC status
oc get pvc huggingface-models-pvc
# Should show: STATUS = Bound
```

---

### STEP 4: Upload Models to PersistentVolume

**Option A: Using a Helper Pod (Recommended)**

```bash
# Create a helper pod to mount the PVC and upload files
cat > model-uploader-pod.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: model-uploader
spec:
  containers:
    - name: uploader
      image: registry.access.redhat.com/ubi8/ubi:latest
      command: ["sleep", "infinity"]
      volumeMounts:
        - name: models-volume
          mountPath: /models
  volumes:
    - name: models-volume
      persistentVolumeClaim:
        claimName: huggingface-models-pvc
  restartPolicy: Never
EOF

oc apply -f model-uploader-pod.yaml

# Wait for pod to be ready
oc wait --for=condition=Ready pod/model-uploader --timeout=60s

# Copy the tarball to the pod
oc cp huggingface-models.tar.gz model-uploader:/tmp/

# Extract models inside the pod
oc exec -it model-uploader -- bash -c "
  cd /models
  tar -xzf /tmp/huggingface-models.tar.gz --strip-components=1
  ls -lh
  echo 'Models uploaded successfully!'
"

# Verify models are there
oc exec model-uploader -- ls -lh /models/
# You should see:
# models--nomic-ai--nomic-embed-text-v1/
# models--mixedbread-ai--mxbai-rerank-xsmall-v1/
# models--onyx-dot-app--hybrid-intent-token-classifier/
# models--onyx-dot-app--information-content-model/

# Clean up the uploader pod
oc delete pod model-uploader
```

**Option B: Using `oc rsync` (If PV is NFS and accessible)**

```bash
# Extract models locally
tar -xzf huggingface-models.tar.gz

# Create a temporary pod to rsync to
oc apply -f model-uploader-pod.yaml
oc wait --for=condition=Ready pod/model-uploader --timeout=60s

# Rsync models to the PV
oc rsync huggingface-models/ model-uploader:/models/ --no-perms=true

# Clean up
oc delete pod model-uploader
```

---

### STEP 5: Update Model Server Deployments to Use PVC

**Update `06-inference-model-server.yaml`:**

```yaml
# ============================================================================
# Inference Model Server for Onyx (Air-Gapped Version)
# ============================================================================
# Uses pre-loaded PersistentVolume for offline model access
# ============================================================================

---
apiVersion: v1
kind: Service
metadata:
  name: inference-model-server
  labels:
    app: inference-model-server
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 9000
      targetPort: 9000
      protocol: TCP
  selector:
    app: inference-model-server

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inference-model-server
  labels:
    app: inference-model-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: inference-model-server
  template:
    metadata:
      labels:
        app: inference-model-server
    spec:
      containers:
        - name: inference-model-server
          image: onyxdotapp/onyx-model-server:nightly-20241004
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 9000
              protocol: TCP
          env:
            - name: MODEL_SERVER_PORT
              value: "9000"
            - name: HF_HOME
              value: "/app/.cache/huggingface"
            - name: HF_HUB_OFFLINE
              value: "1"  # IMPORTANT: Force offline mode
            - name: TRANSFORMERS_OFFLINE
              value: "1"  # IMPORTANT: Force offline mode
          resources:
            requests:
              cpu: 1000m
              memory: 2Gi
            limits:
              cpu: 4000m
              memory: 8Gi
          livenessProbe:
            httpGet:
              path: /health
              port: 9000
            initialDelaySeconds: 120
            periodSeconds: 30
            timeoutSeconds: 10
            failureThreshold: 5
          readinessProbe:
            httpGet:
              path: /health
              port: 9000
            initialDelaySeconds: 60
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 10
          volumeMounts:
            - name: model-cache
              mountPath: /app/.cache/huggingface
              readOnly: true  # Read-only since models are pre-loaded
      volumes:
        - name: model-cache
          persistentVolumeClaim:
            claimName: huggingface-models-pvc  # Shared PVC
            # OR if using separate PVCs:
            # claimName: inference-model-cache-pvc
      restartPolicy: Always
```

**Update `06-indexing-model-server.yaml`:**

```yaml
# ============================================================================
# Indexing Model Server for Onyx (Air-Gapped Version)
# ============================================================================
# Uses pre-loaded PersistentVolume for offline model access
# ============================================================================

---
apiVersion: v1
kind: Service
metadata:
  name: indexing-model-server
  labels:
    app: indexing-model-server
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 9000
      targetPort: 9000
      protocol: TCP
  selector:
    app: indexing-model-server

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: indexing-model-server
  labels:
    app: indexing-model-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: indexing-model-server
  template:
    metadata:
      labels:
        app: indexing-model-server
    spec:
      containers:
        - name: indexing-model-server
          image: onyxdotapp/onyx-model-server:nightly-20241004
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 9000
              protocol: TCP
          env:
            - name: INDEXING_ONLY
              value: "True"  # Key difference from inference server
            - name: MODEL_SERVER_PORT
              value: "9000"
            - name: HF_HOME
              value: "/app/.cache/huggingface"
            - name: HF_HUB_OFFLINE
              value: "1"  # IMPORTANT: Force offline mode
            - name: TRANSFORMERS_OFFLINE
              value: "1"  # IMPORTANT: Force offline mode
          resources:
            requests:
              cpu: 1000m
              memory: 2Gi
            limits:
              cpu: 4000m
              memory: 8Gi
          livenessProbe:
            httpGet:
              path: /health
              port: 9000
            initialDelaySeconds: 120
            periodSeconds: 30
            timeoutSeconds: 10
            failureThreshold: 5
          readinessProbe:
            httpGet:
              path: /health
              port: 9000
            initialDelaySeconds: 60
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 10
          volumeMounts:
            - name: model-cache
              mountPath: /app/.cache/huggingface
              readOnly: true  # Read-only since models are pre-loaded
      volumes:
        - name: model-cache
          persistentVolumeClaim:
            claimName: huggingface-models-pvc  # Shared PVC
            # OR if using separate PVCs:
            # claimName: indexing-model-cache-pvc
      restartPolicy: Always
```

---

### STEP 6: Deploy Model Servers

```bash
# Apply the updated model server deployments
oc apply -f 06-inference-model-server.yaml
oc apply -f 06-indexing-model-server.yaml

# Watch the pods start
oc get pods -w -l app=inference-model-server
oc get pods -w -l app=indexing-model-server

# Check logs to verify models are loading from cache
oc logs -f deployment/inference-model-server
# You should see:
# "Loading nomic-ai/nomic-embed-text-v1"
# "Loaded model from local cache: /app/.cache/huggingface/models--nomic-ai..."
# NO download messages!

oc logs -f deployment/indexing-model-server
# Similar logs

# Verify they're healthy
oc get pods
# Both should show: STATUS = Running, READY = 1/1

# Test health endpoints
oc exec deployment/inference-model-server -- curl -s http://localhost:9000/health
# Should return: {"status":"healthy"}

oc exec deployment/indexing-model-server -- curl -s http://localhost:9000/health
# Should return: {"status":"healthy"}
```

---

## 🔍 Troubleshooting

### Issue 1: PVC Not Binding

```bash
# Check PVC status
oc get pvc huggingface-models-pvc
# If STATUS = Pending

# Check events
oc describe pvc huggingface-models-pvc

# Common issues:
# - StorageClass doesn't exist
# - No available PersistentVolume
# - Quota exceeded

# Check available storage classes
oc get storageclass

# Check if PV exists
oc get pv

# Ask your colleague for the correct StorageClass name
```

### Issue 2: Models Not Found

```bash
# Check if models are in the PVC
oc apply -f model-uploader-pod.yaml
oc wait --for=condition=Ready pod/model-uploader --timeout=60s
oc exec model-uploader -- ls -lh /models/

# Should show model directories
# If empty, re-upload models (see Step 4)

# Check permissions
oc exec model-uploader -- ls -la /models/
# Should be readable by all

oc delete pod model-uploader
```

### Issue 3: Pod Fails to Start - "Model Not Found"

```bash
# Check logs
oc logs deployment/inference-model-server

# If you see errors like:
# "OSError: Can't load model from https://huggingface.co/..."

# This means:
# 1. Models not in PVC, OR
# 2. HF_HUB_OFFLINE not set, OR
# 3. Volume not mounted correctly

# Verify volume mount
oc exec deployment/inference-model-server -- ls -lh /app/.cache/huggingface/
# Should show model directories

# Verify environment variables
oc exec deployment/inference-model-server -- env | grep HF_
# Should show:
# HF_HOME=/app/.cache/huggingface
# HF_HUB_OFFLINE=1
```

### Issue 4: ReadWriteMany Not Supported

```bash
# If your storage doesn't support ReadWriteMany:

# Option A: Use separate PVCs for each server (already shown above)

# Option B: Use ReadWriteOnce and run only one replica
# This works but limits scaling

# Option C: Use a shared NFS/Ceph/GlusterFS storage that supports ReadWriteMany
# Ask your infrastructure team
```

---

## 📊 Architecture Summary

```
┌─────────────────────────────────────────────────────────────────────┐
│                   AIR-GAPPED DEPLOYMENT FLOW                        │
└─────────────────────────────────────────────────────────────────────┘

Pre-deployment (One-time):
══════════════════════════
1. Download models on machine with internet (2-3GB)
2. Transfer to OpenShift environment
3. Create PVC for model storage (10Gi)
4. Upload models to PVC

Deployment (Repeatable):
════════════════════════
5. Mount PVC to model server pods (read-only)
6. Set HF_HUB_OFFLINE=1 (force offline mode)
7. Pods start and load models from PVC
8. No internet access needed! ✅

Benefits:
═════════
✅ Works in air-gapped environments
✅ Fast startup (1-2 minutes, no download)
✅ Models persist across pod restarts
✅ Can be shared between both servers (ReadWriteMany)
✅ Complies with network restrictions
✅ Predictable and reliable
```

---

## 🎯 Quick Reference Commands

```bash
# === PRE-DEPLOYMENT (On Machine with Internet) ===

# Download models using Docker
docker pull onyxdotapp/onyx-model-server:nightly-20241004
docker run -d --name temp onyxdotapp/onyx-model-server:nightly-20241004 sleep infinity
docker cp temp:/app/.cache/huggingface/. ./huggingface-models/
docker stop temp && docker rm temp
tar -czf huggingface-models.tar.gz huggingface-models/

# Transfer to OpenShift environment
scp huggingface-models.tar.gz user@bastion:/tmp/


# === IN OPENSHIFT ===

# Create PVC
oc apply -f model-cache-pvc.yaml
oc get pvc huggingface-models-pvc

# Upload models
oc apply -f model-uploader-pod.yaml
oc wait --for=condition=Ready pod/model-uploader --timeout=60s
oc cp huggingface-models.tar.gz model-uploader:/tmp/
oc exec -it model-uploader -- tar -xzf /tmp/huggingface-models.tar.gz -C /models --strip-components=1
oc exec model-uploader -- ls -lh /models/
oc delete pod model-uploader

# Deploy model servers
oc apply -f 06-inference-model-server.yaml
oc apply -f 06-indexing-model-server.yaml

# Verify
oc get pods -l app=inference-model-server
oc get pods -l app=indexing-model-server
oc logs -f deployment/inference-model-server
oc exec deployment/inference-model-server -- curl http://localhost:9000/health


# === MAINTENANCE ===

# Update models (re-run upload process)
# Scale down model servers first
oc scale deployment inference-model-server --replicas=0
oc scale deployment indexing-model-server --replicas=0

# Upload new models
oc apply -f model-uploader-pod.yaml
oc cp new-models.tar.gz model-uploader:/tmp/
oc exec -it model-uploader -- bash -c "rm -rf /models/* && tar -xzf /tmp/new-models.tar.gz -C /models --strip-components=1"
oc delete pod model-uploader

# Scale up
oc scale deployment inference-model-server --replicas=1
oc scale deployment indexing-model-server --replicas=1
```

---

## 📋 Checklist for Your Colleague

Ask your colleague to confirm:

- [ ] **StorageClass name**: What is the exact name? (You said `nfs-example`)
- [ ] **ReadWriteMany support**: Does the storage support multiple pods reading?
- [ ] **Storage quota**: Do you have at least 10Gi available?
- [ ] **Access mode**: Can pods in your namespace access the PV?
- [ ] **File transfer method**: How can you transfer the 2-3GB tarball? (scp, upload portal, etc.)
- [ ] **Image registry**: Can you pull `onyxdotapp/onyx-model-server:nightly-20241004`? (Or need to push to internal registry?)

---

## 🚀 Summary

**For air-gapped OpenShift with network restrictions:**

1. **Pre-download models** on a machine with internet (2-3GB)
2. **Create a PVC** using your colleague's storage class (`nfs-example`)
3. **Upload models** to the PVC using a helper pod
4. **Mount PVC** to both model servers (read-only, shared)
5. **Set offline mode** with `HF_HUB_OFFLINE=1` and `TRANSFORMERS_OFFLINE=1`
6. **Deploy** - models load from PVC, no internet needed!

**Key Environment Variables:**
- `HF_HOME=/app/.cache/huggingface` - Where to look for models
- `HF_HUB_OFFLINE=1` - Don't try to download from Hugging Face
- `TRANSFORMERS_OFFLINE=1` - Force offline mode for transformers library

**Benefits:**
- ✅ Works without internet access
- ✅ Fast startup (1-2 minutes)
- ✅ Persistent across restarts
- ✅ Compliant with network restrictions
- ✅ Production-ready and reliable

---

**This is the recommended approach for restricted/air-gapped OpenShift environments!** 🎉

