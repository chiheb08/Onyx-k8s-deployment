# Tekton Pipeline Tutorial - Example Files

This directory contains all the files you need to test the Tekton Pipeline tutorial locally with Docker.

## 📁 Files Included

- **`pipeline.yaml`** - Tekton Pipeline definition (builds and pushes Docker images)
- **`serviceaccount.yaml`** - Service account with DockerHub and GitHub secrets
- **`Dockerfile`** - Simple test application (nginx with custom HTML)
- **`test-pipelinerun.yaml`** - Manual test PipelineRun (for testing without webhook)
- **`webhook-server.py`** - Python webhook server (receives GitHub webhooks)
- **`setup.sh`** - Automated setup script (does everything for you!)
- **`TESTING-WITH-DOCKER.md`** - Complete testing guide with Docker
- **`README.md`** - This file

---

## 🚀 Quick Start (Easiest Way)

### **Option 1: Automated Setup (Recommended)**

```bash
# 1. Navigate to this directory
cd onyx-k8s-infrastructure/documentation/tekton-tutorial-example

# 2. Make setup script executable (if not already)
chmod +x setup.sh

# 3. Run the setup script
./setup.sh
```

The setup script will:
- ✅ Check all prerequisites
- ✅ Install Tekton Pipelines
- ✅ Install required Tekton tasks
- ✅ Ask for your credentials
- ✅ Update all files automatically
- ✅ Apply everything to Kubernetes

### **Option 2: Manual Setup**

See `TESTING-WITH-DOCKER.md` for detailed step-by-step instructions.

---

## 🧪 Testing the Pipeline

### **Test 1: Manual Test (No GitHub Required)**

```bash
# Apply the test PipelineRun
kubectl apply -f test-pipelinerun.yaml

# Watch the pipeline
kubectl get pipelineruns -w

# View logs
tkn pipelinerun logs test-build-and-push -f
# Or without tkn:
kubectl get pods
kubectl logs <pod-name> -c step-build
```

### **Test 2: Full Test with GitHub Webhook**

1. **Start webhook server:**
   ```bash
   python3 webhook-server.py
   ```

2. **Expose with ngrok:**
   ```bash
   ngrok http 8080
   ```

3. **Configure GitHub webhook** (use ngrok URL)

4. **Create and push a tag:**
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

5. **Watch pipeline trigger automatically!**

---

## 📋 Prerequisites

Before running the tutorial, make sure you have:

- ✅ **Docker Desktop** (with Kubernetes enabled)
- ✅ **kubectl** installed
- ✅ **Git** installed
- ✅ **DockerHub account** (free)
- ✅ **GitHub account** (for webhook testing)
- ✅ **Python 3** (for webhook server)
- ✅ **ngrok** (for exposing webhook server) - Optional, only for webhook testing

---

## 🔧 Configuration

Before using the files, you need to update:

1. **`serviceaccount.yaml`** - Replace:
   - `YOUR_DOCKERHUB_USERNAME` → Your DockerHub username
   - `YOUR_DOCKERHUB_PASSWORD` → Your DockerHub password/token
   - `YOUR_GITHUB_USERNAME` → Your GitHub username
   - `YOUR_GITHUB_TOKEN` → Your GitHub personal access token

2. **`pipeline.yaml`** - Replace:
   - `YOUR_USERNAME/tekton-tutorial.git` → Your GitHub repository URL

3. **`test-pipelinerun.yaml`** - Replace:
   - `YOUR_DOCKERHUB_USERNAME` → Your DockerHub username

**Or use the `setup.sh` script** - it does all of this automatically!

---

## 📚 Documentation

- **`TESTING-WITH-DOCKER.md`** - Complete testing guide with Docker Desktop
- **`../TEKTON-PIPELINE-LOCAL-TUTORIAL.md`** - Full detailed tutorial

---

## 🐛 Troubleshooting

See `TESTING-WITH-DOCKER.md` for troubleshooting guide.

Common issues:
- Kubernetes not starting → Enable in Docker Desktop
- Tekton not installing → Check network connection
- Pipeline failing → Check service account secrets
- Webhook not working → Check ngrok and GitHub webhook configuration

---

## ✅ Quick Checklist

- [ ] Docker Desktop running with Kubernetes enabled
- [ ] Run `./setup.sh` or manually configure files
- [ ] Test manually: `kubectl apply -f test-pipelinerun.yaml`
- [ ] Verify image on DockerHub
- [ ] (Optional) Test with GitHub webhook

---

## 🎯 What This Tutorial Does

1. **Sets up Tekton Pipelines** locally (using Docker Desktop Kubernetes)
2. **Creates a pipeline** that builds Docker images
3. **Pushes images** to DockerHub automatically
4. **Triggers on GitHub tags** via webhook (optional)

**Result:** When you create a GitHub tag, Tekton automatically builds and pushes a Docker image to DockerHub! 🚀

