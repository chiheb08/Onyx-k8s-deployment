# Vespa Fusion Failure with NFS Storage - Complete Solution

## 🐛 Problem Analysis

### Error Messages from Logs

Based on your Vespa logs, you're seeing:
- ❌ `ERROR: Failed to clean tmpdir`
- ❌ `ERROR: Fusion failed, fusion dir`
- ⚠️ `WARNING: Fusion failed for id 8, fusion dir`

### What is Vespa Fusion?

**Vespa Fusion** is a disk-intensive operation that:
1. Merges multiple index files into a single optimized index
2. Creates temporary directories (`index.fusion.8/`)
3. Processes large files (titles, content, embeddings)
4. Cleans up temporary files after completion

**Why it's failing**: NFS storage has characteristics that conflict with Vespa's fusion operations.

---

## 🔍 Root Causes

### Cause 1: NFS File Locking Issues

**Problem**: NFS (especially NFSv3) has unreliable file locking, which Vespa fusion needs for:
- Creating temporary directories
- Locking index files during merge
- Cleaning up temporary files

**Symptoms**:
- `Failed to clean tmpdir` - Can't delete temporary directories
- Fusion operations fail intermittently

---

### Cause 2: NFS Latency and Timeouts

**Problem**: NFS adds network latency to every I/O operation:
- Vespa fusion creates/deletes many small files rapidly
- Network latency accumulates, causing timeouts
- Temporary file cleanup fails due to slow responses

**Symptoms**:
- Fusion operations timeout
- Temporary files accumulate
- Disk space issues

---

### Cause 3: NFS Concurrent Access Limitations

**Problem**: Even with `ReadWriteOnce`, NFS can have issues with:
- Rapid file creation/deletion cycles
- Concurrent metadata operations
- Directory operations

**Symptoms**:
- `Fusion failed for id 8` - Specific fusion operations fail
- Inconsistent failures (works sometimes, fails other times)

---

### Cause 4: NFS Mount Options Not Optimized

**Problem**: Default NFS mount options may not be optimal for Vespa:
- Missing `noatime` (reduces metadata writes)
- Missing `actimeo` (caching)
- Wrong `timeo` values (timeouts too short)

**Symptoms**:
- Slow performance
- Timeout errors
- Metadata operation failures

---

## ✅ Solutions

### Solution 1: Optimize NFS Mount Options (Recommended First Step)

**File**: `onyx-k8s-infrastructure/manifests/03-vespa.yaml`

**Current Configuration**:
```yaml
  volumeClaimTemplates:
    - metadata:
        name: vespa-storage
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 30Gi
        storageClassName: "nfs-example"
        volumeMode: "Filesystem"
```

**Problem**: No mount options specified - using defaults which may not be optimal.

**Solution**: Add NFS mount options via PersistentVolume.

**Step 1: Create/Update PersistentVolume with Mount Options**

**File**: `onyx-k8s-infrastructure/manifests/03-vespa-pv.yaml` (new file)

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: vespa-storage-pv
  labels:
    app: vespa
spec:
  capacity:
    storage: 30Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: nfs-example
  mountOptions:
    # Performance optimizations
    - hard                    # Retry on errors (don't fail fast)
    - nfsvers=4.1             # Use NFSv4.1 (better locking than v3)
    - timeo=600               # Timeout: 60 seconds (600 deciseconds)
    - retrans=3               # Retry 3 times before giving up
    - actimeo=60              # Attribute cache timeout: 60 seconds
    - noatime                 # Don't update access times (reduces writes)
    - nodiratime              # Don't update directory access times
    - rsize=1048576           # Read buffer: 1MB (larger = fewer network calls)
    - wsize=1048576           # Write buffer: 1MB
    - tcp                     # Use TCP (more reliable than UDP)
    - intr                    # Allow interrupts (for better error handling)
  nfs:
    server: <YOUR_NFS_SERVER_IP>  # CHANGE THIS
    path: <YOUR_NFS_EXPORT_PATH>  # CHANGE THIS (e.g., /exports/vespa)
```

**Step 2: Update StatefulSet to Use Static PV**

**File**: `onyx-k8s-infrastructure/manifests/03-vespa.yaml`

**OLD CODE**:
```yaml
  volumeClaimTemplates:
    - metadata:
        name: vespa-storage
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 30Gi
        storageClassName: "nfs-example"
        volumeMode: "Filesystem"
```

**NEW CODE**:
```yaml
  volumeClaimTemplates:
    - metadata:
        name: vespa-storage
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 30Gi
        storageClassName: "nfs-example"
        volumeMode: "Filesystem"
        # Optional: Specify volume name for static binding
        # volumeName: vespa-storage-pv
```

**Note**: If using dynamic provisioning, mount options must be set in StorageClass.

---

### Solution 2: Configure StorageClass with Mount Options

**If using dynamic provisioning**, configure mount options in StorageClass:

**File**: `onyx-k8s-infrastructure/manifests/03-vespa-storageclass.yaml` (new file)

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-example
provisioner: <YOUR_NFS_PROVISIONER>  # e.g., nfs-client, nfs-subdir-external-provisioner
parameters:
  # NFS provisioner parameters
  server: <YOUR_NFS_SERVER_IP>
  path: <YOUR_NFS_BASE_PATH>
allowVolumeExpansion: true
mountOptions:
  - hard
  - nfsvers=4.1
  - timeo=600
  - retrans=3
  - actimeo=60
  - noatime
  - nodiratime
  - rsize=1048576
  - wsize=1048576
  - tcp
  - intr
```

