# Test Pod – Connectivity & Troubleshooting

All-in-one debug pod for testing Onyx services (S3, PostgreSQL, Redis, Vespa, API, DNS).

---

## Deploy

```bash
# Set your namespace (e.g. onyx-infra)
export NS=onyx-infra

# Deploy the test pod
kubectl apply -f manifests/test-pod.yaml -n $NS

# Wait until Running
kubectl wait --for=condition=Ready pod/test-pod -n $NS --timeout=60s

# Exec into the pod
kubectl exec -it test-pod -n $NS -- bash
```

---

## Commands to Run Inside the Pod

### DNS Resolution

```bash
# Resolve PostgreSQL
dig +short $POSTGRES_HOST

# Resolve Redis
dig +short $REDIS_HOST

# Resolve Vespa
dig +short $VESPA_HOST

# Resolve API Server (adjust namespace if not onyx-infra)
dig +short api-server.onyx-infra.svc.cluster.local

# Full DNS lookup
nslookup api-server.onyx-infra.svc.cluster.local
```

### PostgreSQL

```bash
# Test connection (PGPASSWORD from optional secret)
psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT 1"

# Or set password manually if not injected
export PGPASSWORD='your-password'
psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U postgres -d postgres -c "\conninfo"
```

### Redis

```bash
# Test connection (REDISCLI_AUTH from optional secret)
redis-cli -h $REDIS_HOST -p $REDIS_PORT ping

# If auth required and not injected
redis-cli -h $REDIS_HOST -p $REDIS_PORT -a 'your-password' ping
```

### Vespa

```bash
# Health check
curl -s "http://$VESPA_HOST:19071/state/v1/health" | jq .

# Query port reachability
curl -s -o /dev/null -w "%{http_code}" "http://$VESPA_HOST:8081/"
```

### API Server

```bash
# Health check
curl -s "http://api-server.onyx-infra.svc.cluster.local:8080/health" | jq .

# Or from env
curl -s "$INTERNAL_URL/health" | jq .
```

### S3 / MinIO

```bash
# List bucket (requires S3 env vars: S3_ENDPOINT_URL, S3_FILE_STORE_BUCKET_NAME, etc.)
aws s3 ls s3://$S3_FILE_STORE_BUCKET_NAME/ \
  --endpoint-url $S3_ENDPOINT_URL \
  --region ${AWS_REGION_NAME:-us-east-1}

# Test with path-style if needed
aws s3 ls s3://$S3_FILE_STORE_BUCKET_NAME/ \
  --endpoint-url $S3_ENDPOINT_URL \
  --region ${AWS_REGION_NAME:-us-east-1} \
  --no-verify-ssl

# Quick connectivity to S3 host (parse from endpoint)
curl -v -k --connect-timeout 5 "$S3_ENDPOINT_URL" 2>&1 | head -20
```

### Network / Port Checks

```bash
# Test port reachability
nc -zv $POSTGRES_HOST $POSTGRES_PORT
nc -zv $REDIS_HOST $REDIS_PORT
nc -zv $VESPA_HOST 19071
nc -zv api-server.onyx-infra.svc.cluster.local 8080

# Ping (may be blocked in some clusters)
ping -c 2 $POSTGRES_HOST
```

### General Utilities

```bash
# List available tools
which curl dig nslookup psql redis-cli aws jq python3 nc ping traceroute

# Check env vars (without secrets)
env | grep -E 'POSTGRES_|REDIS_|VESPA_|S3_|MODEL_SERVER|INTERNAL_URL' | sort
```

---

## Optional: Inject S3 / DB Credentials

If `onyx-config` or `postgresql-secret` / `redis-secret` are in another namespace, or you need S3:

1. Create a Secret with S3 credentials, or
2. Pass them when exec'ing:

```bash
kubectl exec -it test-pod -n $NS -- env \
  S3_AWS_ACCESS_KEY_ID=xxx \
  S3_AWS_SECRET_ACCESS_KEY=xxx \
  S3_ENDPOINT_URL=https://your-s3:443 \
  S3_FILE_STORE_BUCKET_NAME=your-bucket \
  bash -c 'aws s3 ls s3://$S3_FILE_STORE_BUCKET_NAME/ --endpoint-url $S3_ENDPOINT_URL'
```

---

## Cleanup

```bash
kubectl delete pod test-pod -n $NS
```
