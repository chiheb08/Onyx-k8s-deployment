# Complete Setup: S3 Virtual Addressing Style Configuration

## 🎯 For AWS S3-Compatible Internal Storage

This guide provides **exact code changes** and **configuration** for using virtual addressing style.

---

## Step 1: Update `app_configs.py`

**File**: `onyx-repo/backend/onyx/configs/app_configs.py`

**Location**: After line 914 (after `S3_AWS_SECRET_ACCESS_KEY`)

**Find this code** (around lines 912-919):
```python
# S3/MinIO Access Keys
S3_AWS_ACCESS_KEY_ID = os.environ.get("S3_AWS_ACCESS_KEY_ID")
S3_AWS_SECRET_ACCESS_KEY = os.environ.get("S3_AWS_SECRET_ACCESS_KEY")

# Should we force S3 local checksumming
S3_GENERATE_LOCAL_CHECKSUM = (
    os.environ.get("S3_GENERATE_LOCAL_CHECKSUM", "").lower() == "true"
)
```

**Replace with**:
```python
# S3/MinIO Access Keys
S3_AWS_ACCESS_KEY_ID = os.environ.get("S3_AWS_ACCESS_KEY_ID")
S3_AWS_SECRET_ACCESS_KEY = os.environ.get("S3_AWS_SECRET_ACCESS_KEY")

# S3 Addressing Style Configuration
# - "path": Path-style addressing (http://endpoint/bucket/key) - For MinIO
# - "virtual": Virtual-hosted style (http://bucket.endpoint/key) - For AWS S3
# - "auto": Let boto3 decide automatically (default, falls back to "path")
S3_ADDRESSING_STYLE = os.environ.get("S3_ADDRESSING_STYLE", "auto")

# S3 Timeout Configuration (for OpenShift network latency)
# Connect timeout in seconds (default: 60)
S3_CONNECT_TIMEOUT = int(os.environ.get("S3_CONNECT_TIMEOUT", "60"))
# Read timeout in seconds (default: 60, increase for large files)
S3_READ_TIMEOUT = int(os.environ.get("S3_READ_TIMEOUT", "60"))

# S3 SSL CA Certificate Path (optional, for custom CA certificates)
S3_CA_CERT_PATH = os.environ.get("S3_CA_CERT_PATH")

# Should we force S3 local checksumming
S3_GENERATE_LOCAL_CHECKSUM = (
    os.environ.get("S3_GENERATE_LOCAL_CHECKSUM", "").lower() == "true"
)
```

---

## Step 2: Update `file_store.py`

**File**: `onyx-repo/backend/onyx/file_store/file_store.py`

**Location**: Lines 193-207 (inside `_get_s3_client` method)

**Find this code**:
```python
# Add endpoint URL if specified (for MinIO, etc.)
if self._s3_endpoint_url:
    client_kwargs["endpoint_url"] = self._s3_endpoint_url
    client_kwargs["config"] = Config(
        signature_version="s3v4",
        s3={"addressing_style": "path"},  # Required for MinIO
    )
    # Disable SSL verification if requested (for local development)
    if not self._s3_verify_ssl:
        import urllib3

        urllib3.disable_warnings(
            urllib3.exceptions.InsecureRequestWarning
        )
        client_kwargs["verify"] = False
```

