# Tekton Pipeline Tutorial - Local Setup with Docker

## 🎯 Goal

Create a Tekton pipeline that:
1. ✅ Runs **locally** (on your machine)
2. ✅ Triggers when you **create a GitHub tag**
3. ✅ **Builds a Docker image**
4. ✅ **Pushes to DockerHub**

---

## 📋 Prerequisites

Before starting, make sure you have:

- **Docker Desktop** (with Kubernetes enabled) OR **Minikube**
- **kubectl** installed
- **Git** installed
- **DockerHub account** (free)
- **GitHub account** (for testing)

---

## 🚀 Step 1: Set Up Local Kubernetes

### **Option A: Docker Desktop (Easiest)**

1. **Open Docker Desktop**
2. **Go to Settings** → **Kubernetes**
3. **Enable Kubernetes**
4. **Click "Apply & Restart"**

Wait for Kubernetes to start (green icon in Docker Desktop).

### **Option B: Minikube**

```bash
# Install minikube (if not installed)
# macOS: brew install minikube
# Linux: See https://minikube.sigs.k8s.io/docs/start/

# Start minikube
minikube start

# Verify it's running
kubectl get nodes
```

### **Verify Kubernetes is Running**

```bash
# Check if Kubernetes is running
kubectl get nodes

# Should show:
# NAME             STATUS   ROLES           AGE   VERSION
# docker-desktop   Ready    control-plane   1m    v1.28.0
```

---

## 🚀 Step 2: Install Tekton Pipelines

### **Install Tekton Pipelines**

```bash
# Install Tekton Pipelines
kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# Wait for Tekton to be ready (takes 1-2 minutes)
kubectl wait --for=condition=ready pod --all -n tekton-pipelines --timeout=300s

# Verify installation
kubectl get pods -n tekton-pipelines

# Should show pods running:
# tekton-pipelines-controller-xxx   1/1   Running
# tekton-pipelines-webhook-xxx      1/1   Running
```

### **Install Tekton CLI (Optional but Helpful)**

```bash
# macOS
brew install tektoncd-cli

# Linux
# Download from: https://github.com/tektoncd/cli/releases
# Or use: go install github.com/tektoncd/cli/cmd/tkn@latest

# Verify installation
tkn version
```

---

## 🚀 Step 3: Create a Simple Test Project

### **Create a Simple Dockerfile**

```bash
# Create a new directory for our test project
mkdir tekton-tutorial
cd tekton-tutorial

# Create a simple Dockerfile
cat > Dockerfile <<EOF
FROM nginx:alpine

# Add a simple HTML page
RUN echo '<h1>Hello from Tekton Pipeline!</h1><p>Tag: ${TAG}</p>' > /usr/share/nginx/html/index.html

# Expose port 80
EXPOSE 80
EOF

# Create a simple README
cat > README.md <<EOF
# Tekton Tutorial Project

This is a simple project to test Tekton pipelines.
EOF
```

### **Initialize Git Repository**

```bash
# Initialize git
git init

# Add files
git add Dockerfile README.md

# Create initial commit
git commit -m "Initial commit"

# Add your GitHub repository as remote
# Replace with your actual GitHub repo URL
git remote add origin https://github.com/YOUR_USERNAME/tekton-tutorial.git

# Push to GitHub
git push -u origin main
```

---

## 🚀 Step 4: Create Tekton Pipeline

### **Create Pipeline YAML**

