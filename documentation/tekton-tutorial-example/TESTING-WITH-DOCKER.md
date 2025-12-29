# Testing Tekton Pipeline Tutorial with Docker

This guide shows you how to test the Tekton pipeline tutorial using Docker Desktop.

---

## 🎯 Quick Test (5 Minutes)

### **Step 1: Enable Kubernetes in Docker Desktop**

1. Open **Docker Desktop**
2. Go to **Settings** (gear icon) → **Kubernetes**
3. Check **"Enable Kubernetes"**
4. Click **"Apply & Restart"**
5. Wait for Kubernetes to start (green icon in Docker Desktop)

### **Step 2: Run Setup Script**

```bash
# Navigate to the tutorial directory
cd onyx-k8s-infrastructure/documentation/tekton-tutorial-example

# Make setup script executable
chmod +x setup.sh

# Run setup script
./setup.sh
```

The setup script will:
- ✅ Check prerequisites (kubectl, Docker, Kubernetes)
- ✅ Install Tekton Pipelines (if not installed)
- ✅ Install required Tekton tasks (git-clone, buildah)
- ✅ Ask for your credentials (DockerHub, GitHub)
- ✅ Update all configuration files automatically

### **Step 3: Test Pipeline Manually**

```bash
# Apply the test PipelineRun
kubectl apply -f test-pipelinerun.yaml

# Watch the pipeline run
kubectl get pipelineruns -w

# In another terminal, watch pods
kubectl get pods -w

# View logs (if you have tkn CLI installed)
tkn pipelinerun logs test-build-and-push -f

# Or view logs manually
kubectl get pods
kubectl logs <pod-name> -c step-build
```

### **Step 4: Verify Image on DockerHub**

1. Go to https://hub.docker.com
2. Check your repository: `your-username/tekton-tutorial:test-manual`
3. You should see the new image!

### **Step 5: Test the Image Locally**

```bash
# Pull the image
docker pull YOUR_DOCKERHUB_USERNAME/tekton-tutorial:test-manual

# Run the container
docker run -p 8080:80 YOUR_DOCKERHUB_USERNAME/tekton-tutorial:test-manual

# Visit http://localhost:8080 in your browser
# You should see: "Hello from Tekton Pipeline!"
```

---

## 🔄 Full Test with GitHub Webhook

### **Step 1: Start Webhook Server**

```bash
# In the tutorial directory
cd onyx-k8s-infrastructure/documentation/tekton-tutorial-example

# Set DockerHub username (if not set in webhook-server.py)
export DOCKERHUB_USERNAME=your-dockerhub-username

# Start webhook server
python3 webhook-server.py
```

You should see:
```
============================================================
🚀 Tekton Webhook Server
============================================================
📡 Listening on port 8080
🌐 Use ngrok to expose: ngrok http 8080
...
```

### **Step 2: Expose Webhook with ngrok**

**Install ngrok:**
```bash
# macOS
brew install ngrok

# Or download from: https://ngrok.com/download
```

**Start ngrok:**
```bash
# In a new terminal
ngrok http 8080
```

**Copy the ngrok URL** (e.g., `https://abc123.ngrok.io`)

### **Step 3: Configure GitHub Webhook**

1. Go to your GitHub repository
2. Click **Settings** → **Webhooks**
3. Click **"Add webhook"**
4. **Payload URL:** `https://YOUR_NGROK_URL.ngrok.io` (from ngrok)
5. **Content type:** `application/json`
6. **Events:** Select **"Just the push event"**
7. Click **"Add webhook"**

### **Step 4: Create and Push a Tag**

```bash
# In your project directory
cd /path/to/your/project

# Create a tag
git tag v1.0.0

# Push the tag
git push origin v1.0.0
```

### **Step 5: Watch Pipeline Trigger**

```bash
# Watch for new pipeline runs
kubectl get pipelineruns -w

# Or check pods
kubectl get pods -w

# View webhook server logs
# (in the terminal where webhook-server.py is running)
# You should see: "✅ Tag detected: v1.0.0"
```

### **Step 6: Verify Results**

