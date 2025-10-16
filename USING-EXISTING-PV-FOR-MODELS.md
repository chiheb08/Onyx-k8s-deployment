# Using Existing PV with Pre-loaded Models - Quick Guide

**Scenario:** You have an existing PersistentVolume (PV) in your OpenShift cluster that already contains the Hugging Face models. You need to configure the inference and indexing model servers to use this existing PV.

---

## 🎯 The Problem

- ✅ **You HAVE:** An existing PV with models already stored
- ❌ **You DON'T HAVE:** Internet access in pods
- ❌ **You CAN'T:** Download models from Hugging Face
- ✅ **You NEED:** Model servers to use the existing PV

---

## 📋 What You Need to Know from Your Colleague

Before starting, ask your colleague for these details:

1. **PV Name or StorageClass Name**: What is the name of the existing PV or StorageClass?
2. **PV Path**: What is the path inside the PV where models are stored?
3. **Access Mode**: Does it support `ReadWriteMany` or only `ReadWriteOnce`?
4. **PV Size**: How much storage is allocated?

**Example answers:**
- PV Name: `huggingface-models-pv` or StorageClass: `nfs-models`
- Path: `/huggingface-models/` or `/models/cache/`
- Access Mode: `ReadWriteMany` (both servers can share) or `ReadWriteOnce` (need separate PVCs)
- Size: `10Gi`

---

## 🔧 Solution: Two Scenarios

### Scenario A: PV Supports ReadWriteMany (Recommended)

**One PVC shared by both model servers**

### Scenario B: PV Only Supports ReadWriteOnce

**Two separate PVCs (one for inference, one for indexing)**

---

## 📝 SCENARIO A: ReadWriteMany (Both Servers Share One PV)

### Step 1: Create PVC to Claim the Existing PV

**File: `pvc-shared-models.yaml`**

```yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: huggingface-models-pvc
  labels:
    app: onyx-model-servers
spec:
  # IMPORTANT: Use ReadWriteMany so both servers can read simultaneously
  accessModes:
    - ReadWriteMany
  
  # OPTION 1: If you know the StorageClass name
  storageClassName: "nfs-models"  # ← Ask your colleague for the exact name
  
  # OPTION 2: If you want to bind to a specific PV by name
  # Remove storageClassName and add:
  # volumeName: "huggingface-models-pv"  # ← The existing PV name
  
  volumeMode: Filesystem
  
  resources:
    requests:
      storage: 10Gi  # ← Should match or be less than the PV size
```

**Deploy the PVC:**

```bash
# Create the PVC
oc apply -f pvc-shared-models.yaml

# Check if it binds to the existing PV
oc get pvc huggingface-models-pvc
# Expected: STATUS = Bound

# Verify which PV it's bound to
oc get pvc huggingface-models-pvc -o yaml | grep volumeName
# Should show the PV name

# Check the PV details
oc describe pv <pv-name-from-above>
```

---

### Step 2: Update Inference Model Server to Use the PVC

**File: `06-inference-model-server.yaml`**

Replace the existing file with this:

```yaml
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
            # ==============================================================
            # CRITICAL: These environment variables force offline mode
            # ==============================================================
            - name: HF_HOME
              value: "/app/.cache/huggingface"
            - name: HF_HUB_OFFLINE
              value: "1"  # Force offline - don't try to download!
            - name: TRANSFORMERS_OFFLINE
              value: "1"  # Force transformers to use cached models only
            - name: MODEL_SERVER_PORT
              value: "9000"
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
            # ==============================================================
            # CRITICAL: Mount the PVC to the Hugging Face cache directory
            # ==============================================================
            - name: model-cache
              mountPath: /app/.cache/huggingface
              readOnly: true  # Read-only since models are pre-loaded
      volumes:
        - name: model-cache
          persistentVolumeClaim:
            claimName: huggingface-models-pvc  # ← The PVC we created above
      restartPolicy: Always
```

---

### Step 3: Update Indexing Model Server to Use the Same PVC

**File: `06-indexing-model-server.yaml`**

Replace the existing file with this:

```yaml
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
            # ==============================================================
            # CRITICAL: INDEXING_ONLY=True makes this the indexing server
            # ==============================================================
            - name: INDEXING_ONLY
              value: "True"
            # ==============================================================
            # CRITICAL: These environment variables force offline mode
            # ==============================================================
            - name: HF_HOME
              value: "/app/.cache/huggingface"
            - name: HF_HUB_OFFLINE
              value: "1"  # Force offline - don't try to download!
            - name: TRANSFORMERS_OFFLINE
              value: "1"  # Force transformers to use cached models only
            - name: MODEL_SERVER_PORT
              value: "9000"
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
            # ==============================================================
            # CRITICAL: Mount the SAME PVC to the Hugging Face cache directory
            # ==============================================================
            - name: model-cache
              mountPath: /app/.cache/huggingface
              readOnly: true  # Read-only since models are pre-loaded
      volumes:
        - name: model-cache
          persistentVolumeClaim:
            claimName: huggingface-models-pvc  # ← Same PVC as inference server!
      restartPolicy: Always
```

