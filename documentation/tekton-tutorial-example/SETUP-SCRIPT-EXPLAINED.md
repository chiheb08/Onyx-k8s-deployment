# Setup Script Explained - Detailed Breakdown

This document explains every part of the `setup.sh` script in detail.

---

## 📋 Script Overview

The `setup.sh` script automates the entire setup process for the Tekton Pipeline tutorial. It:
1. Checks prerequisites
2. Installs Tekton Pipelines
3. Installs required Tekton tasks
4. Asks for your credentials
5. Updates configuration files
6. Applies everything to Kubernetes

---

## 🔍 Line-by-Line Explanation

### **Lines 1-5: Script Header**

```bash
#!/bin/bash
# Setup script for Tekton Pipeline Tutorial
# This script helps you set up the tutorial quickly

set -e
```

**Explanation:**
- `#!/bin/bash` - **Shebang line**: Tells the system to use bash to run this script
- `# Setup script...` - **Comments**: Documentation for humans
- `set -e` - **Error handling**: If any command fails, the script stops immediately (prevents continuing with errors)

**Why `set -e`?**
- If a prerequisite check fails, we don't want to continue
- Prevents partial setup that could cause confusion

---

### **Lines 7-10: Welcome Message**

```bash
echo "=========================================="
echo "🚀 Tekton Pipeline Tutorial Setup"
echo "=========================================="
echo ""
```

**Explanation:**
- `echo` - Prints text to the terminal
- Creates a nice header to show the script has started
- Empty `echo ""` adds a blank line for readability

---

### **Lines 12-16: Color Definitions**

```bash
# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
```

**Explanation:**
- Defines color codes for terminal output
- `RED` - For error messages (❌)
- `GREEN` - For success messages (✅)
- `YELLOW` - For warnings (⚠️)
- `NC` - Resets color back to normal

**Example usage:**
```bash
echo -e "${GREEN}✅ Success${NC}"  # Prints green "✅ Success"
echo -e "${RED}❌ Error${NC}"      # Prints red "❌ Error"
```

---

### **Lines 18-27: Check kubectl**

```bash
# Check prerequisites
echo "📋 Checking prerequisites..."

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl is not installed${NC}"
    echo "   Install kubectl: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi
echo -e "${GREEN}✅ kubectl is installed${NC}"
```

**Explanation:**
- `command -v kubectl` - Checks if `kubectl` command exists
- `&> /dev/null` - Hides output (we only care if it exists, not what it prints)
- `!` - Negates the result (if command NOT found)
- `if ... then ... fi` - Conditional statement
- `exit 1` - Stops script with error code 1 if kubectl is missing

**What it does:**
- Checks if kubectl is installed
- If not found: Shows error and stops script
- If found: Shows success message and continues

---

### **Lines 29-35: Check Docker**

```bash
# Check if Docker is running
if ! docker info &> /dev/null; then
    echo -e "${RED}❌ Docker is not running${NC}"
    echo "   Please start Docker Desktop"
    exit 1
fi
echo -e "${GREEN}✅ Docker is running${NC}"
```

**Explanation:**
- `docker info` - Gets Docker system information
- If this command fails, Docker is not running
- Same pattern as kubectl check

**What it does:**
- Checks if Docker daemon is accessible
- If not: Shows error and stops
- If yes: Shows success and continues

---

### **Lines 37-44: Check Kubernetes**

```bash
# Check if Kubernetes is enabled
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Kubernetes cluster is not accessible${NC}"
    echo "   Please enable Kubernetes in Docker Desktop:"
    echo "   Docker Desktop → Settings → Kubernetes → Enable"
    exit 1
fi
echo -e "${GREEN}✅ Kubernetes cluster is accessible${NC}"
```

**Explanation:**
- `kubectl cluster-info` - Gets Kubernetes cluster information
- If this fails, Kubernetes is not running or not accessible
- Provides helpful instructions if it fails

**What it does:**
- Checks if Kubernetes cluster is accessible
- If not: Shows error with instructions
- If yes: Shows success and continues

---

### **Lines 46-56: Install Tekton Pipelines**

```bash
# Check if Tekton is installed
if ! kubectl get namespace tekton-pipelines &> /dev/null; then
    echo -e "${YELLOW}⚠️  Tekton Pipelines not installed${NC}"
    echo "   Installing Tekton Pipelines..."
    kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
    echo "   Waiting for Tekton to be ready..."
    kubectl wait --for=condition=ready pod --all -n tekton-pipelines --timeout=300s || true
    echo -e "${GREEN}✅ Tekton Pipelines installed${NC}"
else
    echo -e "${GREEN}✅ Tekton Pipelines is installed${NC}"
fi
```

