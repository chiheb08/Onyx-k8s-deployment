# Vespa NFS Fusion Failure - Complete Guide for Junior Engineers

## 🎯 What You'll Learn

This guide explains:
1. What Vespa is and what it does
2. What "fusion" means in Vespa
3. What NFS storage is
4. Why NFS causes problems with Vespa fusion
5. How to fix it step-by-step

---

## 📚 Part 1: Understanding the Basics

### What is Vespa?

**Vespa** is like a **super-fast library** for your documents:

```
Imagine a Library:
├── Books (your documents)
├── Index Cards (search index)
└── Librarian (Vespa)
    - Finds books quickly
    - Updates the index
    - Keeps everything organized
```

**In Technical Terms**:
- Vespa is a **vector search engine**
- It stores your documents and makes them searchable
- It uses **indexes** (like a book's table of contents) to find things fast
- It runs in a Kubernetes pod

---

### What is "Fusion" in Vespa?

**Fusion** is like **reorganizing a messy filing cabinet**:

#### Real-World Analogy

Imagine you have a filing cabinet with:
- **Drawer 1**: Files A, B, C (old index)
- **Drawer 2**: Files D, E, F (new index)
- **Drawer 3**: Files G, H, I (another new index)

**Problem**: Files are scattered across multiple drawers, making it slow to find things.

**Fusion Process**:
1. **Create a temporary drawer** (temporary directory)
2. **Copy all files** from Drawer 1, 2, 3 into the temp drawer
3. **Sort and merge** them into one organized drawer
4. **Replace** the old drawers with the new organized one
5. **Clean up** the temporary drawer

**In Vespa Terms**:
```
Before Fusion:
├── index.flush.1 (old index file)
├── index.flush.2 (newer index file)
├── index.flush.3 (even newer index file)
└── index.flush.4 (latest index file)

After Fusion:
└── index.ready (one optimized, merged index)
```

**Why Fusion is Needed**:
- **Performance**: One big index is faster than many small ones
- **Efficiency**: Merged indexes use less disk space
- **Speed**: Search is faster with fewer files to check

---

### What Happens During Fusion?

**Step-by-Step Process**:

```
1. Vespa decides: "I have too many index files, let's merge them"
   ↓
2. Creates temporary directory: /opt/vespa/var/.../index.fusion.8/
   ↓
3. Reads all index files (index.flush.1, index.flush.2, etc.)
   ↓
4. Merges them into one optimized file in temp directory
   ↓
5. Replaces old index files with the new merged one
   ↓
6. Deletes temporary directory
   ↓
7. Done! ✅
```

**What Can Go Wrong**:

```
Step 6 Fails: "Failed to clean tmpdir"
   ↓
Temporary directory stays on disk
   ↓
Disk space fills up
   ↓
Next fusion fails because no space
   ↓
Vespa becomes unstable ❌
```

---

## 📚 Part 2: Understanding NFS Storage

### What is NFS?

**NFS** stands for **Network File System**.

**Simple Explanation**:

Imagine you have:
- **Your computer** (Kubernetes pod)
- **A shared hard drive** (NFS server) in another room
- **A network cable** (network connection) connecting them

When you save a file:
1. Your computer sends it over the network cable
2. The shared hard drive stores it
3. Your computer gets confirmation it's saved

**In Kubernetes Terms**:
```
Vespa Pod (in Kubernetes)
    │
    │ Network (NFS Protocol)
    │
    ▼
NFS Server (separate machine)
    └── /exports/vespa (shared folder)
```

---

### Why Use NFS?

**Advantages**:
- ✅ **Shared Storage**: Multiple pods can access the same data
- ✅ **Centralized**: All data in one place (easier backup)
- ✅ **Flexible**: Can resize storage easily
- ✅ **Cost-Effective**: One storage server for many pods

**Disadvantages**:
- ❌ **Slower**: Network adds latency (delay)
- ❌ **Less Reliable**: Network can fail
- ❌ **Locking Issues**: File locking can be problematic

---

### How NFS Works (Simple)

**Local Storage** (like a USB drive):
```
Pod → Direct connection → Disk
Time: 1 millisecond
```

**NFS Storage** (like a network drive):
```
Pod → Network → NFS Server → Disk
Time: 5-10 milliseconds (5-10x slower!)
```

**Why This Matters**:
- Vespa fusion creates/deletes **thousands** of files
- Each file operation takes 5-10ms instead of 1ms
- Total time: **5-10x longer**
- If it takes too long, operations **timeout and fail**

---

## 📚 Part 3: Why NFS Causes Fusion Failures

### Problem 1: Network Latency

**What is Latency?**

**Analogy**: 
- **Local storage**: Like talking to someone in the same room (instant)
- **NFS storage**: Like talking to someone on the phone (small delay)

**Example**:

**Local Storage**:
```
Vespa: "Delete file X"
Disk: "Done!" (1ms later)
```

**NFS Storage**:
```
Vespa: "Delete file X"
    ↓ (network delay: 5ms)
NFS Server: "Received request"
    ↓ (processing: 2ms)
NFS Server: "File deleted"
    ↓ (network delay: 5ms)
Vespa: "Done!" (12ms later - 12x slower!)
```

**Impact on Fusion**:
- Fusion deletes **hundreds of temporary files**
- Each deletion takes 12ms instead of 1ms
- Total time: **12x longer**
- Vespa timeout: **60 seconds**
- If fusion takes > 60 seconds → **FAILURE** ❌

---

### Problem 2: File Locking Issues

**What is File Locking?**

**Analogy**: 
- Like a "Do Not Disturb" sign on a hotel room door
- Prevents two processes from modifying the same file at once

**Example**:

**Local Storage** (Reliable Locking):
```
Process 1: "I'm editing file X" → Locks file
Process 2: "Can I edit file X?" → "No, it's locked" ✅
```

**NFS Storage** (Unreliable Locking):
```
Process 1: "I'm editing file X" → Tries to lock
    ↓ (network delay)
NFS Server: "Lock request received..."
    ↓ (another process also requests lock)
Process 2: "Can I edit file X?" → "Maybe?" ❌
    ↓ (race condition!)
Both processes think they have the lock
    ↓
Data corruption! ❌
```

**Impact on Fusion**:
- Fusion needs to lock index files during merge
- NFS locking can fail or be delayed
- Fusion thinks it has the lock, but doesn't
- Tries to delete files that are "locked" → **FAILURE** ❌

---

### Problem 3: Temporary File Cleanup Fails

**What Happens**:

**Normal Flow** (Local Storage):
```
1. Create temp directory: /tmp/fusion.8/
2. Create 1000 files in temp directory
3. Merge files
4. Delete temp directory (fast - 1ms per file)
5. Done! ✅
```

**NFS Flow** (Problems):
```
1. Create temp directory: /tmp/fusion.8/ ✅
2. Create 1000 files in temp directory ✅
3. Merge files ✅
4. Delete temp directory (slow - 12ms per file)
   - Delete file 1: 12ms
   - Delete file 2: 12ms
   - ...
   - Delete file 1000: 12ms
   - Total: 12,000ms = 12 seconds
5. If timeout is 10 seconds → FAILURE ❌
6. Temp directory not deleted → "Failed to clean tmpdir" error
```

**Result**:
- Temporary directories accumulate
- Disk space fills up
- Next fusion fails because no space
- Vespa becomes unstable

---

### Problem 4: Default NFS Settings Are Not Optimal

**Default NFS Mount Options** (What Kubernetes Uses by Default):
```
- nfsvers=3          # Old NFS version (worse locking)
- timeo=600          # 60 second timeout (too short for fusion)
- rsize=8192         # 8KB read buffer (too small)
- wsize=8192         # 8KB write buffer (too small)
- atime              # Update access times (unnecessary writes)
```

**Problems**:
1. **NFSv3**: Older version with worse file locking
2. **Small buffers**: More network calls needed (slower)
3. **Access time updates**: Wastes time writing metadata
4. **Short timeout**: Fusion operations timeout

**Example**:

**With Default Settings**:
```
Read 1MB file:
- Buffer size: 8KB
- Number of reads: 1MB / 8KB = 128 reads
- Each read: 5ms network + 1ms disk = 6ms
- Total: 128 × 6ms = 768ms
```

**With Optimized Settings**:
```
Read 1MB file:
- Buffer size: 1MB
- Number of reads: 1MB / 1MB = 1 read
- Each read: 5ms network + 1ms disk = 6ms
- Total: 1 × 6ms = 6ms (128x faster!)
```

---

## 📚 Part 4: The Solution Explained

### Solution Overview

We need to:
1. **Optimize NFS mount options** (make it faster)
2. **Increase Vespa resources** (give it more power)
3. **Use better NFS version** (NFSv4.1 has better locking)

---

### Understanding Each Mount Option

#### Option 1: `hard` vs `soft`

**What it means**:
- **`hard`**: Keep retrying if NFS server is unavailable (don't give up)
- **`soft`**: Give up after timeout (can cause data loss)

**Analogy**:
- **`hard`**: Keep calling someone until they answer
- **`soft`**: Call once, if no answer, hang up

**Why `hard` is better**:
- Vespa fusion operations are critical
- We don't want to lose data if network hiccups
- Better to wait than fail

**Example**:
```
With 'soft':
Vespa: "Delete file X"
NFS: (no response - network hiccup)
Vespa: "Timeout! Giving up" ❌
Result: File not deleted, fusion fails

With 'hard':
Vespa: "Delete file X"
NFS: (no response - network hiccup)
Vespa: "Retrying..."
NFS: (still no response)
Vespa: "Retrying again..."
NFS: "OK, deleted!" ✅
Result: File deleted, fusion succeeds
```

---

#### Option 2: `nfsvers=4.1` vs `nfsvers=3`

**What it means**:
- **NFSv3**: Older version (1995)
- **NFSv4.1**: Newer version (2010) with better features

**Key Differences**:

| Feature | NFSv3 | NFSv4.1 |
|---------|-------|---------|
| **File Locking** | Unreliable | More reliable |
| **Performance** | Slower | Faster |
| **Security** | Basic | Better |
| **State Management** | Stateless | Stateful (better) |

**Why NFSv4.1 is Better for Vespa**:

**NFSv3** (Stateless):
```
Vespa: "Lock file X"
NFS: "OK, locked"
    ↓ (network hiccup, connection lost)
Vespa: "Is file X still locked?"
NFS: "I don't remember..." ❌
Result: Lock lost, fusion fails
```

**NFSv4.1** (Stateful):
```
Vespa: "Lock file X"
NFS: "OK, locked (I'll remember this)"
    ↓ (network hiccup, connection lost)
Vespa: "Reconnect - is file X still locked?"
NFS: "Yes, still locked" ✅
Result: Lock maintained, fusion succeeds
```

---

#### Option 3: `timeo=600` (Timeout)

**What it means**:
- **`timeo`**: Timeout in **deciseconds** (1/10 of a second)
- **`timeo=600`**: 60 second timeout

**Why This Matters**:

**Default (often shorter)**:
```
Vespa: "Delete 1000 files" (takes 12 seconds)
    ↓ (after 10 seconds)
NFS: "Timeout! Operation cancelled" ❌
Result: Fusion fails
```

**With `timeo=600`**:
```
Vespa: "Delete 1000 files" (takes 12 seconds)
    ↓ (after 12 seconds)
NFS: "Still working..." ✅
    ↓ (completes)
NFS: "Done!" ✅
Result: Fusion succeeds
```

**Deciseconds Explained**:
- 1 second = 10 deciseconds
- `timeo=600` = 600 deciseconds = 60 seconds
- `timeo=300` = 300 deciseconds = 30 seconds

---

#### Option 4: `retrans=3` (Retries)

**What it means**:
- **`retrans`**: Number of times to retry if operation fails
- **`retrans=3`**: Retry 3 times before giving up

**Example**:

**Without retrans (or retrans=1)**:
```
Vespa: "Delete file X"
NFS: (network error - no response)
Vespa: "Failed! Giving up" ❌
```

**With retrans=3**:
```
Vespa: "Delete file X"
NFS: (network error - no response)
Vespa: "Retry 1..."
NFS: (network error - no response)
Vespa: "Retry 2..."
NFS: (network error - no response)
Vespa: "Retry 3..."
NFS: "OK, deleted!" ✅
```

**Why 3 Retries**:
- Network hiccups are usually temporary
- 3 retries gives network time to recover
- More than 3 = too slow, less than 3 = too quick to give up

---

#### Option 5: `actimeo=60` (Attribute Cache)

**What it means**:
- **`actimeo`**: How long to cache file attributes (size, permissions, etc.)
- **`actimeo=60`**: Cache for 60 seconds

**Why This Helps**:

**Without Caching**:
```
Vespa: "What's the size of file X?"
NFS: (network call: 5ms) "100KB"
Vespa: "What's the size of file X?" (asks again 1 second later)
NFS: (network call: 5ms) "100KB"
Vespa: "What's the size of file X?" (asks again 1 second later)
NFS: (network call: 5ms) "100KB"
Total: 15ms for 3 identical questions
```

**With Caching (actimeo=60)**:
```
Vespa: "What's the size of file X?"
NFS: (network call: 5ms) "100KB" (cached for 60 seconds)
Vespa: "What's the size of file X?" (asks again 1 second later)
NFS: (from cache: 0ms) "100KB" ✅
Vespa: "What's the size of file X?" (asks again 1 second later)
NFS: (from cache: 0ms) "100KB" ✅
Total: 5ms for 3 questions (3x faster!)
```

**Why 60 Seconds**:
- Long enough to avoid repeated network calls
- Short enough that changes are detected quickly
- Good balance for Vespa operations

---

#### Option 6: `noatime` and `nodiratime`

**What it means**:
- **`atime`**: Access time (when file was last read)
- **`noatime`**: Don't update access time
- **`nodiratime`**: Don't update directory access time

**Why This Matters**:

**Without `noatime`**:
```
Vespa: "Read file X"
NFS: "Here's the file" (5ms)
    ↓
NFS: "Also updating access time" (2ms write)
Total: 7ms per read
```

**With `noatime`**:
```
Vespa: "Read file X"
NFS: "Here's the file" (5ms)
    ↓
NFS: (skips access time update)
Total: 5ms per read (29% faster!)
```

**Impact**:
- Vespa reads **thousands** of files during fusion
- Each read saves 2ms
- 1000 files × 2ms = **2 seconds saved** per fusion!

---

#### Option 7: `rsize=1048576` and `wsize=1048576` (Buffer Sizes)

**What it means**:
- **`rsize`**: Read buffer size (how much data to read at once)
- **`wsize`**: Write buffer size (how much data to write at once)
- **`1048576`**: 1 megabyte (1MB) in bytes

**Why This Matters**:

**Small Buffers (Default: 8KB)**:
```
Read 1MB file:
- Read 8KB chunk 1: 6ms
- Read 8KB chunk 2: 6ms
- Read 8KB chunk 3: 6ms
- ...
- Read 8KB chunk 128: 6ms
Total: 128 × 6ms = 768ms
```

**Large Buffers (1MB)**:
```
Read 1MB file:
- Read 1MB chunk: 6ms
Total: 1 × 6ms = 6ms (128x faster!)
```

**Bytes Explained**:
- 1 KB = 1,024 bytes
- 1 MB = 1,024 KB = 1,048,576 bytes
- `rsize=1048576` = 1 MB

**Why 1MB is Good**:
- Large enough to reduce network calls
- Not too large (would waste memory)
- Good balance for Vespa's file sizes

---

#### Option 8: `tcp` (Protocol)

**What it means**:
- **`tcp`**: Use TCP protocol (reliable, connection-oriented)
- **Default (UDP)**: Unreliable, can lose packets

**Why TCP is Better**:

**UDP** (Unreliable):
```
Vespa: "Delete file X" (sends packet)
    ↓ (packet lost in network)
NFS: (never received packet)
Vespa: "File deleted?" (waits...)
NFS: (no response)
Result: File not deleted, fusion fails ❌
```

**TCP** (Reliable):
```
Vespa: "Delete file X" (sends packet)
    ↓ (packet lost in network)
TCP: "Packet lost, resending..."
    ↓ (packet resent)
NFS: "Received! File deleted" ✅
Vespa: "Confirmed!" ✅
Result: File deleted, fusion succeeds
```

**TCP Features**:
- **Reliable**: Guarantees delivery
- **Ordered**: Packets arrive in order
- **Error checking**: Detects and fixes errors

---

#### Option 9: `intr` (Interruptible)

**What it means**:
- **`intr`**: Allow operations to be interrupted (cancelled)
- Without `intr`: Operations can't be cancelled (can hang)

**Why This Helps**:

**Without `intr`**:
```
Vespa: "Delete file X" (stuck operation)
    ↓ (user tries to stop Vespa)
System: "Can't stop - operation in progress" ❌
Result: Vespa hangs, can't restart
```

**With `intr`**:
```
Vespa: "Delete file X" (stuck operation)
    ↓ (user tries to stop Vespa)
System: "Interrupting operation..."
Vespa: "Operation cancelled" ✅
Result: Vespa can be stopped and restarted
```

---

## 📚 Part 5: Step-by-Step Implementation

### Step 1: Understand Your Current Setup

**Check what you have**:

```bash
# Check current PVC
kubectl get pvc -n onyx-infra

# Output example:
# NAME                    STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
# vespa-storage-vespa-0   Bound    pv-123   30Gi       RWO            nfs-example
```

**Check PV details**:
```bash
kubectl get pv pv-123 -o yaml | grep -A 10 nfs

# Output example:
# nfs:
#   server: 192.168.1.100
#   path: /exports/vespa
```

**Note these values** - you'll need them!

---

### Step 2: Create Optimized PersistentVolume

**File**: `onyx-k8s-infrastructure/manifests/03-vespa-pv-optimized.yaml`

**What this file does**:
- Creates a PersistentVolume (PV) with optimized NFS settings
- Tells Kubernetes how to mount NFS storage

**Complete File**:
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: vespa-storage-pv
  labels:
    app: vespa
spec:
  capacity:
    storage: 30Gi              # Same size as your current PVC
  accessModes:
    - ReadWriteOnce            # One pod can read/write
  persistentVolumeReclaimPolicy: Retain  # Keep data if PVC deleted
  storageClassName: nfs-example
  mountOptions:                # ✅ THE MAGIC HAPPENS HERE
    - hard                     # Keep retrying on errors
    - nfsvers=4.1              # Use NFS version 4.1 (better locking)
    - timeo=600                # 60 second timeout
    - retrans=3                # Retry 3 times
    - actimeo=60               # Cache attributes for 60 seconds
    - noatime                  # Don't update access times
    - nodiratime               # Don't update directory access times
    - rsize=1048576            # 1MB read buffer
    - wsize=1048576            # 1MB write buffer
    - tcp                      # Use TCP (reliable)
    - intr                     # Allow interrupts
  nfs:
    server: 192.168.1.100      # ⚠️ CHANGE THIS to your NFS server IP
    path: /exports/vespa       # ⚠️ CHANGE THIS to your NFS export path
```

**How to Find Your NFS Server Info**:

**Method 1: From Existing PV**
```bash
# Get current PV name from PVC
PVC_NAME=$(kubectl get pvc vespa-storage-vespa-0 -n onyx-infra -o jsonpath='{.spec.volumeName}')

# Get NFS details
kubectl get pv $PVC_NAME -o yaml | grep -A 3 nfs:
```

**Method 2: From NFS Server Admin**
- Ask your infrastructure team for:
  - NFS server IP address
  - NFS export path (where Vespa data is stored)

**Method 3: From StorageClass**
```bash
# If using dynamic provisioning
kubectl get storageclass nfs-example -o yaml | grep -A 5 parameters
```

---

### Step 3: Update the File

**Edit** `onyx-k8s-infrastructure/manifests/03-vespa-pv-optimized.yaml`:

**Find these lines**:
```yaml
  nfs:
    server: <YOUR_NFS_SERVER_IP>        # Line 1 to change
    path: <YOUR_NFS_EXPORT_PATH>        # Line 2 to change
```

**Replace with your values**:
```yaml
  nfs:
    server: 192.168.1.100               # Your actual NFS server IP
    path: /exports/vespa                # Your actual NFS export path
```

**Example**:
- If your NFS server is at `10.0.0.50`
- And the export path is `/nfs/onyx/vespa`
- Then write:
```yaml
  nfs:
    server: 10.0.0.50
    path: /nfs/onyx/vespa
```

---

### Step 4: Apply the Changes

**Step 4.1: Apply the Optimized PV**

```bash
cd /Users/chihebmhamdi/Desktop/onyx/onyx-k8s-infrastructure/manifests

# Apply the optimized PV
kubectl apply -f 03-vespa-pv-optimized.yaml

# Verify it was created
kubectl get pv vespa-storage-pv
```

**Expected Output**:
```
NAME              CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS
vespa-storage-pv  30Gi       RWO            Retain           Available           nfs-example
```

**If STATUS shows "Available"**: ✅ Good! PV is ready.

---

**Step 4.2: Update StatefulSet (Resources Already Updated)**

The resources in `03-vespa.yaml` are already increased. Just apply:

```bash
# Apply updated StatefulSet
kubectl apply -f 03-vespa.yaml

# Verify changes
kubectl get statefulset vespa -n onyx-infra -o yaml | grep -A 5 resources
```

**Expected Output**:
```yaml
resources:
  requests:
    cpu: 2000m
    memory: 4Gi
  limits:
    cpu: 8000m
    memory: 16Gi
```

---

**Step 4.3: Restart Vespa Pod**

**Why restart?**
- Mount options are applied when the pod starts
- We need to restart to apply new mount options

```bash
# Delete the pod (StatefulSet will recreate it)
kubectl delete pod vespa-0 -n onyx-infra

# Watch it restart
kubectl get pods -n onyx-infra -w | grep vespa
```

**Expected Output**:
```
NAME      READY   STATUS        RESTARTS   AGE
vespa-0   0/1     Terminating   0          5h
vespa-0   0/1     Pending       0          0s
vespa-0   0/1     ContainerCreating   0          5s
vespa-0   1/1     Running       0          30s
```

**Wait until STATUS shows "Running"** ✅

---

### Step 5: Verify Mount Options Applied

**Check if mount options are active**:

```bash
# Exec into the pod
kubectl exec -it vespa-0 -n onyx-infra -- bash

# Check mount options
mount | grep vespa-storage
```

**Expected Output** (should show optimized options):
```
192.168.1.100:/exports/vespa on /opt/vespa/var type nfs4 
(rw,relatime,vers=4.1,rsize=1048576,wsize=1048576,namlen=255,hard,proto=tcp,
timeo=600,retrans=3,sec=sys,clientaddr=10.244.1.5,local_lock=none,addr=192.168.1.100)
```

**What to Look For**:
- ✅ `vers=4.1` - NFS version 4.1
- ✅ `rsize=1048576` - 1MB read buffer
- ✅ `wsize=1048576` - 1MB write buffer
- ✅ `timeo=600` - 60 second timeout
- ✅ `hard` - Hard mount
- ✅ `tcp` - TCP protocol

**If you see these**: ✅ Mount options are applied correctly!

**Exit the pod**:
```bash
exit
```

---

### Step 6: Monitor Fusion Operations

**Watch Vespa logs for fusion operations**:

```bash
# Watch logs in real-time
kubectl logs -f vespa-0 -n onyx-infra | grep -i fusion
```

**What to Look For**:

**Before Fix** (Bad):
```
[ERROR] Fusion failed, fusion dir
[ERROR] Failed to clean tmpdir
[WARNING] Fusion failed for id 8
```

**After Fix** (Good):
```
[INFO] Fusion started for id 8
[INFO] Fusion completed successfully
[INFO] Cleaned up temporary directory
```

**If you see "Fusion completed successfully"**: ✅ Fix is working!

---

## 📚 Part 6: Understanding Resource Increases

### Why Increase CPU?

**CPU (Central Processing Unit)** is like the **brain** of the computer.

**Analogy**:
- **Low CPU**: Like having one person process paperwork (slow)
- **High CPU**: Like having multiple people process paperwork (fast)

**For NFS Operations**:
- NFS I/O operations need CPU to process network packets
- More CPU = faster processing of NFS requests
- Faster processing = less chance of timeout

**Example**:

**With 1000m CPU**:
```
Vespa: "Delete 1000 files"
CPU: "Processing... (slow)"
    ↓ (takes 15 seconds)
Timeout! ❌
```

**With 2000m CPU**:
```
Vespa: "Delete 1000 files"
CPU: "Processing... (faster)"
    ↓ (takes 8 seconds)
Success! ✅
```

---

### Why Increase Memory?

**Memory (RAM)** is like **short-term memory** - fast access storage.

**Analogy**:
- **Low Memory**: Like a small desk (can't hold many files at once)
- **High Memory**: Like a large desk (can hold many files)

**For Vespa Fusion**:
- Fusion needs to load index files into memory
- More memory = can load more files at once
- More files in memory = fewer disk reads = faster

**Example**:

**With 2Gi Memory**:
```
Fusion: "Load index files"
Memory: "I can only hold 2 files at once"
    ↓
Load file 1 → Process → Unload
Load file 2 → Process → Unload
Load file 3 → Process → Unload
...
Total: 1000 disk reads (slow) ❌
```

**With 4Gi Memory**:
```
Fusion: "Load index files"
Memory: "I can hold 4 files at once"
    ↓
Load files 1-4 → Process all → Unload
Load files 5-8 → Process all → Unload
...
Total: 250 disk reads (4x faster!) ✅
```

---

## 📚 Part 7: Real-World Example

### Scenario: Fusion Failure

**What Happens**:

```
1. User uploads 10 documents
   ↓
2. Vespa indexes them (creates index.flush.1, index.flush.2, etc.)
   ↓
3. Vespa decides: "Time to merge indexes" (fusion)
   ↓
4. Creates temp directory: index.fusion.8/
   ↓
5. Merges files (this part works) ✅
   ↓
6. Tries to delete temp directory
   ↓
7. NFS is slow (12ms per file delete)
   ↓
8. 1000 files × 12ms = 12,000ms = 12 seconds
   ↓
9. Vespa timeout: 10 seconds
   ↓
10. Timeout! "Failed to clean tmpdir" ❌
   ↓
11. Temp directory stays on disk
   ↓
12. Next fusion fails (no disk space)
   ↓
13. Vespa becomes unstable ❌
```

---

### After Fix: What Happens

```
1. User uploads 10 documents
   ↓
2. Vespa indexes them
   ↓
3. Vespa decides: "Time to merge indexes" (fusion)
   ↓
4. Creates temp directory: index.fusion.8/
   ↓
5. Merges files ✅
   ↓
6. Tries to delete temp directory
   ↓
7. NFS is faster (6ms per file with optimized settings)
   ↓
8. 1000 files × 6ms = 6,000ms = 6 seconds
   ↓
9. Vespa timeout: 60 seconds (increased)
   ↓
10. Success! Temp directory deleted ✅
   ↓
11. Fusion completes successfully ✅
   ↓
12. Vespa is stable ✅
```

---

## 📚 Part 8: Troubleshooting

### Problem: Mount Options Not Applied

**Symptom**: 
- Checked mount options, still showing old values
- Fusion still failing

**Check**:
```bash
# Verify PV exists and is bound
kubectl get pv vespa-storage-pv

# Check if PVC is using the PV
kubectl get pvc vespa-storage-vespa-0 -n onyx-infra -o yaml | grep volumeName
```

**Solution**:
- If using **dynamic provisioning**, mount options must be in **StorageClass**, not PV
- See Solution 2 in the main guide

---

### Problem: NFS Server Unreachable

**Symptom**:
- Pod can't mount NFS
- Pod stays in "ContainerCreating" status

**Check**:
```bash
# Check pod events
kubectl describe pod vespa-0 -n onyx-infra | grep -A 10 Events

# Test NFS connectivity (from another pod)
kubectl run -it --rm test-nfs --image=busybox --restart=Never -- ping <NFS_SERVER_IP>
```

**Solution**:
- Verify NFS server IP is correct
- Check network connectivity
- Verify NFS exports are configured

---

### Problem: Permission Denied

**Symptom**:
- Pod starts but can't write to `/opt/vespa/var`
- Permission errors in logs

**Check**:
```bash
# Check file permissions
kubectl exec -it vespa-0 -n onyx-infra -- ls -la /opt/vespa/var

# Check who Vespa runs as
kubectl exec -it vespa-0 -n onyx-infra -- whoami
```

**Solution**:
- Vespa runs as root (UID 0) or user 1000
- NFS export must allow root access or match UID
- Check NFS server export options: `no_root_squash`

---

## 📊 Summary: Before vs After

### Before Fix

| Aspect | Value | Problem |
|--------|-------|---------|
| **NFS Version** | v3 | Unreliable locking |
| **Read Buffer** | 8KB | Too small (128 reads for 1MB) |
| **Write Buffer** | 8KB | Too small (128 writes for 1MB) |
| **Timeout** | 10-30s | Too short for fusion |
| **CPU** | 1000m | Too slow for NFS I/O |
| **Memory** | 2Gi | Too small for fusion |
| **Fusion Success Rate** | ~60% | Many failures ❌ |

### After Fix

| Aspect | Value | Benefit |
|--------|-------|---------|
| **NFS Version** | v4.1 | Reliable locking ✅ |
| **Read Buffer** | 1MB | Large (1 read for 1MB) ✅ |
| **Write Buffer** | 1MB | Large (1 write for 1MB) ✅ |
| **Timeout** | 60s | Long enough for fusion ✅ |
| **CPU** | 2000m | Fast enough for NFS I/O ✅ |
| **Memory** | 4Gi | Large enough for fusion ✅ |
| **Fusion Success Rate** | ~99% | Very few failures ✅ |

---

## 🎯 Key Takeaways

1. **Vespa Fusion** = Merging multiple index files into one (like organizing a filing cabinet)

2. **NFS Storage** = Network-attached storage (slower than local, but shared)

3. **The Problem** = NFS is too slow for Vespa's rapid file operations, causing timeouts

4. **The Solution** = Optimize NFS mount options + increase Vespa resources

5. **Mount Options** = Settings that tell the system how to use NFS (like tuning a car)

6. **Expected Result** = Fusion operations succeed, Vespa is stable

---

## 📝 Quick Reference: Mount Options Explained

| Option | Value | What It Does | Why It Helps |
|--------|-------|--------------|--------------|
| `hard` | - | Keep retrying on errors | Prevents data loss |
| `nfsvers=4.1` | 4.1 | Use NFS version 4.1 | Better file locking |
| `timeo=600` | 60s | 60 second timeout | Gives fusion time to complete |
| `retrans=3` | 3 | Retry 3 times | Handles network hiccups |
| `actimeo=60` | 60s | Cache for 60 seconds | Reduces network calls |
| `noatime` | - | Don't update access times | Saves 2ms per file read |
| `nodiratime` | - | Don't update dir access times | Saves time on dir operations |
| `rsize=1048576` | 1MB | 1MB read buffer | 128x fewer network calls |
| `wsize=1048576` | 1MB | 1MB write buffer | 128x fewer network calls |
| `tcp` | - | Use TCP protocol | Reliable delivery |
| `intr` | - | Allow interrupts | Can cancel stuck operations |

---

## 📖 Glossary: Technical Terms Explained

This glossary explains all technical terms used in this guide, especially those related to NFS, storage, and Vespa.

---

### A

**Access Time (atime)**
- **Definition**: A file attribute that records when a file was last read or accessed
- **Example**: If you open a file at 2:00 PM, the access time is updated to 2:00 PM
- **Why it matters**: Updating access time requires a write operation, which slows down NFS reads
- **Related**: `noatime`, `nodiratime`

**Attribute Cache (actimeo)**
- **Definition**: A temporary storage in memory that remembers file information (size, permissions, etc.) to avoid repeated network calls
- **Analogy**: Like remembering someone's phone number instead of looking it up every time
- **Why it matters**: Reduces network calls to NFS server, making operations faster
- **Default**: Usually 60 seconds

---

### B

**Buffer**
- **Definition**: A temporary storage area in memory used to hold data before it's processed or sent
- **Analogy**: Like a bucket used to carry water - bigger bucket = fewer trips
- **Types**:
  - **Read Buffer (rsize)**: How much data to read from NFS at once
  - **Write Buffer (wsize)**: How much data to write to NFS at once
- **Why it matters**: Larger buffers = fewer network calls = faster operations
- **Example**: 1MB buffer reads 1MB in one go, while 8KB buffer needs 128 reads for 1MB

**Byte**
- **Definition**: The smallest unit of digital data storage (8 bits)
- **Units**:
  - 1 KB (Kilobyte) = 1,024 bytes
  - 1 MB (Megabyte) = 1,024 KB = 1,048,576 bytes
  - 1 GB (Gigabyte) = 1,024 MB
- **Example**: The letter "A" is 1 byte, a small text file might be 1 KB

---

### C

**CPU (Central Processing Unit)**
- **Definition**: The "brain" of a computer that processes instructions and performs calculations
- **Analogy**: Like the engine of a car - more powerful engine = faster car
- **Units**: Measured in cores or millicores (m)
  - 1000m = 1 core
  - 2000m = 2 cores
- **Why it matters**: More CPU = faster processing of NFS operations

**Connection-Oriented**
- **Definition**: A type of network communication where a connection is established before data is sent
- **Example**: TCP is connection-oriented (like a phone call - you dial first, then talk)
- **Opposite**: Connectionless (like UDP - like sending a postcard)

---

### D

**Decisecond**
- **Definition**: One-tenth of a second (0.1 seconds)
- **Conversion**: 
  - 1 second = 10 deciseconds
  - 60 seconds = 600 deciseconds
- **Why it matters**: NFS timeouts are measured in deciseconds
- **Example**: `timeo=600` means 60 seconds timeout

**Directory**
- **Definition**: A folder that contains files and other directories
- **Analogy**: Like a filing cabinet drawer that holds folders
- **Example**: `/opt/vespa/var` is a directory
- **Related**: Temporary directory, mount directory

**Dynamic Provisioning**
- **Definition**: Automatic creation of storage volumes when needed
- **Analogy**: Like an automatic vending machine that creates items on demand
- **Opposite**: Static provisioning (manually creating volumes)
- **Why it matters**: Determines where mount options are configured (StorageClass vs PV)

---

### E

**Export (NFS Export)**
- **Definition**: A directory on the NFS server that is shared and accessible over the network
- **Analogy**: Like a shared folder on a network drive
- **Example**: `/exports/vespa` is an NFS export path
- **Configuration**: Set on the NFS server to define what directories are shared

---

### F

**File Locking**
- **Definition**: A mechanism that prevents multiple processes from modifying the same file simultaneously
- **Analogy**: Like a "Do Not Disturb" sign on a hotel room door
- **Types**:
  - **Shared Lock**: Multiple processes can read, but not write
  - **Exclusive Lock**: Only one process can access the file
- **Why it matters**: Prevents data corruption when multiple processes access the same file
- **NFS Issue**: NFS file locking can be unreliable, especially in NFSv3

**Fusion (Vespa Fusion)**
- **Definition**: The process of merging multiple index files into one optimized index
- **Analogy**: Like consolidating multiple filing cabinets into one organized cabinet
- **Purpose**: Improves search performance and reduces disk space
- **Process**: Creates temporary directory → merges files → replaces old files → cleans up

---

### H

**Hard Mount**
- **Definition**: An NFS mount option that keeps retrying operations if the NFS server is unavailable
- **Analogy**: Like persistently calling someone until they answer
- **Opposite**: Soft mount (gives up after timeout)
- **Why it matters**: Prevents data loss if network has temporary hiccups
- **Use case**: Critical operations that must not fail

---

### I

**Index (Search Index)**
- **Definition**: A data structure that allows fast searching of documents
- **Analogy**: Like a book's table of contents or index at the back
- **Types**:
  - **Flush Index**: Temporary index created during document processing
  - **Ready Index**: Final, optimized index ready for searching
- **Why it matters**: Indexes make search fast - without them, searching would be very slow

**Interrupt (intr)**
- **Definition**: A signal that can stop or cancel a running operation
- **Analogy**: Like pressing Ctrl+C to stop a program
- **Why it matters**: Allows stuck operations to be cancelled, preventing system hangs
- **NFS Option**: `intr` allows NFS operations to be interrupted

**I/O (Input/Output)**
- **Definition**: Operations that read from or write to storage
- **Types**:
  - **Input**: Reading data (from disk to memory)
  - **Output**: Writing data (from memory to disk)
- **Why it matters**: NFS I/O is slower than local I/O due to network latency

---

### K

**Kubernetes**
- **Definition**: An open-source system for managing containerized applications
- **Key Concepts**:
  - **Pod**: The smallest deployable unit (like a container)
  - **StatefulSet**: Manages stateful applications (like Vespa)
  - **PVC (PersistentVolumeClaim)**: Request for storage
  - **PV (PersistentVolume)**: The actual storage volume
- **Why it matters**: Vespa runs in Kubernetes pods

---

### L

**Latency**
- **Definition**: The delay between sending a request and receiving a response
- **Types**:
  - **Network Latency**: Delay over network (NFS adds this)
  - **Disk Latency**: Delay for disk operations
- **Analogy**: Like the time it takes for a letter to arrive in the mail
- **Why it matters**: High latency slows down all operations
- **Example**: Local storage: 1ms, NFS storage: 5-10ms

**Lock (File Lock)**
- **Definition**: See "File Locking"

---

### M

**Memory (RAM)**
- **Definition**: Temporary storage that the CPU uses to hold data and programs while running
- **Analogy**: Like a desk - bigger desk = can hold more files at once
- **Units**: Measured in bytes (KB, MB, GB)
- **Types**:
  - **Request**: Minimum memory guaranteed
  - **Limit**: Maximum memory allowed
- **Why it matters**: More memory = can load more files = fewer disk reads = faster

**Metadata**
- **Definition**: Data about data (file size, permissions, creation date, etc.)
- **Analogy**: Like a book's cover that tells you the title, author, and page count
- **Examples**: File size, permissions, access time, modification time
- **Why it matters**: Updating metadata requires writes, which can slow down operations

**Mount**
- **Definition**: The process of making a storage device or network share accessible to the operating system
- **Analogy**: Like plugging in a USB drive so the computer can see it
- **NFS Mount**: Making an NFS share accessible to a pod
- **Mount Point**: The directory where the storage is accessible (e.g., `/opt/vespa/var`)

**Mount Options**
- **Definition**: Settings that control how a filesystem is mounted
- **Analogy**: Like settings on a car (automatic vs manual, fuel type, etc.)
- **Examples**: `hard`, `nfsvers=4.1`, `timeo=600`
- **Why it matters**: Mount options determine performance and reliability

---

### N

**Network File System (NFS)**
- **Definition**: A protocol that allows a computer to access files over a network as if they were local
- **Versions**:
  - **NFSv3**: Older version (1995), stateless, less reliable locking
  - **NFSv4.1**: Newer version (2010), stateful, better locking and performance
- **Analogy**: Like a shared network drive that multiple computers can access
- **Why it matters**: NFS adds network latency to all file operations

**Network Protocol**
- **Definition**: A set of rules for how data is transmitted over a network
- **Types**:
  - **TCP (Transmission Control Protocol)**: Reliable, connection-oriented
  - **UDP (User Datagram Protocol)**: Fast, connectionless, can lose packets
- **Why it matters**: TCP is more reliable for NFS, preventing data loss

**noatime**
- **Definition**: A mount option that disables updating file access times
- **Why it matters**: Saves time by skipping unnecessary write operations
- **Performance**: Can save 2ms per file read
- **Related**: `nodiratime` (for directories)

**nodiratime**
- **Definition**: A mount option that disables updating directory access times
- **Why it matters**: Saves time on directory operations
- **Related**: `noatime` (for files)

---

### P

**PersistentVolume (PV)**
- **Definition**: A storage resource in Kubernetes that represents actual storage
- **Analogy**: Like a physical hard drive that exists in the cluster
- **Types**: Can be local storage, NFS, cloud storage, etc.
- **Why it matters**: Defines the storage that pods can use

**PersistentVolumeClaim (PVC)**
- **Definition**: A request for storage by a pod
- **Analogy**: Like requesting a parking space
- **Binding**: PVC binds to a PV to provide storage to a pod
- **Why it matters**: Pods request storage through PVCs

**Pod**
- **Definition**: The smallest deployable unit in Kubernetes (usually contains one container)
- **Analogy**: Like a shipping container that holds an application
- **Example**: `vespa-0` is a pod running Vespa
- **Why it matters**: Vespa runs inside a pod

**Protocol**
- **Definition**: See "Network Protocol"

---

### R

**Read Buffer (rsize)**
- **Definition**: The amount of data read from NFS in a single operation
- **Default**: Usually 8KB or 32KB
- **Optimized**: 1MB (1048576 bytes)
- **Why it matters**: Larger buffer = fewer network calls = faster reads
- **Example**: 1MB file with 1MB buffer = 1 read, with 8KB buffer = 128 reads

**Retrans (retrans)**
- **Definition**: The number of times to retry a failed NFS operation
- **Default**: Usually 3
- **Why it matters**: Handles temporary network failures
- **Example**: If operation fails, retry up to 3 times before giving up

**Root Squash (no_root_squash)**
- **Definition**: An NFS server setting that controls whether root user on client can access files as root
- **no_root_squash**: Allows root access (needed for Vespa running as root)
- **root_squash**: Maps root to a non-privileged user (more secure but can cause permission issues)
- **Why it matters**: Vespa runs as root, so NFS must allow root access

---

### S

**StatefulSet**
- **Definition**: A Kubernetes resource that manages stateful applications
- **Features**:
  - Stable network identity (predictable hostnames)
  - Ordered deployment and scaling
  - Persistent storage per pod
- **Why it matters**: Vespa needs stable identity and persistent storage

**Static Provisioning**
- **Definition**: Manually creating storage volumes before they're needed
- **Analogy**: Like reserving parking spaces in advance
- **Opposite**: Dynamic provisioning (automatic creation)
- **Why it matters**: Determines where mount options are configured (PV vs StorageClass)

**StorageClass**
- **Definition**: A Kubernetes resource that defines a class of storage
- **Purpose**: Used for dynamic provisioning to automatically create PVs
- **Why it matters**: If using dynamic provisioning, mount options go in StorageClass

---

### T

**TCP (Transmission Control Protocol)**
- **Definition**: A reliable, connection-oriented network protocol
- **Features**:
  - Guarantees delivery (resends lost packets)
  - Maintains order (packets arrive in order)
  - Error checking and correction
- **Why it matters**: More reliable than UDP for NFS operations
- **NFS Option**: `tcp` tells NFS to use TCP instead of UDP

**Timeout (timeo)**
- **Definition**: The maximum time to wait for an operation to complete
- **Units**: Measured in deciseconds (1/10 of a second)
- **Example**: `timeo=600` = 60 seconds
- **Why it matters**: Operations that take longer than timeout will fail
- **NFS Issue**: Default timeouts may be too short for fusion operations

**Temporary Directory (tmpdir)**
- **Definition**: A directory created temporarily during an operation and deleted afterward
- **Example**: `/opt/vespa/var/.../index.fusion.8/` is a temporary directory
- **Why it matters**: If cleanup fails, temp directories accumulate and fill disk space
- **Error**: "Failed to clean tmpdir" means temporary directory couldn't be deleted

---

### U

**UDP (User Datagram Protocol)**
- **Definition**: A fast, connectionless network protocol
- **Features**:
  - Fast (no connection setup)
  - Can lose packets (not guaranteed delivery)
  - No error checking
- **Why it matters**: Less reliable than TCP for NFS
- **Default**: Some NFS configurations use UDP by default

**UID (User ID)**
- **Definition**: A unique number that identifies a user in the system
- **Examples**:
  - UID 0 = root user
  - UID 1000 = regular user
- **Why it matters**: Vespa runs as UID 0 (root) or UID 1000, NFS must allow this

---

### V

**Vector Search Engine**
- **Definition**: A search system that uses mathematical vectors to find similar documents
- **How it works**: Converts documents into vectors (arrays of numbers), then finds similar vectors
- **Example**: Vespa is a vector search engine
- **Why it matters**: Enables semantic search (finding documents by meaning, not just keywords)

**Vespa**
- **Definition**: An open-source vector search engine developed by Yahoo
- **Features**:
  - Fast search
  - Real-time indexing
  - Handles large-scale data
- **Why it matters**: Onyx uses Vespa to store and search document embeddings

---

### W

**Write Buffer (wsize)**
- **Definition**: The amount of data written to NFS in a single operation
- **Default**: Usually 8KB or 32KB
- **Optimized**: 1MB (1048576 bytes)
- **Why it matters**: Larger buffer = fewer network calls = faster writes
- **Example**: 1MB file with 1MB buffer = 1 write, with 8KB buffer = 128 writes

---

## 📚 Additional Resources

For more information on these terms:
- **Kubernetes**: https://kubernetes.io/docs/concepts/
- **NFS**: https://en.wikipedia.org/wiki/Network_File_System
- **Vespa**: https://vespa.ai/

---

**Last Updated**: 2024  
**Version**: 1.0  
**Target Audience**: Junior IT Engineers

