# Fix: ImportError for section_to_llm_doc_with_empty_doc_citation_number

## 🐛 Error Message

```
ImportError: cannot import name 'section_to_llm_doc_with_empty_doc_citation_number' 
from 'onyx.tools.tool_implementations.search.search_utils'
```

## 🔍 Root Cause

The error occurs because:
1. **Docker Container Outdated**: The code in your running Docker container doesn't have the latest changes
2. **Python Cache**: Cached `.pyc` files might be stale
3. **Code Not Synced**: Local changes haven't been copied to the container

## ✅ Solutions

### Solution 1: Rebuild Docker Container (Recommended)

**If using Docker Compose:**
```bash
cd /Users/chihebmhamdi/Desktop/onyx/onyx-repo
docker-compose down
docker-compose build --no-cache backend
docker-compose up -d
```

**If using Kubernetes:**
```bash
# Delete the pod to force recreation
kubectl delete pod -l app=onyx-api-server

# Or rebuild the image
docker build -t onyx-backend:latest ./backend
kubectl rollout restart deployment/onyx-api-server
```

---

### Solution 2: Clear Python Cache

**Inside the container:**
```bash
# Connect to container
docker exec -it <container-name> bash

# Remove Python cache
find /app -type d -name __pycache__ -exec rm -r {} +
find /app -name "*.pyc" -delete

# Restart the application
```

---

### Solution 3: Verify Function Exists

**Check if function exists in the file:**
```bash
# In your local codebase
grep -n "def section_to_llm_doc_with_empty_doc_citation_number" \
  onyx-repo/backend/onyx/tools/tool_implementations/search/search_utils.py
```

**Expected output:**
```
43:def section_to_llm_doc_with_empty_doc_citation_number(
```

---

### Solution 4: Check File in Container

**If function doesn't exist in container:**
```bash
# Connect to container
docker exec -it <container-name> bash

# Check if function exists
grep -n "def section_to_llm_doc_with_empty_doc_citation_number" \
  /app/onyx/tools/tool_implementations/search/search_utils.py
```

**If it doesn't exist**, the container needs to be rebuilt with latest code.

---

## 🔧 Quick Fix: Verify Import Works

**Test the import locally:**
```bash
cd /Users/chihebmhamdi/Desktop/onyx/onyx-repo/backend
python3 -c "
import sys
sys.path.insert(0, '.')
from onyx.tools.tool_implementations.search.search_utils import section_to_llm_doc_with_empty_doc_citation_number
print('Import successful!')
"
```

**If this works locally but fails in container**, it's a container sync issue.

---

## 📋 Step-by-Step Fix

### Step 1: Verify Function Exists Locally

```bash
cd /Users/chihebmhamdi/Desktop/onyx/onyx-repo
grep "def section_to_llm_doc_with_empty_doc_citation_number" \
  backend/onyx/tools/tool_implementations/search/search_utils.py
```

**Expected**: Should show the function definition

---

### Step 2: Check Docker Container

```bash
# List running containers
docker ps | grep onyx

# Check file in container
docker exec <container-id> cat /app/onyx/tools/tool_implementations/search/search_utils.py | grep "def section_to_llm_doc_with_empty_doc_citation_number"
```

---

### Step 3: Rebuild Container

**Option A: Docker Compose**
```bash
cd /Users/chihebmhamdi/Desktop/onyx/onyx-repo
docker-compose build backend
docker-compose up -d backend
```

**Option B: Kubernetes**
```bash
# Rebuild image
cd /Users/chihebmhamdi/Desktop/onyx/onyx-repo
docker build -t your-registry/onyx-backend:latest -f backend/Dockerfile backend/

# Push image (if using registry)
docker push your-registry/onyx-backend:latest

# Restart deployment
kubectl rollout restart deployment/onyx-api-server
```

---

### Step 4: Clear Cache (If Still Failing)

```bash
# Inside container
docker exec -it <container-id> bash
find /app -type d -name __pycache__ -exec rm -r {} + 2>/dev/null
find /app -name "*.pyc" -delete
exit

# Restart container
docker restart <container-id>
```

---

## 🎯 Most Likely Solution

**The function exists in your code**, but your **Docker container has old code**. 

**Fix**: Rebuild the container with the latest code.

```bash
# Rebuild and restart
docker-compose down
docker-compose build --no-cache backend
docker-compose up -d
```

---

## ⚠️ Important Notes

1. **Function Exists**: The function is definitely in the codebase at line 43 of `search_utils.py`
2. **Import is Correct**: The import statement in `internal_search.py` is correct
3. **Container Issue**: The error path `/app/onyx/` indicates this is a container issue
4. **No Code Changes Needed**: The code is correct, just needs to be in the container

---

## 🔍 Verification

After rebuilding, verify the fix:

```bash
# Check logs
docker logs <container-id> | grep -i "import\|error" | tail -20

# Or in Kubernetes
kubectl logs -l app=onyx-api-server | grep -i "import\|error" | tail -20
```

**Expected**: No import errors, application starts successfully.

---

**Last Updated**: 2024  
**Version**: 1.0