**Replace with**:
```python
# Add endpoint URL if specified (for MinIO, etc.)
if self._s3_endpoint_url:
    from onyx.configs.app_configs import (
        S3_ADDRESSING_STYLE,
        S3_CONNECT_TIMEOUT,
        S3_READ_TIMEOUT,
        S3_CA_CERT_PATH,
    )
    
    # Determine addressing style
    # If "auto", default to "path" for backward compatibility with MinIO
    addressing_style = (
        S3_ADDRESSING_STYLE if S3_ADDRESSING_STYLE != "auto" else "path"
    )
    
    client_kwargs["endpoint_url"] = self._s3_endpoint_url
    client_kwargs["config"] = Config(
        signature_version="s3v4",
        s3={"addressing_style": addressing_style},
        connect_timeout=S3_CONNECT_TIMEOUT,
        read_timeout=S3_READ_TIMEOUT,
        retries={
            "max_attempts": 5,
            "mode": "adaptive",
        },
    )
    
    # SSL verification configuration
    if not self._s3_verify_ssl:
        import urllib3

        urllib3.disable_warnings(
            urllib3.exceptions.InsecureRequestWarning
        )
        client_kwargs["verify"] = False
    elif S3_CA_CERT_PATH:
        # Use custom CA certificate
        client_kwargs["verify"] = S3_CA_CERT_PATH
    else:
        # Use default system CA certificates
        client_kwargs["verify"] = True
```

---

## Step 3: Update ConfigMap

**File**: `onyx-k8s-infrastructure/manifests/05-configmap.yaml`

**Add to the `data:` section** (add after your existing S3 configuration):

```yaml
data:
  # ... your existing configuration ...
  
  # ============================================================================
  # S3 STORAGE CONFIGURATION (for AWS S3-compatible internal storage)
  # ============================================================================
  
  # S3 Addressing Style
  # - "virtual": Virtual-hosted style (http://bucket.endpoint/key) - For AWS S3
  # - "path": Path-style (http://endpoint/bucket/key) - For MinIO
  # - "auto": Let boto3 decide (default, falls back to "path")
  S3_ADDRESSING_STYLE: "virtual"  # ← Set to "virtual" for AWS S3-compatible
  
  # S3 Timeout Configuration (for OpenShift network latency)
  # Increase these if you experience timeout errors with large files
  S3_CONNECT_TIMEOUT: "120"  # 2 minutes (default: 60)
  S3_READ_TIMEOUT: "300"     # 5 minutes for large files (default: 60)
  
  # S3 SSL Configuration
  # Set to "false" if using self-signed certificates
  S3_VERIFY_SSL: "false"  # Change to "true" if using valid SSL certificates
  
  # S3 SSL CA Certificate Path (optional)
  # Uncomment and set if you have a custom CA certificate
  # S3_CA_CERT_PATH: "/path/to/ca-cert.pem"
  
  # Disable checksum if your S3 service doesn't support it
  S3_GENERATE_LOCAL_CHECKSUM: "false"  # Set to "false" if checksums cause errors
  
  # ... rest of your configuration ...
```

---

## Step 4: Complete ConfigMap Example

Here's a complete example of what your S3 configuration section should look like in the ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: onyx-config
  namespace: onyx-infra
data:
  # ... other configuration ...
  
  # ============================================================================
  # S3 STORAGE CONFIGURATION
  # ============================================================================
  # S3 Endpoint URL (for non-AWS S3 services)
  S3_ENDPOINT_URL: "https://your-internal-s3-endpoint:443"
  
  # S3 Credentials
  S3_AWS_ACCESS_KEY_ID: "your-access-key-id"
  S3_AWS_SECRET_ACCESS_KEY: "your-secret-access-key"
  
  # S3 Bucket Configuration
  S3_FILE_STORE_BUCKET_NAME: "onyx-file-store-bucket"
  S3_FILE_STORE_PREFIX: "onyx-files"
  
  # AWS Region (can be any region for non-AWS services)
  AWS_REGION_NAME: "us-east-1"
  
  # S3 Addressing Style - VIRTUAL for AWS S3-compatible
  S3_ADDRESSING_STYLE: "virtual"
  
  # S3 Timeout Configuration
  S3_CONNECT_TIMEOUT: "120"
  S3_READ_TIMEOUT: "300"
  
  # S3 SSL Configuration
  S3_VERIFY_SSL: "false"  # Set to "false" for self-signed certs
  
  # S3 Checksum (disable if not supported)
  S3_GENERATE_LOCAL_CHECKSUM: "false"
  
  # ... other configuration ...
