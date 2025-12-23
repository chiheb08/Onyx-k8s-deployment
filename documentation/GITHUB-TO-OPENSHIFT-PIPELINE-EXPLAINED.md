# How GitHub Tags Trigger OpenShift Pipelines - Explained Simply

## 🎯 Overview

When you create a tag in GitHub, it automatically triggers a pipeline in OpenShift. This guide explains **how this connection works** in simple terms.

---

## 🔗 The Connection: GitHub ↔ OpenShift

There are **three main ways** GitHub tags can trigger OpenShift pipelines:

1. **GitHub Webhooks** → OpenShift Pipeline (Most Common)
2. **GitHub Actions** → OpenShift API
3. **Tekton Pipelines** with GitHub Integration

---

## 📊 Method 1: GitHub Webhooks → OpenShift Pipeline (Most Common)

### **How It Works - Simple Explanation**

```
┌─────────────────────────────────────────────────────────────────┐
│                    YOU CREATE A TAG                             │
│                                                                   │
│  git tag v1.2.3                                                  │
│  git push origin v1.2.3                                         │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    GITHUB RECEIVES TAG                          │
│                                                                   │
│  GitHub detects: "A new tag was pushed!"                        │
│  GitHub triggers: Webhook event                                  │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    GITHUB SENDS WEBHOOK                          │
│                                                                   │
│  POST https://openshift-cluster.com/webhook/github              │
│  Headers:                                                        │
│    X-GitHub-Event: push                                          │
│    X-GitHub-Delivery: <unique-id>                               │
│  Body:                                                           │
│    {                                                             │
│      "ref": "refs/tags/v1.2.3",                                 │
│      "repository": { "name": "onyx", ... },                     │
│      "pusher": { "name": "your-name" },                         │
│      ...                                                         │
│    }                                                             │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│              OPENSHIFT RECEIVES WEBHOOK                          │
│                                                                   │
│  OpenShift Webhook Handler:                                      │
│  - Validates webhook signature                                   │
│  - Checks if event is a tag push                                 │
│  - Extracts tag name (v1.2.3)                                    │
│  - Triggers pipeline                                             │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│              OPENSHIFT PIPELINE STARTS                          │
│                                                                   │
│  Pipeline Steps:                                                 │
│  1. Checkout code from GitHub                                   │
│  2. Build Docker images                                         │
│  3. Push images to registry                                     │
│  4. Deploy to OpenShift                                         │
│  5. Run tests                                                   │
│  6. Update deployment                                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔧 Step-by-Step Setup (How Your Colleague Did It)

### **Step 1: Create OpenShift Pipeline**

Your colleague created a **Tekton Pipeline** in OpenShift:

```yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: onyx-deployment-pipeline
spec:
  params:
    - name: git-tag
      description: Git tag to deploy
    - name: image-tag
      description: Docker image tag
  
  tasks:
    - name: checkout-code
      taskRef:
        name: git-clone
      params:
        - name: url
          value: https://github.com/your-org/onyx.git
        - name: revision
          value: $(params.git-tag)  # Uses the tag you pushed
    
    - name: build-image
      taskRef:
        name: buildah
      params:
        - name: IMAGE
          value: registry.example.com/onyx:$(params.image-tag)
    
    - name: deploy-to-openshift
      taskRef:
        name: oc-deploy
      params:
        - name: IMAGE
          value: registry.example.com/onyx:$(params.image-tag)
```

### **Step 2: Create PipelineRun Trigger**

Your colleague created a **Trigger** that listens for GitHub webhooks:

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: github-tag-trigger-template
spec:
  params:
    - name: git-tag
      description: Git tag from webhook
  resourcetemplates:
    - apiVersion: tekton.dev/v1beta1
      kind: PipelineRun
      metadata:
        generateName: onyx-deploy-
      spec:
        pipelineRef:
          name: onyx-deployment-pipeline
        params:
          - name: git-tag
            value: $(params.git-tag)
          - name: image-tag
            value: $(params.git-tag)  # Use tag as image tag
```

### **Step 3: Configure GitHub Webhook**

Your colleague configured GitHub to send webhooks to OpenShift:

**In GitHub Repository Settings:**
1. Go to **Settings** → **Webhooks**
2. Click **Add webhook**
3. **Payload URL**: `https://your-openshift-cluster.com/webhook/github`
4. **Content type**: `application/json`
5. **Events**: Select **"Just the push event"** or **"Let me select individual events"** → **Pushes**
6. **Secret**: (Optional) Shared secret for security

