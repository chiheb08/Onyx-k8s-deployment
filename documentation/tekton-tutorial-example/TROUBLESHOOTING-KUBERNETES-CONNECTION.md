# Troubleshooting: Kubernetes Connection Refused Error

## 🔴 Error Message

```
The connection to the server 127.0.0.1:51389 was refused
dial tcp 127.0.0.1:51389: connect: connection refused
```

**What this means:** kubectl is trying to connect to Kubernetes, but the cluster is not running or not accessible.

---

## 🔍 Step-by-Step Troubleshooting

### **Step 1: Check if Docker Desktop is Running**

```bash
# Check if Docker is running
docker info
```

**If you see an error:**
- ❌ Docker Desktop is not running
- **Solution:** Open Docker Desktop and wait for it to start

**If Docker is running:**
- ✅ Continue to Step 2

---

### **Step 2: Check if Kubernetes is Enabled in Docker Desktop**

1. **Open Docker Desktop**
2. **Click the Settings icon** (gear icon) in the top right
3. **Go to "Kubernetes"** in the left sidebar
4. **Check if "Enable Kubernetes" is checked**

**If NOT checked:**
- ❌ Kubernetes is disabled
- **Solution:**
  1. Check the box "Enable Kubernetes"
  2. Click "Apply & Restart"
  3. Wait 1-2 minutes for Kubernetes to start
  4. You'll see a green icon when it's ready

**If checked:**
- ✅ Continue to Step 3

---

### **Step 3: Wait for Kubernetes to Start**

Kubernetes takes 1-2 minutes to start after enabling.

**How to check if it's ready:**

1. **In Docker Desktop:**
   - Look at the Kubernetes section
   - You should see a **green icon** and "Kubernetes is running"

2. **In terminal:**
   ```bash
   # Check if Kubernetes is ready
   kubectl get nodes
   ```

**If you see:**
```
NAME             STATUS   ROLES           AGE   VERSION
docker-desktop   Ready    control-plane   1m    v1.28.0
```
- ✅ Kubernetes is running! You're good to go.

**If you see an error:**
- ❌ Kubernetes is still starting
- **Solution:** Wait a bit longer (1-2 minutes), then try again

---

### **Step 4: Check kubectl Context**

Sometimes kubectl is pointing to the wrong cluster.

```bash
# Check current context
kubectl config current-context

# Should show something like:
# docker-desktop
# or
# docker-for-desktop
```

**If it shows something else (like minikube):**

```bash
# List all contexts
kubectl config get-contexts

# Switch to Docker Desktop context
kubectl config use-context docker-desktop
# or
kubectl config use-context docker-for-desktop
```

---

### **Step 5: Restart Docker Desktop (If Still Not Working)**

Sometimes Docker Desktop needs a restart:

1. **Quit Docker Desktop completely:**
   - macOS: Docker Desktop → Quit Docker Desktop
   - Windows: Right-click Docker Desktop icon → Quit

2. **Wait 10 seconds**

3. **Start Docker Desktop again**

4. **Enable Kubernetes** (if not already enabled)

5. **Wait 1-2 minutes** for Kubernetes to start

6. **Test again:**
   ```bash
   kubectl get nodes
   ```

---

## 🎯 Quick Fix Checklist

Try these in order:

- [ ] **Docker Desktop is running** → Check Docker Desktop icon in menu bar
- [ ] **Kubernetes is enabled** → Docker Desktop → Settings → Kubernetes → Enable
- [ ] **Waited 1-2 minutes** → Kubernetes needs time to start
- [ ] **Green icon visible** → In Docker Desktop Kubernetes section
- [ ] **kubectl context is correct** → `kubectl config current-context`
- [ ] **Restarted Docker Desktop** → If nothing else works

---

## 🔧 Detailed Solutions

### **Solution 1: Enable Kubernetes in Docker Desktop**

**For macOS:**
1. Open Docker Desktop
2. Click Settings (gear icon)
3. Click "Kubernetes" in left sidebar
4. Check "Enable Kubernetes"
5. Click "Apply & Restart"
6. Wait for green icon

**For Windows:**
1. Right-click Docker Desktop icon in system tray
2. Click "Settings"
3. Click "Kubernetes" in left sidebar
4. Check "Enable Kubernetes"
5. Click "Apply & Restart"
6. Wait for green icon

---

### **Solution 2: Reset Kubernetes (If Still Not Working)**

If Kubernetes won't start:

1. **In Docker Desktop:**
   - Settings → Kubernetes
   - Click "Reset Kubernetes Cluster"
   - Confirm

2. **Re-enable Kubernetes:**
   - Check "Enable Kubernetes"
   - Click "Apply & Restart"

3. **Wait 2-3 minutes** for it to start

---

### **Solution 3: Check Docker Desktop Resources**

Kubernetes needs resources to run:

