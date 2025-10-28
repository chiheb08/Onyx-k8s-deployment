# Disable "Invited Users Only" Feature - Quick Fix

## 🚨 **Problem**

The "invited users only" feature is preventing you from creating new users freely. This is controlled by environment variables in your Onyx configuration.

---

## 🛠️ **Quick Fix - Disable Invited Users Only**

### **Step 1: Edit Your ConfigMap**
```bash
# Edit the Onyx configuration
oc edit configmap onyx-config
```

### **Step 2: Find and Change These Variables**

**Look for these lines in your ConfigMap:**
```yaml
data:
  ENABLE_EMAIL_INVITES: "true"     # ← CHANGE THIS
  VALID_EMAIL_DOMAINS: "yourcompany.com"  # ← CHANGE THIS TOO
```

**Change them to:**
```yaml
data:
  ENABLE_EMAIL_INVITES: "false"    # ← Allow anyone to register
  VALID_EMAIL_DOMAINS: ""          # ← Allow any email domain
```

### **Step 3: Restart API Server**
```bash
# Restart API server to pick up changes
oc rollout restart deployment/api-server

# Wait for API server to be ready
oc get pods -l app=api-server -w
```

---

## 🔧 **Alternative: Complete Removal**

If you want to completely remove these settings:

### **Method 1: Remove the Variables Entirely**
```bash
# Edit ConfigMap
oc edit configmap onyx-config

# DELETE these lines completely:
# ENABLE_EMAIL_INVITES: "true"
# VALID_EMAIL_DOMAINS: "yourcompany.com"

# Save and restart
oc rollout restart deployment/api-server
```

### **Method 2: Use Command Line**
```bash
# Remove ENABLE_EMAIL_INVITES
oc patch configmap onyx-config --type json -p='[{"op": "remove", "path": "/data/ENABLE_EMAIL_INVITES"}]'

# Remove VALID_EMAIL_DOMAINS  
oc patch configmap onyx-config --type json -p='[{"op": "remove", "path": "/data/VALID_EMAIL_DOMAINS"}]'

# Restart API server
oc rollout restart deployment/api-server
```

### **Method 3: Set to Default Values**
```bash
# Set ENABLE_EMAIL_INVITES to false
oc patch configmap onyx-config --type merge -p '{"data":{"ENABLE_EMAIL_INVITES":"false"}}'

# Remove email domain restrictions
oc patch configmap onyx-config --type merge -p '{"data":{"VALID_EMAIL_DOMAINS":""}}'

# Restart API server
oc rollout restart deployment/api-server
```

---

## ✅ **Verify the Fix**

### **Step 1: Check ConfigMap**
```bash
# Verify the changes
oc get configmap onyx-config -o yaml | grep -E "(ENABLE_EMAIL_INVITES|VALID_EMAIL_DOMAINS)"
```

**Should show:**
```yaml
ENABLE_EMAIL_INVITES: "false"
VALID_EMAIL_DOMAINS: ""
```

**OR no output if you removed them completely**

### **Step 2: Check API Server Logs**
```bash
# Check if API server picked up the changes
oc logs -l app=api-server --tail=20 | grep -i "email\|invite"
```

### **Step 3: Test User Registration**
1. **Go to your Onyx login page**
2. **Click "Sign Up" or "Register"**
3. **Try creating a new user with any email**
4. **Should work without invitation requirement**

---

## 🎯 **What These Settings Do**

### **ENABLE_EMAIL_INVITES:**
- `"true"` = Only invited users can register (RESTRICTS registration)
- `"false"` = Anyone can register freely (ALLOWS open registration)
- **Not set** = Defaults to false (open registration)

### **VALID_EMAIL_DOMAINS:**
- `"yourcompany.com"` = Only emails from this domain can register
- `""` (empty) = Any email domain can register
- **Not set** = Any email domain can register

---

## 🚀 **Super Quick One-Liner Fix**

If you just want to fix it immediately:

```bash
# Disable invited users only and allow any email domain
oc patch configmap onyx-config --type merge -p '{"data":{"ENABLE_EMAIL_INVITES":"false","VALID_EMAIL_DOMAINS":""}}' && oc rollout restart deployment/api-server
```

**This single command will:**
1. Set `ENABLE_EMAIL_INVITES` to `false`
2. Set `VALID_EMAIL_DOMAINS` to empty (allow any domain)
3. Restart the API server to apply changes

---

## 📋 **Step-by-Step Process**

### **Option A: Quick Command Line Fix (30 seconds)**
```bash
# 1. Disable invitation requirement
oc patch configmap onyx-config --type merge -p '{"data":{"ENABLE_EMAIL_INVITES":"false","VALID_EMAIL_DOMAINS":""}}'

# 2. Restart API server
oc rollout restart deployment/api-server

# 3. Wait for restart
oc get pods -l app=api-server -w
```

### **Option B: Manual Edit (2 minutes)**
```bash
# 1. Edit ConfigMap
oc edit configmap onyx-config

# 2. Find and change:
#    ENABLE_EMAIL_INVITES: "true" → "false"
#    VALID_EMAIL_DOMAINS: "domain.com" → ""

# 3. Save and exit

# 4. Restart API server
oc rollout restart deployment/api-server
```

### **Option C: Complete Removal (1 minute)**
```bash
# 1. Remove both settings completely
oc patch configmap onyx-config --type json -p='[{"op": "remove", "path": "/data/ENABLE_EMAIL_INVITES"}]'
oc patch configmap onyx-config --type json -p='[{"op": "remove", "path": "/data/VALID_EMAIL_DOMAINS"}]'

# 2. Restart API server
oc rollout restart deployment/api-server
```

---

## 🎉 **After the Fix**

Once you apply any of these fixes:

✅ **Users can register freely** without invitations
✅ **Any email domain is accepted** (gmail.com, yahoo.com, etc.)
✅ **No more "invitation required" errors**
✅ **Open registration is enabled**

---

## 🔍 **Troubleshooting**

### **If it's still not working:**

#### **Check 1: Verify ConfigMap Changes**
```bash
oc get configmap onyx-config -o yaml | grep -A 5 -B 5 -E "(ENABLE_EMAIL_INVITES|VALID_EMAIL_DOMAINS)"
```

#### **Check 2: Verify API Server Restarted**
```bash
oc get pods -l app=api-server
# Should show recent restart time
```

#### **Check 3: Check API Server Logs**
```bash
oc logs -l app=api-server --tail=50 | grep -i error
```

#### **Check 4: Test Registration Endpoint**
```bash
# Test if registration endpoint is accessible
oc exec -it deploy/api-server -- curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"testpass123"}' \
  http://localhost:8080/api/auth/register
```

---

## 🎯 **Summary**

**The quickest fix is this one command:**
```bash
oc patch configmap onyx-config --type merge -p '{"data":{"ENABLE_EMAIL_INVITES":"false","VALID_EMAIL_DOMAINS":""}}' && oc rollout restart deployment/api-server
```

**This will:**
- ✅ Disable the "invited users only" requirement
- ✅ Allow any email domain to register
- ✅ Enable open user registration
- ✅ Restart the API server to apply changes

**After this, anyone can create new users without invitations!** 🎉
