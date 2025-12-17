# Quick Fix: Vespa NFS Fusion Failures

## 🚨 Problem

Vespa fusion operations failing with errors:
- `Failed to clean tmpdir`
- `Fusion failed, fusion dir`
- `Fusion failed for id 8`

**Root Cause**: NFS storage not optimized for Vespa's disk-intensive fusion operations.

---

## ⚡ Quick Fix (5 Minutes)

### Step 1: Find Your NFS Server Details

```bash
# Get current PVC details
kubectl get pvc vespa-storage-vespa-0 -n onyx-infra -o yaml | grep -A 10 nfs

# Or check PV
kubectl get pv -o yaml | grep -A 5 "server:\|path:"
```

**Note the values**:
- NFS server IP
- NFS export path

---

### Step 2: Create Optimized PV

**File**: `onyx-k8s-infrastructure/manifests/03-vespa-pv-optimized.yaml`

**Update these lines**:
```yaml
  nfs:
    server: <YOUR_NFS_SERVER_IP>        # Replace with actual IP
    path: <YOUR_NFS_EXPORT_PATH>        # Replace with actual path
```

**Apply**:
```bash
kubectl apply -f onyx-k8s-infrastructure/manifests/03-vespa-pv-optimized.yaml
```

---

### Step 3: Update StatefulSet Resources

**File**: `onyx-k8s-infrastructure/manifests/03-vespa.yaml`

**Already updated** - resources increased for NFS performance.

**Apply**:
```bash
kubectl apply -f onyx-k8s-infrastructure/manifests/03-vespa.yaml
```

---

### Step 4: Restart Vespa Pod

```bash
# Delete pod to apply new mount options
kubectl delete pod vespa-0 -n onyx-infra

# Wait for restart
kubectl get pods -n onyx-infra -w | grep vespa
```

---

### Step 5: Verify Mount Options

```bash
# Check mount options applied
kubectl exec -it vespa-0 -n onyx-infra -- mount | grep vespa-storage

# Should show optimized options like:
# ... nfs4 (rw,relatime,vers=4.1,rsize=1048576,wsize=1048576,...)
```

---

## ✅ Expected Results

**Before Fix**:
- ❌ Fusion failures every few hours
- ❌ Temporary directories not cleaned
- ❌ Index corruption risk

**After Fix**:
- ✅ Fusion operations succeed
- ✅ Temporary files cleaned properly
- ✅ Stable index operations

---

## 🔍 If Issues Persist

### Option A: Use Block Storage Instead

Change StorageClass in `03-vespa.yaml`:
```yaml
storageClassName: "gp3"  # AWS EBS
# OR
storageClassName: "pd-ssd"  # GCP
# OR
storageClassName: "managed-premium"  # Azure
```

### Option B: Check NFS Server Configuration

Ensure NFS server has:
- Sufficient disk space
- Proper export permissions
- Stable network connection
- NFSv4.1 support

---

**See**: `VESPA-NFS-FUSION-FAILURE-SOLUTION.md` for complete details.

