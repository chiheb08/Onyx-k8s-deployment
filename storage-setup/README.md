# Storage Setup for Hugging Face Models

This folder contains all files and documentation related to setting up persistent storage for Hugging Face models in your Kubernetes/OpenShift environment.

---

## 📁 Files in This Folder

### Primary Files (Your Scenario: Two NFS Servers)

**1. `PV-PVC-SETUP-GUIDE.md`** ⭐ **START HERE**
- Complete guide for your specific NFS setup
- Explains Production and Dev NFS servers (800Gi each)
- Step-by-step instructions for creating PV and PVC
- Troubleshooting and verification steps

**2. `01-pv-huggingface-models.yaml`** (Deploy FIRST)
- PersistentVolume definition pointing to NFS server
- **YOU MUST UPDATE**: NFS server IP and path
- Creates a 10Gi volume from the 800Gi NFS server

**3. `02-pvc-huggingface-models.yaml`** (Deploy SECOND)
- PersistentVolumeClaim that binds to the PV
- Use as-is (no changes needed)
- Name: `huggingface-models-pvc`

### Alternative Files (For Reference)

**4. `USING-EXISTING-PV-FOR-MODELS.md`**
- General guide for using existing PVs
- Useful for understanding concepts
- Not specific to your two-NFS setup

**5. `pvc-shared-models.yaml`**
- Alternative PVC using StorageClass auto-binding
- Use this if you have StorageClass configured
- For ReadWriteMany storage

**6. `pvc-separate-models.yaml`**
- Two separate PVCs for ReadWriteOnce storage
- Use if your storage doesn't support ReadWriteMany

---

## 🎯 Your Environment

### Infrastructure Team Setup

```
Production Cluster:
├─ NFS Server: 10.x.x.x (get exact IP from team)
├─ Capacity: 800 Gi
├─ Used: ~5-6GB (Hugging Face models)
└─ Path: /exports/huggingface-models (verify with team)

Dev Cluster:
├─ NFS Server: 10.y.y.y (different IP)
├─ Capacity: 800 Gi
├─ Used: ~5-6GB (same models)
└─ Path: /exports/huggingface-models (verify with team)
```

### Your Task

For EACH cluster (Prod and Dev):
1. Create PV pointing to that cluster's NFS server
2. Create PVC that binds to the PV
3. Model servers will mount the PVC

---

## 🚀 Quick Start

### Step 1: Get Information from Your Team

Ask for:
- [ ] Production NFS Server IP: `_______________`
- [ ] Dev NFS Server IP: `_______________`
- [ ] NFS Export Path: `_______________`
- [ ] NFS Version (3 or 4.1): `_______________`

### Step 2: Update PV YAML

Edit `01-pv-huggingface-models.yaml`:

```yaml
# Line 54: Change this
server: 10.0.0.100  # ← YOUR Production/Dev NFS IP

# Line 68: Verify this
path: "/exports/huggingface-models"  # ← YOUR NFS path
```

### Step 3: Deploy PV and PVC

```bash
# Create PersistentVolume
oc apply -f 01-pv-huggingface-models.yaml

# Verify PV is created
oc get pv huggingface-models-pv
# Expected: STATUS = Available

# Create PersistentVolumeClaim
oc apply -f 02-pvc-huggingface-models.yaml

# Verify PVC is bound
oc get pvc huggingface-models-pvc
# Expected: STATUS = Bound
```

### Step 4: Verify NFS Mount

```bash
# Create test pod
oc run test-nfs --image=registry.access.redhat.com/ubi8/ubi --command -- sleep 3600

# Add PVC to test pod
oc set volume pod/test-nfs --add --name=models --type=pvc --claim-name=huggingface-models-pvc --mount-path=/models

# Check if models are accessible
oc exec test-nfs -- ls -lh /models/
# Should show: models--nomic-ai--nomic-embed-text-v1/ etc.

# Clean up
oc delete pod test-nfs
```

### Step 5: Deploy Model Servers

```bash
# Go back to parent directory
cd ..

# Deploy model servers (they reference huggingface-models-pvc)
oc apply -f 06-inference-model-server.yaml
oc apply -f 06-indexing-model-server.yaml

# Verify pods are running
oc get pods | grep model-server

# Check logs
oc logs deployment/inference-model-server | grep "loaded model"
```

