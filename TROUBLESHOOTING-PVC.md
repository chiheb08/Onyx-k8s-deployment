# Troubleshooting: PersistentVolumeClaim Issues

**Error:** `0/9 nodes are available: persistentvolumeclaim "postgresql-pvc" not found`

Complete guide to debug and fix PVC issues in Kubernetes/OpenShift.

---

## 🔍 Understanding the Error

### What the Error Means

```
0/9 nodes are available: persistentvolumeclaim "postgresql-pvc" not found
│   │                        │                                          │
│   │                        │                                          └─ PVC name
│   │                        └─ Reason pod can't be scheduled
│   └─ Number of nodes checked
└─ No nodes can run this pod
```

**Translation:** 
- Kubernetes tried to schedule the PostgreSQL pod
- The pod needs a PVC named `postgresql-pvc`
- Kubernetes checked all 9 nodes
- None of them can run the pod because the PVC doesn't exist or isn't bound

---

## 🔧 Diagnosis Steps

### Step 1: Check if PVC Exists

```bash
# List all PVCs in your namespace
kubectl get pvc

# OR in OpenShift
oc get pvc

# Expected output:
# NAME             STATUS    VOLUME    CAPACITY   ACCESS MODES   STORAGECLASS
# postgresql-pvc   Pending   -         -          -              -
```

**Possible states:**

| Status | Meaning | Action Needed |
|--------|---------|---------------|
| **Bound** | ✅ Ready to use | No action, PVC is working |
| **Pending** | ⚠️ Waiting for PV | See Step 2 |
| **Lost** | ❌ PV deleted | Recreate PVC |
| *Not listed* | ❌ PVC doesn't exist | See Step 3 |

---

### Step 2: If PVC is Pending

```bash
# Describe the PVC to see why it's pending
kubectl describe pvc postgresql-pvc

# OR
oc describe pvc postgresql-pvc
```

**Look for events at the bottom:**

#### Scenario A: No StorageClass

```
Events:
  Type     Reason              Message
  ----     ------              -------
  Warning  ProvisioningFailed  storageclass.storage.k8s.io "" not found
```

**Cause:** No default StorageClass configured

**Solution:** See "Solution 1: Configure StorageClass" below

---

#### Scenario B: Waiting for First Consumer

```
Events:
  Type    Reason                Message
  ----    ------                -------
  Normal  WaitForFirstConsumer  waiting for first consumer to be created
```

**Cause:** StorageClass uses `WaitForFirstConsumer` binding mode

**Solution:** This is normal! The PVC will bind when the pod starts. If pod still won't start, see "Solution 2: WaitForFirstConsumer" below

---

#### Scenario C: No PersistentVolumes Available

```
Events:
  Type     Reason              Message
  ----     ------              -------
  Warning  ProvisioningFailed  no persistent volumes available
```

**Cause:** No dynamic provisioner and no pre-created PVs

**Solution:** See "Solution 3: Create PersistentVolume" below

---

### Step 3: If PVC Doesn't Exist

```bash
# Check if PVC was created at all
kubectl get pvc postgresql-pvc

# If "Error from server (NotFound)":
# The PVC wasn't created

# Check the YAML file
cat 02-postgresql.yaml | grep -A 10 "kind: PersistentVolumeClaim"
```

**Cause:** PVC section might have been skipped or has error

**Solution:** Apply the PVC section manually (see Solution 4)

---

## ✅ Solutions

### Solution 1: Configure StorageClass (Most Common)

**Check available StorageClasses:**

```bash
# List StorageClasses
kubectl get storageclass

# OR OpenShift
oc get storageclass

# Example output:
# NAME                 PROVISIONER              RECLAIMPOLICY   VOLUMEBINDINGMODE
# standard (default)   kubernetes.io/aws-ebs    Delete          Immediate
# fast-ssd            kubernetes.io/gce-pd     Delete          Immediate
```

**Option A: Use Default StorageClass**

If you see one marked `(default)`, update `02-postgresql.yaml`:

```yaml
# In 02-postgresql.yaml, PersistentVolumeClaim section:
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  # storageClassName: ""  # DELETE or comment out this line
  # Kubernetes will use default StorageClass
```

**Option B: Specify StorageClass**

If you have a specific StorageClass (like `fast-ssd`):

```yaml
# In 02-postgresql.yaml:
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: "fast-ssd"  # Specify your StorageClass name
```

**Apply changes:**

```bash
# Delete old PVC if exists
kubectl delete pvc postgresql-pvc

# Reapply
kubectl apply -f 02-postgresql.yaml

# Check status
kubectl get pvc postgresql-pvc -w
```

---

### Solution 2: WaitForFirstConsumer Mode

Some StorageClasses wait for a pod to request the PVC before binding.

**Check binding mode:**

```bash
kubectl get storageclass <name> -o yaml | grep volumeBindingMode
# Output: WaitForFirstConsumer
```

**This is NORMAL!** The PVC will bind when the PostgreSQL pod starts.

**Action:**

1. Make sure pod can start (no other errors)
2. PVC will automatically bind when pod requests it
3. If pod still won't start, check pod events:

```bash
kubectl describe pod <postgresql-pod-name>

# Look for other errors besides PVC
```

---

### Solution 3: Create PersistentVolume (Manual Provisioning)

If your cluster doesn't have dynamic provisioning:

**Create a PersistentVolume:**

```yaml
# Save as pv-postgresql.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: postgresql-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:  # For testing only! Use real storage in production
    path: /mnt/data/postgresql
    type: DirectoryOrCreate
```