```bash
# Create pipeline directory
mkdir -p tekton

# Create pipeline.yaml
cat > tekton/pipeline.yaml <<'EOF'
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: build-and-push-pipeline
spec:
  params:
    - name: git-tag
      description: Git tag that triggered the pipeline
    - name: image-name
      description: Docker image name
    - name: image-tag
      description: Docker image tag
    - name: dockerhub-username
      description: DockerHub username
    - name: dockerhub-password
      description: DockerHub password (secret)
  
  tasks:
    # Task 1: Clone the repository
    - name: git-clone
      taskRef:
        name: git-clone
      params:
        - name: url
          value: https://github.com/YOUR_USERNAME/tekton-tutorial.git
        - name: revision
          value: $(params.git-tag)
        - name: subdirectory
          value: ""
    
    # Task 2: Build Docker image
    - name: build-image
      taskRef:
        name: buildah
      params:
        - name: IMAGE
          value: $(params.dockerhub-username)/$(params.image-name):$(params.image-tag)
        - name: DOCKERFILE
          value: Dockerfile
        - name: CONTEXT
          value: $(workspaces.source.path)
      workspaces:
        - name: source
          workspace: shared-workspace
      runAfter:
        - git-clone
    
    # Task 3: Push to DockerHub
    - name: push-image
      taskRef:
        name: buildah
      params:
        - name: IMAGE
          value: $(params.dockerhub-username)/$(params.image-name):$(params.image-tag)
        - name: DOCKERFILE
          value: Dockerfile
        - name: CONTEXT
          value: $(workspaces.source.path)
        - name: STORAGE_DRIVER
          value: vfs
      workspaces:
        - name: source
          workspace: shared-workspace
      runAfter:
        - build-image
  
  workspaces:
    - name: shared-workspace
      description: Shared workspace for all tasks
EOF
```

**⚠️ Important:** Replace `YOUR_USERNAME` with your GitHub username in the pipeline.yaml file!

### **Install Required Tekton Tasks**

```bash
# Install git-clone task
kubectl apply -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/git-clone/0.9/git-clone.yaml

# Install buildah task (for building Docker images)
kubectl apply -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/buildah/0.6/buildah.yaml

# Verify tasks are installed
kubectl get tasks

# Should show:
# NAME        AGE
# buildah     1m
# git-clone   1m
```

### **Create Service Account for DockerHub**

```bash
# Create service account
cat > tekton/serviceaccount.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tekton-pipeline-sa
---
apiVersion: v1
kind: Secret
metadata:
  name: dockerhub-secret
  annotations:
    tekton.dev/docker-0: https://index.docker.io/v1/
type: kubernetes.io/basic-auth
stringData:
  username: YOUR_DOCKERHUB_USERNAME
  password: YOUR_DOCKERHUB_PASSWORD
---
apiVersion: v1
kind: Secret
metadata:
  name: github-secret
type: kubernetes.io/basic-auth
stringData:
  username: YOUR_GITHUB_USERNAME
  password: YOUR_GITHUB_TOKEN
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tekton-pipeline-sa
secrets:
  - name: dockerhub-secret
  - name: github-secret
EOF
```

**⚠️ Important:** Replace:
- `YOUR_DOCKERHUB_USERNAME` with your DockerHub username
- `YOUR_DOCKERHUB_PASSWORD` with your DockerHub password (or access token)
- `YOUR_GITHUB_USERNAME` with your GitHub username
- `YOUR_GITHUB_TOKEN` with a GitHub personal access token

