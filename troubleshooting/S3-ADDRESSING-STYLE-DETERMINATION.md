# S3 Addressing Style: How to Determine Which One to Use

## 🎯 Quick Answer for AWS S3-Compatible Storage

**For AWS S3 or AWS S3-compatible internal storage**: Use **`"virtual"`** addressing style.

**Reason**: AWS S3 uses virtual-hosted style by default, and most AWS S3-compatible services (even internal ones) follow the same pattern.

---

## 📊 Addressing Style Comparison

### Virtual-Hosted Style (AWS S3 Default)
**Format**: `http://bucket-name.endpoint/key`

**Example**:
```
https://onyx-bucket.s3.amazonaws.com/file.pdf
https://onyx-bucket.internal-s3.company.com/file.pdf
```

**When to use**:
- ✅ AWS S3 (even internal/private)
- ✅ AWS S3-compatible services that mimic AWS behavior
- ✅ Most enterprise S3-compatible object storage
- ✅ Services that support virtual-hosted style

**ConfigMap setting**:
```yaml
S3_ADDRESSING_STYLE: "virtual"
```

---

### Path-Style (MinIO Default)
**Format**: `http://endpoint/bucket-name/key`

**Example**:
```
http://minio:9000/onyx-bucket/file.pdf
http://s3-endpoint:9000/onyx-bucket/file.pdf
```

**When to use**:
- ✅ MinIO
- ✅ Some older S3-compatible services
- ✅ Services that don't support virtual-hosted style

**ConfigMap setting**:
```yaml
S3_ADDRESSING_STYLE: "path"
```

---

## 🧪 How to Test Which Style Your Service Uses

### Test 1: Using AWS CLI

**Test Virtual Style** (AWS S3 default):
```bash
# Test if your service supports virtual-hosted style
aws s3 ls s3://your-bucket-name \
  --endpoint-url https://your-internal-s3-endpoint \
  --no-verify-ssl  # If using self-signed certs
```

**Test Path Style**:
```bash
# Force path-style addressing
aws s3 ls s3://your-bucket-name \
  --endpoint-url https://your-internal-s3-endpoint \
  --no-verify-ssl \
  --force-path-style
```

**Which one works?**
- If **virtual style works** → Use `S3_ADDRESSING_STYLE: "virtual"`
- If **path style works** → Use `S3_ADDRESSING_STYLE: "path"`
- If **both work** → Use `"virtual"` (more common for AWS-compatible)

---

### Test 2: Using Python/boto3

**Test Virtual Style**:
```python
import boto3
from botocore.client import Config

client = boto3.client(
    's3',
    endpoint_url='https://your-internal-s3-endpoint',
    aws_access_key_id='your-key',
    aws_secret_access_key='your-secret',
    config=Config(
        signature_version='s3v4',
        s3={'addressing_style': 'virtual'}  # Test virtual
    ),
    verify=False  # If using self-signed certs
)

try:
    response = client.list_buckets()
    print("✅ Virtual style works!")
    print(response)
except Exception as e:
    print(f"❌ Virtual style failed: {e}")
```

**Test Path Style**:
```python
import boto3
from botocore.client import Config

client = boto3.client(
    's3',
    endpoint_url='https://your-internal-s3-endpoint',
    aws_access_key_id='your-key',
    aws_secret_access_key='your-secret',
    config=Config(
        signature_version='s3v4',
        s3={'addressing_style': 'path'}  # Test path
    ),
    verify=False  # If using self-signed certs
)

try:
    response = client.list_buckets()
    print("✅ Path style works!")
    print(response)
except Exception as e:
    print(f"❌ Path style failed: {e}")
```

---

### Test 3: Check Service Documentation

**Look for these keywords in your S3 service documentation**:
- **"Virtual-hosted style"** → Use `"virtual"`
- **"Path-style"** → Use `"path"`
- **"AWS S3 compatible"** → Usually `"virtual"`
- **"MinIO"** → Usually `"path"`

