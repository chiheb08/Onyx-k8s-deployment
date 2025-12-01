# S3 Storage Code Changes - Exact Implementation Guide

## 📝 Step-by-Step Code Changes

### Step 1: Add Configuration to `app_configs.py`

**File**: `onyx-repo/backend/onyx/configs/app_configs.py`

**Location**: After line 914 (after `S3_AWS_SECRET_ACCESS_KEY`)

**Add this code**:

```python
# S3/MinIO Access Keys
S3_AWS_ACCESS_KEY_ID = os.environ.get("S3_AWS_ACCESS_KEY_ID")
S3_AWS_SECRET_ACCESS_KEY = os.environ.get("S3_AWS_SECRET_ACCESS_KEY")

# S3 Addressing Style Configuration
# - "path": Path-style addressing (http://endpoint/bucket/key) - Required for MinIO
# - "virtual": Virtual-hosted style (http://bucket.endpoint/key) - For AWS S3
# - "auto": Let boto3 decide automatically (default)
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

**Complete section should look like this** (lines 912-924):

```python
# S3/MinIO Access Keys
S3_AWS_ACCESS_KEY_ID = os.environ.get("S3_AWS_ACCESS_KEY_ID")
S3_AWS_SECRET_ACCESS_KEY = os.environ.get("S3_AWS_SECRET_ACCESS_KEY")

# S3 Addressing Style Configuration
# - "path": Path-style addressing (http://endpoint/bucket/key) - Required for MinIO
# - "virtual": Virtual-hosted style (http://bucket.endpoint/key) - For AWS S3
# - "auto": Let boto3 decide automatically (default)
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

### Step 2: Update `file_store.py` to Use Configuration

**File**: `onyx-repo/backend/onyx/file_store/file_store.py`

**Location**: Lines 193-207 (inside `_get_s3_client` method)

**BEFORE** (current code):
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

**AFTER** (updated code):
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

### Step 3: Update ConfigMap

**File**: `onyx-k8s-infrastructure/manifests/05-configmap.yaml`

**Add to `data:` section**:

```yaml
data:
  # ... existing configuration ...
  
  # ============================================================================
  # S3 STORAGE CONFIGURATION (for non-MinIO S3 services)
  # ============================================================================
  # S3_ADDRESSING_STYLE: How S3 URLs are constructed
  # - "path": Path-style (http://endpoint/bucket/key) - For MinIO
  # - "virtual": Virtual-hosted (http://bucket.endpoint/key) - For AWS S3
  # - "auto": Let boto3 decide (default, falls back to "path")
  S3_ADDRESSING_STYLE: "auto"  # Change to "path" or "virtual" based on your S3 service
  
  # S3 Timeout Configuration (for OpenShift network latency)
  # Increase these if you experience timeout errors with large files
  S3_CONNECT_TIMEOUT: "120"  # 2 minutes (default: 60)
  S3_READ_TIMEOUT: "300"     # 5 minutes for large files (default: 60)
  
  # S3 SSL Configuration
  # S3_CA_CERT_PATH: Path to custom CA certificate (optional)
  # Leave empty to use system CA certificates
  # S3_CA_CERT_PATH: ""
  
  # ... rest of configuration ...
```

---

## 🔍 Complete Code Comparison

### `app_configs.py` - What to Add

**Find this section** (around line 912-919):
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
# - "path": Path-style addressing (http://endpoint/bucket/key) - Required for MinIO
# - "virtual": Virtual-hosted style (http://bucket.endpoint/key) - For AWS S3
# - "auto": Let boto3 decide automatically (default)
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

### `file_store.py` - What to Change

**Find this section** (around line 193-207):
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

## ✅ Verification Steps

After making the changes:

1. **Check imports work**:
   ```bash
   cd onyx-repo/backend
   python3 -c "from onyx.configs.app_configs import S3_ADDRESSING_STYLE; print(S3_ADDRESSING_STYLE)"
   ```

2. **Test configuration loading**:
   ```bash
   export S3_ADDRESSING_STYLE="virtual"
   python3 -c "from onyx.configs.app_configs import S3_ADDRESSING_STYLE; print(S3_ADDRESSING_STYLE)"
   # Should print: virtual
   ```

3. **Build and test**:
   ```bash
   # Build backend image
   docker build -t onyx-backend:test ./backend
   
   # Or test in your deployment
   oc rollout restart deployment/api-server
   oc logs -f deployment/api-server | grep -i "s3\|addressing"
   ```

---

## 📋 Summary

**What you need to add to `app_configs.py`**:
1. `S3_ADDRESSING_STYLE` - Configurable addressing style
2. `S3_CONNECT_TIMEOUT` - Connection timeout
3. `S3_READ_TIMEOUT` - Read timeout
4. `S3_CA_CERT_PATH` - Optional CA certificate path

**What you need to change in `file_store.py`**:
1. Import the new configuration variables
2. Use `S3_ADDRESSING_STYLE` instead of hardcoded `"path"`
3. Add timeout configuration to `Config()`
4. Add retry configuration
5. Improve SSL verification handling

**What you need to add to ConfigMap**:
1. `S3_ADDRESSING_STYLE: "auto"` (or `"path"` or `"virtual"`)
2. `S3_CONNECT_TIMEOUT: "120"`
3. `S3_READ_TIMEOUT: "300"`

---

## 🎯 Quick Reference

**For MinIO** (current default):
- `S3_ADDRESSING_STYLE: "path"` or leave as `"auto"`

**For AWS S3**:
- `S3_ADDRESSING_STYLE: "virtual"`

**For other S3-compatible services**:
- Test with `"path"` first
- If that doesn't work, try `"virtual"`
- Check your S3 service documentation