**To create GitHub token:**
1. Go to GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Click "Generate new token"
3. Give it a name (e.g., "Tekton Tutorial")
4. Select scopes: `repo` (for private repos) or `public_repo` (for public repos)
5. Click "Generate token"
6. Copy the token (you won't see it again!)

### **Apply Service Account**

```bash
# Apply service account
kubectl apply -f tekton/serviceaccount.yaml

# Verify
kubectl get serviceaccount tekton-pipeline-sa
kubectl get secret dockerhub-secret
kubectl get secret github-secret
```

### **Update Pipeline to Use Service Account**

```bash
# Update pipeline.yaml to include service account
# We'll create a PipelineRun that uses the service account
```

### **Create PipelineRun Template**

```bash
cat > tekton/pipelinerun-template.yaml <<'EOF'
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: build-and-push-
spec:
  pipelineRef:
    name: build-and-push-pipeline
  serviceAccountName: tekton-pipeline-sa
  params:
    - name: git-tag
      value: "v1.0.0"  # Default tag, will be overridden
    - name: image-name
      value: "tekton-tutorial"
    - name: image-tag
      value: "v1.0.0"  # Default tag, will be overridden
    - name: dockerhub-username
      value: "YOUR_DOCKERHUB_USERNAME"
    - name: dockerhub-password
      value: ""  # Will use secret instead
  workspaces:
    - name: shared-workspace
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 1Gi
EOF
```

**⚠️ Important:** Replace `YOUR_DOCKERHUB_USERNAME` with your DockerHub username!

### **Apply Pipeline**

```bash
# Apply pipeline
kubectl apply -f tekton/pipeline.yaml

# Verify
kubectl get pipeline

# Should show:
# NAME                      AGE
# build-and-push-pipeline   1m
```

---

## 🚀 Step 5: Test Pipeline Manually

### **Test with a Simple PipelineRun**

```bash
# Create a test PipelineRun
cat > tekton/test-pipelinerun.yaml <<EOF
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  name: test-build-and-push
spec:
  pipelineRef:
    name: build-and-push-pipeline
  serviceAccountName: tekton-pipeline-sa
  params:
    - name: git-tag
      value: "main"  # Use main branch for testing
    - name: image-name
      value: "tekton-tutorial"
    - name: image-tag
      value: "test-$(date +%s)"  # Unique tag
    - name: dockerhub-username
      value: "YOUR_DOCKERHUB_USERNAME"
    - name: dockerhub-password
      value: ""
  workspaces:
    - name: shared-workspace
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 1Gi
EOF

# Replace YOUR_DOCKERHUB_USERNAME
sed -i '' 's/YOUR_DOCKERHUB_USERNAME/your-actual-username/g' tekton/test-pipelinerun.yaml

# Apply and run
kubectl apply -f tekton/test-pipelinerun.yaml

# Watch the pipeline run
tkn pipelinerun logs test-build-and-push -f

# Or without tkn CLI:
kubectl get pipelineruns
kubectl get pods
kubectl logs <pod-name> -c step-build
```

### **Check Pipeline Status**

```bash
# List pipeline runs
kubectl get pipelineruns

# Describe pipeline run
kubectl describe pipelinerun test-build-and-push

# Check pods
kubectl get pods

# View logs
kubectl logs <pod-name> -c step-build
```

---

## 🚀 Step 6: Set Up GitHub Webhook (Local)

For local testing, we'll use a simple approach: **ngrok** to expose a local webhook server.

### **Option A: Use ngrok (Easiest)**

1. **Install ngrok:**
   ```bash
   # macOS
   brew install ngrok
   
   # Or download from: https://ngrok.com/download
   ```

2. **Start ngrok:**
   ```bash
   # This will expose port 8080 to the internet
   ngrok http 8080
   ```

3. **Copy the ngrok URL** (e.g., `https://abc123.ngrok.io`)

### **Option B: Use a Simple Webhook Server**

Create a simple webhook server that triggers the pipeline:

```bash
# Create webhook server script
cat > webhook-server.py <<'EOF'
#!/usr/bin/env python3
import http.server
import json
import subprocess
import sys
from urllib.parse import urlparse, parse_qs

class WebhookHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        
        try:
            data = json.loads(post_data.decode('utf-8'))
            
            # Check if it's a tag push
            ref = data.get('ref', '')
            if ref.startswith('refs/tags/'):
                tag = ref.replace('refs/tags/', '')
                print(f"Tag detected: {tag}")
                
                # Trigger pipeline
                self.trigger_pipeline(tag)
                
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'status': 'success', 'tag': tag}).encode())
            else:
                print(f"Ignoring non-tag push: {ref}")
                self.send_response(200)
                self.end_headers()
        except Exception as e:
            print(f"Error: {e}")
            self.send_response(500)
            self.end_headers()
    
    def trigger_pipeline(self, tag):
        """Create a PipelineRun for the tag"""
        pipelinerun_yaml = f"""
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  name: build-and-push-{tag.replace('.', '-')}
spec:
  pipelineRef:
    name: build-and-push-pipeline
  serviceAccountName: tekton-pipeline-sa
  params:
    - name: git-tag
      value: "{tag}"
    - name: image-name
      value: "tekton-tutorial"
    - name: image-tag
      value: "{tag}"
    - name: dockerhub-username
      value: "YOUR_DOCKERHUB_USERNAME"
    - name: dockerhub-password
      value: ""
  workspaces:
    - name: shared-workspace
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 1Gi
"""
        # Write to file
        with open(f'/tmp/pipelinerun-{tag}.yaml', 'w') as f:
            f.write(pipelinerun_yaml)
        
        # Apply using kubectl
        subprocess.run(['kubectl', 'apply', '-f', f'/tmp/pipelinerun-{tag}.yaml'])
        print(f"Pipeline triggered for tag: {tag}")

if __name__ == '__main__':
    port = 8080
    server = http.server.HTTPServer(('', port), WebhookHandler)
    print(f"Webhook server running on port {port}")
    print(f"Use ngrok to expose: ngrok http {port}")
    server.serve_forever()
EOF

# Make executable
chmod +x webhook-server.py

# Install Python if needed (usually pre-installed on macOS/Linux)
# python3 --version

# Start webhook server
python3 webhook-server.py
```

**⚠️ Important:** Replace `YOUR_DOCKERHUB_USERNAME` in the webhook-server.py file!

### **Configure GitHub Webhook**

1. **Go to your GitHub repository**
2. **Click Settings** → **Webhooks**
3. **Click "Add webhook"**
4. **Payload URL:** `https://YOUR_NGROK_URL.ngrok.io` (from ngrok)
5. **Content type:** `application/json`
6. **Events:** Select **"Just the push event"**
7. **Click "Add webhook"**

---

## 🚀 Step 7: Test the Complete Flow

### **Create a Tag in GitHub**

```bash
# In your project directory
cd tekton-tutorial

# Create a tag
git tag v1.0.0

# Push the tag
git push origin v1.0.0
```

### **Watch the Pipeline Trigger**

```bash
# In another terminal, watch for new pipeline runs
watch -n 2 'kubectl get pipelineruns'

# Or watch pods
watch -n 2 'kubectl get pods'

# Or use tkn CLI
tkn pipelinerun list
tkn pipelinerun logs <pipelinerun-name> -f
```

### **Check DockerHub**

1. Go to DockerHub: https://hub.docker.com
2. Check your repository
3. You should see the new image: `your-username/tekton-tutorial:v1.0.0`

### **Test the Image**

```bash
# Pull and run the image
docker pull YOUR_DOCKERHUB_USERNAME/tekton-tutorial:v1.0.0
docker run -p 8080:80 YOUR_DOCKERHUB_USERNAME/tekton-tutorial:v1.0.0

# Visit http://localhost:8080 in your browser
# You should see: "Hello from Tekton Pipeline! Tag: v1.0.0"
```

---

## 🔍 Troubleshooting

### **Problem: Pipeline Not Starting**

**Check 1: Verify Pipeline is Installed**
```bash
kubectl get pipeline
```

**Check 2: Check Service Account**
```bash
kubectl get serviceaccount tekton-pipeline-sa
kubectl describe serviceaccount tekton-pipeline-sa
```

**Check 3: Check PipelineRun**
```bash
kubectl get pipelineruns
kubectl describe pipelinerun <name>
```

### **Problem: Build Fails**

**Check 1: View Pod Logs**
```bash
kubectl get pods
kubectl logs <pod-name> -c step-build
```

**Check 2: Check DockerHub Credentials**
```bash
kubectl get secret dockerhub-secret
kubectl describe secret dockerhub-secret
```

**Check 3: Test DockerHub Login Manually**
```bash
docker login -u YOUR_DOCKERHUB_USERNAME
# Enter password when prompted
```

### **Problem: Webhook Not Receiving Events**

**Check 1: Verify ngrok is Running**
```bash
# Check ngrok status
curl http://localhost:4040/api/tunnels
```

**Check 2: Check Webhook Server Logs**
```bash
# Look at the webhook-server.py output
# It should show incoming requests
```

**Check 3: Check GitHub Webhook Delivery**
1. Go to GitHub → Settings → Webhooks
2. Click on your webhook
3. Check "Recent Deliveries"
4. Look for failed deliveries

### **Problem: Image Not Pushing to DockerHub**

**Check 1: Verify Buildah Task**
```bash
kubectl get task buildah
kubectl describe task buildah
```

**Check 2: Check Push Task Logs**
```bash
kubectl logs <pod-name> -c step-push
```

**Check 3: Verify Image Name Format**
- Should be: `username/repository:tag`
- Example: `myuser/tekton-tutorial:v1.0.0`

---

## 📊 Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    YOU CREATE TAG                                │
│                                                                   │
│  $ git tag v1.0.0                                                │
│  $ git push origin v1.0.0                                       │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│              GITHUB RECEIVES TAG                                 │
│                                                                   │
│  GitHub: "Tag v1.0.0 was pushed!"                                │
│  GitHub: "I need to send webhook to ngrok URL"                  │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│              NGROK RECEIVES WEBHOOK                              │
│                                                                   │
│  ngrok: "Forwarding to localhost:8080"                           │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│        WEBHOOK SERVER RECEIVES REQUEST                           │
│                                                                   │
│  webhook-server.py:                                             │
│  - Parses JSON payload                                           │
│  - Extracts tag: "v1.0.0"                                        │
│  - Creates PipelineRun YAML                                     │
│  - Runs: kubectl apply -f pipelinerun.yaml                       │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│        TEKTON PIPELINE STARTS                                    │
│                                                                   │
│  Task 1: git-clone                                               │
│    - Clones repository                                           │
│    - Checks out tag v1.0.0                                       │
│                                                                   │
│  Task 2: build-image                                            │
│    - Builds Docker image                                        │
│    - Tags: username/tekton-tutorial:v1.0.0                      │
│                                                                   │
│  Task 3: push-image                                             │
│    - Pushes to DockerHub                                        │
│    - Image available at: hub.docker.com/...                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🎯 Summary

**What We Built:**
1. ✅ Local Kubernetes cluster (Docker Desktop or Minikube)
2. ✅ Tekton Pipelines installed
3. ✅ Pipeline that builds Docker images
4. ✅ Pipeline that pushes to DockerHub
5. ✅ Webhook server that triggers on GitHub tags
6. ✅ Complete CI/CD flow from tag to deployed image

**Key Files:**
- `tekton/pipeline.yaml` - Pipeline definition
- `tekton/serviceaccount.yaml` - Service account with secrets
- `webhook-server.py` - Webhook server
- `Dockerfile` - Simple test application

**Commands to Remember:**
```bash
# Watch pipeline runs
kubectl get pipelineruns -w

# View pipeline logs
tkn pipelinerun logs <name> -f

# Check pods
kubectl get pods

# View pod logs
kubectl logs <pod-name> -c step-build
```

**Next Steps:**
- Customize the Dockerfile for your project
- Add more pipeline tasks (tests, security scans, etc.)
- Deploy the image to a Kubernetes cluster
- Add notifications (Slack, email, etc.)

---

## 📚 Additional Resources

- **Tekton Documentation:** https://tekton.dev/docs/
- **Tekton Catalog:** https://github.com/tektoncd/catalog
- **DockerHub:** https://hub.docker.com
- **ngrok:** https://ngrok.com/

---

## ✅ Quick Checklist

- [ ] Docker Desktop with Kubernetes enabled
- [ ] Tekton Pipelines installed
- [ ] GitHub repository created
- [ ] DockerHub account created
- [ ] Service account with secrets configured
- [ ] Pipeline created and applied
- [ ] Webhook server running
- [ ] ngrok tunnel active
- [ ] GitHub webhook configured
- [ ] Test tag created and pushed
- [ ] Pipeline executed successfully
- [ ] Image pushed to DockerHub
- [ ] Image tested locally

**Congratulations! You now have a working Tekton pipeline! 🎉**

