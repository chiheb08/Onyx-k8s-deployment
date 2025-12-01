# Complete File Upload Performance Fix: Backend + Frontend

## 🎯 Problem Summary

You're experiencing **two related issues**:

1. **Backend**: Files process slowly in OpenShift (60-120 seconds)
2. **Frontend**: Endless network requests every 3 seconds (20-40+ requests per file)

**Result**: Slow processing + unnecessary network load = poor user experience

---

## 🔍 Root Causes

### Backend Issues (Why Processing is Slow)

1. **Low Celery Worker Concurrency**: Only 2 threads (should be 8+)
2. **Single Worker Replica**: No horizontal scaling
3. **Insufficient Resources**: 500m CPU, 512Mi memory (too low)
4. **Network Latency**: Services communicate over network (5-20ms per call)
5. **Small Batch Sizes**: Embedding batch size is 8 (should be 16+)

### Frontend Issues (Why Endless Requests)

1. **Too Frequent Polling**: Checks status every 3 seconds
2. **No Exponential Backoff**: Same frequency regardless of time elapsed
3. **No Smart Stopping**: Continues even when tab is hidden

---

## ✅ Complete Solution

### Part 1: Backend Optimization (5-10x Faster Processing)

**Quick Fix (5 minutes)**:

#### Step 1.1: Modify ConfigMap - Add Worker Concurrency

**File Location**: `manifests/05-configmap.yaml` (or your ConfigMap file)

**What to do**: Add the environment variable to the `data` section

**Exact Location**: In the `data:` section of the ConfigMap (around line 20-50, depending on your file)

**Current File Structure**:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: onyx-config
data:
  POSTGRES_HOST: "postgresql.onyx-infra.svc.cluster.local"
  POSTGRES_PORT: "5432"
  # ... other variables ...
```

**Add This Line** (add it anywhere in the `data:` section):
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: onyx-config
data:
  POSTGRES_HOST: "postgresql.onyx-infra.svc.cluster.local"
  POSTGRES_PORT: "5432"
  # ... other variables ...
  
  # ============================================================================
  # CELERY WORKER CONFIGURATION - FILE UPLOAD OPTIMIZATION
  # ============================================================================
  # Controls how many file processing tasks run in parallel per worker
  # Default: 2, Recommended for OpenShift: 8
  # Higher values = faster processing but more CPU/memory usage
  CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY: "8"
```

**Apply the change**:
```bash
# Option 1: Edit directly
oc edit configmap onyx-config
# Add the line above in the data section, save and exit

# Option 2: Apply from file
oc apply -f manifests/05-configmap.yaml

# Option 3: Set via command
oc set env configmap/onyx-config CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY=8
```

#### Step 1.2: Scale Workers

**What to do**: Increase the number of worker replicas

**File Location** (if using Helm): `deployment/helm/charts/onyx/values.yaml`

**Exact Location**: Find `celery_worker_user_file_processing:` section (around line 620)

**Current Value**:
```yaml
celery_worker_user_file_processing:
  replicaCount: 1  # ← Change this
```

**Change To**:
```yaml
celery_worker_user_file_processing:
  replicaCount: 3  # ← Changed from 1 to 3
```

**Or via Command** (if not using Helm):
```bash
oc scale deployment celery-worker-user-file-processing --replicas=3
```

#### Step 1.3: Restart Workers

**What to do**: Restart workers to pick up new configuration

```bash
oc rollout restart deployment celery-worker-user-file-processing
```

**Expected Result**: Files process 2-3x faster (60s → 20-30s)

**Full Optimization**: See `FILE-UPLOAD-PERFORMANCE-OPTIMIZATION.md`

---

### Part 2: Frontend Optimization (70% Fewer Requests)

**Quick Fix (5 minutes)**:

#### Step 2.1: Modify Frontend Polling Interval

**File Location**: `onyx-repo/web/src/app/chat/projects/ProjectsContext.tsx`

**Exact Location**: Line 666 (or search for `setInterval(poll, 3000)`)

**What to do**: Change the polling interval from 3 seconds to 10 seconds