```

---

## Step 5: Apply Changes

### 5.1 Apply Code Changes

If you're modifying the Onyx source code:

```bash
# Navigate to backend directory
cd onyx-repo/backend

# Build new Docker image (if using custom build)
docker build -t onyx-backend:custom -f Dockerfile .

# Or push to your registry
docker tag onyx-backend:custom your-registry/onyx-backend:custom
docker push your-registry/onyx-backend:custom
```

### 5.2 Update ConfigMap

```bash
# Apply ConfigMap changes
oc apply -f onyx-k8s-infrastructure/manifests/05-configmap.yaml

# Verify ConfigMap
oc get configmap onyx-config -o yaml | grep -i s3
```

### 5.3 Restart Services

```bash
# Restart API Server
oc rollout restart deployment/api-server

# Restart User File Processing Worker (if exists)
oc rollout restart deployment/celery-worker-user-file-processing

# Wait for rollout
oc rollout status deployment/api-server
```

### 5.4 Verify Changes

```bash
# Check API Server logs for S3 configuration
oc logs deployment/api-server | grep -i "s3\|addressing"

# Test file upload
# Upload a file through the UI and check logs
oc logs -f deployment/api-server | grep -i "s3\|file\|upload"
```

---

## Step 6: Verification Checklist

After applying changes, verify:

- [ ] ConfigMap has `S3_ADDRESSING_STYLE: "virtual"`
- [ ] ConfigMap has timeout values set
- [ ] API Server pod restarted successfully
- [ ] No errors in API Server logs related to S3
- [ ] File upload works (test with small file first)
- [ ] File retrieval works (download uploaded file)

---

## Troubleshooting

### Error: "ModuleNotFoundError: No module named 'onyx.configs.app_configs'"

**Solution**: Make sure you're importing from the correct location. The import should be:
```python
from onyx.configs.app_configs import S3_ADDRESSING_STYLE
```

### Error: "Addressing style not working"

**Solution**: 
1. Check ConfigMap value: `oc get configmap onyx-config -o yaml | grep S3_ADDRESSING_STYLE`
2. Verify it's set to `"virtual"` (with quotes in YAML)
3. Restart services after changing ConfigMap

### Error: "Timeout errors"

**Solution**: Increase timeout values in ConfigMap:
```yaml
S3_CONNECT_TIMEOUT: "180"  # 3 minutes
S3_READ_TIMEOUT: "600"    # 10 minutes
```

### Error: "SSL certificate verification failed"

**Solution**: Set `S3_VERIFY_SSL: "false"` in ConfigMap (for self-signed certificates)

---

## Complete File Changes Summary

### Files to Modify:

1. ✅ `onyx-repo/backend/onyx/configs/app_configs.py`
   - Add: `S3_ADDRESSING_STYLE`, `S3_CONNECT_TIMEOUT`, `S3_READ_TIMEOUT`, `S3_CA_CERT_PATH`

2. ✅ `onyx-repo/backend/onyx/file_store/file_store.py`
   - Update: `_get_s3_client()` method to use configurable addressing style

3. ✅ `onyx-k8s-infrastructure/manifests/05-configmap.yaml`
   - Add: `S3_ADDRESSING_STYLE: "virtual"` and timeout configurations

---

## Quick Reference

**For AWS S3-Compatible Internal Storage**:
- ✅ `S3_ADDRESSING_STYLE: "virtual"`
- ✅ `S3_CONNECT_TIMEOUT: "120"`
- ✅ `S3_READ_TIMEOUT: "300"`
- ✅ `S3_VERIFY_SSL: "false"` (if using self-signed certs)
- ✅ `S3_GENERATE_LOCAL_CHECKSUM: "false"` (if not supported)

---

## Next Steps

1. Apply code changes to `app_configs.py` and `file_store.py`
2. Update ConfigMap with `S3_ADDRESSING_STYLE: "virtual"`
3. Restart services
4. Test file upload
5. Monitor logs for any errors

If you encounter issues, check the troubleshooting section or try switching to `"path"` style as a fallback.

