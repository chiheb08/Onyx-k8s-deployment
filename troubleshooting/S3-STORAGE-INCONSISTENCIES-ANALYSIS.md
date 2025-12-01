# S3 Storage Inconsistencies: Deep Analysis & Solutions

## 🎯 Executive Summary

**Problem**: Using a different S3-compatible storage (not MinIO) in OpenShift deployment causes file upload inconsistencies.

**Root Cause**: Onyx's S3 client configuration is **hardcoded for MinIO** with specific settings that may not be compatible with other S3-compatible services.

**Impact**: 
- Files upload successfully sometimes, fail other times
- Files appear uploaded but cannot be retrieved
- Timeout errors during upload
- Connection errors
- Files stuck in "PROCESSING" status

---

## 🔍 Deep Technical Analysis

### 1. **Addressing Style Mismatch** ⚠️ **CRITICAL**

**Location**: `backend/onyx/file_store/file_store.py:196-199`

**Current Code**:
```python
if self._s3_endpoint_url:
    client_kwargs["endpoint_url"] = self._s3_endpoint_url
    client_kwargs["config"] = Config(
        signature_version="s3v4",
        s3={"addressing_style": "path"},  # ← HARDCODED FOR MINIO
    )
```

**Problem**:
- **MinIO** requires `"path"` addressing style: `http://endpoint/bucket/key`
- **AWS S3** uses `"virtual"` addressing style: `http://bucket.endpoint/key`
- **Other S3-compatible services** may require `"virtual"` or `"auto"`

**Impact**:
- URLs are constructed incorrectly
- Requests fail with 404 or 403 errors
- Inconsistent behavior depending on service type

**Example**:
```
# MinIO (path style) - CORRECT:
http://s3.example.com:9000/onyx-bucket/file.pdf

# AWS S3 (virtual style) - CORRECT:
https://onyx-bucket.s3.amazonaws.com/file.pdf

# If you use path style with AWS S3 - WRONG:
https://s3.amazonaws.com/onyx-bucket/file.pdf  # May fail
```

---

### 2. **Missing Timeout Configuration** ⚠️ **HIGH PRIORITY**

**Location**: `backend/onyx/file_store/file_store.py:184-226`

**Problem**:
- No explicit timeout configuration for boto3 client
- Uses boto3 defaults (60 seconds connect timeout, 60 seconds read timeout)
- **OpenShift network latency** may exceed these defaults
- Large file uploads may timeout

**Impact**:
- Uploads fail silently after 60 seconds
- No retry mechanism for timeout errors
- Inconsistent behavior with large files

**Missing Configuration**:
```python
# Should include:
Config(
    connect_timeout=120,  # 2 minutes for OpenShift network
    read_timeout=300,     # 5 minutes for large files
    retries={
        'max_attempts': 3,
        'mode': 'adaptive'
    }
)
```

---

### 3. **No Retry Strategy** ⚠️ **HIGH PRIORITY**

**Location**: `backend/onyx/file_store/file_store.py:196-199`

**Problem**:
- boto3 uses default retry strategy (3 attempts)
- No custom retry configuration for transient errors
- Network issues in OpenShift may cause temporary failures

**Impact**:
- Temporary network glitches cause permanent failures
- No exponential backoff
- Inconsistent upload success rates

**Missing Configuration**:
```python
Config(
    retries={
        'max_attempts': 5,  # More retries for OpenShift
        'mode': 'adaptive',  # Adaptive retry with exponential backoff
    }
)
```

---

### 4. **SSL/TLS Verification Issues** ⚠️ **MEDIUM PRIORITY**

**Location**: `backend/onyx/file_store/file_store.py:200-207`

**Current Code**:
```python
if not self._s3_verify_ssl:
    import urllib3
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    client_kwargs["verify"] = False
```

**Problem**:
- Only handles disabling SSL verification
- **Does not handle custom CA certificates**
- OpenShift S3 services may use internal CA certificates
- SSL verification may fail with self-signed certificates

**Impact**:
- SSL handshake failures
- Connection refused errors
- Inconsistent behavior with HTTPS endpoints

**Missing Configuration**:
```python
# Should support:
client_kwargs["verify"] = "/path/to/ca-cert.pem"  # Custom CA
# OR
client_kwargs["verify"] = False  # Disable (current)
# OR
client_kwargs["verify"] = True  # Default (current)
```

---

### 5. **Region Configuration Issues** ⚠️ **MEDIUM PRIORITY**

**Location**: `backend/onyx/file_store/file_store.py:179`

**Current Code**:
```python
self._aws_region_name = aws_region_name or "us-east-2"  # ← Defaults to AWS region
```

**Problem**:
- Defaults to AWS region `"us-east-2"`
- **Non-AWS S3 services don't use AWS regions**
- Some services require specific region names or may ignore region
- Region mismatch can cause signature errors

