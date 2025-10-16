# Troubleshooting: Security Context Constraint (SCC) Issues

**Error:** `Forbidden: not usable by user or serviceaccount` for providers like `hostmount-anyuid`, `privileged`, `hostnetwork`

This is an **OpenShift-specific security issue** where your service account doesn't have permission to use certain security contexts.

---

## 🔍 Understanding the Error

### What Security Context Constraints (SCCs) Are

OpenShift uses SCCs to control what security privileges pods can have. Think of them as "permission levels" for containers.

**Common SCCs:**
- `restricted` - Most restrictive (default)
- `anyuid` - Can run as any user ID
- `hostmount-anyuid` - Can mount host directories
- `privileged` - Can do almost anything (dangerous!)
- `hostnetwork` - Can use host networking

### Why Vespa Needs Special Permissions

Vespa (vector search engine) often needs:
- **Host mounting** - To access storage efficiently
- **Any UID** - To run as specific user for file permissions
- **Privileged access** - For performance optimizations

---

## 🔧 Solutions

### Solution 1: Grant SCC to Service Account (Recommended)

**Step 1: Find the service account**

```bash
# Check what service account Vespa is using
kubectl get statefulset vespa -o yaml | grep serviceAccount

# OR check the pod
kubectl get pod vespa-0 -o yaml | grep serviceAccount
```

**Step 2: Grant SCC permission**

```bash
# Grant anyuid SCC to the service account
oc adm policy add-scc-to-user anyuid -z default

# OR if using a specific service account:
oc adm policy add-scc-to-user anyuid -z <service-account-name>

# For more permissive access (if needed):
oc adm policy add-scc-to-user hostmount-anyuid -z default
```

**Step 3: Restart Vespa**

```bash
# Delete the StatefulSet to recreate with new permissions
kubectl delete statefulset vespa

# Reapply
kubectl apply -f 03-vespa.yaml

# Check status
kubectl get pods -l app=vespa
```

---

### Solution 2: Modify Vespa YAML (Less Permissive)

**Edit `03-vespa.yaml` to use restricted security context:**

```yaml
# In the StatefulSet spec.template.spec section:
spec:
  template:
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      containers:
        - name: vespa
          securityContext:
            allowPrivilegeEscalation: false
            runAsNonRoot: true
            runAsUser: 1000
            capabilities:
              drop:
                - ALL
```

**Apply:**
```bash
kubectl apply -f 03-vespa.yaml
```

---

### Solution 3: Create Custom SCC (Advanced)

**Create a custom SCC for Vespa:**

```yaml
# Save as vespa-scc.yaml
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: vespa-scc
allowHostDirVolumePlugin: true
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegeEscalation: true
allowPrivilegedContainer: false
allowedCapabilities: null
defaultAddCapabilities: null
fsGroup:
  type: RunAsAny
readOnlyRootFilesystem: false
requiredDropCapabilities:
- KILL
- MKNOD
- SETUID
- SETGID
runAsUser:
  type: RunAsAny
seLinuxContext:
  type: MustRunAs
volumes:
- configMap
- downwardAPI
- emptyDir
- persistentVolumeClaim
- projected
- secret
```

**Apply and grant:**
```bash
kubectl apply -f vespa-scc.yaml
oc adm policy add-scc-to-user vespa-scc -z default
```

---

## 🎯 Quick Fix for Your Situation

**Based on your error, try this:**

```bash
# 1. Grant anyuid SCC (most common fix)
oc adm policy add-scc-to-user anyuid -z default

# 2. If that doesn't work, try hostmount-anyuid
oc adm policy add-scc-to-user hostmount-anyuid -z default

# 3. Restart Vespa
kubectl delete statefulset vespa
kubectl apply -f 03-vespa.yaml

# 4. Check if it works
kubectl get pods -l app=vespa
kubectl describe pod vespa-0
```

---

## 🔍 Diagnosis Commands

**Check current SCC permissions:**
```bash
# See what SCCs your service account can use
oc get scc
oc describe scc anyuid
oc describe scc hostmount-anyuid

# Check if service account has permissions
oc auth can-i use scc/anyuid --as=system:serviceaccount:$(oc project -q):default
```

**Check Vespa pod details:**
```bash
# See what's failing
kubectl describe pod vespa-0

# Check events
kubectl get events --sort-by=.metadata.creationTimestamp

# Check logs
kubectl logs vespa-0
```

---

## ⚠️ Security Considerations

### Production Recommendations

**Use least privilege:**
- Start with `anyuid` (minimal permissions)
- Only add `hostmount-anyuid` if needed
- **Never use `privileged`** unless absolutely necessary

**Alternative approaches:**
- Use non-root containers
- Mount volumes with proper permissions
- Use init containers for setup

### Testing vs Production

**For testing:**
```bash
# Quick fix - more permissive
oc adm policy add-scc-to-user hostmount-anyuid -z default
```

**For production:**
```bash
# More restrictive - create custom SCC
# Use Solution 3 above
```

---

## 📊 Common OpenShift SCCs

| SCC Name | Permissions | Use Case |
|----------|-------------|----------|
| `restricted` | Minimal | Default, most secure |
| `anyuid` | Run as any user | Most applications |
| `hostmount-anyuid` | Mount host + any user | Storage-heavy apps |
| `privileged` | Full access | System components only |
| `hostnetwork` | Use host networking | Network tools |

---

## 🎯 Troubleshooting Workflow

```bash
# 1. Check the error
kubectl describe pod vespa-0
# Look for "Forbidden" or "SCC" in events

# 2. Check current permissions
oc get scc
oc auth can-i use scc/anyuid --as=system:serviceaccount:$(oc project -q):default

# 3. Grant minimal permissions
oc adm policy add-scc-to-user anyuid -z default

# 4. Test
kubectl delete statefulset vespa
kubectl apply -f 03-vespa.yaml

# 5. If still failing, try more permissive
oc adm policy add-scc-to-user hostmount-anyuid -z default

# 6. Verify
kubectl get pods -l app=vespa
kubectl logs vespa-0
```

---

## 📝 Summary

**Root cause:** OpenShift security policy blocking Vespa from using required privileges

**Quick fix:**
```bash
oc adm policy add-scc-to-user anyuid -z default
kubectl delete statefulset vespa
kubectl apply -f 03-vespa.yaml
```

**Verify:**
```bash
kubectl get pods -l app=vespa
# Should show: Running ✅
```

---

**This is different from the PVC issue - this is about OpenShift security permissions!**