**Current Code** (around line 663-667):
```typescript
if (shouldPoll && pollIntervalRef.current === null) {
  // Kick once immediately, then start interval
  poll();
  pollIntervalRef.current = window.setInterval(poll, 3000); // ← Line 666: Change this
}
```

**Change To**:
```typescript
if (shouldPoll && pollIntervalRef.current === null) {
  // Kick once immediately, then start interval
  poll();
  pollIntervalRef.current = window.setInterval(poll, 10000); // ← Changed from 3000 to 10000
}
```

**Explanation**:
- `3000` = 3 seconds (too frequent, creates 20+ requests)
- `10000` = 10 seconds (optimal, creates 6-8 requests)
- This reduces network requests by 70% without affecting user experience

#### Step 2.2: Rebuild and Deploy Frontend

```bash
# Navigate to web directory
cd onyx-repo/web

# Build the frontend
npm run build
# Or if using Docker:
# docker build -t onyx-web:latest .

# Deploy (depends on your setup)
# For Kubernetes/OpenShift:
# kubectl set image deployment/web-server web-server=onyx-web:latest
# Or rebuild your container image and push to registry
```

**Expected Result**: 70% fewer network requests (20 → 6 requests for 60s processing)

**Full Optimization**: See `FRONTEND-POLLING-OPTIMIZATION.md`

---

## 📊 Combined Impact

### Before (Current State)

| Metric | Value |
|--------|-------|
| Processing Time | 60-120 seconds |
| Network Requests | 20-40 requests |
| Backend Load | High (frequent status checks) |
| User Experience | Poor (slow + many requests) |

### After (Optimized)

| Metric | Value | Improvement |
|--------|-------|-------------|
| Processing Time | 15-30 seconds | **4-8x faster** |
| Network Requests | 6-8 requests | **70-80% less** |
| Backend Load | Low (fewer status checks) | **Much better** |
| User Experience | Excellent | **Significantly improved** |

---

## 🚀 Implementation Order

### Step 1: Backend Quick Fix (5 minutes)

#### 1.1: Add Environment Variable to ConfigMap

**File**: `manifests/05-configmap.yaml` (or your ConfigMap file)

**Location**: In the `data:` section (around line 20-50)

**Add this line**:
```yaml
CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY: "8"
```

**Apply**:
```bash
oc apply -f manifests/05-configmap.yaml
# OR
oc edit configmap onyx-config
# (add the line in the data section, save and exit)
```

#### 1.2: Scale Workers

**File** (if using Helm): `deployment/helm/charts/onyx/values.yaml`

**Location**: `celery_worker_user_file_processing.replicaCount` (around line 621)

**Change**: `replicaCount: 1` → `replicaCount: 3`

**Or via command**:
```bash
oc scale deployment celery-worker-user-file-processing --replicas=3
```

#### 1.3: Restart Workers

```bash
oc rollout restart deployment celery-worker-user-file-processing
```

**Test**: Upload a file, measure processing time

### Step 2: Frontend Quick Fix (5 minutes)

#### 2.1: Modify Polling Interval

**File**: `onyx-repo/web/src/app/chat/projects/ProjectsContext.tsx`

**Location**: Line 666 (search for `setInterval(poll, 3000)`)

**Change**: `setInterval(poll, 3000)` → `setInterval(poll, 10000)`

**Exact change**:
```typescript
// Line 666 - BEFORE:
pollIntervalRef.current = window.setInterval(poll, 3000);

// Line 666 - AFTER:
pollIntervalRef.current = window.setInterval(poll, 10000);
```

#### 2.2: Rebuild Frontend

```bash
cd onyx-repo/web
npm run build
# Then deploy your updated frontend
```

**Test**: Upload a file, check Network tab - should see fewer requests

### Step 3: Backend Full Optimization (15 minutes)

#### 3.1: Add Embedding Batch Size

**File**: `manifests/05-configmap.yaml`

**Location**: In the `data:` section (add after the concurrency setting)

**Add this line**:
```yaml
EMBEDDING_BATCH_SIZE: "16"
```

**Apply**:
```bash
oc apply -f manifests/05-configmap.yaml
```

#### 3.2: Increase Worker Resources

**File** (if using Helm): `deployment/helm/charts/onyx/values.yaml`