**Apply:**

```bash
kubectl apply -f pv-postgresql.yaml
kubectl get pv

# PVC should now bind
kubectl get pvc postgresql-pvc
```

**⚠️ Warning:** `hostPath` is for testing only! For production, use:
- **AWS:** EBS volumes
- **GCP:** Persistent Disks
- **Azure:** Azure Disks
- **OpenShift:** Use cluster's default storage

---

### Solution 4: Use emptyDir (No Persistence - Testing Only)

For **testing purposes only** (data lost on pod restart):

**Edit `02-postgresql.yaml`:**

```yaml
# BEFORE (with PVC):
volumes:
  - name: postgresql-data
    persistentVolumeClaim:
      claimName: postgresql-pvc

# AFTER (with emptyDir - NO PERSISTENCE):
volumes:
  - name: postgresql-data
    emptyDir: {}
```

**AND remove the PVC definition:**

```yaml
# DELETE this entire section:
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgresql-pvc
spec:
  ...
```

**Apply:**

```bash
kubectl apply -f 02-postgresql.yaml
```

**⚠️ WARNING:** All data lost when pod restarts! Use only for testing.

---

## 🎯 Recommended Solution for OpenShift

### OpenShift Usually Has Default Storage

```bash
# Check OpenShift storage classes
oc get storageclass

# Common OpenShift StorageClasses:
# - gp2 (AWS)
# - thin (VMware)
# - cinder (OpenStack)
# - glusterfs-storage
```

**Update 02-postgresql.yaml:**

```yaml
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: "gp2"  # Use your OpenShift storage class
```

**Same for Vespa (03-vespa.yaml):**

```yaml
# In volumeClaimTemplates section:
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 30Gi
  storageClassName: "gp2"  # Same storage class
```

---

## 🔍 Complete Debug Workflow

```bash
# 1. Check PVC status
kubectl get pvc
# → Shows if PVC exists and its status

# 2. If Pending, describe it
kubectl describe pvc postgresql-pvc
# → Shows why it's pending (events section)

# 3. Check StorageClasses
kubectl get storageclass
# → Shows available storage options

# 4. Check if default exists
kubectl get storageclass | grep default
# → If yes, you can use it

# 5. Update YAML with StorageClass
# Edit 02-postgresql.yaml and 03-vespa.yaml
# Set: storageClassName: "<your-storage-class>"

# 6. Delete old PVC (if exists)
kubectl delete pvc postgresql-pvc
kubectl delete pvc vespa-storage-vespa-0

# 7. Reapply
kubectl apply -f 02-postgresql.yaml
kubectl apply -f 03-vespa.yaml

# 8. Watch PVC bind
kubectl get pvc -w
# Wait for STATUS: Bound

# 9. Deploy rest of services
./deploy.sh
```

---

## 📊 Common OpenShift Storage Scenarios

### Scenario 1: OCS/ODF (OpenShift Container Storage)

```yaml
storageClassName: "ocs-storagecluster-ceph-rbd"
# Or
storageClassName: "ocs-storagecluster-cephfs"
```

### Scenario 2: AWS EBS

```yaml
storageClassName: "gp2"
# Or
storageClassName: "gp3"
```

### Scenario 3: VMware vSphere

```yaml
storageClassName: "thin"
```

### Scenario 4: NFS

```yaml
storageClassName: "nfs-client"
```

**Find yours:**
```bash
oc get storageclass
# Use the NAME from output
```

---

## 🛠️ Quick Fix Script

```bash
#!/bin/bash
# Quick fix for PVC issues

echo "Checking StorageClasses..."
kubectl get storageclass

echo ""
echo "Select a StorageClass from above and update:"
echo "1. Edit 02-postgresql.yaml"
echo "2. Find: storageClassName: \"\""
echo "3. Change to: storageClassName: \"<your-storage-class>\""
echo ""
echo "Then run:"
echo "kubectl apply -f 02-postgresql.yaml"
echo "kubectl get pvc -w"
```

---

## ⚠️ Important Notes

### For Production

**Never use:**
- ❌ `emptyDir` (data loss on restart)
- ❌ `hostPath` (data stuck on one node)

**Always use:**
- ✅ StorageClass with dynamic provisioning
- ✅ Backup strategy for PVCs
- ✅ `persistentVolumeReclaimPolicy: Retain` (prevents data loss)

### For Testing/Development

**Can use:**
- ⚠️ `emptyDir` (if you don't care about data loss)
- ⚠️ Default StorageClass (if available)

---

## 📝 Summary

**Root cause:** PVC not bound (no storage provisioned)

**Quick fix:**
1. Check StorageClass: `kubectl get storageclass`
2. Update YAML: Add `storageClassName: "<name>"`
3. Reapply: `kubectl apply -f 02-postgresql.yaml`
4. Verify: `kubectl get pvc` → STATUS should be `Bound`

**Once PVC is Bound:**
- Pod can be scheduled
- PostgreSQL starts successfully
- Deployment proceeds

---

## 🎯 Next Steps After Fixing

```bash
# 1. Fix PVC (apply solution above)

# 2. Verify PVC is bound
kubectl get pvc postgresql-pvc
# STATUS: Bound ✅

# 3. Check PostgreSQL pod
kubectl get pods -l app=postgresql
# READY: 1/1 ✅

# 4. Continue deployment
./deploy.sh
# Or deploy remaining services manually
```

---

**See below for step-by-step commands specific to your situation.**

