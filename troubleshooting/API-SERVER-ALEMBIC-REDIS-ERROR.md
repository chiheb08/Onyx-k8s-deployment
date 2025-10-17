# API Server Alembic & Redis Connection Error - Investigation & Fix

**Problem:** API server pod doesn't show "Starting Onyx Api Server" message and Alembic command fails with Redis connection error

---

## 🔍 Problem Analysis

### Observed Issues

1. **Pod doesn't show startup message**
   - The message "Starting Onyx Api Server" is not displayed
   - This means the command chain is failing before reaching the echo statement

2. **Alembic command fails**
   - When running `alembic upgrade head` manually in the pod
   - Error related to Redis connection/port

3. **Command chain in Helm chart:**
   ```yaml
   command:
     - "/bin/sh"
     - "-c"
     - |
       alembic upgrade head &&
       echo "Starting Onyx Api Server" &&
       uvicorn onyx.main:app --host 0.0.0.0 --port 8080
   ```

### Root Cause

The command uses `&&` which means:
- If `alembic upgrade head` **fails**, the subsequent commands don't run
- The echo statement and uvicorn never execute
- This is why you don't see the startup message

**Alembic requires database AND Redis connection** to run migrations:
- PostgreSQL: For running migrations
- Redis: For coordination/locking during migrations (multi-pod safety)

---

## 🔧 Investigation Steps

### Step 1: Check Pod Status
```bash
# Check if pod is running
oc get pods -l app=api-server

# Check pod logs
oc logs <api-server-pod-name>

# Check pod events
oc describe pod <api-server-pod-name>
```

### Step 2: Check Redis Connection
```bash
# Check if Redis service exists
oc get service cache

# Check if Redis service has endpoints
oc get endpoints cache

# Check if Redis pod is running
oc get pods -l app=redis
```

### Step 3: Check Environment Variables
```bash
# Check if Redis environment variables are set
oc exec <api-server-pod-name> -- env | grep REDIS

# Expected variables:
# REDIS_HOST=cache (or redis service name)
# REDIS_PORT=6379
# REDIS_DB=0
```

### Step 4: Test Redis Connection from API Server Pod
```bash
# Enter the pod
oc exec -it <api-server-pod-name> -- /bin/bash

# Test Redis connection with telnet
telnet cache 6379
# Or with nc
nc -zv cache 6379

# Test with redis-cli if available
redis-cli -h cache -p 6379 ping
```

### Step 5: Check Alembic Configuration
```bash
# Check alembic.ini
oc exec <api-server-pod-name> -- cat alembic.ini

# Check if sqlalchemy.url is configured
# Check if Redis is used in alembic/env.py
```

---

## 🛠️ Common Fixes

### Fix 1: Missing Redis Service

**Problem:** Redis service doesn't exist or has no endpoints

**Solution:**
```bash
# Deploy Redis service
oc apply -f manifests/04-redis.yaml

# Verify service exists
oc get service cache

# Verify service has endpoints (Redis pod running)
oc get endpoints cache
```

### Fix 2: Wrong Redis Service Name

**Problem:** Environment variable points to wrong service name

**Check current configuration:**
```bash
# Check what Redis host is configured
oc exec <api-server-pod-name> -- env | grep REDIS_HOST
```

**If wrong, update the ConfigMap or environment variables:**
```yaml
# In your ConfigMap or deployment
env:
  - name: REDIS_HOST
    value: "cache"  # Or whatever your Redis service is named
  - name: REDIS_PORT
    value: "6379"
```

### Fix 3: Redis Not Ready When API Server Starts

**Problem:** API server starts before Redis is ready

**Solution: Add initContainer to wait for Redis**

Update your API server deployment:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
spec:
  template:
    spec:
      initContainers:
        - name: wait-for-redis
          image: busybox:1.35
          command: ['sh', '-c']
          args:
            - |
              echo "Waiting for Redis..."
              until nc -zv cache 6379; do
                echo "Redis not ready, waiting..."
                sleep 2
              done
              echo "Redis is ready!"
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
      containers:
        - name: api-server
          # ... rest of your API server config
