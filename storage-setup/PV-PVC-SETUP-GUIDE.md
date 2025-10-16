# PV and PVC Setup Guide - Complete Explanation

**Understanding and creating PersistentVolume (PV) and PersistentVolumeClaim (PVC) for NFS storage in Production and Dev clusters**

---

## 🎯 Your Situation Explained

### What Your Team Has

Your infrastructure team manages **TWO separate NFS servers** with pre-loaded Hugging Face models:

```
┌─────────────────────────────────────────────────────────────────┐
│                  INFRASTRUCTURE TEAM SETUP                      │
└─────────────────────────────────────────────────────────────────┘

Production Environment:
━━━━━━━━━━━━━━━━━━━━━
NFS Server: 10.x.x.x (example IP)
Storage: 800 Gi
Path: /exports/huggingface-models (example)
Contents: Pre-loaded Hugging Face models (~5-6GB used)
Access: NFSv3 or NFSv4

Dev Environment:
━━━━━━━━━━━━━━━━
NFS Server: 10.y.y.y (different IP)
Storage: 800 Gi
Path: /exports/huggingface-models (example)
Contents: Same models as Production
Access: NFSv3 or NFSv4
```

### What You Need to Do

You need to create **TWO Kubernetes resources** in each cluster:

1. **PersistentVolume (PV)** - Represents the NFS storage
2. **PersistentVolumeClaim (PVC)** - Claims/binds to the PV

```
┌─────────────────────────────────────────────────────────────────┐
│                       YOUR TASK                                 │
└─────────────────────────────────────────────────────────────────┘

For EACH cluster (Prod and Dev):

Step 1: Create PV
        └─ Points to the NFS server (specific IP for that cluster)
        └─ Defines size: 800Gi
        └─ Defines access mode: ReadWriteMany

Step 2: Create PVC
        └─ Requests storage from the PV
        └─ Binds to the PV you created
        └─ Used by model server pods
```

---

## 📋 Complete Architecture Diagram

```
┌═══════════════════════════════════════════════════════════════════════════┐
║                    PRODUCTION CLUSTER ARCHITECTURE                        ║
╚═══════════════════════════════════════════════════════════════════════════╝

INFRASTRUCTURE LAYER (Your Team Manages):
═══════════════════════════════════════════

┌──────────────────────────────────────┐
│  NFS Server (Production)             │
│  ─────────────────────────           │
│  IP: 10.x.x.x                        │  ← Team provides this
│  Size: 800 Gi                        │
│  Protocol: NFSv3/NFSv4               │
│                                      │
│  Exported Path:                      │
│  /exports/huggingface-models         │  ← Team provides this
│                                      │
│  Contents:                           │
│  ├── models--nomic-ai--nomic-...    │
│  ├── models--mixedbread-ai--...     │
│  └── models--onyx-dot-app--...      │
│                                      │
│  Total Used: ~5-6GB                  │
│  Total Available: 800GB              │
└──────────────────────────────────────┘
            ↑
            │ (NFS mount)
            │


KUBERNETES LAYER (You Create):
═══════════════════════════════

Step 1: Create PersistentVolume
┌──────────────────────────────────────┐
│  PersistentVolume                    │
│  ────────────────                    │
│  name: huggingface-models-pv-prod    │  ← YOU choose this name
│  capacity: 10Gi                      │  ← YOU choose this (≤ 800Gi)
│  accessModes: ReadWriteMany          │
│  nfs:                                │
│    server: 10.x.x.x                  │  ← From team (Prod IP)
│    path: /exports/huggingface-models │  ← From team
│                                      │
│  Status: Available                   │  ← After creation
└──────────────────────────────────────┘
            ↑
            │ (Binding)
            │
Step 2: Create PersistentVolumeClaim
┌──────────────────────────────────────┐
│  PersistentVolumeClaim               │
│  ──────────────────────              │
│  name: huggingface-models-pvc        │  ← YOU choose this name
│  storage: 10Gi                       │  ← Must match PV
│  accessModes: ReadWriteMany          │  ← Must match PV
│  volumeName: huggingface-models-...  │  ← References PV
│                                      │
│  Status: Bound                       │  ← After binding
└──────────────────────────────────────┘
            ↑
            │ (Mount)
            │
Step 3: Pods Use the PVC
┌──────────────────────────────────────────────────────────────┐
│  Pod: inference-model-server-xxx                             │
│  ────────────────────────────────────                        │
│  volumeMounts:                                               │
│    - name: model-cache                                       │
│      mountPath: /app/.cache/huggingface                      │
│  volumes:                                                    │
│    - name: model-cache                                       │
│      persistentVolumeClaim:                                  │
│        claimName: huggingface-models-pvc  ← References PVC   │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  Pod: indexing-model-server-xxx                              │
│  ───────────────────────────────────                         │
│  volumeMounts:                                               │
│    - name: model-cache                                       │
│      mountPath: /app/.cache/huggingface                      │
│  volumes:                                                    │
│    - name: model-cache                                       │
│      persistentVolumeClaim:                                  │
│        claimName: huggingface-models-pvc  ← Same PVC!        │
└──────────────────────────────────────────────────────────────┘


┌═══════════════════════════════════════════════════════════════════════════┐
║                        DEV CLUSTER ARCHITECTURE                           ║
╚═══════════════════════════════════════════════════════════════════════════╝

Same structure, but with Dev NFS Server:

NFS Server (Dev)
├─ IP: 10.y.y.y                          ← Different IP!
├─ Size: 800 Gi
└─ Path: /exports/huggingface-models     ← Same path (or different)

PersistentVolume
├─ name: huggingface-models-pv-dev       ← Different name!
└─ nfs.server: 10.y.y.y                  ← Points to Dev NFS!

PersistentVolumeClaim
└─ name: huggingface-models-pvc          ← Same name (but in different cluster)
```