---

## 📊 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│  Infrastructure Team's NFS Server                               │
│  IP: 10.x.x.x (Production) or 10.y.y.y (Dev)                   │
│  Capacity: 800 Gi                                               │
│  Contents: Hugging Face models (~5-6GB)                         │
└─────────────────────────────────────────────────────────────────┘
                          ↓
                          ↓ (NFS mount)
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│  PersistentVolume (YOU create)                                  │
│  Name: huggingface-models-pv                                    │
│  Capacity: 10Gi (from NFS)                                      │
│  Access Mode: ReadWriteMany                                     │
│  File: 01-pv-huggingface-models.yaml                           │
└─────────────────────────────────────────────────────────────────┘
                          ↓
                          ↓ (Binding)
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│  PersistentVolumeClaim (YOU create)                             │
│  Name: huggingface-models-pvc                                   │
│  Requests: 10Gi                                                 │
│  Access Mode: ReadWriteMany                                     │
│  File: 02-pvc-huggingface-models.yaml                          │
└─────────────────────────────────────────────────────────────────┘
                          ↓
                          ↓ (Mount)
                          ↓
      ┌───────────────────────────────────────────┐
      │                                           │
      ▼                                           ▼
┌─────────────────────┐              ┌─────────────────────┐
│ Inference Server    │              │ Indexing Server     │
│ Port: 9000          │              │ Port: 9000          │
│ Mounts PVC at:      │              │ Mounts PVC at:      │
│ /app/.cache/        │              │ /app/.cache/        │
│ huggingface/        │              │ huggingface/        │
└─────────────────────┘              └─────────────────────┘
```

---

## 🔍 Troubleshooting

### PVC Stuck in "Pending"

```bash
oc describe pvc huggingface-models-pvc
```

**Common causes:**
- PV not created yet → Create PV first
- volumeName mismatch → Check PVC references correct PV name
- Size mismatch → PVC requests more than PV offers

### Pods Can't Mount PVC

```bash
oc describe pod <pod-name>
```

**Common causes:**
- NFS server unreachable → Check network connectivity
- Wrong NFS IP → Verify IP in PV
- Wrong NFS path → Verify path with team
- NFS permissions → Ask team to add cluster to NFS exports

### Models Not Found

```bash
oc exec deployment/inference-model-server -- ls -lh /app/.cache/huggingface/
```

**If empty:**
- Wrong NFS path → Update PV
- Models in subdirectory → Update NFS path in PV
- NFS export not accessible → Contact infrastructure team

---

## 📋 File Decision Guide

### Which Files Should I Use?

**Scenario 1: You have two NFS servers (Prod and Dev) - 800Gi each**
✅ Use: `01-pv-huggingface-models.yaml` + `02-pvc-huggingface-models.yaml`
✅ Read: `PV-PVC-SETUP-GUIDE.md`

**Scenario 2: Your team already created PV with StorageClass**
✅ Use: `pvc-shared-models.yaml`
✅ Read: `USING-EXISTING-PV-FOR-MODELS.md`

**Scenario 3: Storage only supports ReadWriteOnce**
✅ Use: `pvc-separate-models.yaml`
✅ Read: `USING-EXISTING-PV-FOR-MODELS.md`

---

## 📖 Documentation

For complete explanations and step-by-step guides:

1. **Start here:** `PV-PVC-SETUP-GUIDE.md` (if you need to create PV)
2. **Or here:** `USING-EXISTING-PV-FOR-MODELS.md` (if PV already exists)
3. **Then deploy:** `01-pv-huggingface-models.yaml` → `02-pvc-huggingface-models.yaml`

---

## ✅ Checklist

Before deploying, ensure:

- [ ] Got NFS IP from infrastructure team
- [ ] Got NFS path from infrastructure team
- [ ] Updated `01-pv-huggingface-models.yaml` with correct IP
- [ ] Updated `01-pv-huggingface-models.yaml` with correct path
- [ ] Have cluster-admin permissions to create PV
- [ ] Network connectivity from cluster to NFS server verified

---

**For questions or issues, refer to the detailed guides in this folder!** 📚