**Explanation:**
- `kubectl get namespace tekton-pipelines` - Checks if Tekton namespace exists
- If namespace doesn't exist, Tekton is not installed
- `kubectl apply --filename ...` - Downloads and applies Tekton YAML from internet
- `kubectl wait ...` - Waits for Tekton pods to be ready (up to 5 minutes)
- `|| true` - If wait fails, continue anyway (some pods might take longer)

**What it does:**
- Checks if Tekton is already installed
- If not: Downloads and installs Tekton Pipelines
- Waits for installation to complete
- Shows success message

**Why check first?**
- Avoids reinstalling if already installed
- Saves time on subsequent runs

---

### **Lines 58-72: Install Tekton Tasks**

```bash
# Check if required tasks are installed
echo ""
echo "📦 Checking required Tekton tasks..."

if ! kubectl get task git-clone &> /dev/null; then
    echo "   Installing git-clone task..."
    kubectl apply -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/git-clone/0.9/git-clone.yaml
fi
echo -e "${GREEN}✅ git-clone task installed${NC}"

if ! kubectl get task buildah &> /dev/null; then
    echo "   Installing buildah task..."
    kubectl apply -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/buildah/0.6/buildah.yaml
fi
echo -e "${GREEN}✅ buildah task installed${NC}"
```

**Explanation:**
- Checks for two required Tekton tasks:
  - `git-clone` - For cloning Git repositories
  - `buildah` - For building Docker images
- Downloads from Tekton Catalog (official repository of tasks)
- Only installs if not already present

**What it does:**
- Checks if `git-clone` task exists
- If not: Downloads and installs it
- Checks if `buildah` task exists
- If not: Downloads and installs it
- Shows success for each

**Why these tasks?**
- `git-clone`: Pipeline needs to clone your GitHub repository
- `buildah`: Pipeline needs to build Docker images

---

### **Lines 74-87: Get User Credentials**

```bash
# Prompt for configuration
echo ""
echo "=========================================="
echo "⚙️  Configuration"
echo "=========================================="
echo ""

read -p "Enter your DockerHub username: " DOCKERHUB_USERNAME
read -sp "Enter your DockerHub password (or access token): " DOCKERHUB_PASSWORD
echo ""
read -p "Enter your GitHub username: " GITHUB_USERNAME
read -sp "Enter your GitHub personal access token: " GITHUB_TOKEN
echo ""
read -p "Enter your GitHub repository URL (e.g., https://github.com/username/repo.git): " GITHUB_REPO_URL
```

**Explanation:**
- `read -p "..."` - Prompts user and reads input
- `read -sp "..."` - Same, but `-s` hides input (for passwords)
- Stores input in variables:
  - `DOCKERHUB_USERNAME` - Your DockerHub username
  - `DOCKERHUB_PASSWORD` - Your DockerHub password/token
  - `GITHUB_USERNAME` - Your GitHub username
  - `GITHUB_TOKEN` - Your GitHub personal access token
  - `GITHUB_REPO_URL` - Your repository URL

**What it does:**
- Asks you to enter your credentials
- Hides passwords as you type (security)
- Stores them in variables for later use

**Why ask for these?**
- Needed to configure the pipeline
- DockerHub: To push Docker images
- GitHub: To clone repository and authenticate

---

### **Line 90: Extract Repository Name**

```bash
# Extract repo name from URL
GITHUB_REPO_NAME=$(basename "$GITHUB_REPO_URL" .git)
```

**Explanation:**
- `basename "$GITHUB_REPO_URL" .git` - Extracts filename from path, removes `.git` extension
- Example: `https://github.com/user/repo.git` → `repo`
- Stores in `GITHUB_REPO_NAME` variable (not used later, but could be useful)

**What it does:**
- Takes `https://github.com/user/repo.git`
- Extracts just `repo`
- Stores for potential future use

---

### **Lines 92-114: Update Configuration Files**

```bash
echo ""
echo "📝 Updating configuration files..."

# Update serviceaccount.yaml
sed -i.bak "s/YOUR_DOCKERHUB_USERNAME/$DOCKERHUB_USERNAME/g" serviceaccount.yaml
sed -i.bak "s/YOUR_DOCKERHUB_PASSWORD/$DOCKERHUB_PASSWORD/g" serviceaccount.yaml
sed -i.bak "s/YOUR_GITHUB_USERNAME/$GITHUB_USERNAME/g" serviceaccount.yaml
sed -i.bak "s/YOUR_GITHUB_TOKEN/$DOCKERHUB_PASSWORD/g" serviceaccount.yaml
rm -f serviceaccount.yaml.bak

# Update pipeline.yaml
sed -i.bak "s|YOUR_USERNAME/tekton-tutorial.git|$GITHUB_REPO_URL|g" pipeline.yaml
rm -f serviceaccount.yaml.bak

# Update test-pipelinerun.yaml
sed -i.bak "s/YOUR_DOCKERHUB_USERNAME/$DOCKERHUB_USERNAME/g" test-pipelinerun.yaml
rm -f test-pipelinerun.yaml.bak

# Update webhook-server.py
sed -i.bak "s/YOUR_DOCKERHUB_USERNAME/$DOCKERHUB_USERNAME/g" webhook-server.py
rm -f webhook-server.py.bak
```