**What GitHub Sends:**
```json
{
  "ref": "refs/tags/v1.2.3",
  "repository": {
    "name": "onyx",
    "full_name": "your-org/onyx"
  },
  "pusher": {
    "name": "your-name"
  },
  "head_commit": {
    "id": "abc123...",
    "message": "Release v1.2.3"
  }
}
```

### **Step 4: Configure OpenShift to Receive Webhooks**

Your colleague configured OpenShift **EventListener**:

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: github-webhook-listener
spec:
  serviceAccountName: tekton-triggers-sa
  triggers:
    - name: github-tag-trigger
      interceptors:
        - name: "filter-tags"
          ref:
            name: cel
            kind: ClusterInterceptor
          params:
            - name: filter
              value: |
                body.ref.startsWith('refs/tags/')
      bindings:
        - ref: github-tag-binding
      template:
        ref: github-tag-trigger-template
```

**What This Does:**
- **EventListener**: Listens for incoming webhooks
- **Interceptor**: Filters to only process tag pushes (not branch pushes)
- **Binding**: Extracts tag name from webhook payload
- **Template**: Creates PipelineRun with tag name

---

## 📊 Method 2: GitHub Actions → OpenShift API

### **How It Works**

Instead of webhooks, GitHub Actions can directly call OpenShift API:

```yaml
# .github/workflows/deploy-to-openshift.yml
name: Deploy to OpenShift

on:
  push:
    tags:
      - 'v*'  # Triggers on tags starting with 'v'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Extract tag name
        id: tag
        run: echo "TAG_NAME=${GITHUB_REF#refs/tags/}" >> $GITHUB_OUTPUT
      
      - name: Trigger OpenShift Pipeline
        run: |
          oc start-build onyx-pipeline \
            --follow \
            --env TAG_NAME=${{ steps.tag.outputs.TAG_NAME }}
```

**What This Does:**
- GitHub Actions detects tag push
- Extracts tag name
- Calls OpenShift API (`oc start-build`)
- Triggers OpenShift pipeline

---

## 📊 Method 3: Tekton Pipelines with GitHub Integration

### **How It Works**

OpenShift Pipelines (Tekton) can be configured to watch GitHub:

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: github-tag-binding
spec:
  params:
    - name: git-tag
      value: $(body.ref)
    - name: git-repo-url
      value: $(body.repository.clone_url)
    - name: git-commit-sha
      value: $(body.head_commit.id)
```

**What This Does:**
- **TriggerBinding**: Maps webhook data to pipeline parameters
- Extracts tag name from `body.ref` (e.g., `refs/tags/v1.2.3`)
- Passes tag to pipeline as parameter

---

## 🔍 How to Check What Your Colleague Set Up

### **1. Check OpenShift Pipelines**

```bash
# List all pipelines
oc get pipelines

# View pipeline details
oc describe pipeline onyx-deployment-pipeline

# Check pipeline runs
oc get pipelineruns
```

### **2. Check GitHub Webhooks**

1. Go to your GitHub repository
2. Click **Settings** → **Webhooks**
3. Look for webhook pointing to OpenShift cluster
4. Check **Recent Deliveries** to see webhook activity

### **3. Check OpenShift EventListeners**

```bash
# List event listeners
oc get eventlisteners

# View event listener details
oc describe eventlistener github-webhook-listener

# Check event listener logs
oc logs -l eventlistener=github-webhook-listener
```

### **4. Check Trigger Templates**

```bash
# List trigger templates
oc get triggertemplates

# View trigger template
oc describe triggertemplate github-tag-trigger-template
```

---

