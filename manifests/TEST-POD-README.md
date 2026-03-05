# Test Pod – S3 Connectivity (Vault-backed credentials)

Test pod for S3 connectivity. S3 config comes from ConfigMap; credentials come from **Vault** (not Kubernetes Secrets).

---

## Prerequisites

1. **Vault** with S3 credentials (this manifest uses **Vault Agent Injector**)
2. **Vault Agent Injector** installed in the cluster, or **External Secrets Operator** syncing Vault → K8s Secret (see alternative below)
3. **ConfigMap** with S3 config: `S3_ENDPOINT_URL`, `S3_FILE_STORE_BUCKET_NAME`, `AWS_REGION_NAME`

---

## Configure Vault annotations

Edit `manifests/test-pod.yaml` and set:

```yaml
vault.hashicorp.com/role: "your-vault-k8s-role"           # e.g. onyx-s3-test
vault.hashicorp.com/agent-inject-secret-s3: "secret/data/onyx/s3"  # your Vault path
vault.hashicorp.com/agent-inject-template-s3: |
  {{- with secret "secret/data/onyx/s3" -}}
  export S3_AWS_ACCESS_KEY_ID="{{ .Data.data.S3_AWS_ACCESS_KEY_ID | default .Data.data.access_key_id }}"
  export S3_AWS_SECRET_ACCESS_KEY="{{ .Data.data.S3_AWS_SECRET_ACCESS_KEY | default .Data.data.secret_access_key }}"
  {{- end -}}
```

Update the path in both `agent-inject-secret-s3` and the `with secret` line to match your Vault path (KV v2: `secret/data/...`, KV v1: `secret/...`).

---

## Deploy

```bash
export NS=onyx-infra

kubectl apply -f manifests/test-pod.yaml -n $NS

kubectl wait --for=condition=Ready pod/test-pod -n $NS --timeout=120s

kubectl exec -it test-pod -n $NS -- bash
```

---

## Commands to Test S3 Connectivity Inside the Pod

Run these **after** `kubectl exec -it test-pod -n $NS -- bash`.

### 1. Verify S3 environment variables

Check that endpoint, bucket, and (optionally) credential vars are set (credentials come from Vault; do not print secrets in logs).

```bash
# Show non-secret S3 config
env | grep -E 'S3_|AWS_' | grep -v SECRET

# Confirm credentials are present (no values)
[ -n "$S3_AWS_ACCESS_KEY_ID" ] && echo "S3_AWS_ACCESS_KEY_ID is set" || echo "S3_AWS_ACCESS_KEY_ID is NOT set"
[ -n "$S3_AWS_SECRET_ACCESS_KEY" ] && echo "S3_AWS_SECRET_ACCESS_KEY is set" || echo "S3_AWS_SECRET_ACCESS_KEY is NOT set"
```

---

### 2. Test raw connectivity to the S3 endpoint

Before using AWS CLI, confirm the pod can reach the S3 host (TCP + TLS).

```bash
# Replace with your endpoint if not using env (e.g. https://s3.example.com or https://minio.onyx-infra.svc.cluster.local:443)
curl -v -k --connect-timeout 10 "$S3_ENDPOINT_URL" 2>&1 | head -40
```

- **Connection refused / timeout** → network or firewall: check route, SecurityGroup, or service DNS.
- **SSL certificate problem** → use `-k` (insecure) only for testing, or fix CA/certs.

Optional: test only DNS and TCP (no HTTPS):

```bash
# Extract host and port from endpoint (e.g. https://my-s3.example.com:443 → my-s3.example.com 443)
# Example if S3_ENDPOINT_URL is https://minio.default.svc:9000:
nc -zv minio.default.svc 9000
```

---

### 3. List bucket (basic S3 API test)

Uses credentials and confirms the bucket exists and is readable.

```bash
aws s3 ls s3://$S3_FILE_STORE_BUCKET_NAME/ \
  --endpoint-url "$S3_ENDPOINT_URL" \
  --region "${AWS_REGION_NAME:-us-east-1}" \
  --no-verify-ssl
```

- **Success** → listing of keys (or empty). Connectivity and credentials are OK.
- **Access Denied (403)** → wrong credentials or bucket policy.
- **NoSuchBucket (404)** → wrong bucket name or endpoint.
- **Could not connect** → same as step 2 (network/DNS).

With path-style addressing (e.g. some MinIO setups):