**Explanation:**
- `sed` - Stream editor, used for text replacement
- `sed -i.bak "s/OLD/NEW/g" file` - Replaces OLD with NEW in file
  - `-i.bak` - Edits file in-place, creates backup with `.bak` extension
  - `s/OLD/NEW/g` - Substitute OLD with NEW globally (all occurrences)
  - `g` at end - Replace all occurrences, not just first
- `rm -f *.bak` - Removes backup files (cleanup)

**What it does:**
- Replaces placeholders in files with your actual credentials:
  - `serviceaccount.yaml` - Updates DockerHub and GitHub secrets
  - `pipeline.yaml` - Updates GitHub repository URL
  - `test-pipelinerun.yaml` - Updates DockerHub username
  - `webhook-server.py` - Updates DockerHub username

**Example:**
```bash
# Before:
username: YOUR_DOCKERHUB_USERNAME

# After (if you entered "myuser"):
username: myuser
```

**Why `.bak` files?**
- Safety: Creates backup before editing
- If something goes wrong, you can restore
- Script removes them after (cleanup)

---

### **Lines 116-124: Apply Tekton Resources**

```bash
# Apply Tekton resources
echo ""
echo "🚀 Applying Tekton resources..."

kubectl apply -f serviceaccount.yaml
echo -e "${GREEN}✅ Service account created${NC}"

kubectl apply -f pipeline.yaml
echo -e "${GREEN}✅ Pipeline created${NC}"
```

**Explanation:**
- `kubectl apply -f file.yaml` - Applies YAML configuration to Kubernetes
- Creates resources defined in the YAML files
- Shows success message after each

**What it does:**
1. Applies `serviceaccount.yaml`:
   - Creates service account
   - Creates secrets (DockerHub, GitHub credentials)
   - Links secrets to service account

2. Applies `pipeline.yaml`:
   - Creates Tekton Pipeline
   - Defines build and push steps

**Why apply these?**
- Service account: Pipeline needs credentials to access DockerHub and GitHub
- Pipeline: Defines what the pipeline does (clone, build, push)

---

### **Lines 126-148: Summary and Next Steps**

```bash
# Verify
echo ""
echo "=========================================="
echo "✅ Setup Complete!"
echo "=========================================="
echo ""
echo "📋 Summary:"
echo "   DockerHub username: $DOCKERHUB_USERNAME"
echo "   GitHub repository: $GITHUB_REPO_URL"
echo "   Pipeline name: build-and-push-pipeline"
echo ""
echo "🧪 To test the pipeline:"
echo "   1. kubectl apply -f test-pipelinerun.yaml"
echo "   2. kubectl get pipelineruns"
echo "   3. tkn pipelinerun logs test-build-and-push -f"
echo ""
echo "🌐 To start webhook server:"
echo "   1. python3 webhook-server.py"
echo "   2. In another terminal: ngrok http 8080"
echo "   3. Configure GitHub webhook with ngrok URL"
echo ""
echo "📚 For full tutorial, see: ../TEKTON-PIPELINE-LOCAL-TUTORIAL.md"
echo ""
```

**Explanation:**
- Shows summary of what was configured
- Provides next steps for testing
- Shows commands to run

**What it does:**
- Displays a nice summary
- Shows your configuration (for verification)
- Provides instructions for next steps

---