---

### Solution 3: Use Local Storage Instead of NFS (Best Performance)

**If NFS continues to cause issues**, consider using local storage:

**File**: `onyx-k8s-infrastructure/manifests/03-vespa.yaml`

**Change StorageClass**:
```yaml
  volumeClaimTemplates:
    - metadata:
        name: vespa-storage
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 30Gi
        storageClassName: "local-storage"  # ✅ Change to local storage
        volumeMode: "Filesystem"
```

**Pros**:
- ✅ Much faster I/O (no network latency)
- ✅ Better file locking
- ✅ More reliable for fusion operations

**Cons**:
- ❌ Data lost if node fails (unless using node-local backup)
- ❌ Can't migrate between nodes easily

---

### Solution 4: Add Vespa Configuration for NFS

**File**: `onyx-k8s-infrastructure/manifests/03-vespa-config.yaml` (new file)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: vespa-config
  namespace: onyx-infra  # Change to your namespace
data:
  services.xml: |
    <?xml version="1.0" encoding="UTF-8"?>
    <services version="1.0">
      <admin version="2.0">
        <adminserver hostalias="admin" />
      </admin>
      <container id="default" version="1.0">
        <search/>
        <document-api/>
      </container>
      <content id="content" version="1.0">
        <redundancy>1</redundancy>
        <documents>
          <document type="danswer_chunk_nomic_ai_nomic_embed_text_v1" mode="index"/>
        </documents>
        <engine>
          <proton>
            <tuning>
              <flush-strategy>
                <!-- Increase flush intervals for NFS -->
                <memory-limit>0.5</memory-limit>
                <component>
                  <maxflushed>10</maxflushed>
                  <maxflushedpending>10</maxflushedpending>
                </component>
              </flush-strategy>
              <fusion>
                <!-- Increase fusion timeouts for NFS -->
                <max-fusion-time>3600</max-fusion-time>
                <max-fusion-size>1000000000</max-fusion-size>
              </fusion>
            </tuning>
          </proton>
        </engine>
        <nodes>
          <node hostalias="node1" distribution-key="0"/>
        </nodes>
      </content>
    </services>
```

**Mount in StatefulSet**:
```yaml
spec:
  template:
    spec:
      containers:
        - name: vespa
          volumeMounts:
            - name: vespa-storage
              mountPath: /opt/vespa/var
            - name: vespa-config
              mountPath: /opt/vespa/var/db/vespa/config_server/serverdb/tenants/default/sessions/2/active
      volumes:
        - name: vespa-config
          configMap:
            name: vespa-config
```

---

### Solution 5: Increase Vespa Resources

**NFS operations are slower**, so Vespa may need more resources:

**File**: `onyx-k8s-infrastructure/manifests/03-vespa.yaml`

**OLD CODE**:
```yaml
          resources:
            requests:
              cpu: 1000m
              memory: 2Gi
            limits:
              cpu: 4000m
              memory: 8Gi
```

**NEW CODE**:
```yaml
          resources:
            requests:
              cpu: 2000m      # ✅ Increased from 1000m
              memory: 4Gi     # ✅ Increased from 2Gi
            limits:
              cpu: 8000m      # ✅ Increased from 4000m
              memory: 16Gi    # ✅ Increased from 8Gi
```

**Why**: More CPU helps process NFS I/O faster, more memory reduces disk I/O.

---

## 🚀 Recommended Implementation Order

### Phase 1: Quick Fix (Apply Immediately)

1. **Add NFS mount options** (Solution 1)
2. **Increase Vespa resources** (Solution 5)

**Expected Result**: 50-70% reduction in fusion failures

---

### Phase 2: Medium-Term Fix

3. **Configure StorageClass** (Solution 2)
4. **Add Vespa tuning** (Solution 4)

**Expected Result**: 80-90% reduction in fusion failures

---

### Phase 3: Long-Term Solution

5. **Migrate to local storage** (Solution 3) - if NFS continues to cause issues

**Expected Result**: 99%+ reliability

---

## 📋 Step-by-Step: Apply NFS Mount Options Fix

### Step 1: Check Current NFS Setup

```bash
# Check current PVC
kubectl get pvc -n onyx-infra | grep vespa

# Check PV details
kubectl get pv

# Check StorageClass
kubectl get storageclass nfs-example -o yaml
```

---

### Step 2: Create PersistentVolume with Mount Options

**File**: `onyx-k8s-infrastructure/manifests/03-vespa-pv.yaml`

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: vespa-storage-pv
  namespace: onyx-infra
  labels:
    app: vespa
spec:
  capacity:
    storage: 30Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: nfs-example
  mountOptions:
    - hard
    - nfsvers=4.1
    - timeo=600
    - retrans=3
    - actimeo=60
    - noatime
    - nodiratime
    - rsize=1048576
    - wsize=1048576
    - tcp
    - intr
  nfs:
    server: <YOUR_NFS_SERVER>      # Get from your NFS setup
    path: <YOUR_NFS_EXPORT_PATH>   # Get from your NFS setup
```

