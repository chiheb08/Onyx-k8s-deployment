# Kubernetes DNS Naming - Complete Explanation

**For junior engineers: Understanding `web-server.onyx-infra.svc.cluster.local:3000`**

---

## 🎯 Quick Answer

**You DON'T need to change anything!** 

Our YAML files use **short names** (like `web-server:3000`) which automatically work with your namespace.

---

## 📚 Kubernetes DNS Format Explained

### Full DNS Format

```
<service-name>.<namespace>.svc.cluster.local:<port>

Example:
web-server.onyx-infra.svc.cluster.local:3000
│         │          │   │            │
│         │          │   │            └─ Port number
│         │          │   └─ Kubernetes domain (always same)
│         │          └─ "svc" means Service (always same)
│         └─ Namespace name (YOUR namespace)
└─ Service name
```

**Breaking it down:**

| Part | Value | What It Means | Can You Change? |
|------|-------|---------------|-----------------|
| `web-server` | Service name | The name of the Kubernetes Service | Yes (if you rename service) |
| `onyx-infra` | Namespace | Which namespace the service is in | **Automatic!** |
| `svc` | Service indicator | Indicates this is a Service | No (Kubernetes standard) |
| `cluster.local` | Cluster domain | Your cluster's domain name | No (default) |
| `:3000` | Port | Which port to connect to | Yes (if you change service port) |

---

## ✅ What We Did in Your YAML Files

### We Use SHORT Names (Namespace-Agnostic!)

**In 05-configmap.yaml:**
```yaml
data:
  POSTGRES_HOST: "postgresql"           # SHORT NAME ✅
  VESPA_HOST: "vespa-0.vespa-service"   # SHORT NAME ✅
  REDIS_HOST: "redis"                   # SHORT NAME ✅
```

**NOT:**
```yaml
data:
  POSTGRES_HOST: "postgresql.onyx-infra.svc.cluster.local"  # ❌ DON'T USE
```

**In 09-nginx.yaml (NGINX ConfigMap):**
```nginx
upstream web_server {
    server web-server:3000;        # SHORT NAME ✅
}

upstream api_server {
    server api-server:8080;        # SHORT NAME ✅
}
```

**NOT:**
```nginx
upstream web_server {
    server web-server.onyx-infra.svc.cluster.local:3000;  # ❌ DON'T USE
}
```

---

## 🔍 How Kubernetes DNS Resolution Works

### Scenario: API Server Connects to PostgreSQL

**Your OpenShift project:** `onyx-production`

```
Step 1: API Server reads environment variable
────────────────────────────────────────────────
POSTGRES_HOST=postgresql  # From ConfigMap

Step 2: Python code creates connection
────────────────────────────────────────────────
connection = f"postgresql://user:pass@{POSTGRES_HOST}:5432/db"
→ "postgresql://user:pass@postgresql:5432/db"

Step 3: Container tries to connect
────────────────────────────────────────────────
DNS lookup: "postgresql"

Step 4: Kubernetes DNS (CoreDNS) resolution
────────────────────────────────────────────────
CoreDNS: "Looking for 'postgresql' in current namespace..."
CoreDNS: "Current namespace is: onyx-production"
CoreDNS: "Searching for Service 'postgresql' in onyx-production"
CoreDNS: "Found! Service exists"
CoreDNS: "Full name: postgresql.onyx-production.svc.cluster.local"
CoreDNS: "Service ClusterIP: 10.96.15.23"
CoreDNS: "Returns: 10.96.15.23"

Step 5: Connection established
────────────────────────────────────────────────
api-server pod → 10.96.15.23:5432
                 │
                 └─→ postgresql service
                       │
                       └─→ postgresql pod
```

**Key point:** You said `postgresql`, Kubernetes automatically added your namespace!

---

## 🌐 DNS Resolution Examples

### Example 1: Same Namespace (What We Use)

```
Your namespace: onyx-production

Service name in YAML: web-server
Your code uses: http://web-server:3000

Kubernetes resolves:
  web-server 
  → web-server.onyx-production.svc.cluster.local
  → Service ClusterIP
  → Pod IP
  → Connection works! ✅
```

### Example 2: Different Namespace (Cross-Namespace)

```
Your namespace: onyx-production
Target service in: vllm-namespace

Must use full name: http://vllm-service.vllm-namespace:8001

Why? Kubernetes only searches current namespace for short names.

Kubernetes resolves:
  vllm-service.vllm-namespace
  → vllm-service.vllm-namespace.svc.cluster.local
  → Service in vllm-namespace
  → Connection works! ✅
```

### Example 3: What Happens with Wrong Namespace

