# S3 Storage Quick Fix Guide

## 🎯 Problem Summary

Using a different S3-compatible storage (not MinIO) in OpenShift causes file upload inconsistencies because Onyx's S3 client is **hardcoded for MinIO**.

---

## ⚡ Quick Fixes (No Code Changes Required)

### Fix 1: Disable Checksum (If Not Supported)

**File**: `manifests/05-configmap.yaml`

**Add to `data:` section**:
```yaml
data:
  # ... existing config ...
  
  # Disable checksum (may not be supported by your S3 service)
  S3_GENERATE_LOCAL_CHECKSUM: "false"
```

**Why**: Some S3-compatible services don't support `ChecksumSHA256` parameter.

---

### Fix 2: Configure SSL Verification

**File**: `manifests/05-configmap.yaml`

**Add to `data:` section**:
```yaml
data:
  # ... existing config ...
  
  # SSL Configuration
  # - "true": Verify SSL certificates (default)
  # - "false": Disable SSL verification (for self-signed certs)
  S3_VERIFY_SSL: "false"  # Change to "false" if using self-signed certificates
```

**Why**: OpenShift S3 services may use self-signed certificates.

---

### Fix 3: Verify S3 Endpoint URL

**File**: `manifests/05-configmap.yaml`

**Check**:
```yaml
data:
  # ... existing config ...
  
  # S3 Endpoint URL (for non-AWS S3 services)
  S3_ENDPOINT_URL: "http://your-s3-service:9000"  # ← Verify this is correct
  S3_AWS_ACCESS_KEY_ID: "your-access-key"
  S3_AWS_SECRET_ACCESS_KEY: "your-secret-key"
  S3_FILE_STORE_BUCKET_NAME: "your-bucket-name"
  AWS_REGION_NAME: "us-east-1"  # Can be any region for non-AWS services
```

**Why**: Incorrect endpoint URL causes connection failures.

---

## 🔍 Diagnostic Steps

### Step 1: Check Current Configuration

```bash
# View current S3 configuration
oc get configmap onyx-config -o yaml | grep -i s3
```

### Step 2: Test S3 Connection

```bash
# Test from API Server pod
oc exec -it deployment/api-server -- bash

# Inside pod, test S3 connection
python3 -c "
import boto3
from botocore.client import Config

client = boto3.client(
    's3',
    endpoint_url='http://your-s3-endpoint:9000',
    aws_access_key_id='your-key',
    aws_secret_access_key='your-secret',
    config=Config(
        signature_version='s3v4',
        s3={'addressing_style': 'path'}  # Try 'path' or 'virtual'
    )
)
print(client.list_buckets())
"
```

### Step 3: Check Logs for Errors

```bash
# Check API Server logs for S3 errors
oc logs deployment/api-server | grep -i "s3\|boto3\|timeout\|ssl"

# Check User File Processing Worker logs
oc logs deployment/celery-worker-user-file-processing | grep -i "s3\|boto3\|timeout"
```

---

## 🐛 Common Error Patterns

### Error 1: "Addressing style" or "404 Not Found"

**Symptom**: Files upload but cannot be retrieved

**Quick Fix**: Your S3 service may require `"virtual"` addressing style instead of `"path"`.

**Workaround**: This requires code changes (see main analysis document).

---

### Error 2: "SSL: CERTIFICATE_VERIFY_FAILED"

**Symptom**: Upload fails with SSL errors

**Quick Fix**: Set `S3_VERIFY_SSL: "false"` in ConfigMap.

---

### Error 3: "UnsupportedParameter" or "InvalidParameter"

**Symptom**: Upload fails with parameter errors

**Quick Fix**: Set `S3_GENERATE_LOCAL_CHECKSUM: "false"` in ConfigMap.

---

### Error 4: "ReadTimeout" or "ConnectTimeout"

**Symptom**: Large files fail to upload

**Quick Fix**: This requires code changes to increase timeout (see main analysis document).

---

## 📋 Configuration Checklist

Before deploying, verify:

- [ ] `S3_ENDPOINT_URL` is correct and accessible from pods
- [ ] `S3_AWS_ACCESS_KEY_ID` and `S3_AWS_SECRET_ACCESS_KEY` are correct
- [ ] `S3_FILE_STORE_BUCKET_NAME` exists and is accessible
- [ ] `S3_VERIFY_SSL` is set appropriately (false for self-signed certs)
- [ ] `S3_GENERATE_LOCAL_CHECKSUM` is set to "false" if checksums aren't supported
- [ ] Network connectivity from pods to S3 service is working
- [ ] Bucket has correct permissions (read, write, delete)

---

## 🚀 Apply Quick Fixes

```bash
# 1. Edit ConfigMap
oc edit configmap onyx-config

# 2. Add/update these values:
#    S3_GENERATE_LOCAL_CHECKSUM: "false"
#    S3_VERIFY_SSL: "false"  # If using self-signed certs

# 3. Restart services
oc rollout restart deployment/api-server
oc rollout restart deployment/celery-worker-user-file-processing

# 4. Verify
oc logs -f deployment/api-server | grep -i s3
```

---

## 📚 For Complete Solution

See `S3-STORAGE-INCONSISTENCIES-ANALYSIS.md` for:
- Detailed technical analysis
- Code-level fixes
- Addressing style configuration
- Timeout and retry configuration
- Full compatibility solution

---

## ⚠️ Important Notes

1. **Addressing Style**: The main issue is likely addressing style. Onyx hardcodes `"path"` for MinIO, but your S3 service may need `"virtual"` or `"auto"`. This requires code changes.

2. **Timeouts**: OpenShift network latency may cause timeouts. Default boto3 timeouts (60 seconds) may be too low.

3. **Testing**: Always test with small files first, then large files to identify timeout issues.

4. **Logs**: Check logs immediately after upload attempts to catch errors early.