**Location**: `celery_worker_user_file_processing.resources` (around line 642-648)

**Current**:
```yaml
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 2Gi
```

**Change To**:
```yaml
resources:
  requests:
    cpu: 2000m      # Changed from 500m
    memory: 2Gi     # Changed from 512Mi
  limits:
    cpu: 4000m      # Changed from 2000m
    memory: 4Gi     # Changed from 2Gi
```

**Or via command**:
```bash
oc set resources deployment celery-worker-user-file-processing \
  --requests=cpu=2000m,memory=2Gi \
  --limits=cpu=4000m,memory=4Gi
```

#### 3.3: Scale Model Server

**File** (if using Helm): `deployment/helm/charts/onyx/values.yaml`

**Location**: `indexing_model_server.replicaCount` (search for this section)

**Change**: `replicaCount: 1` → `replicaCount: 2`

**Or via command**:
```bash
oc scale deployment indexing-model-server --replicas=2
```

**Apply all changes**:
```bash
oc rollout restart deployment celery-worker-user-file-processing
oc rollout restart deployment indexing-model-server
```

See: `FILE-UPLOAD-PERFORMANCE-OPTIMIZATION.md` for more details

### Step 4: Frontend Advanced Optimization (15 minutes)
- Exponential backoff
- Smart stopping
- Tab visibility handling

See: `FRONTEND-POLLING-OPTIMIZATION.md`

---

## 📈 Expected Results Timeline

### After Backend Quick Fix
- ✅ Processing: 60s → 30s (2x faster)
- ⚠️ Network: Still 20 requests (no change)

### After Frontend Quick Fix
- ✅ Processing: Still 30s (no change)
- ✅ Network: 20 → 6 requests (70% less)

### After Full Optimization
- ✅ Processing: 30s → 15s (4x faster total)
- ✅ Network: 6 → 4 requests (80% less total)

---

## 🎓 Why Both Fixes Are Needed

### Backend Fix Alone
- ✅ Faster processing
- ❌ Still creates many requests (just faster)
- Result: Better, but not optimal

### Frontend Fix Alone
- ✅ Fewer requests
- ❌ Processing still slow
- Result: Better, but not optimal

### Both Fixes Together
- ✅ Faster processing
- ✅ Fewer requests
- ✅ Optimal user experience
- ✅ Lower backend load
- Result: **Best possible outcome**

---

## 🔧 Quick Reference

### Backend Configuration Files

#### ConfigMap File
**File**: `manifests/05-configmap.yaml`  
**Section**: `data:` (around line 20-50)  
**Variables to add**:
```yaml
CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY: "8"
EMBEDDING_BATCH_SIZE: "16"
```

#### Helm Values File (if using Helm)
**File**: `deployment/helm/charts/onyx/values.yaml`  
**Sections to modify**:
- `celery_worker_user_file_processing.replicaCount` (line ~621)
- `celery_worker_user_file_processing.resources` (line ~642-648)
- `indexing_model_server.replicaCount` (search for this section)

### Backend Commands
```bash
# Check current config
oc get configmap onyx-config -o yaml | grep CELERY_WORKER_USER_FILE

# Update config via command (alternative to editing file)
oc set env configmap/onyx-config CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY=8

# Scale workers
oc scale deployment celery-worker-user-file-processing --replicas=3

# Check status
oc get pods -l app=celery-worker-user-file-processing
```

### Frontend Code Location
**File**: `onyx-repo/web/src/app/chat/projects/ProjectsContext.tsx`  
**Line**: 666 (or search for `setInterval(poll, 3000)`)  
**Current**: `setInterval(poll, 3000)`  
**Change to**: `setInterval(poll, 10000)`

---

## 📚 Detailed Guides

1. **Backend Performance**: `FILE-UPLOAD-PERFORMANCE-OPTIMIZATION.md`
   - Complete backend optimization guide
   - Resource tuning
   - Scaling strategies

2. **Frontend Polling**: `FRONTEND-POLLING-OPTIMIZATION.md`
   - Polling optimization details
   - Exponential backoff implementation
   - Advanced techniques

3. **Quick Fix**: `QUICK-FIX-FILE-UPLOAD-SLOW.md`
   - 5-minute backend fix
   - One-liner commands

