# Testing Tekton Pipeline Locally - No OpenShift Needed!

## ✅ Good News: You DON'T Need OpenShift!

Tekton Pipelines works on **any Kubernetes cluster**, including:
- ✅ **Docker Desktop** (easiest - you probably already have this!)
- ✅ **Minikube** (local Kubernetes cluster)
- ✅ **Kind** (Kubernetes in Docker)
- ✅ Any local Kubernetes cluster

**You do NOT need OpenShift!** OpenShift includes Tekton, but Tekton works on regular Kubernetes too.

---

## 🎯 Option 1: Docker Desktop (Easiest - Recommended)

### **Why Docker Desktop?**
- ✅ Most people already have Docker Desktop installed
- ✅ Just enable Kubernetes (one click!)
- ✅ No additional installation needed
- ✅ Works on macOS, Windows, and Linux

### **Step 1: Enable Kubernetes in Docker Desktop**

1. **Open Docker Desktop**
2. **Click the Settings icon** (gear icon) in the top right
3. **Go to "Kubernetes"** in the left sidebar
4. **Check the box "Enable Kubernetes"**
5. **Click "Apply & Restart"**
6. **Wait 1-2 minutes** for Kubernetes to start

You'll know it's ready when you see a **green icon** next to "Kubernetes" in Docker Desktop.

### **Step 2: Verify Kubernetes is Running**

```bash
# Check if Kubernetes is accessible
kubectl cluster-info

# Should show:
# Kubernetes control plane is running at https://127.0.0.1:6443

# Check nodes
kubectl get nodes

# Should show:
# NAME             STATUS   ROLES           AGE   VERSION
# docker-desktop   Ready    control-plane   1m    v1.28.0
```

**If you see errors:**
- Make sure Docker Desktop is running
- Wait a bit longer for Kubernetes to fully start
- Try restarting Docker Desktop

### **Step 3: Run the Tutorial**

Now you can follow the tutorial! Kubernetes is ready.

```bash
cd onyx-k8s-infrastructure/documentation/tekton-tutorial-example
./setup.sh
```

---

## 🎯 Option 2: Minikube (If You Don't Have Docker Desktop)

### **Install Minikube**

**macOS:**
```bash
brew install minikube
```

**Linux:**
```bash
# Download from: https://minikube.sigs.k8s.io/docs/start/
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
```

**Windows:**
Download from: https://minikube.sigs.k8s.io/docs/start/

### **Start Minikube**

```bash
# Start minikube
minikube start

# Wait for it to start (takes 1-2 minutes)
# You'll see: "Done! kubectl is now configured to use "minikube""

# Verify
kubectl get nodes

# Should show:
# NAME       STATUS   ROLES           AGE   VERSION
# minikube   Ready    control-plane   1m    v1.28.0
```

### **Run the Tutorial**

```bash
cd onyx-k8s-infrastructure/documentation/tekton-tutorial-example
./setup.sh
```

---

## 🎯 Option 3: Kind (Kubernetes in Docker)

### **Install Kind**

**macOS:**
```bash
brew install kind
```

**Linux/Windows:**
```bash
# Download from: https://kind.sigs.k8s.io/docs/user/quick-start/
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

### **Create Kind Cluster**

```bash
# Create a cluster
kind create cluster --name tekton-tutorial

# Verify
kubectl cluster-info --context kind-tekton-tutorial

# Check nodes
kubectl get nodes
```

### **Run the Tutorial**

```bash
cd onyx-k8s-infrastructure/documentation/tekton-tutorial-example
./setup.sh
```

---

## 📊 Comparison: Which Should You Use?

| Option | Pros | Cons | Best For |
|--------|------|------|----------|
| **Docker Desktop** | ✅ Already installed<br>✅ One-click setup<br>✅ GUI management | ❌ Requires Docker Desktop license (free for personal use) | **Most users** |
| **Minikube** | ✅ Free and open source<br>✅ Works everywhere | ❌ Requires separate installation<br>❌ Uses VM (more resources) | Linux users, CI/CD |
| **Kind** | ✅ Fast startup<br>✅ Uses Docker containers | ❌ Requires Docker<br>❌ Less GUI tools | Developers, testing |

**Recommendation:** Use **Docker Desktop** if you have it, otherwise use **Minikube**.

---

## 🔍 How to Check What You Have

### **Check if Docker Desktop is Installed**

```bash
# Check if Docker is running
docker --version