```

### Fix 4: Network Policy Blocking Redis

**Problem:** Network policy prevents API server from connecting to Redis

**Solution: Add network policy to allow API → Redis**
```yaml
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
```

### Fix 5: Change Command to Continue on Error (Not Recommended)

**Problem:** You want the API server to start even if Alembic fails

**Solution: Use || true or separate the command**

```yaml
# Option 1: Continue on error (not recommended for production)
command:
  - "/bin/sh"
  - "-c"
  - |
    alembic upgrade head || echo "Alembic failed, continuing anyway"
    echo "Starting Onyx Api Server"
    uvicorn onyx.main:app --host 0.0.0.0 --port 8080

# Option 2: Run Alembic in a separate init job (recommended)
# See Fix 6
```

### Fix 6: Run Alembic as a Separate Kubernetes Job (Recommended)

**Problem:** Mixing migrations with application startup causes issues

**Solution: Create a separate migration job**

Create `manifests/07-api-server-migration-job.yaml`:
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: api-server-migration
  namespace: onyx-prod
spec:
  template:
    spec:
      restartPolicy: OnFailure
      initContainers:
        - name: wait-for-dependencies
          image: busybox:1.35
          command: ['sh', '-c']
          args:
            - |
              echo "Waiting for PostgreSQL..."
              until nc -zv relational-db 5432; do
                echo "PostgreSQL not ready, waiting..."
                sleep 2
              done
              echo "PostgreSQL is ready!"
              
              echo "Waiting for Redis..."
              until nc -zv cache 6379; do
                echo "Redis not ready, waiting..."
                sleep 2
              done
              echo "Redis is ready!"
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
      containers:
        - name: alembic-migration
          image: onyxdotapp/onyx-backend:latest
          command:
            - "/bin/sh"
            - "-c"
            - |
              echo "Running Alembic migrations..."
              alembic upgrade head
              echo "Migrations completed successfully!"
          envFrom:
            - configMapRef:
                name: onyx-config
          env:
            - name: POSTGRES_HOST
              value: "relational-db"
            - name: POSTGRES_PORT
              value: "5432"
            - name: REDIS_HOST
              value: "cache"
            - name: REDIS_PORT
              value: "6379"
          resources:
            requests:
              cpu: 200m
              memory: 512Mi
            limits:
              cpu: 500m
              memory: 1Gi
```

**Then update API server deployment to remove Alembic:**
```yaml
# In manifests/07-api-server.yaml
containers:
  - name: api-server
    command:
      - "/bin/sh"
      - "-c"
      - |
        echo "Starting Onyx Api Server"
        uvicorn onyx.main:app --host 0.0.0.0 --port 8080
```

**Deployment order:**
```bash
# 1. Deploy infrastructure
oc apply -f manifests/02-postgresql.yaml
oc apply -f manifests/04-redis.yaml

# 2. Wait for them to be ready
oc wait --for=condition=ready pod -l app=postgresql --timeout=300s
oc wait --for=condition=ready pod -l app=redis --timeout=300s

# 3. Run migrations
oc apply -f manifests/07-api-server-migration-job.yaml
oc wait --for=condition=complete job/api-server-migration --timeout=300s

# 4. Deploy API server
oc apply -f manifests/07-api-server.yaml
```

---

## 🔍 Debugging Commands

### Check Current API Server Logs
```bash
# View logs
oc logs <api-server-pod-name>

# Follow logs in real-time
oc logs <api-server-pod-name> -f

# Get previous logs if pod crashed
oc logs <api-server-pod-name> --previous
```

### Test Alembic Manually
```bash
# Enter the pod
oc exec -it <api-server-pod-name> -- /bin/bash

# Check environment variables
env | grep -E "(POSTGRES|REDIS)"

# Test PostgreSQL connection
psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT 1;"

# Test Redis connection
redis-cli -h $REDIS_HOST -p $REDIS_PORT ping

# Run Alembic manually
alembic upgrade head

# Check Alembic current version
alembic current

# Check Alembic history
alembic history
```

### Check Redis from API Server Pod
```bash
# Test Redis connection
oc exec <api-server-pod-name> -- sh -c "nc -zv cache 6379"

# Test with Python (if redis-py is installed)
oc exec <api-server-pod-name> -- python -c "
import redis
r = redis.Redis(host='cache', port=6379, db=0)
print(r.ping())
"
```