```
Your namespace: onyx-production
Service actually in: onyx-production
You used: web-server.onyx-infra.svc.cluster.local

Kubernetes resolves:
  web-server.onyx-infra
  → Looks in namespace: onyx-infra
  → Service not found! (it's in onyx-production)
  → Error: Name resolution failed ❌
```

---

## 💡 Why Short Names Work (And Why We Use Them)

### The Magic of Kubernetes DNS

When a pod tries to resolve a short name (like `postgresql`), Kubernetes:

1. **Checks current namespace FIRST:**
   - Looks for Service named `postgresql` in same namespace
   - If found → Returns Service IP ✅
   - If not found → Goes to step 2

2. **Checks search domains:**
   - Tries: `postgresql.svc.cluster.local`
   - Tries: `postgresql.cluster.local`
   - If none found → Error

**This is why our short names work!**

---

## 🔧 What You Need to Do: NOTHING!

### You DON'T Need to Change

❌ **Don't change** `web-server` to `web-server.your-namespace`  
❌ **Don't edit** YAML files to add your namespace  
❌ **Don't replace** `onyx-infra` with your namespace  

### What Happens Automatically

✅ You deploy to namespace: `my-custom-namespace`  
✅ Service created: `web-server` in `my-custom-namespace`  
✅ Another pod in `my-custom-namespace` looks up: `web-server`  
✅ Kubernetes auto-resolves: `web-server.my-custom-namespace.svc.cluster.local`  
✅ Connection works!  

---

## 📋 Current Configuration in Your Files

### Check Your Files (Already Correct!)

**05-configmap.yaml:**
```yaml
data:
  POSTGRES_HOST: "postgresql"                    # ✅ Correct!
  VESPA_HOST: "vespa-0.vespa-service"           # ✅ Correct!
  REDIS_HOST: "redis"                           # ✅ Correct!
  MODEL_SERVER_HOST: "inference-model-server"   # ✅ Correct!
  INTERNAL_URL: "http://api-server:8080"        # ✅ Correct!
```

**09-nginx.yaml (in ConfigMap):**
```nginx
upstream web_server {
    server web-server:3000;        # ✅ Correct!
}

upstream api_server {
    server api-server:8080;        # ✅ Correct!
}
```

**All using SHORT names = Works with ANY namespace!**

---

## 🎓 When to Use Each Format

### Use SHORT name (service-name)

**When:** Connecting to service in **SAME namespace**

```yaml
# Example: API Server → PostgreSQL (both in same namespace)
POSTGRES_HOST: "postgresql"
```

**Why:** Simple, works anywhere, namespace-agnostic

---

### Use FULL name (service-name.namespace)

**When:** Connecting to service in **DIFFERENT namespace**

```yaml
# Example: API Server → vLLM in different namespace
VLLM_URL: "http://vllm-service.vllm-namespace:8001"
```

**Why:** Must specify namespace when crossing namespace boundaries

---

### Use FQDN (full DNS name)

**When:** Being explicit or for documentation

```yaml
# Example: Documentation or debugging
POSTGRES_HOST: "postgresql.my-namespace.svc.cluster.local"
```

**Why:** Shows complete DNS name, useful for troubleshooting

---

## 🧪 Testing DNS Resolution

### From Inside a Pod

```bash
# Get shell in api-server pod
kubectl exec -it deployment/api-server -- /bin/bash

# Test short name resolution
nslookup postgresql
# Output:
# Name: postgresql.your-namespace.svc.cluster.local
# Address: 10.96.15.23

# Test connection
curl http://postgresql:5432
# Works! ✅

# Test other services
nslookup web-server
nslookup redis
nslookup vespa-0.vespa-service
```

---

## 📊 Real Example from Your Deployment

### Your OpenShift Project: `onyx-test`

**When you deploy:**

```bash
# You run:
oc project onyx-test
./deploy.sh

# Services created:
postgresql (in namespace: onyx-test)
redis (in namespace: onyx-test)
api-server (in namespace: onyx-test)
etc.
```

**DNS resolution happens:**

```
API Server pod tries to connect to PostgreSQL:
1. Reads env: POSTGRES_HOST=postgresql
2. Connects to: postgresql:5432
3. DNS query: "postgresql"
4. CoreDNS: "Current namespace is onyx-test"
5. CoreDNS: "Found service 'postgresql' in onyx-test"
6. Returns: postgresql.onyx-test.svc.cluster.local → 10.96.1.5
7. Connection: api-server pod → 10.96.1.5:5432 → postgresql pod
8. Success! ✅
```

**NGINX tries to forward to Web Server:**

```
1. Config: upstream web_server { server web-server:3000; }
2. NGINX pod resolves: "web-server"
3. CoreDNS: "Current namespace is onyx-test"
4. CoreDNS: "Found service 'web-server' in onyx-test"
5. Returns: web-server.onyx-test.svc.cluster.local → 10.96.1.8
6. NGINX forwards: → 10.96.1.8:3000 → web-server pod
7. Success! ✅
```