1. **Check DockerHub:** Image should be at `your-username/tekton-tutorial:v1.0.0`
2. **Check PipelineRun:** Should show "Succeeded" status
3. **Test Image:** Pull and run the image locally

---

## 🐛 Troubleshooting

### **Problem: Kubernetes Not Starting**

**Solution:**
```bash
# Check Docker Desktop is running
docker info

# Restart Docker Desktop
# Docker Desktop → Quit → Start again

# Check Kubernetes status in Docker Desktop
# Settings → Kubernetes → Should show "Running"
```

### **Problem: Tekton Not Installing**

**Solution:**
```bash
# Check if namespace exists
kubectl get namespace tekton-pipelines

# If not, install manually
kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# Wait for pods
kubectl wait --for=condition=ready pod --all -n tekton-pipelines --timeout=300s

# Check pods
kubectl get pods -n tekton-pipelines
```

### **Problem: Pipeline Fails to Build**

**Check 1: View Pod Logs**
```bash
kubectl get pods
kubectl logs <pod-name> -c step-build
```

**Check 2: Check Service Account**
```bash
kubectl get serviceaccount tekton-pipeline-sa
kubectl describe serviceaccount tekton-pipeline-sa
```

**Check 3: Check Secrets**
```bash
kubectl get secret dockerhub-secret
kubectl describe secret dockerhub-secret
```

### **Problem: Webhook Not Receiving Events**

**Check 1: Verify ngrok is Running**
```bash
# Check ngrok status
curl http://localhost:4040/api/tunnels
```

**Check 2: Check Webhook Server**
```bash
# Test webhook server locally
curl http://localhost:8080
# Should return: "Webhook server is running!"
```

**Check 3: Check GitHub Webhook Delivery**
1. Go to GitHub → Settings → Webhooks
2. Click on your webhook
3. Check "Recent Deliveries"
4. Look for failed deliveries

### **Problem: Image Not Pushing to DockerHub**

**Check 1: Verify DockerHub Credentials**
```bash
# Test DockerHub login manually
docker login -u YOUR_DOCKERHUB_USERNAME
# Enter password when prompted
```

**Check 2: Check Push Task Logs**
```bash
kubectl logs <pod-name> -c step-push
```

**Check 3: Verify Image Name Format**
- Should be: `username/repository:tag`
- Example: `myuser/tekton-tutorial:v1.0.0`

---

## 📊 Testing Checklist

- [ ] Docker Desktop running
- [ ] Kubernetes enabled in Docker Desktop
- [ ] kubectl installed and working
- [ ] Tekton Pipelines installed
- [ ] Required Tekton tasks installed (git-clone, buildah)
- [ ] Service account created with secrets
- [ ] Pipeline created
- [ ] Test PipelineRun executed successfully
- [ ] Image built and pushed to DockerHub
- [ ] Image tested locally
- [ ] Webhook server running
- [ ] ngrok tunnel active
- [ ] GitHub webhook configured
- [ ] Tag created and pushed
- [ ] Pipeline triggered automatically
- [ ] Image available on DockerHub

---

## 🎯 Quick Commands Reference

```bash
# Check Kubernetes cluster
kubectl cluster-info
kubectl get nodes

# Check Tekton
kubectl get pods -n tekton-pipelines
kubectl get pipeline
kubectl get pipelineruns

# Watch pipeline
kubectl get pipelineruns -w
kubectl get pods -w

# View logs
kubectl logs <pod-name> -c step-build
kubectl logs <pod-name> -c step-push

# Clean up
kubectl delete pipelinerun test-build-and-push
kubectl delete pipeline build-and-push-pipeline
```

---

## 📚 Next Steps

1. **Customize the Dockerfile** for your project
2. **Add more pipeline tasks** (tests, security scans, etc.)
3. **Deploy the image** to a Kubernetes cluster
4. **Add notifications** (Slack, email, etc.)
5. **Set up multiple environments** (dev, staging, prod)

For more details, see the full tutorial: `../TEKTON-PIPELINE-LOCAL-TUTORIAL.md`