---

## ✅ Checklist

### Backend
- [ ] **ConfigMap** (`manifests/05-configmap.yaml`): Add `CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY: "8"`
- [ ] **ConfigMap** (`manifests/05-configmap.yaml`): Add `EMBEDDING_BATCH_SIZE: "16"`
- [ ] **Helm Values** (`values.yaml`) or **Command**: Scale workers to 3 replicas
- [ ] **Helm Values** (`values.yaml`) or **Command**: Increase resources (CPU: 2000m, Memory: 2Gi)
- [ ] **Helm Values** (`values.yaml`) or **Command**: Scale model server to 2 replicas

### Frontend
- [ ] Increase polling interval to 10 seconds
- [ ] (Optional) Implement exponential backoff
- [ ] (Optional) Add tab visibility handling
- [ ] Test and verify fewer requests

### Testing
- [ ] Upload test file
- [ ] Measure processing time (should be 15-30s)
- [ ] Check Network tab (should see 6-8 requests)
- [ ] Verify file completes successfully

---

## 🎯 Success Criteria

After implementing both fixes, you should see:

1. **Processing Time**: 15-30 seconds (down from 60-120s)
2. **Network Requests**: 6-8 requests (down from 20-40)
3. **Backend Load**: Lower CPU/memory usage
4. **User Experience**: Fast, responsive file uploads

---

## 💡 Pro Tips

1. **Start Small**: Apply quick fixes first, measure, then optimize further
2. **Monitor**: Watch logs and metrics after changes
3. **Iterate**: Fine-tune based on your specific workload
4. **Test**: Always test with real files after changes

---

## 🆘 Troubleshooting

### Still Slow After Backend Fix?
- Check worker CPU usage: `oc top pods -l app=celery-worker-user-file-processing`
- If CPU < 50%, increase concurrency more
- If CPU > 90%, add more replicas

### Still Many Requests After Frontend Fix?
- Verify code change was applied: Check line 666 in ProjectsContext.tsx
- Clear browser cache and rebuild frontend
- Check browser console for errors

### Files Not Completing?
- Check worker logs: `oc logs -f deployment/celery-worker-user-file-processing`
- Check model server: `oc logs -f deployment/indexing-model-server`
- Verify Redis queue is working

---

## 📝 Complete Variable Reference: Where to Modify Each Setting

This section provides **exact file locations** and **step-by-step instructions** for every variable mentioned in this guide.

---

### Backend Environment Variables (ConfigMap)

#### Variable 1: `CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY`

**Purpose**: Controls how many file processing tasks run in parallel per worker

**Default Value**: `2` (from code)

**Recommended Value**: `8` (for OpenShift)

**File to Modify**: `manifests/05-configmap.yaml`

**Exact Location**: In the `data:` section (around line 20-50, add anywhere in this section)

**How to Add**:

1. Open `manifests/05-configmap.yaml`
2. Find the `data:` section (starts around line 20)
3. Add this line anywhere in the `data:` section:
   ```yaml
   data:
     # ... existing variables ...
     
     # Celery Worker Configuration - File Upload Optimization
     CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY: "8"
   ```

**Complete Example**:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: onyx-config
data:
  POSTGRES_HOST: "postgresql.onyx-infra.svc.cluster.local"
  POSTGRES_PORT: "5432"
  # ... other existing variables ...
  
  # ============================================================================
  # CELERY WORKER CONFIGURATION - FILE UPLOAD OPTIMIZATION
  # ============================================================================
  # Controls how many file processing tasks run in parallel per worker
  # Default: 2, Recommended for OpenShift: 8
  CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY: "8"
```

**Apply Changes**:
```bash
oc apply -f manifests/05-configmap.yaml
```

**Alternative Method** (via command):
```bash
oc set env configmap/onyx-config CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY=8
```

**Code Reference**: `backend/onyx/configs/app_configs.py:400-402`
```python
CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY = int(
    os.environ.get("CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY") or 2
)
```

---

#### Variable 2: `EMBEDDING_BATCH_SIZE`

**Purpose**: Controls how many document chunks are sent to the model server in one batch

**Default Value**: `8` (from code)

**Recommended Value**: `16` (for OpenShift)

**File to Modify**: `manifests/05-configmap.yaml`

**Exact Location**: In the `data:` section (add after the concurrency setting)

**How to Add**:
```yaml
data:
  # ... existing variables ...
  CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY: "8"
  
  # Embedding batch size - reduces HTTP calls to model server
  # Default: 8, Recommended for OpenShift: 16
  EMBEDDING_BATCH_SIZE: "16"