---

## 🔍 Detailed Concepts Explained

### 1. What is NFS?

**NFS (Network File System)** is a protocol that allows you to share files over a network.

**Think of it as:** A shared network drive that multiple computers can access at the same time.

**In your case:**
- Infrastructure team set up NFS servers
- Pre-loaded Hugging Face models on them
- Each environment (Prod/Dev) has its own NFS server
- Both have 800Gi capacity but only ~5-6GB is used

### 2. What is a PersistentVolume (PV)?

**PV** is a Kubernetes resource that represents a piece of storage in your cluster.

**Think of it as:** A "registration" that tells Kubernetes "there's an NFS share available at this IP address."

**Key characteristics:**
- **Cluster-wide resource** (not namespaced)
- **Created by cluster admin** (you, in this case)
- **Points to actual storage** (NFS server IP and path)
- **Defines capacity** (you can claim less than the NFS server's full size)

### 3. What is a PersistentVolumeClaim (PVC)?

**PVC** is a request for storage by a user/application.

**Think of it as:** A "reservation" that says "I want to use that storage."

**Key characteristics:**
- **Namespaced resource** (belongs to a specific namespace)
- **Created by application deployer** (you)
- **Binds to a PV** (locks it for your use)
- **Used by pods** (pods reference the PVC, not the PV)

### 4. Why Create Both?

```
┌─────────────────────────────────────────────────────────────────┐
│                  WHY TWO RESOURCES?                             │
└─────────────────────────────────────────────────────────────────┘

Separation of Concerns:
━━━━━━━━━━━━━━━━━━━━━━

Admin/Infrastructure Team:
├─ Manages physical storage (NFS servers)
├─ Creates PVs (tells Kubernetes where storage is)
└─ Controls capacity and access policies

Application Team (You):
├─ Creates PVCs (requests storage)
├─ Doesn't need to know NFS details
└─ Just uses the claim in pods


Why Not Directly Mount NFS in Pods?
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

❌ Without PV/PVC (direct NFS mount):
   Every pod needs NFS server IP and path hardcoded
   Hard to change storage backend later
   Security risks (exposing NFS details)

✅ With PV/PVC:
   Pods only reference PVC name (abstraction!)
   Easy to change storage backend (just update PV)
   Better security (NFS details in PV, not pod specs)
```

---

## 📝 YAML Files for Your Environment

### File 1: PersistentVolume (Create This FIRST)

**`01-pv-huggingface-models.yaml`**

```yaml
# ============================================================================
# PersistentVolume for Hugging Face Models (NFS)
# ============================================================================
# This PV points to your infrastructure team's NFS server
# Create ONE of these per cluster (Production or Dev)
# 
# IMPORTANT: Update the NFS server IP and path for each environment!
# ============================================================================

---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: huggingface-models-pv
  labels:
    type: nfs
    app: onyx-model-servers
spec:
  # How much storage to make available from this NFS share
  # NOTE: You can claim less than the NFS server's total (800Gi)
  # We only need ~10Gi since models are ~5-6GB
  capacity:
    storage: 10Gi
  
  # ReadWriteMany = multiple pods can read/write simultaneously
  # This is perfect for our use case (both model servers can share)
  accessModes:
    - ReadWriteMany
  
  # persistentVolumeReclaimPolicy determines what happens when PVC is deleted
  # Retain = keep the data (recommended for pre-loaded models)
  # Delete = delete the data (dangerous!)
  # Recycle = deprecated, don't use
  persistentVolumeReclaimPolicy: Retain
  
  # storageClassName (OPTIONAL)
  # Leave empty for static provisioning (manual binding)
  # Or specify a class name if you want
  storageClassName: ""
  
  # mountOptions for NFS (adjust based on your NFS server version)
  mountOptions:
    - hard           # Retry NFS requests if server is unavailable
    - nfsvers=4.1    # NFS version (change to 3 if needed)
    - timeo=600      # Timeout in deciseconds (60 seconds)
    - retrans=2      # Number of retries before giving up
  
  # NFS-specific configuration
  nfs:
    # ================================================================
    # CHANGE THIS: NFS server IP address
    # Production: Use production NFS IP (e.g., 10.x.x.x)
    # Dev: Use dev NFS IP (e.g., 10.y.y.y)
    # Ask your infrastructure team for the exact IP
    # ================================================================
    server: 10.0.0.100  # ← REPLACE WITH YOUR NFS SERVER IP
    
    # ================================================================
    # CHANGE THIS: NFS export path
    # This is where models are stored on the NFS server
    # Ask your infrastructure team for the exact path
    # Common examples: /exports/huggingface-models
    #                  /mnt/nfs/models
    #                  /data/ml-models
    # ================================================================
    path: "/exports/huggingface-models"  # ← REPLACE WITH YOUR NFS PATH
```

### File 2: PersistentVolumeClaim (Create This SECOND)

**`02-pvc-huggingface-models.yaml`**

```yaml
# ============================================================================
# PersistentVolumeClaim for Hugging Face Models
# ============================================================================
# This PVC binds to the PV created above
# Pods will reference this PVC (not the PV directly)
# ============================================================================

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: huggingface-models-pvc
  labels:
    app: onyx-model-servers
    component: model-cache
spec:
  # Must match PV's accessModes
  accessModes:
    - ReadWriteMany
  
  # Must match PV's storageClassName (empty in this case)
  storageClassName: ""
  
  # Request storage size
  # Must be ≤ PV's capacity (10Gi)
  resources:
    requests:
      storage: 10Gi
  
  # CRITICAL: Bind to specific PV by name
  # This ensures it binds to YOUR PV (not some other PV)
  volumeName: huggingface-models-pv
  
  # volumeMode must be Filesystem (not Block)
  volumeMode: Filesystem

---
# Optional: Verification ConfigMap to document your setup
apiVersion: v1
kind: ConfigMap
metadata:
  name: pv-pvc-info
data:
  README: |
    PV/PVC Setup for Hugging Face Models
    =====================================
    
    PersistentVolume: huggingface-models-pv
    - Type: NFS
    - Capacity: 10Gi (from 800Gi NFS server)
    - Access Mode: ReadWriteMany
    - Reclaim Policy: Retain
    
    PersistentVolumeClaim: huggingface-models-pvc
    - Bound to: huggingface-models-pv
    - Storage: 10Gi
    - Access Mode: ReadWriteMany
    
    Usage:
    - inference-model-server mounts this PVC (read-only)
    - indexing-model-server mounts this PVC (read-only)
    - Both servers share the same models
```

---

## 🚀 Deployment Steps

### Prerequisites - Information from Your Team

Before deploying, get these details from your infrastructure team:

| Information | Production | Dev | Where to Use |
|------------|------------|-----|--------------|
| **NFS Server IP** | `10.x.x.x` | `10.y.y.y` | PV: `nfs.server` |
| **NFS Export Path** | `/exports/...` | `/exports/...` | PV: `nfs.path` |
| **NFS Version** | `4.1` or `3` | `4.1` or `3` | PV: `mountOptions` |
| **Access Permission** | Can you read/write? | Can you read/write? | Verify access |

### Step 1: Update PV YAML with Your Environment

**For Production:**
```yaml
nfs:
  server: 10.x.x.x  # Production NFS IP
  path: "/exports/huggingface-models"
```

**For Dev:**
```yaml
nfs:
  server: 10.y.y.y  # Dev NFS IP
  path: "/exports/huggingface-models"
```

### Step 2: Create the PV (Cluster Admin Privileges Required)

```bash
# In Production cluster
oc apply -f 01-pv-huggingface-models.yaml

# Verify PV was created
oc get pv huggingface-models-pv

# Expected output:
# NAME                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   AGE
# huggingface-models-pv      10Gi       RWX            Retain           Available                          10s

# Check details
oc describe pv huggingface-models-pv
```

**Key things to check:**
- `STATUS: Available` - PV is ready to be claimed
- `CAPACITY: 10Gi` - Matches what you specified
- `ACCESS MODES: RWX` - ReadWriteMany is enabled
- `NFS Server: 10.x.x.x` - Correct IP
- `NFS Path: /exports/...` - Correct path

### Step 3: Create the PVC

```bash
# Create PVC (in your namespace)
oc apply -f 02-pvc-huggingface-models.yaml

# Verify PVC was created and bound
oc get pvc huggingface-models-pvc

# Expected output:
# NAME                        STATUS   VOLUME                    CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# huggingface-models-pvc      Bound    huggingface-models-pv     10Gi       RWX                           5s

# Check details
oc describe pvc huggingface-models-pvc
```

**Key things to check:**
- `STATUS: Bound` - Successfully bound to PV ✅
- `VOLUME: huggingface-models-pv` - Bound to correct PV
- `CAPACITY: 10Gi` - Got the requested storage

### Step 4: Verify NFS Mount and Contents

```bash
# Create a test pod to verify the NFS mount and see the models
cat > test-pv-mount.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-nfs-mount
spec:
  containers:
    - name: test
      image: registry.access.redhat.com/ubi8/ubi:latest
      command: ["sleep", "3600"]
      volumeMounts:
        - name: models
          mountPath: /models
  volumes:
    - name: models
      persistentVolumeClaim:
        claimName: huggingface-models-pvc
EOF

# Deploy test pod
oc apply -f test-pv-mount.yaml

# Wait for pod to be ready
oc wait --for=condition=Ready pod/test-nfs-mount --timeout=60s

# Check if models are there
oc exec test-nfs-mount -- ls -lh /models/

# You should see:
# models--nomic-ai--nomic-embed-text-v1/
# models--mixedbread-ai--mxbai-rerank-xsmall-v1/
# models--onyx-dot-app--hybrid-intent-token-classifier/
# models--onyx-dot-app--information-content-model/

# Check directory sizes
oc exec test-nfs-mount -- du -sh /models/*

# Clean up test pod
oc delete pod test-nfs-mount
```

### Step 5: Deploy Model Servers

Now you can deploy the model servers using the PVC:

```bash
# Deploy model servers (they will use the PVC)
oc apply -f 06-inference-model-server.yaml
oc apply -f 06-indexing-model-server.yaml

# Watch pods start
oc get pods -w | grep model-server

# Check logs to verify models loaded from NFS
oc logs deployment/inference-model-server | grep -i "loaded model"
# Should see: "Loaded model from local cache: /app/.cache/huggingface/..."

oc logs deployment/indexing-model-server | grep -i "loaded model"
# Should see similar messages
```

---

## 🔍 Troubleshooting

### Issue 1: PV Status Stuck in "Available"

```bash
oc get pv huggingface-models-pv
# STATUS: Available (should be Available before PVC is created)
```

**This is normal if PVC hasn't been created yet!**

### Issue 2: PVC Status Stuck in "Pending"

```bash
oc get pvc huggingface-models-pvc
# STATUS: Pending

# Check why
oc describe pvc huggingface-models-pvc
```

**Common causes:**
1. **PV doesn't exist** - Create PV first
2. **volumeName mismatch** - Check PVC's `volumeName` matches PV's `metadata.name`
3. **Size mismatch** - PVC requests more than PV offers
4. **Access mode mismatch** - PVC and PV access modes don't match
5. **StorageClass mismatch** - Both should be `""` for static binding

### Issue 3: Pods Can't Mount PVC

```bash
oc get pods
# Pod status: ContainerCreating (stuck)

# Check events
oc describe pod <pod-name> | grep -A 10 Events
```

**Common causes:**
1. **NFS server unreachable** - Check network connectivity
2. **Wrong NFS IP** - Verify IP in PV matches team's NFS server
3. **Wrong NFS path** - Verify path in PV is correct
4. **NFS permissions** - NFS export might not allow your cluster
5. **NFS version mismatch** - Try changing `nfsvers=4.1` to `nfsvers=3`

**How to test NFS connectivity:**
```bash
# From a test pod
oc run nfs-test --image=registry.access.redhat.com/ubi8/ubi -- sleep 3600

# Install NFS utilities
oc exec nfs-test -- yum install -y nfs-utils

# Try to mount manually
oc exec nfs-test -- mount -t nfs 10.x.x.x:/exports/huggingface-models /mnt

# Check if accessible
oc exec nfs-test -- ls /mnt

# Clean up
oc delete pod nfs-test
```

### Issue 4: Models Not Found in NFS

```bash
# List contents of NFS mount
oc exec test-nfs-mount -- ls -la /models/

# If empty or different structure
```

**Solutions:**
1. **Verify NFS path** - Ask team for exact path
2. **Check subdirectories** - Models might be in a subdirectory
3. **Mount a subdirectory** - Update PV's `nfs.path` to include subdirectory

### Issue 5: Permission Denied

```bash
# In pod logs
oc logs deployment/inference-model-server
# Error: Permission denied reading /app/.cache/huggingface/...
```

**Solutions:**
1. **Check NFS export permissions** - Ask team to add your cluster to NFS exports
2. **Check file ownership** - Files might be owned by different user
3. **Use readOnly: true** - We're already doing this, which is good
4. **Ask team to set world-readable** - `chmod -R a+r /exports/huggingface-models` on NFS server

---

## 📊 Production vs Dev Differences

### What's Different Between Environments

| Aspect | Production | Dev |
|--------|-----------|-----|
| **NFS Server IP** | `10.x.x.x` | `10.y.y.y` |
| **NFS Path** | Maybe same | Maybe same |
| **PV Name** | Suggest: `...-pv-prod` | Suggest: `...-pv-dev` |
| **PVC Name** | Same: `huggingface-models-pvc` | Same: `huggingface-models-pvc` |
| **Cluster** | Production cluster | Dev cluster |

### What's the Same

✅ **PVC name** - Can be same (different clusters = different namespaces)
✅ **Model servers YAMLs** - Exactly the same!
✅ **Storage size** - Both request 10Gi
✅ **Access modes** - Both use ReadWriteMany
✅ **Models content** - Should be identical

### Deployment Strategy

**Recommended approach:**

1. **Deploy to Dev first** - Test everything
2. **Verify in Dev** - Make sure models load, pods work
3. **Deploy to Prod** - Use same YAMLs, just different PV IP

```bash
# In Dev cluster
oc apply -f 01-pv-huggingface-models.yaml  # with Dev IP
oc apply -f 02-pvc-huggingface-models.yaml
# ... deploy model servers ...
# ... test thoroughly ...

# In Prod cluster (after Dev works)
oc apply -f 01-pv-huggingface-models.yaml  # with Prod IP
oc apply -f 02-pvc-huggingface-models.yaml
# ... deploy model servers ...
```

---

## 📝 Complete File Summary

After this guide, you'll have these files:

```
onyx-k8s-infrastructure/
├── 01-pv-huggingface-models.yaml          ← NEW: Create PV
├── 02-pvc-huggingface-models.yaml         ← NEW: Create PVC
├── pvc-shared-models.yaml                 ← OLD: Delete or ignore
├── pvc-separate-models.yaml               ← OLD: Delete or ignore
├── 06-inference-model-server.yaml         ← Uses the PVC (already correct)
├── 06-indexing-model-server.yaml          ← Uses the PVC (already correct)
└── ... other files ...
```

**Note:** The old `pvc-shared-models.yaml` assumed auto-binding via StorageClass. You don't need it anymore since you're creating the PV explicitly.

---

## ✅ Checklist Before Deploying

### Information from Infrastructure Team

- [ ] Production NFS Server IP: `_______________`
- [ ] Dev NFS Server IP: `_______________`
- [ ] NFS Export Path: `_______________`
- [ ] NFS Version (3 or 4.1): `_______________`
- [ ] Confirmed network access from clusters to NFS servers
- [ ] Confirmed NFS exports allow cluster access

### Files Updated

- [ ] `01-pv-huggingface-models.yaml` - Updated with correct NFS IP
- [ ] `01-pv-huggingface-models.yaml` - Updated with correct NFS path
- [ ] `01-pv-huggingface-models.yaml` - Updated with correct NFS version
- [ ] `02-pvc-huggingface-models.yaml` - Reviewed (usually no changes needed)

### Deployment Steps

- [ ] Created PV: `oc apply -f 01-pv-huggingface-models.yaml`
- [ ] Verified PV status: `oc get pv` shows "Available"
- [ ] Created PVC: `oc apply -f 02-pvc-huggingface-models.yaml`
- [ ] Verified PVC status: `oc get pvc` shows "Bound"
- [ ] Tested NFS mount with test pod
- [ ] Verified models exist in NFS mount
- [ ] Deployed model servers
- [ ] Verified model servers can read models

---

## 🎯 Summary

### The Key Concepts

1. **NFS Servers** - Your team has two (Prod and Dev), each with 800Gi and pre-loaded models
2. **PersistentVolume** - YOU create this to register the NFS server in Kubernetes
3. **PersistentVolumeClaim** - YOU create this to claim/bind the PV
4. **Pods** - Reference the PVC (not PV or NFS directly)

### The Binding Chain

```
NFS Server (Team manages, 800Gi)
      ↓
PersistentVolume (You create, points to NFS)
      ↓
PersistentVolumeClaim (You create, binds to PV)
      ↓
Pod Volume Mount (References PVC)
      ↓
Container filesystem (/app/.cache/huggingface)
```

### Why This Approach

✅ **Explicit binding** - PVC binds to specific PV by name
✅ **No StorageClass needed** - Direct binding without dynamic provisioning
✅ **Full control** - You know exactly which NFS each PV points to
✅ **Environment-specific** - Different PVs for Prod/Dev, same PVC name

---

**You now understand the complete PV/PVC setup for your specific NFS environment!** 🎉

