# Kubernetes Networking Complete Guide for Onyx Deployment

**Complete networking guide covering Kubernetes networking concepts, OpenShift Routes, Network Policies, and how to secure Onyx for company-only access**

---

## 📚 Table of Contents

1. [Kubernetes Networking Fundamentals](#kubernetes-networking-fundamentals)
2. [Services in Kubernetes](#services-in-kubernetes)
3. [OpenShift Routes](#openshift-routes)
4. [Network Policies](#network-policies)
5. [Onyx Architecture Networking](#onyx-architecture-networking)
6. [Company-Only Access Setup](#company-only-access-setup)
7. [Complete Deployment Guide](#complete-deployment-guide)
8. [Security Best Practices](#security-best-practices)

---

## 1. Kubernetes Networking Fundamentals

### 1.1 What is Kubernetes Networking?

Kubernetes networking allows:
- **Pods to communicate with each other** across nodes
- **Services to provide stable endpoints** for pods
- **External traffic to reach applications** inside the cluster
- **Network isolation** between different applications

### 1.2 Kubernetes Networking Model

```
┌─────────────────────────────────────────────────────────────────────┐
│                        KUBERNETES CLUSTER                            │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │                    CLUSTER NETWORK                          │    │
│  │              (All Pods can talk to each other)              │    │
│  │                                                              │    │
│  │  ┌──────────┐    ┌──────────┐    ┌──────────┐             │    │
│  │  │  Pod A   │    │  Pod B   │    │  Pod C   │             │    │
│  │  │ 10.1.0.2 │◄──►│ 10.1.0.3 │◄──►│ 10.1.0.4 │             │    │
│  │  └──────────┘    └──────────┘    └──────────┘             │    │
│  │       ▲               ▲               ▲                      │    │
│  │       │               │               │                      │    │
│  │       └───────────────┴───────────────┘                      │    │
│  │                       │                                       │    │
│  │                ┌──────▼───────┐                              │    │
│  │                │   SERVICE    │                              │    │
│  │                │  10.96.1.10  │                              │    │
│  │                │  (ClusterIP) │                              │    │
│  │                └──────┬───────┘                              │    │
│  └───────────────────────┼──────────────────────────────────────┘    │
│                          │                                            │
│                 ┌────────▼────────┐                                  │
│                 │   INGRESS/ROUTE │                                  │
│                 │  (External IP)  │                                  │
│                 └────────┬────────┘                                  │
└──────────────────────────┼───────────────────────────────────────────┘
                           │
                           ▼
                    ┌──────────────┐
                    │  EXTERNAL    │
                    │   USERS      │
                    └──────────────┘
```

### 1.3 Key Networking Components

#### A. Pod Network
- **What:** Every pod gets its own IP address
- **Range:** Typically `10.x.x.x` or `172.x.x.x`
- **Communication:** All pods can talk to each other by default
- **Example:** Pod `nginx-abc123` gets IP `10.1.0.5`

#### B. Service Network
- **What:** Stable virtual IPs for groups of pods
- **Range:** Typically `10.96.x.x` (different from pod network)
- **Purpose:** Load balancing and service discovery
- **Example:** Service `web-server` gets IP `10.96.1.100`

#### C. Cluster DNS
- **What:** Internal DNS server for service discovery
- **Format:** `<service-name>.<namespace>.svc.cluster.local`
- **Examples:**
  - Short name: `web-server` (same namespace)
  - Full name: `web-server.onyx-prod.svc.cluster.local`

### 1.4 How DNS Resolution Works

```
┌─────────────────────────────────────────────────────────────┐
│  Pod makes request: curl http://web-server:3000             │
│                                                              │
│  Step 1: DNS Lookup                                          │
│  ─────────────────────────────────────────────────────────  │
│  Pod → CoreDNS → Resolves "web-server" to 10.96.1.100      │
│                                                              │
│  Step 2: Service Routing                                     │
│  ─────────────────────────────────────────────────────────  │
│  Request to 10.96.1.100:3000                                │
│  Service (kube-proxy) → Load balances to Pod IPs            │
│  Options: 10.1.0.5, 10.1.0.6, 10.1.0.7 (3 pods)            │
│                                                              │
│  Step 3: Pod Communication                                   │
│  ─────────────────────────────────────────────────────────  │
│  Traffic routed to selected pod (e.g., 10.1.0.6)           │
│  Response flows back through same path                       │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Services in Kubernetes

### 2.1 What is a Service?

A **Service** is a stable network endpoint that:
- Has a **fixed IP address** (doesn't change)
- Has a **DNS name** (e.g., `web-server`)
- **Load balances** traffic to multiple pods
- **Automatically updates** when pods are added/removed

### 2.2 Why Do We Need Services?

**Problem without Services:**
```
Pod 1: 10.1.0.5 (running)
Pod 2: 10.1.0.6 (crashes and restarts)
Pod 2: 10.1.0.9 (new IP after restart!)

❌ Your application must track changing IPs
❌ Load balancing is manual
❌ DNS names don't work
```

**Solution with Services:**
```
Service: web-server (10.96.1.100)
  ├─ Pod 1: 10.1.0.5
  ├─ Pod 2: 10.1.0.6 (crashes)
  └─ Pod 2: 10.1.0.9 (restarted)

✅ Always use "web-server" or 10.96.1.100
✅ Service automatically routes to healthy pods
✅ DNS name never changes
```

### 2.3 Service Types

#### A. ClusterIP (Default)
```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-server
spec:
  type: ClusterIP  # Internal only
  ports:
    - port: 3000      # Service port
      targetPort: 3000 # Pod port
  selector:
    app: webserver    # Which pods to route to
```

**Characteristics:**
- ✅ **Internal only** - Not accessible from outside
- ✅ **Stable IP** - Fixed cluster IP address
- ✅ **DNS name** - `web-server` or `web-server.namespace.svc.cluster.local`
- ✅ **Load balancing** - Distributes traffic across pods
- ❌ **Not external** - Can't access from internet

**Use for:** Internal communication (API server, databases, etc.)

#### B. NodePort
```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-server
spec:
  type: NodePort
  ports:
    - port: 3000
      targetPort: 3000
      nodePort: 30080  # Port on each node (30000-32767)
  selector:
    app: webserver
```

**Characteristics:**
- ✅ **External access** - Accessible via `<NodeIP>:30080`
- ✅ **All nodes** - Port opened on every cluster node
- ⚠️ **High port range** - Must use ports 30000-32767
- ❌ **Not ideal for production** - Exposes random ports

**Use for:** Development, testing, or when no load balancer is available

#### C. LoadBalancer
```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-server
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 3000
  selector:
    app: webserver
```

**Characteristics:**
- ✅ **External IP** - Cloud provider assigns external IP
- ✅ **Standard ports** - Use port 80, 443, etc.
- ✅ **Load balanced** - Cloud provider handles load balancing
- ❌ **Cloud only** - Requires cloud provider (AWS, GCP, Azure)
- ❌ **Costs money** - Each LoadBalancer service creates a cloud load balancer

**Use for:** Production on cloud platforms (AWS ELB, GCP Load Balancer)

### 2.4 How Services Select Pods

Services use **label selectors** to find pods:

```yaml
# Deployment creates pods with labels
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webserver
spec:
  template:
    metadata:
      labels:
        app: webserver     # Pod label
        version: v1
    spec:
      containers:
        - name: web
          image: onyx-web-server

---
# Service selects pods by label
apiVersion: v1
kind: Service
metadata:
  name: web-server
spec:
  selector:
    app: webserver      # Must match pod label!
  ports:
    - port: 3000
```

**How it works:**
1. Service looks for pods with label `app=webserver`
2. Adds matching pod IPs to service endpoints
3. Routes traffic to these endpoints
4. Automatically updates when pods change

**Check service endpoints:**
```bash
oc get endpoints web-server

# Output shows pod IPs:
NAME          ENDPOINTS
web-server    10.1.0.5:3000,10.1.0.6:3000,10.1.0.7:3000
```

---

## 3. OpenShift Routes

### 3.1 What is a Route?

A **Route** is OpenShift's way to expose services to external traffic (similar to Kubernetes Ingress but simpler).

**Route = External URL → Service**

```
External User
      │
      │ https://onyx.company.com
      ▼
┌─────────────────┐
│  ROUTER POD     │  (HAProxy or similar)
│  (OpenShift)    │
└────────┬────────┘
         │
         │ Routes to service
         ▼
┌─────────────────┐
│   SERVICE       │
│   (nginx)       │
└────────┬────────┘
         │
         │ Load balances to pods
         ▼
┌─────────────────┐
│   NGINX PODS    │
└─────────────────┘
```

### 3.2 Route vs Service vs Ingress

| Component | Purpose | Scope | Example |
|-----------|---------|-------|---------|
| **Service** | Internal load balancer | Inside cluster | `web-server:3000` |
| **Route** (OpenShift) | External access | Outside cluster | `https://onyx.company.com` |
| **Ingress** (Kubernetes) | External access | Outside cluster | `https://onyx.company.com` |

**Key Differences:**
- **Service:** Always required for internal communication
- **Route:** OpenShift-specific, easier than Ingress
- **Ingress:** Standard Kubernetes, more complex

### 3.3 Creating a Route

#### Simple Route (HTTP)
```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: onyx-route
  namespace: onyx-prod
spec:
  to:
    kind: Service
    name: nginx           # Service name
    weight: 100
  port:
    targetPort: http      # Service port name or number
```

**Result:** OpenShift assigns URL like `http://onyx-route-onyx-prod.apps.cluster.example.com`

#### Route with Custom Hostname (HTTPS)
```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: onyx-route
  namespace: onyx-prod
spec:
  host: onyx.company.com     # Custom domain
  to:
    kind: Service
    name: nginx
    weight: 100
  port:
    targetPort: http
  tls:
    termination: edge        # SSL termination at router
    insecureEdgeTerminationPolicy: Redirect  # HTTP → HTTPS
```

**Result:** Accessible at `https://onyx.company.com`

#### Route with Path-Based Routing
```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: onyx-api-route
spec:
  host: onyx.company.com
  path: /api                 # Only /api/* requests
  to:
    kind: Service
    name: nginx
```

### 3.4 TLS/SSL Termination Options

#### Edge Termination (Recommended)
```yaml
spec:
  tls:
    termination: edge
    certificate: |
      -----BEGIN CERTIFICATE-----
      [your SSL certificate]
      -----END CERTIFICATE-----
    key: |
      -----BEGIN PRIVATE KEY-----
      [your private key]
      -----END PRIVATE KEY-----
    caCertificate: |
      -----BEGIN CERTIFICATE-----
      [CA certificate]
      -----END CERTIFICATE-----
```

**Flow:**
```
User (HTTPS) → Router (decrypts) → Service (HTTP) → Pods
```

**Pros:**
- ✅ SSL handled by router (less load on pods)
- ✅ Easy to manage certificates
- ✅ Standard for most applications

#### Passthrough Termination
```yaml
spec:
  tls:
    termination: passthrough
```

**Flow:**
```
User (HTTPS) → Router (forwards encrypted) → Service (HTTPS) → Pods (decrypt)
```

**Pros:**
- ✅ End-to-end encryption
- ✅ Pods handle SSL (more secure)

**Cons:**
- ❌ More complex
- ❌ Pods must handle SSL certificates

#### Re-encryption
```yaml
spec:
  tls:
    termination: reencrypt
    destinationCACertificate: |
      [backend CA certificate]
```

**Flow:**
```
User (HTTPS) → Router (decrypt + re-encrypt) → Service (HTTPS) → Pods
```

**Use for:** Maximum security (encrypted at every hop)

### 3.5 Route Commands

```bash
# Create route
oc create route edge onyx-route --service=nginx --hostname=onyx.company.com

# List routes
oc get routes

# Describe route
oc describe route onyx-route

# Get route URL
oc get route onyx-route -o jsonpath='{.spec.host}'

# Delete route
oc delete route onyx-route

# Expose service (auto-create route)
oc expose service nginx --hostname=onyx.company.com
```

---

## 4. Network Policies

### 4.1 What is a Network Policy?

A **Network Policy** is a firewall rule inside Kubernetes that controls:
- **Which pods can talk to each other**
- **Which pods can accept external traffic**
- **Which ports are allowed**

**Without Network Policy:**
```
ANY Pod → ANY Pod ✅ (All traffic allowed)
External → ANY Pod ✅ (No firewall)
```

**With Network Policy:**
```
Specific Pod → Specific Pod ✅ (Only allowed traffic)
Other Pod → Protected Pod ❌ (Blocked)
External → Protected Pod ❌ (Blocked unless explicitly allowed)
```

### 4.2 Why Use Network Policies?

**Security Benefits:**
1. **Principle of Least Privilege** - Only allow necessary communication
2. **Lateral Movement Prevention** - Attacker can't move between services
3. **Data Protection** - Prevent unauthorized access to databases
4. **Compliance** - Meet security requirements (PCI-DSS, HIPAA, etc.)

**Example Scenario:**
```
Without Network Policy:
┌──────────┐      ┌──────────┐      ┌──────────┐
│  NGINX   │─────►│API Server│─────►│PostgreSQL│
└──────────┘      └──────────┘      └──────────┘
     │                                    ▲
     │                                    │
     └────────────────────────────────────┘
     ❌ NGINX can directly access PostgreSQL (BAD!)

With Network Policy:
┌──────────┐      ┌──────────┐      ┌──────────┐
│  NGINX   │─────►│API Server│─────►│PostgreSQL│
└──────────┘      └──────────┘      └──────────┘
     │                                    ▲
     │                                    │
     └────────────────X───────────────────┘
     ✅ NGINX blocked from PostgreSQL (GOOD!)
```

### 4.3 Network Policy Concepts

#### A. Policy Types

1. **Ingress** - Controls incoming traffic to pods
2. **Egress** - Controls outgoing traffic from pods

#### B. Selectors

**Pod Selector:** Which pods does this policy apply to?
```yaml
podSelector:
  matchLabels:
    app: api-server
```

**Namespace Selector:** Allow traffic from specific namespaces
```yaml
namespaceSelector:
  matchLabels:
    environment: production
```

### 4.4 Network Policy Examples

#### Example 1: Default Deny All Traffic
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: onyx-prod
spec:
  podSelector: {}           # Empty = applies to ALL pods
  policyTypes:
    - Ingress
    - Egress
  # No ingress or egress rules = deny all
```

**Result:** All pods in namespace are isolated (no traffic in/out)

#### Example 2: Allow NGINX to API Server
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-nginx-to-api
  namespace: onyx-prod
spec:
  podSelector:
    matchLabels:
      app: api-server       # Applies to API server pods
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: nginx    # Allow from NGINX pods
      ports:
        - protocol: TCP
          port: 8080        # Only port 8080
```

**Result:** API server pods only accept traffic from NGINX on port 8080

#### Example 3: Allow API Server to Database
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-to-postgres
  namespace: onyx-prod
spec:
  podSelector:
    matchLabels:
      app: postgresql
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api-server
      ports:
        - protocol: TCP
          port: 5432
```

#### Example 4: Allow External Traffic to NGINX Only
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-external-to-nginx
  namespace: onyx-prod
spec:
  podSelector:
    matchLabels:
      app: nginx
  policyTypes:
    - Ingress
  ingress:
    - from: []              # Empty = allow from anywhere
      ports:
        - protocol: TCP
          port: 80
```

#### Example 5: Allow DNS Resolution (Important!)
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: onyx-prod
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: kube-system
      ports:
        - protocol: UDP
          port: 53          # DNS port
```

**Why needed:** Without this, pods can't resolve service names!

### 4.5 Complete Network Policy for Onyx

See section "5.4 Complete Network Policies" below for full implementation.

---

## 5. Onyx Architecture Networking

### 5.1 Onyx Component Communication Flow

Based on the architecture diagram, here's how Onyx components communicate:

```
External User
      │
      │ HTTPS (443)
      ▼
┌─────────────────┐
│  ROUTE/INGRESS  │  (OpenShift Route)
│  onyx.company   │
└────────┬────────┘
         │ HTTP (80)
         ▼
┌─────────────────┐
│     NGINX       │  (Reverse Proxy)
│   Service:      │
│   ClusterIP     │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌─────────┐ ┌──────────┐
│  Web    │ │   API    │
│ Server  │ │  Server  │
│  :3000  │ │  :8080   │
└────┬────┘ └────┬─────┘
     │           │
     │           ├────► PostgreSQL :5432
     │           ├────► Vespa :19071
     │           ├────► Redis :6379
     │           ├────► MinIO :9000
     │           └────► Model Server :9000
     │
     └─────────────────► API Server :8080
```

### 5.2 Service Definitions for All Onyx Components

#### 1. NGINX Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
  namespace: onyx-prod
  labels:
    app: nginx
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 80
      targetPort: 80
      protocol: TCP
  selector:
    app: nginx
```

#### 2. Web Server Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-server
  namespace: onyx-prod
  labels:
    app: webserver
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 3000
      targetPort: 3000
      protocol: TCP
  selector:
    io.kompose.service: webserver
```

#### 3. API Server Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: api-server
  namespace: onyx-prod
  labels:
    app: api-server
spec:
  type: ClusterIP
  ports:
    - name: api-server-port
      port: 8080
      targetPort: 8080
      protocol: TCP
  selector:
    app: api-server
```

#### 4. PostgreSQL Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: relational-db
  namespace: onyx-prod
  labels:
    app: postgresql
spec:
  type: ClusterIP
  ports:
    - name: postgres
      port: 5432
      targetPort: 5432
      protocol: TCP
  selector:
    app: postgresql
```

#### 5. Vespa Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: index
  namespace: onyx-prod
  labels:
    app: vespa
spec:
  type: ClusterIP
  ports:
    - name: config
      port: 19071
      targetPort: 19071
      protocol: TCP
    - name: query
      port: 8081
      targetPort: 8081
      protocol: TCP
  selector:
    app: vespa
```

#### 6. Redis Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: cache
  namespace: onyx-prod
  labels:
    app: redis
spec:
  type: ClusterIP
  ports:
    - name: redis
      port: 6379
      targetPort: 6379
      protocol: TCP
  selector:
    app: redis
```

#### 7. MinIO Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: onyx-prod
  labels:
    app: minio
spec:
  type: ClusterIP
  ports:
    - name: api
      port: 9000
      targetPort: 9000
      protocol: TCP
    - name: console
      port: 9001
      targetPort: 9001
      protocol: TCP
  selector:
    app: minio
```

#### 8. Inference Model Server Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: inference-model-server
  namespace: onyx-prod
  labels:
    app: inference-model-server
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 9000
      targetPort: 9000
      protocol: TCP
  selector:
    app: inference-model-server
```

#### 9. Indexing Model Server Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: indexing-model-server
  namespace: onyx-prod
  labels:
    app: indexing-model-server
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 9000
      targetPort: 9000
      protocol: TCP
  selector:
    app: indexing-model-server
```

### 5.3 DNS Names in Onyx

All services are accessible via DNS:

```bash
# Short names (same namespace)
web-server:3000
api-server:8080
relational-db:5432
cache:6379
index:19071
minio:9000
inference-model-server:9000
indexing-model-server:9000

# Full DNS names (any namespace)
web-server.onyx-prod.svc.cluster.local:3000
api-server.onyx-prod.svc.cluster.local:8080
relational-db.onyx-prod.svc.cluster.local:5432
```

### 5.4 Complete Network Policies for Onyx

#### All-in-One Network Policy File
```yaml
# ============================================================================
# ONYX NETWORK POLICIES - COMPLETE SECURITY SETUP
# ============================================================================
# This file contains all network policies for securing Onyx deployment
# Apply with: oc apply -f network-policies.yaml
# ============================================================================

---
# 1. Default Deny All (Baseline Security)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: onyx-prod
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress

---
# 2. Allow DNS Resolution (Required for all pods)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: onyx-prod
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: kube-system
      ports:
        - protocol: UDP
          port: 53

---
# 3. Allow External Traffic to NGINX Only
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-external-to-nginx
  namespace: onyx-prod
spec:
  podSelector:
    matchLabels:
      app: nginx
  policyTypes:
    - Ingress
  ingress:
    - ports:
        - protocol: TCP
          port: 80

---
# 4. Allow NGINX to Web Server
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-nginx-to-web-server
  namespace: onyx-prod
spec:
  podSelector:
    matchLabels:
      io.kompose.service: webserver
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: nginx
      ports:
        - protocol: TCP
          port: 3000

---
# 5. Allow NGINX to API Server
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-nginx-to-api-server
  namespace: onyx-prod
spec:
  podSelector:
    matchLabels:
      app: api-server
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: nginx
      ports:
        - protocol: TCP
          port: 8080

---
# 6. Allow Web Server to API Server
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-web-server-to-api-server
  namespace: onyx-prod
spec:
  podSelector:
    matchLabels:
      app: api-server
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              io.kompose.service: webserver
      ports:
        - protocol: TCP
          port: 8080

---
# 7. Allow API Server to PostgreSQL
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-to-postgres
  namespace: onyx-prod
spec:
  podSelector:
    matchLabels:
      app: postgresql
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api-server
      ports:
        - protocol: TCP
          port: 5432

---
# 8. Allow API Server to Vespa
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-to-vespa
  namespace: onyx-prod
spec:
  podSelector:
    matchLabels:
      app: vespa
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api-server
      ports:
        - protocol: TCP
          port: 19071
        - protocol: TCP
          port: 8081

---
# 9. Allow API Server to Redis
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-to-redis
  namespace: onyx-prod
spec:
  podSelector:
    matchLabels:
      app: redis
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api-server
      ports:
        - protocol: TCP
          port: 6379

---
# 10. Allow API Server to MinIO
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-to-minio
  namespace: onyx-prod
spec:
  podSelector:
    matchLabels:
      app: minio
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api-server
      ports:
        - protocol: TCP
          port: 9000

---
# 11. Allow API Server to Inference Model Server
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-to-inference-model
  namespace: onyx-prod
spec:
  podSelector:
    matchLabels:
      app: inference-model-server
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api-server
      ports:
        - protocol: TCP
          port: 9000

---
# 12. Allow Background Workers to All Backend Services
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-background-to-all
  namespace: onyx-prod
spec:
  podSelector:
    matchLabels:
      app: background
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: postgresql
      ports:
        - protocol: TCP
          port: 5432
    - to:
        - podSelector:
            matchLabels:
              app: vespa
      ports:
        - protocol: TCP
          port: 19071
    - to:
        - podSelector:
            matchLabels:
              app: redis
      ports:
        - protocol: TCP
          port: 6379
    - to:
        - podSelector:
            matchLabels:
              app: minio
      ports:
        - protocol: TCP
          port: 9000
    - to:
        - podSelector:
            matchLabels:
              app: indexing-model-server
      ports:
        - protocol: TCP
          port: 9000

---
# 13. Allow NGINX Egress to Web Server and API Server
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-nginx-egress
  namespace: onyx-prod
spec:
  podSelector:
    matchLabels:
      app: nginx
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              io.kompose.service: webserver
      ports:
        - protocol: TCP
          port: 3000
    - to:
        - podSelector:
            matchLabels:
              app: api-server
      ports:
        - protocol: TCP
          port: 8080

---
# 14. Allow Web Server Egress to API Server
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-web-server-egress
  namespace: onyx-prod
spec:
  podSelector:
    matchLabels:
      io.kompose.service: webserver
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: api-server
      ports:
        - protocol: TCP
          port: 8080

---
# 15. Allow API Server Egress to All Backend Services
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-egress
  namespace: onyx-prod
spec:
  podSelector:
    matchLabels:
      app: api-server
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: postgresql
      ports:
        - protocol: TCP
          port: 5432
    - to:
        - podSelector:
            matchLabels:
              app: vespa
      ports:
        - protocol: TCP
          port: 19071
        - protocol: TCP
          port: 8081
    - to:
        - podSelector:
            matchLabels:
              app: redis
      ports:
        - protocol: TCP
          port: 6379
    - to:
        - podSelector:
            matchLabels:
              app: minio
      ports:
        - protocol: TCP
          port: 9000
    - to:
        - podSelector:
            matchLabels:
              app: inference-model-server
      ports:
        - protocol: TCP
          port: 9000
```

---

## 6. Company-Only Access Setup

### 6.1 Access Control Options

To restrict Onyx access to company employees only, you have several options:

#### Option 1: Network-Level Restriction (Recommended)
Restrict access at the Route/Ingress level using IP whitelisting.

#### Option 2: VPN Requirement
Require employees to connect via company VPN.

#### Option 3: OAuth/SAML Authentication
Use company SSO (Single Sign-On) for authentication.

#### Option 4: Combination
Use multiple layers (IP whitelist + SSO + VPN).

### 6.2 IP Whitelisting with OpenShift Route

#### A. Whitelist Specific IP Ranges
```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: onyx-route
  namespace: onyx-prod
  annotations:
    # Allow only company IP ranges
    haproxy.router.openshift.io/ip_whitelist: "192.168.1.0/24 10.0.0.0/8"
spec:
  host: onyx.company.com
  to:
    kind: Service
    name: nginx
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
```

**What it does:**
- Only allows traffic from specified IP ranges
- `192.168.1.0/24` = Company office network
- `10.0.0.0/8` = Company VPN range
- All other IPs are blocked

#### B. Whitelist Multiple Locations
```yaml
metadata:
  annotations:
    # Headquarters: 203.0.113.0/24
    # Branch Office: 198.51.100.0/24
    # VPN Users: 10.0.0.0/8
    haproxy.router.openshift.io/ip_whitelist: "203.0.113.0/24 198.51.100.0/24 10.0.0.0/8"
```

### 6.3 Network Policy for Company Access

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-company-network-only
  namespace: onyx-prod
spec:
  podSelector:
    matchLabels:
      app: nginx
  policyTypes:
    - Ingress
  ingress:
    - from:
        # Option 1: Allow from specific IP blocks (requires CNI support)
        - ipBlock:
            cidr: 192.168.1.0/24      # Company office
        - ipBlock:
            cidr: 198.51.100.0/24     # Branch office
        - ipBlock:
            cidr: 10.0.0.0/8          # VPN
      ports:
        - protocol: TCP
          port: 80
```

**Note:** IP-based Network Policies require CNI plugins that support `ipBlock` (e.g., Calico, Cilium).

### 6.4 OAuth/SAML Integration

Configure Onyx to use company SSO:

#### In Onyx Settings (via UI):
1. Navigate to: Settings → Authentication
2. Choose authentication method:
   - **OAuth 2.0** (Google Workspace, Microsoft Azure AD)
   - **SAML 2.0** (Okta, OneLogin)
   - **LDAP** (Active Directory)

#### Example: Azure AD OAuth Configuration
```yaml
# In api-server deployment environment variables
env:
  - name: AUTH_TYPE
    value: "oauth"
  - name: OAUTH_CLIENT_ID
    value: "your-azure-app-id"
  - name: OAUTH_CLIENT_SECRET
    valueFrom:
      secretKeyRef:
        name: oauth-secret
        key: client-secret
  - name: OAUTH_AUTHORIZATION_ENDPOINT
    value: "https://login.microsoftonline.com/{tenant-id}/oauth2/v2.0/authorize"
  - name: OAUTH_TOKEN_ENDPOINT
    value: "https://login.microsoftonline.com/{tenant-id}/oauth2/v2.0/token"
```

### 6.5 VPN-Only Access

#### Network Diagram with VPN:
```
Employee (Home)
      │
      │ VPN Connection (encrypted)
      ▼
┌─────────────────┐
│  Company VPN    │
│  Gateway        │
│  10.0.0.1       │
└────────┬────────┘
         │
         │ Company network (10.0.0.0/8)
         ▼
┌─────────────────┐
│  OpenShift      │
│  Cluster        │
│                 │
│  ┌───────────┐  │
│  │   Onyx    │  │
│  │   Route   │  │
│  └───────────┘  │
└─────────────────┘
```

**Configuration:**
1. Route only accessible from VPN IP range: `10.0.0.0/8`
2. VPN required for all remote employees
3. Office network has direct access

### 6.6 Complete Company-Only Access Setup

#### Step 1: Create Secure Route with IP Whitelist
```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: onyx-secure-route
  namespace: onyx-prod
  annotations:
    # Company IP ranges
    haproxy.router.openshift.io/ip_whitelist: "192.168.1.0/24 10.0.0.0/8"
    # Rate limiting (optional)
    haproxy.router.openshift.io/rate-limit-connections: "100"
spec:
  host: onyx.company.com
  to:
    kind: Service
    name: nginx
    weight: 100
  port:
    targetPort: http
  tls:
    termination: edge
    certificate: |
      -----BEGIN CERTIFICATE-----
      [your company SSL certificate]
      -----END CERTIFICATE-----
    key: |
      -----BEGIN PRIVATE KEY-----
      [your private key]
      -----END PRIVATE KEY-----
    insecureEdgeTerminationPolicy: Redirect
```

#### Step 2: Apply Network Policies
```bash
oc apply -f network-policies.yaml
```

#### Step 3: Configure OAuth/SAML
```bash
# Set authentication environment variables
oc set env deployment/api-server \
  AUTH_TYPE=oauth \
  OAUTH_CLIENT_ID=your-client-id \
  REQUIRE_EMAIL_VERIFICATION=true
```

#### Step 4: Verify Access
```bash
# Test from allowed IP
curl https://onyx.company.com
# Should return: 200 OK

# Test from blocked IP
curl https://onyx.company.com
# Should return: 403 Forbidden
```

---

## 7. Complete Deployment Guide

### 7.1 Deployment Order

```
1. Create Namespace
2. Deploy Backend Services (PostgreSQL, Redis, Vespa, MinIO)
3. Deploy Model Servers
4. Deploy Application Services (API Server, Web Server)
5. Deploy NGINX
6. Create Services for All Components
7. Apply Network Policies
8. Create Route for External Access
```

### 7.2 Step-by-Step Commands

#### Step 1: Create Namespace
```bash
oc new-project onyx-prod
```

#### Step 2: Deploy Backend Services
```bash
# PostgreSQL
oc apply -f 01-postgresql.yaml

# Redis
oc apply -f 02-redis.yaml

# Vespa
oc apply -f 03-vespa.yaml

# MinIO
oc apply -f 04-minio.yaml
```

#### Step 3: Deploy Model Servers
```bash
oc apply -f 05-inference-model-server.yaml
oc apply -f 05-indexing-model-server.yaml
```

#### Step 4: Deploy Application Services
```bash
oc apply -f 06-api-server.yaml
oc apply -f 06-web-server.yaml
oc apply -f 06-background-workers.yaml
```

#### Step 5: Deploy NGINX
```bash
oc apply -f 09-nginx-simple.yaml
```

#### Step 6: Create All Services
```bash
# Create service files
oc apply -f 07-api-server-service.yaml
oc apply -f 08-web-server-service.yaml
oc apply -f services/
```

#### Step 7: Apply Network Policies
```bash
# Apply all network policies
oc apply -f network-policies.yaml

# Verify network policies
oc get networkpolicies
```

#### Step 8: Create Route
```bash
# Create route with IP whitelist
oc apply -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: onyx-route
  namespace: onyx-prod
  annotations:
    haproxy.router.openshift.io/ip_whitelist: "192.168.1.0/24 10.0.0.0/8"
spec:
  host: onyx.company.com
  to:
    kind: Service
    name: nginx
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF
```

#### Step 9: Verify Everything
```bash
# Check all pods
oc get pods

# Check all services
oc get services

# Check route
oc get route onyx-route

# Test access
curl https://onyx.company.com
```

### 7.3 Verification Checklist

```bash
# 1. Check pod status
oc get pods
# All pods should be Running

# 2. Check service endpoints
oc get endpoints
# All services should have endpoints listed

# 3. Test DNS resolution from NGINX
oc exec deployment/nginx -- nslookup web-server
oc exec deployment/nginx -- nslookup api-server

# 4. Test service connectivity
oc exec deployment/nginx -- curl http://web-server:3000
oc exec deployment/nginx -- curl http://api-server:8080/health

# 5. Check network policies
oc get networkpolicies
oc describe networkpolicy default-deny-all

# 6. Test route
curl https://onyx.company.com

# 7. Test from blocked IP (should fail)
curl https://onyx.company.com
# Expected: 403 Forbidden
```

---

## 8. Security Best Practices

### 8.1 Network Security Checklist

- [ ] **Default Deny Policy** - Block all traffic by default
- [ ] **Least Privilege** - Only allow necessary connections
- [ ] **IP Whitelisting** - Restrict to company networks
- [ ] **TLS/SSL** - Encrypt all external traffic
- [ ] **Strong Authentication** - Use OAuth/SAML
- [ ] **Regular Updates** - Keep all components updated
- [ ] **Monitoring** - Log all access attempts
- [ ] **Backup** - Regular backups of data

### 8.2 Network Policy Best Practices

1. **Start with Default Deny**
   ```yaml
   # Always start with this
   podSelector: {}
   policyTypes: [Ingress, Egress]
   ```

2. **Be Specific with Selectors**
   ```yaml
   # Good
   podSelector:
     matchLabels:
       app: api-server
       tier: backend
   
   # Avoid
   podSelector: {}  # Too broad
   ```

3. **Always Allow DNS**
   ```yaml
   # Required for service discovery
   - to:
       - namespaceSelector:
           matchLabels:
             name: kube-system
     ports:
       - protocol: UDP
         port: 53
   ```

4. **Test Before Deploying**
   ```bash
   # Test in dev/staging first
   oc apply -f network-policies.yaml -n onyx-dev
   # Verify application still works
   # Then deploy to production
   oc apply -f network-policies.yaml -n onyx-prod
   ```

### 8.3 Route Security Best Practices

1. **Always Use TLS/SSL**
   ```yaml
   tls:
     termination: edge
     insecureEdgeTerminationPolicy: Redirect  # Force HTTPS
   ```

2. **IP Whitelisting**
   ```yaml
   annotations:
     haproxy.router.openshift.io/ip_whitelist: "company-ip-ranges"
   ```

3. **Rate Limiting**
   ```yaml
   annotations:
     haproxy.router.openshift.io/rate-limit-connections: "100"
   ```

4. **Custom Domain**
   ```yaml
   spec:
     host: onyx.company.com  # Not auto-generated URL
   ```

### 8.4 Monitoring and Logging

#### Monitor Network Policies
```bash
# Check if network policies are applied
oc get networkpolicies

# Describe specific policy
oc describe networkpolicy default-deny-all

# Check for policy violations (requires audit logging)
oc logs -n openshift-network-operator <pod-name>
```

#### Monitor Route Access
```bash
# Check route traffic
oc get route onyx-route -o yaml

# View router logs
oc logs -n openshift-ingress <router-pod-name>

# Check for blocked IPs
oc logs -n openshift-ingress <router-pod-name> | grep "403"
```

---

## 9. Troubleshooting

### 9.1 Common Networking Issues

#### Issue 1: Service Not Accessible
```bash
# Check if service exists
oc get service web-server

# Check if service has endpoints
oc get endpoints web-server

# If no endpoints, check pod labels
oc get pods --show-labels
oc describe service web-server
```

#### Issue 2: Network Policy Blocking Traffic
```bash
# List all network policies
oc get networkpolicies

# Check if traffic is allowed
oc describe networkpolicy allow-nginx-to-api-server

# Temporarily remove policy for testing
oc delete networkpolicy default-deny-all
# Test connectivity
# Re-apply policy
oc apply -f network-policies.yaml
```

#### Issue 3: Route Not Working
```bash
# Check route status
oc get route onyx-route

# Check route details
oc describe route onyx-route

# Test from inside cluster
oc exec deployment/nginx -- curl http://nginx

# Check router logs
oc logs -n openshift-ingress -l app=router
```

#### Issue 4: DNS Resolution Fails
```bash
# Test DNS from pod
oc exec deployment/nginx -- nslookup web-server

# Check CoreDNS
oc get pods -n kube-system | grep dns

# Check if DNS network policy allows traffic
oc describe networkpolicy allow-dns
```

### 9.2 Debugging Commands

```bash
# 1. Check pod connectivity
oc exec deployment/nginx -- curl http://web-server:3000
oc exec deployment/nginx -- curl http://api-server:8080

# 2. Check DNS resolution
oc exec deployment/nginx -- nslookup web-server
oc exec deployment/nginx -- nslookup api-server

# 3. Check service endpoints
oc get endpoints

# 4. Check network policies
oc get networkpolicies
oc describe networkpolicy <policy-name>

# 5. Check route
oc get route
oc describe route onyx-route

# 6. Check pod labels
oc get pods --show-labels

# 7. Test from debug pod
oc run debug --image=busybox:1.35 --rm -it -- sh
# Then inside pod:
nslookup web-server
wget -O- http://web-server:3000
```

---

## 10. Summary

### Key Concepts Recap

| Concept | What It Is | When to Use |
|---------|-----------|-------------|
| **Service** | Stable network endpoint for pods | Always - for internal communication |
| **ClusterIP** | Internal-only service | Backend services (databases, APIs) |
| **NodePort** | Service on each node's IP | Testing, development |
| **LoadBalancer** | Cloud load balancer | Production on cloud |
| **Route** (OpenShift) | External access to services | Expose application to users |
| **Ingress** (K8s) | External access to services | Alternative to Route |
| **Network Policy** | Firewall rules for pods | Security, isolation |
| **DNS** | Service name resolution | Always - automatic |

### Onyx Networking Architecture

```
External (Company Network Only)
      │
      │ (IP Whitelisted)
      ▼
┌─────────────────┐
│  ROUTE (HTTPS)  │
│ onyx.company    │
└────────┬────────┘
         │ (TLS Termination)
         ▼
┌─────────────────┐
│  NGINX Service  │
│  (ClusterIP)    │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌─────────┐ ┌──────────┐
│  Web    │ │   API    │
│ Server  │ │  Server  │
│ Service │ │  Service │
└────┬────┘ └────┬─────┘
     │           │
     │           ├────► PostgreSQL Service
     │           ├────► Vespa Service
     │           ├────► Redis Service
     │           ├────► MinIO Service
     │           └────► Model Server Service
     │
     └─────────────────► API Server Service

All connections secured by Network Policies
```

### Quick Reference Commands

```bash
# Create service
oc expose deployment nginx --port=80 --target-port=80

# Create route
oc expose service nginx --hostname=onyx.company.com

# Apply network policy
oc apply -f network-policies.yaml

# Check service DNS
oc exec deployment/nginx -- nslookup web-server

# Test connectivity
oc exec deployment/nginx -- curl http://web-server:3000

# View route URL
oc get route onyx-route -o jsonpath='{.spec.host}'

# Check network policies
oc get networkpolicies
```

---

## 📝 Next Steps

1. **Review your company IP ranges** - Get IP ranges for offices and VPN
2. **Choose authentication method** - OAuth, SAML, or LDAP
3. **Prepare SSL certificate** - Get SSL cert for your domain
4. **Apply network policies** - Start with default deny, then allow necessary traffic
5. **Create secure route** - With IP whitelist and TLS
6. **Test access** - From allowed and blocked IPs
7. **Monitor and audit** - Set up logging and monitoring

---

**This guide provides everything you need to securely deploy Onyx with company-only access using Kubernetes/OpenShift networking!**
