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

## Commands Inside the Pod

### Check S3 env vars (credentials from Vault)

```bash
env | grep -E 'S3_|AWS_' | grep -v SECRET
```

### List bucket

```bash
aws s3 ls s3://$S3_FILE_STORE_BUCKET_NAME/ \
  --endpoint-url $S3_ENDPOINT_URL \
  --region ${AWS_REGION_NAME:-us-east-1} \
  --no-verify-ssl
```

### Test endpoint connectivity

```bash
curl -v -k --connect-timeout 5 "$S3_ENDPOINT_URL" 2>&1 | head -30
```

### Head bucket (stronger connectivity test)

```bash
aws s3api head-bucket \
  --bucket $S3_FILE_STORE_BUCKET_NAME \
  --endpoint-url $S3_ENDPOINT_URL \
  --region ${AWS_REGION_NAME:-us-east-1} \
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