# Check if Docker Desktop is running
docker info

# If you see "Operating System: Docker Desktop" → You have Docker Desktop!
```

### **Check if Minikube is Installed**

```bash
minikube version
```

### **Check if Kind is Installed**

```bash
kind version
```

### **Check if kubectl is Installed**

```bash
kubectl version --client
```

**If kubectl is not installed:**
- **macOS:** `brew install kubectl`
- **Linux:** See https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
- **Windows:** See https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/

---

## 🚀 Complete Setup Flow (Docker Desktop Example)

```
1. Open Docker Desktop
   ↓
2. Settings → Kubernetes → Enable
   ↓
3. Wait for green icon (Kubernetes running)
   ↓
4. Run: kubectl get nodes
   ↓
5. Should see: docker-desktop Ready
   ↓
6. cd tekton-tutorial-example
   ↓
7. ./setup.sh
   ↓
8. Follow prompts (enter credentials)
   ↓
9. Test pipeline: kubectl apply -f test-pipelinerun.yaml
   ↓
10. Watch: kubectl get pipelineruns -w
   ↓
11. Check DockerHub for your image!
```

---

## ❓ FAQ

### **Q: Do I need OpenShift?**
**A:** No! Tekton works on any Kubernetes cluster. OpenShift includes Tekton, but you can use Tekton on regular Kubernetes (Docker Desktop, Minikube, etc.).

### **Q: Do I need a cloud account?**
**A:** No! Everything runs locally on your machine. You only need:
- DockerHub account (free) - to push images
- GitHub account (free) - to test webhooks (optional)

### **Q: Will this work on my Mac/Windows/Linux?**
**A:** Yes! All options work on all platforms.

### **Q: How much resources does it need?**
**A:** 
- Docker Desktop: ~2GB RAM, ~20GB disk
- Minikube: ~2GB RAM, ~20GB disk
- Kind: ~1GB RAM, ~10GB disk

### **Q: Can I use this in production?**
**A:** This tutorial is for learning. For production, you'd use a real Kubernetes cluster (cloud or on-premises).

### **Q: What if I already have Kubernetes running?**
**A:** Perfect! Just make sure `kubectl` is configured to use your cluster:
```bash
kubectl cluster-info
kubectl get nodes
```
Then run the tutorial as normal.

---

## 🐛 Troubleshooting

### **Problem: "kubectl: command not found"**

**Solution:**
```bash
# Install kubectl
# macOS:
brew install kubectl

# Linux:
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Verify
kubectl version --client
```

### **Problem: "Kubernetes is not running" (Docker Desktop)**

**Solution:**
1. Open Docker Desktop
2. Go to Settings → Kubernetes
3. Make sure "Enable Kubernetes" is checked
4. If not, check it and click "Apply & Restart"
5. Wait 1-2 minutes for it to start

### **Problem: "Cannot connect to the Docker daemon"**

**Solution:**
1. Make sure Docker Desktop is running
2. Check Docker Desktop status (should show "Running")
3. Try: `docker ps` to verify Docker is working

### **Problem: Minikube won't start**

**Solution:**
```bash
# Check minikube status
minikube status

# Delete and recreate
minikube delete
minikube start

# Check logs
minikube logs
```

---

## ✅ Quick Start Checklist

- [ ] Choose your Kubernetes option (Docker Desktop recommended)
- [ ] Install/Enable Kubernetes
- [ ] Verify: `kubectl get nodes` works
- [ ] Run: `cd tekton-tutorial-example && ./setup.sh`
- [ ] Test: `kubectl apply -f test-pipelinerun.yaml`
- [ ] Watch: `kubectl get pipelineruns -w`
- [ ] Check DockerHub for your image!

---

## 📚 Summary

**You DON'T need OpenShift!** 

Just use:
- ✅ **Docker Desktop** (easiest) - enable Kubernetes
- ✅ **Minikube** - install and start
- ✅ **Kind** - install and create cluster

Then follow the tutorial. Everything runs **locally on your machine** - no cloud needed!

The tutorial works exactly the same way on any Kubernetes cluster, whether it's OpenShift, Docker Desktop, Minikube, or any other Kubernetes.

---

**Ready to start?** Choose Docker Desktop (if you have it) and enable Kubernetes - that's it! 🚀