---

### Step 4: Deploy Both Model Servers

```bash
# Deploy the inference model server
oc apply -f 06-inference-model-server.yaml

# Deploy the indexing model server
oc apply -f 06-indexing-model-server.yaml

# Watch pods starting
oc get pods -w

# Expected output after ~1-2 minutes:
# NAME                                     READY   STATUS    RESTARTS   AGE
# inference-model-server-xxxxxxxxx-xxxxx   1/1     Running   0          2m
# indexing-model-server-xxxxxxxxx-xxxxx    1/1     Running   0          2m
```

---

### Step 5: Verify Models Are Loading from PV

```bash
# Check inference server logs
oc logs deployment/inference-model-server

# You should see:
# ✅ "Loading nomic-ai/nomic-embed-text-v1"
# ✅ "Loaded model from local cache: /app/.cache/huggingface/models--nomic-ai..."
# ❌ NO messages about downloading from huggingface.co!

# Check indexing server logs
oc logs deployment/indexing-model-server

# Similar output, should NOT see any download attempts

# Test health endpoints
oc exec deployment/inference-model-server -- curl -s http://localhost:9000/health
# Expected: {"status":"healthy"}

oc exec deployment/indexing-model-server -- curl -s http://localhost:9000/health
# Expected: {"status":"healthy"}
```

---

## 📝 SCENARIO B: ReadWriteOnce (Separate PVCs for Each Server)

If your PV only supports `ReadWriteOnce`, you need **two separate PVCs**.

### Step 1: Create Two Separate PVCs

**File: `pvc-separate-models.yaml`**

```yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: inference-model-cache-pvc
  labels:
    app: inference-model-server
spec:
  accessModes:
    - ReadWriteOnce  # Only one pod can mount this
  storageClassName: "nfs-models"  # ← Your StorageClass name
  volumeMode: Filesystem
  resources:
    requests:
      storage: 5Gi  # Half the size since models will be duplicated

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: indexing-model-cache-pvc
  labels:
    app: indexing-model-server
spec:
  accessModes:
    - ReadWriteOnce  # Only one pod can mount this
  storageClassName: "nfs-models"  # ← Your StorageClass name
  volumeMode: Filesystem
  resources:
    requests:
      storage: 5Gi
```

**Note:** With `ReadWriteOnce`, you'll need to copy the models to both PVCs separately (ask your colleague how to do this, or they may have already set it up).

---

### Step 2: Update Model Servers to Use Separate PVCs

In `06-inference-model-server.yaml`, change the volume section:

```yaml
      volumes:
        - name: model-cache
          persistentVolumeClaim:
            claimName: inference-model-cache-pvc  # ← Specific to inference server
```

In `06-indexing-model-server.yaml`, change the volume section:

```yaml
      volumes:
        - name: model-cache
          persistentVolumeClaim:
            claimName: indexing-model-cache-pvc  # ← Specific to indexing server
```

---

## 🔍 Troubleshooting

### Issue 1: PVC Stays in "Pending" Status

```bash
# Check PVC status
oc get pvc huggingface-models-pvc
# If STATUS = Pending

# Check why it's pending
oc describe pvc huggingface-models-pvc

# Common reasons:
# 1. StorageClass name is wrong
# 2. No PV available with the requested size
# 3. Access mode mismatch (asking for ReadWriteMany but PV only supports ReadWriteOnce)

# Solution: Ask your colleague for the correct StorageClass name and access mode
```

### Issue 2: Pod Fails with "Model Not Found" Error

```bash
# Check if models are actually in the PV
# Create a debug pod to check the PV contents:

cat > debug-pod.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: debug-pv
spec:
  containers:
    - name: debug
      image: registry.access.redhat.com/ubi8/ubi:latest
      command: ["sleep", "infinity"]
      volumeMounts:
        - name: models
          mountPath: /models
  volumes:
    - name: models
      persistentVolumeClaim:
        claimName: huggingface-models-pvc
EOF

oc apply -f debug-pod.yaml
oc wait --for=condition=Ready pod/debug-pv --timeout=60s

# Check what's in the PV
oc exec debug-pv -- ls -lh /models/

# You should see directories like:
# models--nomic-ai--nomic-embed-text-v1/
# models--mixedbread-ai--mxbai-rerank-xsmall-v1/
# etc.

# If you DON'T see these, the PV might be empty or the path is wrong!
# Ask your colleague where exactly the models are stored in the PV

# Clean up
oc delete pod debug-pv
```

