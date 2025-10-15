# Before Deploying - Important Setup

**Read this before running `deploy.sh`!**

---

## 🔧 Prerequisites for OpenShift

### 1. Create or Use Existing Namespace/Project

```bash
# In OpenShift, create a project (or use existing one)
oc new-project onyx-infra

# Or use existing project
oc project onyx-infra

# Verify you're in the correct namespace
oc project
```

### 2. Namespace Configuration

**✅ GOOD NEWS:** All YAML files have NO hardcoded namespace!

They will deploy to whatever namespace you're currently using.

**Make sure you're in the correct namespace/project:**

```bash
# Kubernetes
kubectl config set-context --current --namespace=your-namespace

# OR OpenShift
oc project your-namespace

# Verify current namespace
kubectl config view --minify | grep namespace:
# OR
oc project
```

**All resources will be created in your current namespace!**

### 3. Storage Configuration ✅

**Storage is pre-configured for your environment:**

- **Storage Class:** `nfs-example`
- **Volume Mode:** `Filesystem`
- **PostgreSQL:** 10Gi persistent storage
- **Vespa:** 30Gi persistent storage

**No changes needed** - the YAML files are already configured with your storage settings.

**If you need to verify your storage class exists:**
```bash
# Check available storage classes
kubectl get storageclass

# OR in OpenShift
oc get storageclass

# Should show: nfs-example
```

**For testing only:** Use `02-postgresql-emptydir.yaml` (no persistence, data lost on restart)

---

## 🚀 Ready to Deploy

Once namespace is set correctly:

```bash
./deploy.sh
```

---

## 💡 OpenShift Specific Notes

### Service Type

NGINX is set to `type: LoadBalancer`. In OpenShift:

**Option 1: Use Route (Recommended for OpenShift)**

Create a route after deployment:
```bash
oc expose svc/nginx -n onyx-infra
oc get route -n onyx-infra
```

**Option 2: Change to ClusterIP**

Edit `09-nginx.yaml`:
```yaml
type: ClusterIP  # Change from LoadBalancer
```

Then create route manually.

### Security Context Constraints

If you get permission errors:

```bash
# Grant anyuid SCC to default service account
oc adm policy add-scc-to-user anyuid -z default -n onyx-infra

# Or create a service account and grant privileges
```

### Image Pull

OpenShift can pull from Docker Hub by default, but if you have issues:

```bash
# Create pull secret (if needed)
oc create secret docker-registry dockerhub \
  --docker-server=docker.io \
  --docker-username=<username> \
  --docker-password=<password>

# Add to YAML files:
imagePullSecrets:
  - name: dockerhub
```

---

## ✅ Checklist Before Deployment

- [ ] Namespace/project created
- [ ] All YAML files have correct namespace
- [ ] Storage class configured (if needed)
- [ ] Sufficient resources available (6GB+ RAM)
- [ ] Security constraints reviewed (if OpenShift)

---

**Once ready, run: `./deploy.sh`**