**Impact**:
- Signature validation failures
- 403 Forbidden errors
- Inconsistent authentication

**Solution**:
- For non-AWS S3 services, region should be configurable or ignored
- Some services accept any region name (e.g., MinIO)
- Others require specific region format

---

### 6. **Checksum Compatibility** ⚠️ **MEDIUM PRIORITY**

**Location**: `backend/onyx/file_store/file_store.py:338-342`

**Current Code**:
```python
if S3_GENERATE_LOCAL_CHECKSUM:
    data_bytes = str(file_content).encode()
    sha256_hash.update(data_bytes)
    hash256 = sha256_hash.hexdigest()
    kwargs["ChecksumSHA256"] = hash256  # ← May not be supported
```

**Problem**:
- `ChecksumSHA256` is an **AWS S3-specific feature**
- **Not all S3-compatible services support checksums**
- May cause upload failures with non-AWS services

**Impact**:
- Upload fails with "UnsupportedParameter" error
- Files cannot be uploaded if checksum is enabled
- Inconsistent behavior

**Solution**:
- Make checksum optional based on service type
- Detect service compatibility
- Fall back to no checksum if unsupported

---

### 7. **Connection Pooling Issues** ⚠️ **LOW PRIORITY**

**Problem**:
- No explicit connection pool configuration
- boto3 uses default connection pooling
- **OpenShift may have connection limits**
- Multiple concurrent uploads may exhaust connections

**Impact**:
- Connection pool exhaustion
- Slow uploads under load
- Timeout errors with concurrent uploads

**Missing Configuration**:
```python
Config(
    max_pool_connections=50,  # Increase for OpenShift
)
```

---

### 8. **Bucket Creation Logic** ⚠️ **LOW PRIORITY**

**Location**: `backend/onyx/file_store/file_store.py:273-281`

**Current Code**:
```python
if region and region != "us-east-1":
    s3_client.create_bucket(
        Bucket=bucket_name,
        CreateBucketConfiguration={"LocationConstraint": region},
    )
else:
    s3_client.create_bucket(Bucket=bucket_name)
```

**Problem**:
- `LocationConstraint` is **AWS S3-specific**
- Non-AWS services may reject this parameter
- May cause bucket creation to fail

**Impact**:
- Initialization fails
- Files cannot be stored
- Service startup errors

---

## 📊 Inconsistency Patterns

### Pattern 1: Intermittent Upload Failures

**Symptoms**:
- Upload succeeds 50% of the time
- Fails with timeout or connection errors
- No clear pattern

**Root Cause**: Timeout configuration too low for OpenShift network latency

**Solution**: Increase timeout values

---

### Pattern 2: Files Upload but Cannot Be Retrieved

**Symptoms**:
- Upload appears successful
- File record created in database
- `read_file()` fails with 404

**Root Cause**: Addressing style mismatch - URL constructed incorrectly

**Solution**: Configure correct addressing style for your S3 service

---

### Pattern 3: SSL Handshake Failures

**Symptoms**:
- Upload fails with SSL errors
- `SSL: CERTIFICATE_VERIFY_FAILED`
- Works with HTTP, fails with HTTPS

**Root Cause**: Custom CA certificates not configured

**Solution**: Configure SSL verification or provide CA certificate

---

### Pattern 4: Signature Validation Errors

**Symptoms**:
- 403 Forbidden errors
- `SignatureDoesNotMatch`
- Authentication appears correct

**Root Cause**: Region mismatch or addressing style issue

**Solution**: Configure correct region and addressing style

---

## 🛠️ Solutions & Fixes

### Solution 1: Add S3 Addressing Style Configuration

**File**: `manifests/05-configmap.yaml`

**Add**:
```yaml
data:
  # ... existing config ...
  
  # S3 Addressing Style Configuration
  # - "path": For MinIO and path-style S3 services (http://endpoint/bucket/key)
  # - "virtual": For AWS S3 and virtual-hosted style (http://bucket.endpoint/key)
  # - "auto": Let boto3 decide (default)
  S3_ADDRESSING_STYLE: "auto"  # Change to "path" for MinIO, "virtual" for AWS S3
```

**File**: `backend/onyx/configs/app_configs.py`

**Add** (after line 914):
```python
# S3 Addressing Style (for non-MinIO S3 services)
S3_ADDRESSING_STYLE = os.environ.get("S3_ADDRESSING_STYLE", "auto")  # "path", "virtual", or "auto"
```

**File**: `backend/onyx/file_store/file_store.py`