1. **In Docker Desktop:**
   - Settings → Resources
   - Make sure you have:
     - **CPU:** At least 2 CPUs allocated
     - **Memory:** At least 4GB allocated
   - Click "Apply & Restart"

---

### **Solution 4: Use Minikube Instead**

If Docker Desktop Kubernetes keeps having issues, use Minikube:

```bash
# Install Minikube
brew install minikube  # macOS

# Start Minikube
minikube start

# Verify
kubectl get nodes

# Should show:
# NAME       STATUS   ROLES           AGE   VERSION
# minikube   Ready    control-plane   1m    v1.28.0
```

---

## 🐛 Common Issues and Fixes

### **Issue 1: "Kubernetes is starting..." Forever**

**Symptoms:**
- Docker Desktop shows "Kubernetes is starting..." but never finishes

**Fix:**
1. Quit Docker Desktop completely
2. Restart Docker Desktop
3. Enable Kubernetes again
4. Wait 2-3 minutes

**If still not working:**
- Check Docker Desktop logs
- Try resetting Kubernetes cluster (Settings → Kubernetes → Reset)

---

### **Issue 2: "Port already in use"**

**Symptoms:**
- Error about port 6443 or other ports being in use

**Fix:**
```bash
# Find what's using the port (macOS)
lsof -i :6443

# Kill the process
kill -9 <PID>

# Or restart Docker Desktop
```

---

### **Issue 3: "Cannot connect to Docker daemon"**

**Symptoms:**
- `docker info` fails

**Fix:**
1. Make sure Docker Desktop is running
2. Check Docker Desktop status
3. Restart Docker Desktop if needed

---

### **Issue 4: kubectl Points to Wrong Cluster**

**Symptoms:**
- kubectl works but connects to wrong cluster (e.g., minikube instead of docker-desktop)

**Fix:**
```bash
# List all contexts
kubectl config get-contexts

# Switch to Docker Desktop
kubectl config use-context docker-desktop

# Verify
kubectl config current-context
# Should show: docker-desktop
```

---

## ✅ Verification Steps

After fixing, verify everything works:

```bash
# 1. Check Docker is running
docker info
# Should show Docker information (no errors)

# 2. Check Kubernetes cluster
kubectl cluster-info
# Should show:
# Kubernetes control plane is running at https://127.0.0.1:6443

# 3. Check nodes
kubectl get nodes
# Should show:
# NAME             STATUS   ROLES           AGE   VERSION
# docker-desktop   Ready    control-plane   1m    v1.28.0

# 4. Check namespaces
kubectl get namespaces
# Should show default, kube-system, etc.
```

**If all these work:**
- ✅ Kubernetes is running correctly!
- ✅ You can proceed with the Tekton tutorial

---

## 📊 What the Error Means (Technical Explanation)

The error `dial tcp 127.0.0.1:51389: connect: connection refused` means:

1. **kubectl is trying to connect** to Kubernetes API server
2. **The connection is refused** because:
   - Kubernetes API server is not running
   - The port is not listening
   - Firewall is blocking it
   - Docker Desktop Kubernetes is not enabled

**The port number (51389) is random** - Docker Desktop assigns a random port for Kubernetes API server.

**The IP (127.0.0.1)** means localhost - kubectl is trying to connect to local Kubernetes cluster.

---

## 🎯 Quick Command Reference

```bash
# Check Docker
docker info

# Check Kubernetes
kubectl cluster-info
kubectl get nodes

# Check kubectl context
kubectl config current-context
kubectl config get-contexts

# Switch context
kubectl config use-context docker-desktop

# Check if Kubernetes namespace exists (means Kubernetes is running)
kubectl get namespace default
```

---

## 📚 Next Steps

Once Kubernetes is working:

1. **Run the setup script:**
   ```bash
   cd onyx-k8s-infrastructure/documentation/tekton-tutorial-example
   ./setup.sh
   ```

2. **The script will:**
   - Check if Kubernetes is accessible (this step will now pass!)
   - Install Tekton Pipelines
   - Install required tasks
   - Ask for your credentials
   - Set up everything

---

## 💡 Pro Tips

1. **Always wait 1-2 minutes** after enabling Kubernetes in Docker Desktop
2. **Check the green icon** in Docker Desktop - that's the best indicator
3. **Use `kubectl get nodes`** to verify - it's the simplest test
4. **If stuck, restart Docker Desktop** - fixes 90% of issues
5. **Check Docker Desktop logs** if nothing works - Settings → Troubleshoot → View logs

---

## ✅ Summary

**The error means:** Kubernetes is not running or not accessible.

**Most common cause:** Kubernetes is not enabled in Docker Desktop.

**Quick fix:**
1. Open Docker Desktop
2. Settings → Kubernetes → Enable
3. Wait 1-2 minutes
4. Test: `kubectl get nodes`

**If that doesn't work:** Follow the troubleshooting steps above.

Once `kubectl get nodes` works, you're ready to continue with the Tekton tutorial! 🚀