### Issue 3: Pod Still Tries to Download from Internet

```bash
# Check if offline environment variables are set
oc exec deployment/inference-model-server -- env | grep HF_

# You MUST see:
# HF_HOME=/app/.cache/huggingface
# HF_HUB_OFFLINE=1
# TRANSFORMERS_OFFLINE=1

# If missing, the YAML file wasn't applied correctly
# Redeploy:
oc delete deployment inference-model-server
oc apply -f 06-inference-model-server.yaml
```

### Issue 4: Wrong Path Inside PV

```bash
# If models are stored in a different path (e.g., /models/cache/ instead of /models/)
# You need to adjust the mountPath

# Example: Models are in /models/huggingface/ in the PV
# Change the volumeMount in both YAML files:

volumeMounts:
  - name: model-cache
    mountPath: /app/.cache/huggingface
    subPath: huggingface  # ← Mount only the huggingface subdirectory

# Ask your colleague for the exact directory structure in the PV
```

---

## 📊 Summary: What Changes You Need to Make

### 1. Create PVC (One File)

**File: `pvc-shared-models.yaml`** (Scenario A) or **`pvc-separate-models.yaml`** (Scenario B)

**Key Configuration:**
- `storageClassName`: Ask your colleague
- `accessModes`: `ReadWriteMany` (preferred) or `ReadWriteOnce`
- `storage`: Match or be less than PV size

### 2. Update Both Model Server YAMLs

**In BOTH `06-inference-model-server.yaml` AND `06-indexing-model-server.yaml`:**

**Add these environment variables:**
```yaml
env:
  - name: HF_HOME
    value: "/app/.cache/huggingface"
  - name: HF_HUB_OFFLINE
    value: "1"
  - name: TRANSFORMERS_OFFLINE
    value: "1"
```

**Update the volumes section:**
```yaml
volumeMounts:
  - name: model-cache
    mountPath: /app/.cache/huggingface
    readOnly: true

volumes:
  - name: model-cache
    persistentVolumeClaim:
      claimName: huggingface-models-pvc  # ← Your PVC name
```

---

## ✅ Quick Checklist

Before deploying, make sure:

- [ ] You know the **StorageClass name** or **PV name**
- [ ] You know if it's **ReadWriteMany** or **ReadWriteOnce**
- [ ] You know the **path inside the PV** where models are stored
- [ ] The PV **already has models** (check with debug pod if unsure)
- [ ] You've added **HF_HUB_OFFLINE=1** to both model server YAMLs
- [ ] You've added **TRANSFORMERS_OFFLINE=1** to both model server YAMLs
- [ ] You've mounted the PVC to **/app/.cache/huggingface**
- [ ] The **INDEXING_ONLY=True** env var is in the indexing server YAML

---

## 🚀 Deployment Commands (Copy-Paste Ready)

```bash
# Step 1: Create PVC
oc apply -f pvc-shared-models.yaml

# Step 2: Verify PVC is bound
oc get pvc huggingface-models-pvc
# Wait until STATUS = Bound

# Step 3: (Optional) Verify models are in the PV
# See "Issue 2" in Troubleshooting section above

# Step 4: Deploy model servers
oc apply -f 06-inference-model-server.yaml
oc apply -f 06-indexing-model-server.yaml

# Step 5: Watch pods start
oc get pods -w
# Wait for both to show: READY = 1/1, STATUS = Running

# Step 6: Check logs for successful model loading
oc logs deployment/inference-model-server | grep -i "loaded model"
oc logs deployment/indexing-model-server | grep -i "loaded model"

# Step 7: Test health endpoints
oc exec deployment/inference-model-server -- curl -s http://localhost:9000/health
oc exec deployment/indexing-model-server -- curl -s http://localhost:9000/health
```

---

## 🎯 The Key Differences from Default Deployment

**What's Different:**

| Default (with internet) | Your Setup (no internet, existing PV) |
|------------------------|----------------------------------------|
| Models downloaded on first start | Models pre-loaded in PV |
| `emptyDir` volumes | PersistentVolumeClaim |
| No offline env vars | `HF_HUB_OFFLINE=1` required |
| ~5-15 min first startup | ~1-2 min startup |
| Internet required | No internet needed ✅ |

**Critical Environment Variables You MUST Add:**
```yaml
- name: HF_HUB_OFFLINE
  value: "1"
- name: TRANSFORMERS_OFFLINE
  value: "1"
```

**Critical Volume Configuration:**
```yaml
volumes:
  - name: model-cache
    persistentVolumeClaim:
      claimName: huggingface-models-pvc  # ← Use existing PV
```

---

**This is exactly what you need to use your existing PV with pre-loaded models!** 🎉