### Check Network Connectivity
```bash
# Check if services can resolve DNS
oc exec <api-server-pod-name> -- nslookup cache
oc exec <api-server-pod-name> -- nslookup relational-db

# Check if ports are accessible
oc exec <api-server-pod-name> -- telnet cache 6379
oc exec <api-server-pod-name> -- telnet relational-db 5432
```

---

## ✅ Verification Steps

After applying fixes:

### 1. Check Services Are Running
```bash
oc get pods -l app=redis
oc get pods -l app=postgresql
oc get pods -l app=api-server
```

### 2. Check Service Endpoints
```bash
oc get endpoints cache
oc get endpoints relational-db
```

### 3. Check API Server Logs for Startup Message
```bash
oc logs <api-server-pod-name> | grep "Starting Onyx"
```

### 4. Test API Server Health
```bash
# Port forward to API server
oc port-forward service/api-server 8080:8080

# Test health endpoint
curl http://localhost:8080/health
```

---

## 📋 Quick Troubleshooting Checklist

- [ ] Redis pod is running: `oc get pods -l app=redis`
- [ ] Redis service exists: `oc get service cache`
- [ ] Redis service has endpoints: `oc get endpoints cache`
- [ ] PostgreSQL pod is running: `oc get pods -l app=postgresql`
- [ ] PostgreSQL service has endpoints: `oc get endpoints relational-db`
- [ ] API server can resolve Redis DNS: `oc exec <pod> -- nslookup cache`
- [ ] API server can connect to Redis: `oc exec <pod> -- nc -zv cache 6379`
- [ ] Environment variables are set correctly: `oc exec <pod> -- env | grep REDIS`
- [ ] Network policies allow API → Redis traffic
- [ ] Check API server logs for error details: `oc logs <pod>`

---

## 🎯 Recommended Solution

**For Production Deployments:**

1. **Separate migrations from application startup**
   - Use a Kubernetes Job for Alembic migrations
   - Deploy the Job before the API server Deployment
   - This ensures migrations run once, not on every pod restart

2. **Add initContainer to API server**
   - Wait for Redis and PostgreSQL to be ready
   - Prevents race conditions on startup

3. **Use proper environment variable configuration**
   - Ensure all Redis/PostgreSQL env vars are set
   - Use ConfigMaps for non-sensitive config
   - Use Secrets for sensitive data (passwords, etc.)

4. **Apply network policies**
   - Explicitly allow API server → Redis
   - Explicitly allow API server → PostgreSQL

---

## 📝 Example: Complete Fixed API Server Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
  namespace: onyx-prod
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api-server
  template:
    metadata:
      labels:
        app: api-server
    spec:
      initContainers:
        - name: wait-for-dependencies
          image: busybox:1.35
          command: ['sh', '-c']
          args:
            - |
              echo "Waiting for PostgreSQL..."
              until nc -zv relational-db 5432; do
                sleep 2
              done
              
              echo "Waiting for Redis..."
              until nc -zv cache 6379; do
                sleep 2
              done
              
              echo "All dependencies ready!"
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
      containers:
        - name: api-server
          image: onyxdotapp/onyx-backend:latest
          command:
            - "/bin/sh"
            - "-c"
            - |
              echo "Starting Onyx Api Server"
              uvicorn onyx.main:app --host 0.0.0.0 --port 8080
          ports:
            - name: api-server-port
              containerPort: 8080
          envFrom:
            - configMapRef:
                name: onyx-config
          env:
            - name: POSTGRES_HOST
              value: "relational-db"
            - name: POSTGRES_PORT
              value: "5432"
            - name: REDIS_HOST
              value: "cache"
            - name: REDIS_PORT
              value: "6379"
          resources:
            requests:
              cpu: 500m
              memory: 1Gi
            limits:
              cpu: 2000m
              memory: 2Gi
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
```

---

## 🔗 Related Documentation

- [API Server Deployment](../manifests/07-api-server.yaml)
- [Redis Deployment](../manifests/04-redis.yaml)
- [PostgreSQL Deployment](../manifests/02-postgresql.yaml)
- [Network Policies Guide](../documentation/KUBERNETES-NETWORKING-COMPLETE-GUIDE.md)
- [Step-by-Step Fix](STEP-BY-STEP-FIX.md)

---

**This guide should help you identify and fix the Alembic/Redis connection issue with the API server!**