**Modify** (lines 196-199):
```python
# BEFORE:
if self._s3_endpoint_url:
    client_kwargs["endpoint_url"] = self._s3_endpoint_url
    client_kwargs["config"] = Config(
        signature_version="s3v4",
        s3={"addressing_style": "path"},  # Hardcoded
    )

# AFTER:
if self._s3_endpoint_url:
    from onyx.configs.app_configs import S3_ADDRESSING_STYLE
    addressing_style = S3_ADDRESSING_STYLE if S3_ADDRESSING_STYLE != "auto" else "path"
    client_kwargs["endpoint_url"] = self._s3_endpoint_url
    client_kwargs["config"] = Config(
        signature_version="s3v4",
        s3={"addressing_style": addressing_style},  # Configurable
    )
```

---

### Solution 2: Add Timeout Configuration

**File**: `manifests/05-configmap.yaml`

**Add**:
```yaml
data:
  # ... existing config ...
  
  # S3 Timeout Configuration (for OpenShift network latency)
  S3_CONNECT_TIMEOUT: "120"  # 2 minutes (default: 60)
  S3_READ_TIMEOUT: "300"    # 5 minutes for large files (default: 60)
```

**File**: `backend/onyx/configs/app_configs.py`

**Add** (after line 914):
```python
# S3 Timeout Configuration
S3_CONNECT_TIMEOUT = int(os.environ.get("S3_CONNECT_TIMEOUT", "60"))
S3_READ_TIMEOUT = int(os.environ.get("S3_READ_TIMEOUT", "60"))
```

**File**: `backend/onyx/file_store/file_store.py`

**Modify** (lines 196-199):
```python
# BEFORE:
client_kwargs["config"] = Config(
    signature_version="s3v4",
    s3={"addressing_style": "path"},
)

# AFTER:
from onyx.configs.app_configs import S3_CONNECT_TIMEOUT, S3_READ_TIMEOUT
client_kwargs["config"] = Config(
    signature_version="s3v4",
    s3={"addressing_style": addressing_style},
    connect_timeout=S3_CONNECT_TIMEOUT,
    read_timeout=S3_READ_TIMEOUT,
    retries={
        'max_attempts': 5,
        'mode': 'adaptive',
    },
)
```

---

### Solution 3: Add SSL CA Certificate Support

**File**: `manifests/05-configmap.yaml`

**Add**:
```yaml
data:
  # ... existing config ...
  
  # S3 SSL Configuration
  S3_VERIFY_SSL: "true"  # "true", "false", or path to CA cert file
  S3_CA_CERT_PATH: ""    # Path to custom CA certificate (optional)
```

**File**: `backend/onyx/file_store/file_store.py`

**Modify** (lines 200-207):
```python
# BEFORE:
if not self._s3_verify_ssl:
    import urllib3
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    client_kwargs["verify"] = False

# AFTER:
from onyx.configs.app_configs import S3_CA_CERT_PATH
if not self._s3_verify_ssl:
    import urllib3
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    client_kwargs["verify"] = False
elif S3_CA_CERT_PATH:
    # Use custom CA certificate
    client_kwargs["verify"] = S3_CA_CERT_PATH
else:
    # Use default system CA certificates
    client_kwargs["verify"] = True
```

---

### Solution 4: Make Checksum Optional

**File**: `backend/onyx/file_store/file_store.py`

**Modify** (lines 338-342):
```python
# BEFORE:
if S3_GENERATE_LOCAL_CHECKSUM:
    data_bytes = str(file_content).encode()
    sha256_hash.update(data_bytes)
    hash256 = sha256_hash.hexdigest()
    kwargs["ChecksumSHA256"] = hash256

# AFTER:
if S3_GENERATE_LOCAL_CHECKSUM:
    try:
        data_bytes = str(file_content).encode()
        sha256_hash.update(data_bytes)
        hash256 = sha256_hash.hexdigest()
        kwargs["ChecksumSHA256"] = hash256
    except Exception as e:
        # If checksum is not supported, log and continue without it
        logger.warning(f"Checksum not supported by S3 service, continuing without: {e}")
```

---

### Solution 5: Fix Bucket Creation for Non-AWS Services

**File**: `backend/onyx/file_store/file_store.py`

**Modify** (lines 273-281):
```python
# BEFORE:
if region and region != "us-east-1":
    s3_client.create_bucket(
        Bucket=bucket_name,
        CreateBucketConfiguration={"LocationConstraint": region},
    )
else:
    s3_client.create_bucket(Bucket=bucket_name)

# AFTER:
try:
    if region and region != "us-east-1" and not self._s3_endpoint_url:
        # Only use LocationConstraint for AWS S3 (no endpoint URL)
        s3_client.create_bucket(
            Bucket=bucket_name,
            CreateBucketConfiguration={"LocationConstraint": region},
        )
    else:
        # For non-AWS S3 services, don't use LocationConstraint
        s3_client.create_bucket(Bucket=bucket_name)
except ClientError as e:
    # If LocationConstraint fails, try without it (for non-AWS services)
    if "LocationConstraint" in str(e):
        logger.warning(f"LocationConstraint not supported, retrying without: {e}")
        s3_client.create_bucket(Bucket=bucket_name)
    else:
        raise
```

