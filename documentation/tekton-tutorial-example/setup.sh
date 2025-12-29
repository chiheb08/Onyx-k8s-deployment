#!/bin/bash
# Setup script for Tekton Pipeline Tutorial
# This script helps you set up the tutorial quickly

set -e

echo "=========================================="
echo "🚀 Tekton Pipeline Tutorial Setup"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
echo "📋 Checking prerequisites..."

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl is not installed${NC}"
    echo "   Install kubectl: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi
echo -e "${GREEN}✅ kubectl is installed${NC}"

# Check if Docker is running
if ! docker info &> /dev/null; then
    echo -e "${RED}❌ Docker is not running${NC}"
    echo "   Please start Docker Desktop"
    exit 1
fi
echo -e "${GREEN}✅ Docker is running${NC}"

# Check if Kubernetes is enabled
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Kubernetes cluster is not accessible${NC}"
    echo "   Please enable Kubernetes in Docker Desktop:"
    echo "   Docker Desktop → Settings → Kubernetes → Enable"
    exit 1
fi
echo -e "${GREEN}✅ Kubernetes cluster is accessible${NC}"

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

# Extract repo name from URL
GITHUB_REPO_NAME=$(basename "$GITHUB_REPO_URL" .git)

echo ""
echo "📝 Updating configuration files..."

# Update serviceaccount.yaml
sed -i.bak "s/YOUR_DOCKERHUB_USERNAME/$DOCKERHUB_USERNAME/g" serviceaccount.yaml
sed -i.bak "s/YOUR_DOCKERHUB_PASSWORD/$DOCKERHUB_PASSWORD/g" serviceaccount.yaml
sed -i.bak "s/YOUR_GITHUB_USERNAME/$GITHUB_USERNAME/g" serviceaccount.yaml
sed -i.bak "s/YOUR_GITHUB_TOKEN/$GITHUB_TOKEN/g" serviceaccount.yaml
rm -f serviceaccount.yaml.bak

# Update pipeline.yaml
sed -i.bak "s|YOUR_USERNAME/tekton-tutorial.git|$GITHUB_REPO_URL|g" pipeline.yaml
rm -f pipeline.yaml.bak

# Update test-pipelinerun.yaml
sed -i.bak "s/YOUR_DOCKERHUB_USERNAME/$DOCKERHUB_USERNAME/g" test-pipelinerun.yaml
rm -f test-pipelinerun.yaml.bak

# Update webhook-server.py
sed -i.bak "s/YOUR_DOCKERHUB_USERNAME/$DOCKERHUB_USERNAME/g" webhook-server.py
rm -f webhook-server.py.bak

echo -e "${GREEN}✅ Configuration files updated${NC}"

# Apply Tekton resources
echo ""
echo "🚀 Applying Tekton resources..."

kubectl apply -f serviceaccount.yaml
echo -e "${GREEN}✅ Service account created${NC}"

kubectl apply -f pipeline.yaml
echo -e "${GREEN}✅ Pipeline created${NC}"

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