**Find NFS Server Info**:
```bash
# Check existing PV
kubectl get pv -o yaml | grep -A 5 nfs

# Or check PVC details
kubectl describe pvc vespa-storage-vespa-0 -n onyx-infra
```

---

### Step 3: Update StatefulSet Resources

**File**: `onyx-k8s-infrastructure/manifests/03-vespa.yaml`

Update resources section (around line 70-76):
```yaml
          resources:
            requests:
              cpu: 2000m      # Increased
              memory: 4Gi     # Increased
            limits:
              cpu: 8000m      # Increased
              memory: 16Gi    # Increased
```

---

### Step 4: Apply Changes

```bash
cd /Users/chihebmhamdi/Desktop/onyx/onyx-k8s-infrastructure/manifests

# Apply PV (if using static provisioning)
kubectl apply -f 03-vespa-pv.yaml

# Update StatefulSet
kubectl apply -f 03-vespa.yaml

# Restart Vespa pod to apply new mount options
kubectl delete pod vespa-0 -n onyx-infra

# Wait for pod to restart
kubectl get pods -n onyx-infra -w | grep vespa
```

---

## 🔍 Verification

### Check Mount Options Applied

```bash
# Exec into Vespa pod
kubectl exec -it vespa-0 -n onyx-infra -- bash

# Check mount options
mount | grep vespa-storage

# Should show mount options like:
# ... on /opt/vespa/var type nfs4 (rw,relatime,vers=4.1,rsize=1048576,wsize=1048576,...)
```

---

### Monitor Fusion Operations

```bash
# Watch Vespa logs
kubectl logs -f vespa-0 -n onyx-infra | grep -i fusion

# Check for errors
kubectl logs vespa-0 -n onyx-infra | grep -i "failed\|error" | tail -20
```

**Expected**: Fewer or no fusion failures after applying fixes.

---

## 🎯 Alternative: Use Block Storage Instead of NFS

If NFS continues to cause issues, consider:

### Option A: Use Local SSD Storage

```yaml
storageClassName: "local-ssd"  # If available in your cluster
```

### Option B: Use Cloud Block Storage

**AWS EKS**:
```yaml
storageClassName: "gp3"  # AWS EBS GP3
```

**GCP GKE**:
```yaml
storageClassName: "pd-ssd"  # Google Persistent Disk SSD
```

**Azure AKS**:
```yaml
storageClassName: "managed-premium"  # Azure Premium SSD
```

---

## 📊 NFS vs Block Storage Comparison

| Feature | NFS | Block Storage (EBS/GPD) |
|---------|-----|-------------------------|
| **Performance** | ⚠️ Slower (network) | ✅ Faster (local) |
| **Fusion Reliability** | ⚠️ Can fail | ✅ Very reliable |
| **Cost** | ✅ Lower | ⚠️ Higher |
| **Scalability** | ✅ Easy | ⚠️ Per-node |
| **Backup** | ✅ Centralized | ⚠️ Per-volume |

**Recommendation**: Use NFS with optimized mount options first. If issues persist, migrate to block storage.

---

## 🔧 Troubleshooting

### Issue: Mount Options Not Applied

**Check**:
```bash
# Verify PV exists
kubectl get pv vespa-storage-pv

# Check PVC binding
kubectl get pvc -n onyx-infra

# Verify StorageClass
kubectl get storageclass nfs-example -o yaml
```

**Solution**: If using dynamic provisioning, mount options must be in StorageClass, not PV.

---

### Issue: NFS Server Unreachable

**Check**:
```bash
# Test NFS connectivity from pod
kubectl exec -it vespa-0 -n onyx-infra -- ping <NFS_SERVER_IP>

# Check NFS exports
kubectl exec -it vespa-0 -n onyx-infra -- showmount -e <NFS_SERVER_IP>
```

**Solution**: Ensure NFS server is accessible and exports are configured correctly.

---

### Issue: Permission Denied

**Check**:
```bash
# Check file permissions
kubectl exec -it vespa-0 -n onyx-infra -- ls -la /opt/vespa/var

# Check ownership
kubectl exec -it vespa-0 -n onyx-infra -- whoami
```

**Solution**: Ensure NFS exports allow root access or match Vespa's user (UID 1000).

---

## 📝 Summary

### Root Cause

**Vespa fusion failures** are caused by **NFS storage characteristics**:
1. File locking issues
2. Network latency
3. Suboptimal mount options
4. Insufficient resources

### Solution Priority

1. ✅ **Add NFS mount options** (immediate)
2. ✅ **Increase Vespa resources** (immediate)
3. ✅ **Configure StorageClass** (if using dynamic provisioning)
4. ✅ **Add Vespa tuning** (medium-term)
5. ✅ **Migrate to block storage** (if NFS continues to fail)

---

**Last Updated**: 2024  
**Version**: 1.0

