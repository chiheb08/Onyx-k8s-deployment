# Quick Fix for Common Kubernetes Issues

**Fast solutions to get Onyx running when you have deployment issues.**

## 🐛 Issue Types

- **PVC Issues** - Storage problems
- **SCC Issues** - OpenShift security permissions (NEW!)

---

## 🚀 Option 1: Use emptyDir (Fastest - Testing Only)

**⚠️ WARNING:** All data lost when pod restarts! Use only for testing.

```bash
cd /Users/chihebmhamdi/Desktop/onyx/onyx-k8s-infrastructure

# Use testing version without PVC
kubectl apply -f 02-postgresql-emptydir.yaml

# Check if pod starts
kubectl get pods -l app=postgresql

# If running, continue with rest of deployment
./deploy.sh
```

**What this does:**
- Uses `emptyDir` instead of PVC
- No persistent storage needed
- PostgreSQL starts immediately
- **Data lost on pod restart!**

---

## 🔧 Option 2: Configure StorageClass (Production)

### Step 1: Find Your StorageClass

```bash
kubectl get storageclass

# OR OpenShift
oc get storageclass

# Example output:
# NAME                 PROVISIONER
# standard (default)   kubernetes.io/gce-pd
# gp2                  kubernetes.io/aws-ebs
# thin                 kubernetes.io/vsphere-volume
```

### Step 2: Update YAML Files

**Edit `02-postgresql.yaml`:**

```yaml
# Find this section (around line 30):
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  # storageClassName: ""  # CHANGE THIS LINE:
  storageClassName: "gp2"  # Replace with YOUR StorageClass name
```

**Edit `03-vespa.yaml`:**

```yaml
# Find volumeClaimTemplates section (around line 95):
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 30Gi
  # storageClassName: ""  # CHANGE THIS LINE:
  storageClassName: "gp2"  # Same StorageClass
```

### Step 3: Apply

```bash
# Apply PostgreSQL
kubectl apply -f 02-postgresql.yaml

# Wait for PVC to bind (30 seconds - 2 minutes)
kubectl get pvc -w

# Once STATUS shows "Bound", apply Vespa
kubectl apply -f 03-vespa.yaml

# Continue with deployment
./deploy.sh
```

---

## 📋 Which Option to Choose?

| Scenario | Use | Reason |
|----------|-----|--------|
| **Just testing Onyx** | Option 1 (emptyDir) | Fast, no config needed |
| **Development** | Option 2 (StorageClass) | Persistent, more realistic |
| **Production** | Option 2 (StorageClass) | Required for data safety |

---

## ✅ Verification

### After applying fix:

```bash
# Check PVC status
kubectl get pvc

# Should show:
# NAME             STATUS   VOLUME      CAPACITY   ACCESS MODES
# postgresql-pvc   Bound    pvc-xxx...  10Gi       RWO

# Check pod
kubectl get pods -l app=postgresql

# Should show:
# NAME                          READY   STATUS    RESTARTS   AGE
# postgresql-xxxxxxxxxx-xxxxx   1/1     Running   0          2m

# Test connection
kubectl exec -it deployment/postgresql -- psql -U postgres -c "SELECT 1"
# Should return: 1
```

---

## 🎯 Recommended Path

**For your OpenShift cluster:**

```bash
# 1. Check what storage is available
oc get storageclass

# 2. Pick one and update both files:
#    - 02-postgresql.yaml (line ~30)
#    - 03-vespa.yaml (line ~95)

# 3. Apply and verify
oc apply -f 02-postgresql.yaml
oc get pvc -w  # Wait for Bound

oc apply -f 03-vespa.yaml
oc get pvc -w  # Wait for Bound

# 4. Deploy rest
./deploy.sh
```

---

## 🔒 Issue 2: Security Context Constraint (SCC) Error

**Error:** `Forbidden: not usable by user or serviceaccount` for `hostmount-anyuid`, `privileged`, etc.

**This is OpenShift security blocking Vespa from using required permissions.**

### Quick Fix

```bash
# Grant anyuid SCC to default service account
oc adm policy add-scc-to-user anyuid -z default

# Restart Vespa
kubectl delete statefulset vespa
kubectl apply -f 03-vespa.yaml

# Check if working
kubectl get pods -l app=vespa
```

### If Still Failing

```bash
# Try more permissive SCC
oc adm policy add-scc-to-user hostmount-anyuid -z default

# Restart again
kubectl delete statefulset vespa
kubectl apply -f 03-vespa.yaml
```

---

**For detailed troubleshooting:**
- PVC issues: `TROUBLESHOOTING-PVC.md`
- SCC issues: `TROUBLESHOOTING-SCC.md`

