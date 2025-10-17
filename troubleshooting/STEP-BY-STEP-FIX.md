# Step-by-Step Fix for NGINX Connection Timeout

**Problem:** NGINX initContainer getting connection timeout for web-server

**Root Cause:** The web-server and api-server services likely don't exist or don't have endpoints (no pods running)

---

## 🔍 Step 1: Check What's Currently Deployed

Run these commands to see what you have:

```bash
# Check your current namespace
oc project

# Check all services
oc get services

# Check all pods
oc get pods

# Check all deployments
oc get deployments
```

**Look for:**
- ✓ Is there a service named `web-server`?
- ✓ Is there a service named `api-server`?
- ✓ Are there pods running for webserver?
- ✓ Are there pods running for api-server?

---

## 🔧 Step 2: Deploy Missing Services

### Deploy web-server Service

```bash
oc apply -f 08-web-server-service.yaml
```

Verify it was created:
```bash
oc get service web-server
oc get endpoints web-server
```

### Deploy api-server Service

```bash
oc apply -f 07-api-server-service.yaml
```

Verify it was created:
```bash
oc get service api-server
oc get endpoints api-server
```

---

## 🔧 Step 3: Check Service Endpoints

**Important:** Services need pods to connect to!

```bash
# Check web-server endpoints
oc get endpoints web-server

# Check api-server endpoints
oc get endpoints api-server
```

**If endpoints show "none":**
- It means there are no pods matching the service selector
- You need to deploy the actual webserver and api-server deployments first

---

## 🔧 Step 4: Deploy NGINX with Correct Namespace

First, get your namespace:
```bash
oc project -q
```

Let's say your namespace is `my-namespace`. We need to update NGINX to use the correct namespace.

### Option A: Use Simple Short Names (Recommended)

Update the NGINX ConfigMap to use simple short names:

```bash
oc apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  default.conf: |
    upstream web_server {
        server web-server:3000;
    }

    upstream api_server {
        server api-server:8080;
    }

    server {
        listen 80;
        server_name _;

        location /api/ {
            proxy_pass http://api_server;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        location / {
            proxy_pass http://web_server;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        location /nginx-health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
EOF
```

### Deploy NGINX without initContainer (Simplified)

```bash
oc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.23.4-alpine
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 80
              protocol: TCP
          volumeMounts:
            - name: nginx-config
              mountPath: /etc/nginx/conf.d/default.conf
              subPath: default.conf
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
          livenessProbe:
            httpGet:
              path: /nginx-health
              port: 80
            initialDelaySeconds: 10
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /nginx-health
              port: 80
            initialDelaySeconds: 5
            periodSeconds: 5
      volumes:
        - name: nginx-config
          configMap:
            name: nginx-config
---
apiVersion: v1
kind: Service
metadata:
  name: nginx
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
EOF
```

---

## 🔧 Step 5: Verify Everything

```bash
# Check all services
oc get services

# Check all pods
oc get pods

# Check NGINX logs
oc logs deployment/nginx

# Test DNS resolution from NGINX pod
oc exec deployment/nginx -- nslookup web-server
oc exec deployment/nginx -- nslookup api-server
```

---

## ❓ What If Services Still Don't Have Endpoints?

If `oc get endpoints web-server` shows no endpoints, it means:

1. **No pods are running** that match the service selector
2. **You need to deploy the actual applications first**

### Check what labels your pods have:

```bash
# Find your webserver pods
oc get pods --show-labels | grep web

# Find your api-server pods  
oc get pods --show-labels | grep api
```

### Update the service selector to match your pods:

For example, if your pods have label `io.kompose.service=webserver`:

```bash
oc patch service web-server -p '{"spec":{"selector":{"io.kompose.service":"webserver"}}}'
```

---

## 🎯 Quick Checklist

Before NGINX can work, you MUST have:

- [ ] `web-server` service exists: `oc get service web-server`
- [ ] `api-server` service exists: `oc get service api-server`
- [ ] Webserver pods are running: `oc get pods -l io.kompose.service=webserver`
- [ ] API server pods are running: `oc get pods -l app=api-server`
- [ ] Services have endpoints: `oc get endpoints web-server api-server`
- [ ] DNS resolution works: `oc run test --image=busybox:1.35 --rm -it -- nslookup web-server`

---

## 🚨 Most Common Issue

**The most common problem is:** The services exist but have no endpoints because the actual application pods aren't running!

Check:
```bash
oc get pods
```

If you don't see pods for `webserver` or `api-server`, you need to deploy them first before deploying NGINX!

---

## 📝 Summary

1. Deploy services first (`08-web-server-service.yaml`, `07-api-server-service.yaml`)
2. Make sure your application pods are running
3. Verify services have endpoints
4. Then deploy NGINX (simplified version without initContainer)
5. Check NGINX logs

**The key is:** Services are just labels and port mappings. They need actual pods running to work!