## 🔄 Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────┐
│  Script Starts                                          │
│  set -e (stop on error)                                 │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│  Check Prerequisites                                    │
│  ├─ kubectl installed?                                 │
│  ├─ Docker running?                                    │
│  └─ Kubernetes accessible?                             │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│  Install Tekton                                         │
│  ├─ Check if installed                                 │
│  ├─ If not: Download and install                        │
│  └─ Wait for pods to be ready                          │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│  Install Tekton Tasks                                   │
│  ├─ Check git-clone task                               │
│  ├─ Install if missing                                 │
│  ├─ Check buildah task                                 │
│  └─ Install if missing                                 │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│  Get User Credentials                                   │
│  ├─ DockerHub username                                 │
│  ├─ DockerHub password                                 │
│  ├─ GitHub username                                    │
│  ├─ GitHub token                                       │
│  └─ GitHub repo URL                                    │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│  Update Configuration Files                             │
│  ├─ serviceaccount.yaml (secrets)                      │
│  ├─ pipeline.yaml (repo URL)                            │
│  ├─ test-pipelinerun.yaml (username)                   │
│  └─ webhook-server.py (username)                       │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│  Apply to Kubernetes                                    │
│  ├─ kubectl apply serviceaccount.yaml                  │
│  └─ kubectl apply pipeline.yaml                        │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│  Show Summary and Next Steps                            │
│  └─ Display instructions                               │
└─────────────────────────────────────────────────────────┘
```

---

## 🎯 Key Concepts Explained

### **1. Error Handling (`set -e`)**

```bash
set -e
```

**What it does:**
- If any command returns non-zero exit code (fails), script stops
- Prevents continuing with errors

**Example:**
```bash
# Without set -e:
kubectl get nodes  # Fails
echo "Continuing..."  # Still runs (bad!)

# With set -e:
kubectl get nodes  # Fails
echo "Continuing..."  # Never runs (good!)
```

---

### **2. Command Substitution**

```bash
GITHUB_REPO_NAME=$(basename "$GITHUB_REPO_URL" .git)
```

**What it does:**
- `$(...)` - Runs command and captures output
- Stores result in variable

**Example:**
```bash
URL="https://github.com/user/repo.git"
NAME=$(basename "$URL" .git)
# NAME now contains "repo"
```

---

### **3. Text Replacement (sed)**

```bash
sed -i.bak "s/OLD/NEW/g" file.yaml
```

**What it does:**
- `s/OLD/NEW/` - Substitute OLD with NEW
- `g` - Global (all occurrences)
- `-i.bak` - Edit in-place, create backup

**Example:**
```bash
# File content:
username: YOUR_DOCKERHUB_USERNAME

# Command:
sed -i.bak "s/YOUR_DOCKERHUB_USERNAME/myuser/g" file.yaml

# File content after:
username: myuser

# Backup file created:
file.yaml.bak  # Original content
```

---

### **4. Conditional Checks**

```bash
if ! command -v kubectl &> /dev/null; then
    echo "Error"
    exit 1
fi
```

**What it does:**
- `command -v kubectl` - Checks if command exists
- `!` - Negates (if NOT found)
- `&> /dev/null` - Hides output
- If command not found: Show error and exit

---

### **5. Color Output**

```bash
echo -e "${GREEN}✅ Success${NC}"
```

**What it does:**
- `-e` - Enable escape sequences
- `${GREEN}` - Green color code
- `${NC}` - Reset to normal color
- Makes output more readable

---

## 🐛 Common Issues and How Script Handles Them

### **Issue 1: kubectl Not Installed**

**Script behavior:**
- Detects missing kubectl
- Shows error message
- Exits with code 1
- User must install kubectl first

---

### **Issue 2: Docker Not Running**

**Script behavior:**
- Detects Docker not accessible
- Shows error message
- Exits with code 1
- User must start Docker Desktop

---

### **Issue 3: Kubernetes Not Accessible**

**Script behavior:**
- Detects Kubernetes not accessible
- Shows helpful instructions
- Exits with code 1
- User must enable Kubernetes

---

### **Issue 4: Tekton Already Installed**

**Script behavior:**
- Detects Tekton namespace exists
- Skips installation
- Shows "already installed" message
- Continues (saves time)

---

## ✅ Summary

The `setup.sh` script:

1. **Checks prerequisites** - Makes sure everything needed is available
2. **Installs Tekton** - Downloads and installs if not present
3. **Installs tasks** - Gets required Tekton tasks
4. **Gets credentials** - Asks for your DockerHub and GitHub info
5. **Updates files** - Replaces placeholders with your credentials
6. **Applies to Kubernetes** - Creates service account and pipeline
7. **Shows next steps** - Tells you what to do next

**Why use the script?**
- ✅ Automates everything
- ✅ Handles errors gracefully
- ✅ Saves time (no manual configuration)
- ✅ Reduces mistakes (automated replacement)

**What you need to do:**
- Just run the script and answer the prompts!
- Everything else is automated.

---

## 📚 Related Files

- `serviceaccount.yaml` - Gets updated with your credentials
- `pipeline.yaml` - Gets updated with your repo URL
- `test-pipelinerun.yaml` - Gets updated with your username
- `webhook-server.py` - Gets updated with your username

All these files are automatically configured by the script!