---

## ⚠️ Common Mistakes to Avoid

### Mistake 1: Hardcoding Namespace

❌ **Wrong:**
```yaml
POSTGRES_HOST: "postgresql.onyx-infra.svc.cluster.local"
```

If you deploy to namespace `my-app`, this will fail because:
- It looks for `postgresql` in namespace `onyx-infra`
- But service is actually in namespace `my-app`

✅ **Correct:**
```yaml
POSTGRES_HOST: "postgresql"
```

This works in ANY namespace!

---

### Mistake 2: Forgetting Namespace for Cross-Namespace Access

❌ **Wrong:**
```yaml
# Trying to access vLLM in different namespace
VLLM_URL: "http://vllm-service:8001"
```

If vLLM is in namespace `ai-services`, this fails because:
- Kubernetes only searches current namespace for short names
- Doesn't find `vllm-service` in your namespace

✅ **Correct:**
```yaml
VLLM_URL: "http://vllm-service.ai-services:8001"
#                           └─ Namespace name
```

Or use FQDN:
```yaml
VLLM_URL: "http://vllm-service.ai-services.svc.cluster.local:8001"
```

---

## 🔧 What Happens in Documentation

### Why You See `onyx-infra` in Some Places

**In documentation/comments/examples**, you might see:

```
Example endpoint: postgresql.onyx-infra.svc.cluster.local
```

**This is just an EXAMPLE!** It shows:
- What the FULL DNS name looks like
- How Kubernetes DNS works
- The format/structure

**In actual YAML files**, we use:
```yaml
POSTGRES_HOST: "postgresql"  # No namespace!
```

Which becomes:
```
postgresql.YOUR-NAMESPACE.svc.cluster.local  # Automatic!
```

---

## 📝 Summary for Your Specific Case

### Your Situation:
- OpenShift namespace: `your-custom-namespace` (not `onyx-infra`)
- Deploying our YAML files

### What Happens:

```
1. You run:
   oc project your-custom-namespace
   ./deploy.sh

2. All services deploy to: your-custom-namespace

3. Service DNS names become:
   postgresql → postgresql.your-custom-namespace.svc.cluster.local
   redis → redis.your-custom-namespace.svc.cluster.local
   web-server → web-server.your-custom-namespace.svc.cluster.local

4. Our YAML files use short names:
   POSTGRES_HOST: "postgresql"
   
5. API Server container looks up "postgresql":
   → Kubernetes auto-adds: .your-custom-namespace.svc.cluster.local
   → Connects successfully! ✅

6. Everything works without any changes! ✅
```

---

## 🎓 Key Takeaways

1. **Short names** (like `postgresql`) automatically use current namespace
2. **Full names** (like `postgresql.namespace.svc.cluster.local`) are explicit
3. **Our YAML files use short names** = Work with any namespace
4. **You don't need to edit anything** = Deploy as-is
5. **Cross-namespace** access requires namespace in DNS name

---

## 🧪 How to Verify

After deployment:

```bash
# Get a shell in any pod
kubectl exec -it deployment/api-server -- /bin/bash

# Check DNS resolution
nslookup postgresql

# Output shows YOUR namespace:
# Name: postgresql.your-custom-namespace.svc.cluster.local
# Address: 10.96.x.x

# Test connection
curl http://postgresql:5432
# Works! ✅
```

---

## 💡 For Cross-Namespace vLLM Access

If your vLLM is in a different namespace:

**vLLM in namespace:** `ai-models`  
**Onyx in namespace:** `onyx-production`

**Configure in Onyx UI:**
```
API Base URL: http://vllm-service.ai-models:8001/v1
                                    └─ Namespace name
```

**Why:** Must specify namespace when crossing boundaries.

---

## 📋 Quick Reference

| Scenario | DNS Format | Example |
|----------|------------|---------|
| Same namespace | `service-name` | `postgresql` |
| Same namespace (explicit) | `service-name.namespace` | `postgresql.onyx-prod` |
| Different namespace | `service-name.namespace` | `vllm.ai-services` |
| Full DNS (any) | `service.namespace.svc.cluster.local` | `postgresql.onyx-prod.svc.cluster.local` |
| External (outside cluster) | IP or hostname | `external-api.company.com` |

---

## ✅ Conclusion

**Your YAML files are already configured correctly!**

- ✅ Use short names (namespace-agnostic)
- ✅ Work with any OpenShift project
- ✅ No changes needed
- ✅ Just deploy and it works!

**If you see `onyx-infra` in documentation, it's just an example!**

---

**Deploy to YOUR namespace, and DNS resolution happens automatically!** 🚀

