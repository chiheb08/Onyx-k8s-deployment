#!/bin/bash

# ============================================================================
# Onyx Kubernetes Infrastructure Deployment Script
# ============================================================================
# Deploys PostgreSQL, Vespa, and Redis for Onyx
# ============================================================================

set -e

echo ""
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║     🚀 Deploying Onyx Kubernetes Infrastructure Components           ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ ERROR: kubectl is not installed or not in PATH"
    echo "   Please install kubectl: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

echo "✅ kubectl is available"
echo ""

# Check if kubectl can connect to cluster
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ ERROR: Cannot connect to Kubernetes cluster"
    echo "   Please ensure your kubeconfig is configured correctly"
    exit 1
fi

echo "✅ Connected to Kubernetes cluster"
echo ""

# Get current context
CURRENT_CONTEXT=$(kubectl config current-context)
echo "📍 Current context: $CURRENT_CONTEXT"
echo ""

read -p "Continue with deployment? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled"
    exit 0
fi

echo ""

# Get current namespace
CURRENT_NAMESPACE=$(kubectl config view --minify -o jsonpath='{..namespace}')
if [ -z "$CURRENT_NAMESPACE" ]; then
    CURRENT_NAMESPACE="default"
fi

echo "📍 Current namespace: $CURRENT_NAMESPACE"
echo ""
read -p "Deploy to this namespace? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Please switch to the correct namespace first:"
    echo "  kubectl config set-context --current --namespace=your-namespace"
    echo "  OR"
    echo "  oc project your-namespace"
    exit 0
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 1/8: Deploying Infrastructure Layer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Deploying PostgreSQL..."
kubectl apply -f 02-postgresql.yaml
echo "✅ PostgreSQL deployed"
echo ""

echo "Deploying Vespa..."
kubectl apply -f 03-vespa.yaml
echo "✅ Vespa deployed"
echo ""

echo "Deploying Redis..."
kubectl apply -f 04-redis.yaml
echo "✅ Redis deployed"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 2/8: Deploying ConfigMap"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

kubectl apply -f 05-configmap.yaml
echo "✅ ConfigMap deployed"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 3/8: Waiting for Infrastructure to be Ready"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "⏳ Waiting for PostgreSQL..."
kubectl wait --for=condition=ready pod -l app=postgresql --timeout=300s
echo "✅ PostgreSQL is ready"
echo ""

echo "⏳ Waiting for Vespa..."
kubectl wait --for=condition=ready pod -l app=vespa --timeout=300s
echo "✅ Vespa is ready"
echo ""

echo "⏳ Waiting for Redis..."
kubectl wait --for=condition=ready pod -l app=redis --timeout=300s
echo "✅ Redis is ready"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 4/8: Deploying AI/ML Layer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

kubectl apply -f 06-inference-model-server.yaml
echo "✅ Inference Model Server deployed"
echo ""

echo "⏳ Waiting for Model Server to be ready (this may take 2-5 minutes)..."
kubectl wait --for=condition=ready pod -l app=inference-model-server --timeout=600s
echo "✅ Inference Model Server is ready"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 5/8: Deploying Application Layer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

kubectl apply -f 07-api-server.yaml
echo "✅ API Server deployed"
echo ""

echo "⏳ Waiting for API Server to be ready (running migrations + startup)..."
kubectl wait --for=condition=ready pod -l app=api-server --timeout=300s
echo "✅ API Server is ready"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 6/8: Deploying Frontend Layer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

kubectl apply -f 08-web-server.yaml
echo "✅ Web Server deployed"
echo ""

echo "⏳ Waiting for Web Server to be ready..."
kubectl wait --for=condition=ready pod -l app=web-server --timeout=300s
echo "✅ Web Server is ready"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 7/8: Deploying Gateway Layer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

kubectl apply -f 09-nginx.yaml
echo "✅ NGINX deployed"
echo ""

echo "⏳ Waiting for NGINX to be ready..."
kubectl wait --for=condition=ready pod -l app=nginx --timeout=120s
echo "✅ NGINX is ready"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 8/8: Final Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Verifying all pods are running..."
kubectl get pods
echo ""

echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║                   🎉 DEPLOYMENT SUCCESSFUL!                           ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

echo "📊 Deployment Status:"
echo ""
kubectl get pods
echo ""
kubectl get svc
echo ""
kubectl get pvc
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SERVICE ENDPOINTS (in namespace: $CURRENT_NAMESPACE):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🌐 NGINX (Entry Point):"
echo "   External: Get LoadBalancer IP/Route with: kubectl get svc nginx"
echo "   Access Onyx UI via the EXTERNAL-IP on port 80"
echo ""
echo "📦 Internal Services (short DNS names within same namespace):"
echo ""
echo "   PostgreSQL: postgresql:5432"
echo "      User: postgres | Password: postgres | Database: postgres"
echo ""
echo "   Vespa: vespa-0.vespa-service:19071"
echo "      Config: port 19071 | Query: port 8081"
echo ""
echo "   Redis: redis:6379"
echo "      Password: password"
echo ""
echo "   Inference Model Server: inference-model-server:9000"
echo ""
echo "   API Server: api-server:8080"
echo ""
echo "   Web Server: web-server:3000"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "USEFUL COMMANDS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "View pods:     kubectl get pods"
echo "View logs:     kubectl logs <pod-name>"
echo "Describe pod:  kubectl describe pod <pod-name>"
echo "View services: kubectl get svc"
echo "Delete all:    kubectl delete all --all  (WARNING: Deletes everything in namespace)"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🎯 Onyx Minimal Deployment is COMPLETE in namespace: $CURRENT_NAMESPACE"
echo ""
echo "To access the Onyx UI:"
echo ""
echo "For OpenShift (Recommended):"
echo "  1. Create route: oc expose svc/nginx"
echo "  2. Get route URL: oc get route nginx"
echo "  3. Open browser to route URL"
echo ""
echo "For Kubernetes LoadBalancer:"
echo "  1. Get LoadBalancer IP: kubectl get svc nginx"
echo "  2. Open browser to: http://<EXTERNAL-IP>"
echo ""
echo "For Port Forward (always works):"
echo "  1. kubectl port-forward svc/nginx 3000:80"
echo "  2. Open: http://localhost:3000"
echo ""

