#!/bin/bash

echo "╔═══════════════════════════════════════════════════════════════════════════╗"
echo "║                    ONYX DEPLOYMENT QUICK FIX                              ║"
echo "╚═══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE=$(oc project -q 2>/dev/null)
echo -e "${GREEN}Working in namespace: $NAMESPACE${NC}"
echo ""

echo "=== STEP 1: Deploy Services First ==="
echo ""

# Deploy web-server service
echo -e "${BLUE}Deploying web-server service...${NC}"
if [ -f "08-web-server-service.yaml" ]; then
    oc apply -f 08-web-server-service.yaml
    echo -e "${GREEN}✓ web-server service deployed${NC}"
else
    echo -e "${YELLOW}⚠ 08-web-server-service.yaml not found${NC}"
fi
echo ""

# Deploy api-server service
echo -e "${BLUE}Deploying api-server service...${NC}"
if [ -f "07-api-server-service.yaml" ]; then
    oc apply -f 07-api-server-service.yaml
    echo -e "${GREEN}✓ api-server service deployed${NC}"
else
    echo -e "${YELLOW}⚠ 07-api-server-service.yaml not found${NC}"
fi
echo ""

echo "=== STEP 2: Wait for Services to be Created ==="
sleep 2
echo ""

echo "=== STEP 3: Check Service Status ==="
echo "Services in namespace $NAMESPACE:"
oc get services | grep -E "(NAME|web-server|api-server)"
echo ""

echo "=== STEP 4: Check Endpoints ==="
echo "web-server endpoints:"
oc get endpoints web-server 2>/dev/null || echo -e "${YELLOW}No endpoints for web-server (pods might not be running)${NC}"
echo ""
echo "api-server endpoints:"
oc get endpoints api-server 2>/dev/null || echo -e "${YELLOW}No endpoints for api-server (pods might not be running)${NC}"
echo ""

echo "=== STEP 5: Deploy NGINX with Hardcoded Namespace ==="
echo ""
echo -e "${BLUE}Creating NGINX deployment with hardcoded namespace...${NC}"

# Create a temporary file with the actual namespace
if [ -f "09-nginx-hardcoded-namespace.yaml" ]; then
    sed "s/YOUR_NAMESPACE/$NAMESPACE/g" 09-nginx-hardcoded-namespace.yaml > /tmp/09-nginx-fixed.yaml
    echo -e "${GREEN}✓ Created NGINX config for namespace: $NAMESPACE${NC}"
    echo ""
    
    echo -e "${BLUE}Deploying NGINX...${NC}"
    oc apply -f /tmp/09-nginx-fixed.yaml
    echo -e "${GREEN}✓ NGINX deployed${NC}"
    echo ""
else
    echo -e "${RED}✗ 09-nginx-hardcoded-namespace.yaml not found!${NC}"
    echo -e "${YELLOW}Trying to use 09-nginx.yaml instead...${NC}"
    if [ -f "09-nginx.yaml" ]; then
        oc apply -f 09-nginx.yaml
        echo -e "${GREEN}✓ NGINX deployed${NC}"
    else
        echo -e "${RED}✗ No NGINX deployment file found!${NC}"
    fi
fi
echo ""

echo "=== STEP 6: Wait for NGINX Pod ==="
echo "Waiting for NGINX pod to be created..."
sleep 5
echo ""

echo "=== STEP 7: Check NGINX Status ==="
echo "NGINX pods:"
oc get pods -l app=nginx
echo ""

NGINX_POD=$(oc get pods -l app=nginx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$NGINX_POD" ]; then
    echo -e "${GREEN}Found NGINX pod: $NGINX_POD${NC}"
    echo ""
    
    echo "=== STEP 8: Check InitContainer Logs ==="
    echo "InitContainer logs (wait-for-services):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    oc logs $NGINX_POD -c wait-for-services 2>/dev/null || echo -e "${YELLOW}InitContainer logs not available yet${NC}"
    echo ""
    
    echo "=== STEP 9: Check NGINX Container Logs ==="
    echo "NGINX container logs:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    oc logs $NGINX_POD -c nginx 2>/dev/null || echo -e "${YELLOW}NGINX container not started yet${NC}"
    echo ""
else
    echo -e "${YELLOW}⚠ NGINX pod not found yet${NC}"
    echo "Check status with: oc get pods -l app=nginx"
fi
echo ""

echo "=== STEP 10: Summary ==="
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "All components have been deployed!"
echo ""
echo "To check the status:"
echo "  oc get pods"
echo "  oc get services"
echo ""
echo "To check NGINX logs:"
echo "  oc logs deployment/nginx -c wait-for-services"
echo "  oc logs deployment/nginx -c nginx"
echo ""
echo "To watch NGINX logs in real-time:"
echo "  oc logs deployment/nginx -c wait-for-services -f"
echo ""
echo "If services are still failing, check if your webserver and api-server pods are running:"
echo "  oc get pods"
echo "  oc logs <pod-name>"
echo ""