## 🎯 Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    YOU CREATE TAG                                │
│                                                                   │
│  $ git tag v1.2.3                                                │
│  $ git push origin v1.2.3                                        │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│              GITHUB RECEIVES TAG PUSH                            │
│                                                                   │
│  GitHub: "Tag v1.2.3 was pushed!"                               │
│  GitHub: "I need to notify OpenShift"                            │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│              GITHUB SENDS WEBHOOK                                │
│                                                                   │
│  POST https://openshift-cluster.com/webhook/github              │
│  Body: { "ref": "refs/tags/v1.2.3", ... }                       │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│        OPENSHIFT EVENTLISTENER RECEIVES WEBHOOK                 │
│                                                                   │
│  EventListener: "I received a webhook!"                         │
│  EventListener: "Let me check if it's a tag..."                 │
│  Interceptor: "Yes, refs/tags/v1.2.3 - it's a tag!"            │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│        TRIGGERBINDING EXTRACTS TAG NAME                          │
│                                                                   │
│  TriggerBinding: "Extracting tag name..."                       │
│  Result: git-tag = "v1.2.3"                                     │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│        TRIGGERTEMPLATE CREATES PIPELINERUN                       │
│                                                                   │
│  TriggerTemplate: "Creating PipelineRun..."                    │
│  PipelineRun:                                                    │
│    - name: onyx-deploy-abc123                                    │
│    - params: git-tag=v1.2.3                                     │
│    - pipelineRef: onyx-deployment-pipeline                       │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│              PIPELINE STARTS EXECUTING                          │
│                                                                   │
│  Task 1: checkout-code                                          │
│    - Clones repo                                                │
│    - Checks out tag v1.2.3                                      │
│                                                                   │
│  Task 2: build-image                                            │
│    - Builds Docker image                                        │
│    - Tags as: registry.com/onyx:v1.2.3                          │
│                                                                   │
│  Task 3: push-image                                             │
│    - Pushes to registry                                         │
│                                                                   │
│  Task 4: deploy-to-openshift                                   │
│    - Updates deployment                                         │
│    - Uses image: registry.com/onyx:v1.2.3                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔐 Security Considerations

### **1. Webhook Secret**

GitHub webhooks can include a **secret** for security:

```yaml
# In EventListener
spec:
  triggers:
    - name: github-tag-trigger
      interceptors:
        - name: "validate-webhook"
          ref:
            name: github
            kind: ClusterInterceptor
          params:
            - name: secretRef
              value:
                secretName: github-webhook-secret
                secretKey: secret
```

**What This Does:**
- Validates webhook signature
- Ensures webhook came from GitHub
- Prevents unauthorized pipeline triggers

### **2. Service Account Permissions**

The EventListener needs a service account with permissions:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tekton-triggers-sa
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tekton-triggers-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: tekton-triggers-eventlistener-roles
subjects:
  - kind: ServiceAccount
    name: tekton-triggers-sa
```

---

## 🧪 Testing the Setup

### **Test 1: Create a Test Tag**

```bash
# Create a test tag
git tag test-tag-1.0.0

# Push the tag
git push origin test-tag-1.0.0
```

### **Test 2: Check Webhook Delivery**

1. Go to GitHub → Settings → Webhooks
2. Click on your webhook
3. Check **Recent Deliveries**
4. Look for your tag push event

### **Test 3: Check Pipeline Run**

```bash
# Watch for new pipeline runs
oc get pipelineruns -w

# Check pipeline run logs
oc logs pipelinerun/onyx-deploy-abc123
```

---

## 🐛 Troubleshooting

### **Problem: Pipeline Not Triggering**

**Check 1: Webhook Configuration**
```bash
# Check if webhook is configured in GitHub
# Go to: GitHub → Settings → Webhooks
# Verify webhook URL is correct
```

**Check 2: EventListener Status**
```bash
# Check EventListener is running
oc get pods -l eventlistener=github-webhook-listener

# Check EventListener logs
oc logs -l eventlistener=github-webhook-listener
```

**Check 3: Webhook Delivery**
```bash
# In GitHub, check webhook "Recent Deliveries"
# Look for failed deliveries
# Check response codes (should be 200 OK)
```

### **Problem: Pipeline Triggers But Fails**

**Check Pipeline Run:**
```bash
# Get pipeline run status
oc get pipelinerun

# Describe pipeline run
oc describe pipelinerun onyx-deploy-abc123

# Check task logs
oc logs pipelinerun/onyx-deploy-abc123 -c step-checkout-code
```

---

## 📋 Summary

**How GitHub Tags Trigger OpenShift Pipelines:**

1. **You create a tag** → `git tag v1.2.3 && git push origin v1.2.3`

2. **GitHub detects tag push** → Triggers webhook event

3. **GitHub sends webhook** → POST request to OpenShift webhook URL

4. **OpenShift EventListener receives webhook** → Validates and processes

5. **TriggerBinding extracts tag name** → Gets "v1.2.3" from webhook payload

6. **TriggerTemplate creates PipelineRun** → Starts pipeline with tag parameter

7. **Pipeline executes** → Builds, tests, and deploys using the tag

**Key Components:**
- **GitHub Webhook**: Sends events to OpenShift
- **EventListener**: Receives webhooks in OpenShift
- **TriggerBinding**: Extracts data from webhook
- **TriggerTemplate**: Creates PipelineRun
- **Pipeline**: Defines build/deploy steps

**That's it!** When you push a tag, OpenShift automatically builds and deploys it! 🚀