```bash
aws s3 ls s3://$S3_FILE_STORE_BUCKET_NAME/ \
  --endpoint-url "$S3_ENDPOINT_URL" \
  --region "${AWS_REGION_NAME:-us-east-1}" \
  --no-verify-ssl \
  --endpoint-url-style path
```

---

### 4. Head bucket (stronger existence + permission check)

Confirms the bucket exists and your identity has `s3:ListBucket` (or equivalent).

```bash
aws s3api head-bucket \
  --bucket "$S3_FILE_STORE_BUCKET_NAME" \
  --endpoint-url "$S3_ENDPOINT_URL" \
  --region "${AWS_REGION_NAME:-us-east-1}" \
  --no-verify-ssl
```

No output = success. Non-zero exit or error message = bucket missing or permissions issue.

---

### 5. Upload and download a test object (full read/write test)

Proves both write and read to the bucket.

```bash
# Create a small test file
echo "test from test-pod $(date)" > /tmp/s3-test.txt

# Upload
aws s3 cp /tmp/s3-test.txt "s3://$S3_FILE_STORE_BUCKET_NAME/test-pod-connectivity-test.txt" \
  --endpoint-url "$S3_ENDPOINT_URL" \
  --region "${AWS_REGION_NAME:-us-east-1}" \
  --no-verify-ssl

# List again to see the new object
aws s3 ls s3://$S3_FILE_STORE_BUCKET_NAME/ --endpoint-url "$S3_ENDPOINT_URL" --region "${AWS_REGION_NAME:-us-east-1}" --no-verify-ssl

# Download to a different path
aws s3 cp "s3://$S3_FILE_STORE_BUCKET_NAME/test-pod-connectivity-test.txt" /tmp/s3-downloaded.txt \
  --endpoint-url "$S3_ENDPOINT_URL" \
  --region "${AWS_REGION_NAME:-us-east-1}" \
  --no-verify-ssl

# Verify content
cat /tmp/s3-downloaded.txt
```

If upload or download fails, check IAM/policy for `s3:PutObject` and `s3:GetObject`.

---

### 6. One-liner summary (all env vars from pod)

Use this when endpoint and bucket are set in the pod env (e.g. from ConfigMap + Vault):

```bash
aws s3 ls "s3://$S3_FILE_STORE_BUCKET_NAME/" --endpoint-url "$S3_ENDPOINT_URL" --region "${AWS_REGION_NAME:-us-east-1}" --no-verify-ssl && echo "S3 connectivity OK" || echo "S3 connectivity FAILED"
```

---

### 7. Manual credentials (no env vars)

If you are testing without env vars (e.g. from the **network test pod**), set credentials and endpoint in the shell:

```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export S3_ENDPOINT_URL="https://your-s3-endpoint:443"
export S3_FILE_STORE_BUCKET_NAME="your-bucket-name"

aws s3 ls "s3://$S3_FILE_STORE_BUCKET_NAME/" \
  --endpoint-url "$S3_ENDPOINT_URL" \
  --region "${AWS_REGION_NAME:-us-east-1}" \
  --no-verify-ssl
```

---

## If S3 Config Is Not in onyx-config

Add a ConfigMap with S3 settings, e.g.:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: s3-config
data:
  S3_ENDPOINT_URL: "https://your-s3-endpoint:443"
  S3_FILE_STORE_BUCKET_NAME: "onyx-file-store"
  AWS_REGION_NAME: "us-east-1"
  S3_ADDRESSING_STYLE: "virtual"
  S3_VERIFY_SSL: "false"
```

Then change `configMapKeyRef.name` in `test-pod.yaml` from `onyx-config` to `s3-config`.

---

## Alternative: External Secrets Operator (Vault → K8s Secret)

If you use ESO to sync Vault to a Kubernetes Secret, remove the Vault Agent annotations and add:

```yaml
env:
  - name: S3_AWS_ACCESS_KEY_ID
    valueFrom:
      secretKeyRef:
        name: onyx-s3-credentials   # your ESO-synced secret
        key: S3_AWS_ACCESS_KEY_ID
  - name: S3_AWS_SECRET_ACCESS_KEY
    valueFrom:
      secretKeyRef:
        name: onyx-s3-credentials
        key: S3_AWS_SECRET_ACCESS_KEY
```

---

## Cleanup

```bash
kubectl delete pod test-pod -n $NS
```