---

## 🔧 Quick Fix: Configuration-Only Solution

If you cannot modify code, try these **configuration-only** fixes:

### 1. Set Addressing Style via Environment Variable

**Add to ConfigMap** (`manifests/05-configmap.yaml`):
```yaml
data:
  # ... existing config ...
  
  # Force path-style addressing (if your S3 service requires it)
  AWS_S3_FORCE_PATH_STYLE: "true"  # Some services respect this
```

**Note**: This may not work if Onyx doesn't read this variable. Check if boto3 respects it.

---

### 2. Disable Checksum

**Add to ConfigMap**:
```yaml
data:
  # ... existing config ...
  
  # Disable checksum (may not be supported by your S3 service)
  S3_GENERATE_LOCAL_CHECKSUM: "false"
```

---

### 3. Increase Timeouts (if boto3 respects environment variables)

**Add to ConfigMap**:
```yaml
data:
  # ... existing config ...
  
  # boto3 timeout environment variables (if supported)
  AWS_METADATA_SERVICE_TIMEOUT: "120"
  AWS_METADATA_SERVICE_NUM_ATTEMPTS: "5"
```

**Note**: These may not affect S3 client timeouts directly.

---

## 📋 Diagnostic Checklist

Use this checklist to identify which issues affect your deployment:

- [ ] **Addressing Style**: Test URL format
  - Path style: `http://endpoint/bucket/key`
  - Virtual style: `http://bucket.endpoint/key`
  - Which format does your S3 service use?

- [ ] **Timeout Issues**: Check logs for timeout errors
  - Look for: `ReadTimeout`, `ConnectTimeout`
  - Do large files fail more often?

- [ ] **SSL Issues**: Check logs for SSL errors
  - Look for: `SSL: CERTIFICATE_VERIFY_FAILED`
  - Does it work with HTTP but fail with HTTPS?

- [ ] **Checksum Errors**: Check logs for checksum errors
  - Look for: `UnsupportedParameter`, `InvalidParameter`
  - Does disabling checksum help?

- [ ] **Region Errors**: Check logs for region/signature errors
  - Look for: `SignatureDoesNotMatch`, `InvalidRegion`
  - Does changing region help?

- [ ] **Connection Pool**: Check for connection errors under load
  - Look for: `ConnectionPool`, `Too many connections`
  - Do concurrent uploads fail?

---

## 🧪 Testing Your S3 Configuration

### Test 1: Addressing Style

```bash
# Test path-style (MinIO)
aws s3 ls s3://bucket-name --endpoint-url http://your-s3-endpoint:9000 --no-verify-ssl

# Test virtual-style (AWS S3)
aws s3 ls s3://bucket-name --endpoint-url https://your-s3-endpoint
```

### Test 2: Upload/Download

```bash
# Upload test
aws s3 cp test-file.txt s3://bucket-name/ --endpoint-url http://your-s3-endpoint:9000

# Download test
aws s3 cp s3://bucket-name/test-file.txt downloaded-file.txt --endpoint-url http://your-s3-endpoint:9000
```

### Test 3: SSL Verification

```bash
# Test with SSL verification disabled
aws s3 ls s3://bucket-name --endpoint-url https://your-s3-endpoint --no-verify-ssl

# Test with custom CA
aws s3 ls s3://bucket-name --endpoint-url https://your-s3-endpoint --ca-bundle /path/to/ca-cert.pem
```

---

## 📚 References

- **boto3 Config Documentation**: https://boto3.amazonaws.com/v1/documentation/api/latest/reference/core/session.html#boto3.session.Session.client
- **S3 Addressing Styles**: https://docs.aws.amazon.com/AmazonS3/latest/userguide/VirtualHosting.html
- **MinIO S3 Compatibility**: https://min.io/docs/minio/linux/developers/minio-drivers-for-python.html
- **Onyx File Store README**: `onyx-repo/backend/onyx/file_store/README.md`

---

## ✅ Summary

**Key Issues**:
1. ⚠️ **Addressing style hardcoded for MinIO** - May not work with other S3 services
2. ⚠️ **No timeout configuration** - OpenShift network latency may cause timeouts
3. ⚠️ **No retry strategy** - Temporary failures become permanent
4. ⚠️ **SSL verification issues** - Custom CA certificates not supported
5. ⚠️ **Checksum compatibility** - AWS-specific feature may not work

**Recommended Actions**:
1. **Immediate**: Add `S3_ADDRESSING_STYLE` configuration to ConfigMap
2. **Short-term**: Add timeout and retry configuration
3. **Long-term**: Implement all fixes above for full compatibility

**Priority**: **HIGH** - File upload inconsistencies are critical for user experience.

