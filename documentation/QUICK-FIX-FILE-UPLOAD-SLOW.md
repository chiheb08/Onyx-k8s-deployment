# Quick Fix: File Upload Processing Too Slow in OpenShift

## 🚀 5-Minute Quick Fix (2-3x Faster)

### Step 1: Increase Worker Concurrency (1 minute)

```bash
# Edit ConfigMap
oc edit configmap onyx-config

# Add or update this line:
CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY: "8"
```

**Or via YAML**:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: onyx-config
data:
  CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY: "8"
```

```bash
oc apply -f configmap.yaml
```

### Step 2: Scale Workers (1 minute)

```bash
# Scale to 3 replicas
oc scale deployment celery-worker-user-file-processing --replicas=3
```

### Step 3: Restart Workers (1 minute)

```bash
# Restart to pick up new config
oc rollout restart deployment celery-worker-user-file-processing
```

### Step 4: Verify (2 minutes)

```bash
# Check workers are running
oc get pods -l app=celery-worker-user-file-processing

# Check logs
oc logs -f deployment/celery-worker-user-file-processing | grep -i concurrency

# Should see: "concurrency: 8"
```

**Expected Result**: Files process 2-3x faster (60s → 20-30s)

---

## ⚡ 15-Minute Advanced Fix (4-8x Faster)

### Step 1: Update ConfigMap

```bash
oc edit configmap onyx-config
```

Add/update:
```yaml
CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY: "8"
EMBEDDING_BATCH_SIZE: "16"
```

### Step 2: Update Worker Resources

```bash
oc set resources deployment celery-worker-user-file-processing \
  --requests=cpu=2000m,memory=2Gi \
  --limits=cpu=4000m,memory=4Gi
```

### Step 3: Scale Workers

```bash
oc scale deployment celery-worker-user-file-processing --replicas=3
```

### Step 4: Scale Model Server (if separate)

```bash
oc scale deployment indexing-model-server --replicas=2
```

### Step 5: Restart Services

```bash
oc rollout restart deployment celery-worker-user-file-processing
oc rollout restart deployment indexing-model-server
```

**Expected Result**: Files process 4-8x faster (60s → 10-15s)

---

## 📊 Check Current Configuration

```bash
# Check worker concurrency
oc exec deployment/celery-worker-user-file-processing -- env | grep CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY

# Check replicas
oc get deployment celery-worker-user-file-processing -o jsonpath='{.spec.replicas}'

# Check resources
oc get deployment celery-worker-user-file-processing -o jsonpath='{.spec.template.spec.containers[0].resources}'

# Check queue length (if Redis monitoring available)
oc exec deployment/cache -- redis-cli LLEN celery
```

---

## 🔍 Troubleshooting

### Workers Not Picking Up New Config

```bash
# Force restart
oc delete pod -l app=celery-worker-user-file-processing

# Or
oc rollout restart deployment celery-worker-user-file-processing
```

### Still Slow After Changes

```bash
# Check if workers are actually using more CPU
oc top pods -l app=celery-worker-user-file-processing

# If CPU < 50%, increase concurrency more
# If CPU > 90%, reduce concurrency or add more replicas
```

### Model Server Bottleneck

```bash
# Check model server CPU
oc top pods -l app=indexing-model-server

# If > 90%, scale it:
oc scale deployment indexing-model-server --replicas=2
```

---

## 📝 Configuration Reference

### Current Defaults (Slow)
- Concurrency: 2
- Replicas: 1
- CPU: 500m / 2000m
- Memory: 512Mi / 2Gi

### Recommended (Fast)
- Concurrency: 8
- Replicas: 3
- CPU: 2000m / 4000m
- Memory: 2Gi / 4Gi

---

## 🎯 One-Liner Quick Fix

```bash
# Apply all quick fixes at once
oc set env configmap/onyx-config CELERY_WORKER_USER_FILE_PROCESSING_CONCURRENCY=8 && \
oc scale deployment celery-worker-user-file-processing --replicas=3 && \
oc set resources deployment celery-worker-user-file-processing --requests=cpu=2000m,memory=2Gi --limits=cpu=4000m,memory=4Gi && \
oc rollout restart deployment celery-worker-user-file-processing
```

**Wait 2-3 minutes for pods to restart, then test!**