```

**Apply Changes**:
```bash
oc apply -f manifests/05-configmap.yaml
```

**Alternative Method** (via command):
```bash
oc set env configmap/onyx-config EMBEDDING_BATCH_SIZE=16
```

**Code Reference**: `backend/onyx/configs/model_configs.py:44-46`
```python
EMBEDDING_BATCH_SIZE = int(os.environ.get("EMBEDDING_BATCH_SIZE") or 0) or None
BATCH_SIZE_ENCODE_CHUNKS = EMBEDDING_BATCH_SIZE or 8
```

---

### Backend Deployment Configuration (Helm Values or Deployment YAML)

#### Setting 1: Worker Replicas

**Purpose**: Number of worker pods running in parallel

**Default Value**: `1`

**Recommended Value**: `3`

**File to Modify** (if using Helm): `deployment/helm/charts/onyx/values.yaml`

**Exact Location**: Find `celery_worker_user_file_processing:` section (around line 620)

**How to Modify**:

1. Open `deployment/helm/charts/onyx/values.yaml`
2. Search for `celery_worker_user_file_processing:`
3. Find `replicaCount:` (should be around line 621)
4. Change the value:

**Current**:
```yaml
celery_worker_user_file_processing:
  replicaCount: 1  # ← Change this
  autoscaling:
    enabled: false
```

**Change To**:
```yaml
celery_worker_user_file_processing:
  replicaCount: 3  # ← Changed from 1 to 3
  autoscaling:
    enabled: false
```

**Apply Changes** (if using Helm):
```bash
helm upgrade onyx ./helm-chart -f values.yaml
```

**Alternative Method** (via command, if not using Helm):
```bash
oc scale deployment celery-worker-user-file-processing --replicas=3
```

**Or if using raw YAML**: Edit your deployment file and change `spec.replicas: 1` to `spec.replicas: 3`

---

#### Setting 2: Worker Resources (CPU/Memory)

**Purpose**: CPU and memory limits for worker pods

**Default Values**:
- CPU Request: `500m`
- CPU Limit: `2000m`
- Memory Request: `512Mi`
- Memory Limit: `2Gi`

**Recommended Values**:
- CPU Request: `2000m`
- CPU Limit: `4000m`
- Memory Request: `2Gi`
- Memory Limit: `4Gi`

**File to Modify** (if using Helm): `deployment/helm/charts/onyx/values.yaml`

**Exact Location**: `celery_worker_user_file_processing.resources` (around line 642-648)

**How to Modify**:

1. Open `deployment/helm/charts/onyx/values.yaml`
2. Find `celery_worker_user_file_processing:` section
3. Find `resources:` subsection (around line 642)
4. Modify the values:

**Current**:
```yaml
celery_worker_user_file_processing:
  replicaCount: 3
  resources:
    requests:
      cpu: 500m      # ← Change this
      memory: 512Mi  # ← Change this
    limits:
      cpu: 2000m     # ← Change this
      memory: 2Gi    # ← Change this
```

**Change To**:
```yaml
celery_worker_user_file_processing:
  replicaCount: 3
  resources:
    requests:
      cpu: 2000m     # ← Changed from 500m
      memory: 2Gi    # ← Changed from 512Mi
    limits:
      cpu: 4000m     # ← Changed from 2000m
      memory: 4Gi    # ← Changed from 2Gi
```

**Apply Changes** (if using Helm):
```bash
helm upgrade onyx ./helm-chart -f values.yaml
```

**Alternative Method** (via command):
```bash
oc set resources deployment celery-worker-user-file-processing \
  --requests=cpu=2000m,memory=2Gi \
  --limits=cpu=4000m,memory=4Gi