---

## 🔍 Common Internal S3 Services

### AWS S3 (Internal/Private)
- **Style**: `"virtual"` ✅
- **Example**: Private S3 buckets, S3-compatible gateways

### Ceph/RadosGW
- **Style**: Usually `"virtual"` ✅ (but can be configured)
- **Check**: Default is virtual-hosted

### Rook (Kubernetes Object Storage)
- **Style**: Usually `"virtual"` ✅
- **Check**: Depends on underlying storage (often Ceph)

### MinIO
- **Style**: `"path"` ✅
- **Note**: MinIO is the exception, uses path-style

### DigitalOcean Spaces
- **Style**: `"virtual"` ✅
- **Note**: AWS S3-compatible

### Backblaze B2
- **Style**: `"virtual"` ✅
- **Note**: AWS S3-compatible

---

## 📋 Recommended Configuration

### For AWS S3-Compatible Internal Storage

**ConfigMap** (`manifests/05-configmap.yaml`):
```yaml
data:
  # ... existing config ...
  
  # S3 Addressing Style
  # For AWS S3 or AWS S3-compatible services, use "virtual"
  S3_ADDRESSING_STYLE: "virtual"
  
  # Timeouts (increase for OpenShift network latency)
  S3_CONNECT_TIMEOUT: "120"  # 2 minutes
  S3_READ_TIMEOUT: "300"     # 5 minutes for large files
  
  # SSL (if using self-signed certificates)
  S3_VERIFY_SSL: "false"  # Set to "false" if using self-signed certs
```

---

## 🎯 Decision Tree

```
Is your S3 service AWS S3 or AWS S3-compatible?
│
├─ YES → Use "virtual" ✅
│   │
│   └─ Is it MinIO specifically?
│       │
│       ├─ YES → Use "path" ✅
│       └─ NO → Use "virtual" ✅
│
└─ UNSURE → Test both styles (see Test 1 or Test 2 above)
    │
    ├─ Virtual works → Use "virtual" ✅
    ├─ Path works → Use "path" ✅
    └─ Both work → Use "virtual" (more common) ✅
```

---

## ⚠️ Troubleshooting

### If "virtual" doesn't work:

1. **Check if your service supports virtual-hosted style**
   - Some older S3 services only support path-style
   - Check service documentation

2. **Try "path" style**
   - Set `S3_ADDRESSING_STYLE: "path"` in ConfigMap
   - Restart services

3. **Check DNS resolution**
   - Virtual style requires DNS to resolve bucket names
   - Path style doesn't require DNS

### If "path" doesn't work:

1. **Check endpoint URL format**
   - Should be: `http://endpoint:port` or `https://endpoint:port`
   - No bucket name in URL

2. **Try "virtual" style**
   - Set `S3_ADDRESSING_STYLE: "virtual"` in ConfigMap
   - Restart services

---

## ✅ Quick Setup for AWS S3-Compatible Storage

**Step 1**: Update ConfigMap
```yaml
S3_ADDRESSING_STYLE: "virtual"
```

**Step 2**: Apply changes
```bash
oc apply -f manifests/05-configmap.yaml
oc rollout restart deployment/api-server
oc rollout restart deployment/celery-worker-user-file-processing
```

**Step 3**: Test upload
```bash
# Check logs for errors
oc logs -f deployment/api-server | grep -i "s3\|addressing"
```

**Step 4**: If errors occur, try "path" style
```yaml
S3_ADDRESSING_STYLE: "path"
```

---

## 📚 Summary

**For your case** (internal S3-like AWS storage):
- **Recommended**: `S3_ADDRESSING_STYLE: "virtual"` ✅
- **Reason**: AWS S3 and most AWS-compatible services use virtual-hosted style
- **Exception**: If it's MinIO, use `"path"`

**If unsure**: Test both styles using the Python script above, or check your service documentation.

