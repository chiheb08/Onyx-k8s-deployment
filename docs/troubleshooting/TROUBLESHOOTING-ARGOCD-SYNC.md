# Troubleshooting: ArgoCD Sync Issues

**Error:** `Resource not found in cluster: apps/v1/Deployment:redis` and similar for secrets

**Context:** You're using ArgoCD and it's showing resources that don't exist in the cluster yet.

---

## 🔍 Understanding ArgoCD Sync Issues

### What's Happening

ArgoCD is trying to sync your Git repository to the cluster, but:

1. **Resources don't exist yet** - The YAML files are in Git but not deployed
2. **ArgoCD is out of sync** - It expects resources to exist but they don't
3. **Sync is failing** - ArgoCD can't create the resources

### ArgoCD Status Meanings

| Status | Meaning | Action Needed |
|--------|---------|---------------|
| **OutOfSync** | Git has changes not in cluster | Sync needed |
| **Missing** | Resource exists in Git but not cluster | Deploy resource |
| **Unknown** | ArgoCD can't determine status | Check permissions |
| **Healthy** | Resource exists and matches Git | No action |

---

## 🔧 Solutions

### Solution 1: Sync ArgoCD Application

**The most common fix - sync your ArgoCD application:**

```bash
# Check ArgoCD applications
argocd app list

# Sync the application
argocd app sync your-app-name

# Or sync with force (if needed)
argocd app sync your-app-name --force

# Check sync status
argocd app get your-app-name
```

**In ArgoCD UI:**
1. Go to your application
2. Click **"SYNC"** button
3. Select **"SYNCHRONIZE"**
4. Watch the sync progress

---

### Solution 2: Check ArgoCD Application Configuration

**Verify your ArgoCD application is configured correctly:**

```bash
# Check application details
argocd app get your-app-name

# Check application manifest
argocd app manifests your-app-name

# Check application resources
argocd app resources your-app-name
```

**Common issues:**
- Wrong repository URL
- Wrong path in repository
- Wrong namespace
- Missing permissions

---

### Solution 3: Deploy Resources Manually First

**If ArgoCD sync keeps failing, deploy manually first:**

```bash
# Deploy resources manually
kubectl apply -f 02-postgresql.yaml
kubectl apply -f 03-vespa.yaml
kubectl apply -f 04-redis.yaml
kubectl apply -f 05-configmap.yaml

# Then sync ArgoCD
argocd app sync your-app-name
```

---

### Solution 4: Check ArgoCD Permissions

**ArgoCD might not have permissions to create resources:**

```bash
# Check ArgoCD service account
kubectl get serviceaccount -n argocd

# Check ArgoCD cluster role
kubectl get clusterrole argocd-server

# Check if ArgoCD can create deployments
kubectl auth can-i create deployments --as=system:serviceaccount:argocd:argocd-server
```

---

## 🔍 Diagnosis Commands

### Check ArgoCD Status

```bash
# List all ArgoCD applications
argocd app list

# Get detailed status of your app
argocd app get your-app-name

# Check application health
argocd app health your-app-name

# Check application sync status
argocd app sync-status your-app-name
```

### Check Cluster Resources

```bash
# Check if resources exist in cluster
kubectl get deployments
kubectl get secrets
kubectl get services
kubectl get pvc

# Check specific resources
kubectl get deployment redis
kubectl get secret redis-secret
```

### Check ArgoCD Logs

```bash
# Check ArgoCD server logs
kubectl logs -n argocd deployment/argocd-server

# Check ArgoCD application controller logs
kubectl logs -n argocd deployment/argocd-application-controller
```

---

## 🎯 Common ArgoCD Scenarios

### Scenario 1: First Time Sync

**Problem:** New ArgoCD application, resources don't exist yet.

**Solution:**
```bash
# Sync the application
argocd app sync your-app-name

# Or in UI: Click SYNC button
```

### Scenario 2: Resources Deleted

**Problem:** Resources were deleted from cluster but still in Git.

**Solution:**
```bash
# Force sync to recreate resources
argocd app sync your-app-name --force

# Or delete and recreate application
argocd app delete your-app-name
argocd app create your-app-name --repo https://github.com/your-repo --path . --dest-server https://kubernetes.default.svc --dest-namespace your-namespace
```

### Scenario 3: Permission Issues

**Problem:** ArgoCD can't create resources due to permissions.

**Solution:**
```bash
# Check ArgoCD permissions
kubectl auth can-i create deployments --as=system:serviceaccount:argocd:argocd-server

# Grant additional permissions if needed
kubectl create clusterrolebinding argocd-admin --clusterrole=cluster-admin --serviceaccount=argocd:argocd-server
```

### Scenario 4: Wrong Repository/Path

**Problem:** ArgoCD is looking in wrong repository or path.

**Solution:**
```bash
# Check application configuration
argocd app get your-app-name

# Update repository URL if needed
argocd app set your-app-name --repo https://github.com/your-repo

# Update path if needed
argocd app set your-app-name --path onyx-k8s-infrastructure
```

---

## 🚀 Quick Fix Workflow

```bash
# 1. Check ArgoCD application status
argocd app get your-app-name

# 2. If OutOfSync, sync it
argocd app sync your-app-name

# 3. Check if resources are created
kubectl get deployments
kubectl get secrets

# 4. If still missing, check ArgoCD logs
kubectl logs -n argocd deployment/argocd-server

# 5. If sync fails, deploy manually first
kubectl apply -f 04-redis.yaml
kubectl apply -f 02-postgresql.yaml
# ... etc

# 6. Then sync ArgoCD again
argocd app sync your-app-name
```

---

## 📊 ArgoCD Application Configuration

**Your ArgoCD application should be configured like:**

```yaml
# ArgoCD Application manifest
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: onyx-deployment
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/chiheb08/Onyx-k8s-deployment
    targetRevision: main
    path: onyx-k8s-infrastructure  # Path to your YAML files
  destination:
    server: https://kubernetes.default.svc
    namespace: your-namespace  # Your target namespace
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

---

## ⚠️ Troubleshooting Tips

### If Sync Keeps Failing

```bash
# Check ArgoCD application events
kubectl get events -n argocd

# Check application controller logs
kubectl logs -n argocd deployment/argocd-application-controller

# Check if ArgoCD can access your repository
argocd app get your-app-name
```

### If Resources Are Created But ArgoCD Shows Missing

```bash
# Refresh ArgoCD application
argocd app get your-app-name --refresh

# Hard refresh
argocd app sync your-app-name --force

# Check if resources have correct labels
kubectl get deployment redis --show-labels
```

### If ArgoCD Can't Access Repository

```bash
# Check repository access
argocd repo get https://github.com/chiheb08/Onyx-k8s-deployment

# Add repository if missing
argocd repo add https://github.com/chiheb08/Onyx-k8s-deployment

# Check repository credentials
argocd repo list
```

---

## 📝 Summary

**Root cause:** ArgoCD is trying to sync resources that don't exist in the cluster yet

**Quick fix:**
```bash
# Sync ArgoCD application
argocd app sync your-app-name

# Or in ArgoCD UI: Click SYNC button
```

**If sync fails:**
```bash
# Deploy manually first
kubectl apply -f 04-redis.yaml

# Then sync ArgoCD
argocd app sync your-app-name
```

**Verify:**
```bash
kubectl get deployments
kubectl get secrets
# Should show your resources
```

---

**This is a common ArgoCD sync issue - just sync the application and it will create the missing resources!**