```

**Or if using raw YAML**: Edit your deployment file and modify the `resources:` section in the container spec

---

#### Setting 3: Indexing Model Server Replicas

**Purpose**: Number of model server pods for embedding generation

**Default Value**: `1`

**Recommended Value**: `2`

**File to Modify** (if using Helm): `deployment/helm/charts/onyx/values.yaml`

**Exact Location**: Search for `indexing_model_server:` section

**How to Modify**:

1. Open `deployment/helm/charts/onyx/values.yaml`
2. Search for `indexing_model_server:`
3. Find `replicaCount:` in that section
4. Change the value:

**Current**:
```yaml
indexing_model_server:
  replicaCount: 1  # ← Change this
```

**Change To**:
```yaml
indexing_model_server:
  replicaCount: 2  # ← Changed from 1 to 2
```

**Apply Changes** (if using Helm):
```bash
helm upgrade onyx ./helm-chart -f values.yaml
```

**Alternative Method** (via command):
```bash
oc scale deployment indexing-model-server --replicas=2
```

---

### Frontend Code Modification

#### Setting: Polling Interval

**Purpose**: How often the frontend checks file upload status

**Default Value**: `3000` milliseconds (3 seconds)

**Recommended Value**: `10000` milliseconds (10 seconds)

**File to Modify**: `onyx-repo/web/src/app/chat/projects/ProjectsContext.tsx`

**Exact Location**: Line 666 (or search for `setInterval(poll, 3000)`)

**How to Modify**:

1. Open `onyx-repo/web/src/app/chat/projects/ProjectsContext.tsx`
2. Search for `setInterval(poll, 3000)` (should be around line 666)
3. Change the value:

**Current** (around line 663-667):
```typescript
if (shouldPoll && pollIntervalRef.current === null) {
  // Kick once immediately, then start interval
  poll();
  pollIntervalRef.current = window.setInterval(poll, 3000); // ← Line 666: Change this
}
```

**Change To**:
```typescript
if (shouldPoll && pollIntervalRef.current === null) {
  // Kick once immediately, then start interval
  poll();
  pollIntervalRef.current = window.setInterval(poll, 10000); // ← Changed from 3000 to 10000
}
```

**Apply Changes**:
```bash
# Rebuild frontend
cd onyx-repo/web
npm run build

# Deploy (depends on your setup)
# For Kubernetes/OpenShift, update your container image
```

---

## 📋 Quick Modification Checklist

### ConfigMap Variables (`manifests/05-configmap.yaml`)

- [ ] **Line ~20-50**: Add `CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY: "8"`
- [ ] **Line ~20-50**: Add `EMBEDDING_BATCH_SIZE: "16"` (after concurrency setting)

### Helm Values (`deployment/helm/charts/onyx/values.yaml`)

- [ ] **Line ~621**: Change `celery_worker_user_file_processing.replicaCount: 1` → `3`
- [ ] **Line ~642-648**: Change `celery_worker_user_file_processing.resources`:
  - `requests.cpu: 500m` → `2000m`
  - `requests.memory: 512Mi` → `2Gi`
  - `limits.cpu: 2000m` → `4000m`
  - `limits.memory: 2Gi` → `4Gi`
- [ ] **Search for**: `indexing_model_server.replicaCount: 1` → `2`

### Frontend Code (`onyx-repo/web/src/app/chat/projects/ProjectsContext.tsx`)

- [ ] **Line 666**: Change `setInterval(poll, 3000)` → `setInterval(poll, 10000)`

---

## 📞 Summary

**The Problem**: Slow processing + endless requests

**The Solution**: 
1. Backend: More workers, more concurrency, more resources
2. Frontend: Longer polling interval, exponential backoff

**The Result**: 4-8x faster processing + 70-80% fewer requests = Excellent user experience!

**Time to Fix**: 10 minutes for quick fixes, 30 minutes for full optimization

**Impact**: Massive improvement in performance and user experience

**All File Locations**:
- ConfigMap: `manifests/05-configmap.yaml` (environment variables)
- Helm Values: `deployment/helm/charts/onyx/values.yaml` (deployment settings)
- Frontend: `onyx-repo/web/src/app/chat/projects/ProjectsContext.tsx` (polling interval)

