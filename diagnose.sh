#!/bin/bash

echo "╔═══════════════════════════════════════════════════════════════════════════╗"
echo "║                    ONYX DEPLOYMENT DIAGNOSTIC TOOL                        ║"
echo "╚═══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== STEP 1: Get Current Namespace ==="
NAMESPACE=$(oc project -q 2>/dev/null || kubectl config view --minify --output 'jsonpath={..namespace}')
echo -e "${GREEN}Current namespace: $NAMESPACE${NC}"
echo ""

echo "=== STEP 2: Check All Services ==="
echo "Looking for web-server and api-server services..."
oc get services 2>/dev/null | grep -E "(NAME|web-server|api-server)" || echo -e "${RED}No services found!${NC}"
echo ""

echo "=== STEP 3: Check Service Details ==="
echo "--- web-server service ---"
if oc get service web-server &>/dev/null; then
    echo -e "${GREEN}✓ web-server service exists${NC}"
    oc get service web-server -o wide
    echo ""
    echo "Endpoints:"
    oc get endpoints web-server
else
    echo -e "${RED}✗ web-server service DOES NOT EXIST!${NC}"
    echo -e "${YELLOW}Action needed: Deploy web-server service${NC}"
fi
echo ""

echo "--- api-server service ---"
if oc get service api-server &>/dev/null; then
    echo -e "${GREEN}✓ api-server service exists${NC}"
    oc get service api-server -o wide
    echo ""
    echo "Endpoints:"
    oc get endpoints api-server
else
    echo -e "${RED}✗ api-server service DOES NOT EXIST!${NC}"
    echo -e "${YELLOW}Action needed: Deploy api-server service${NC}"
fi
echo ""

echo "=== STEP 4: Check All Pods ==="
echo "All pods in namespace $NAMESPACE:"
oc get pods -o wide
echo ""

echo "=== STEP 5: Check Deployments ==="
echo "Looking for webserver and api-server deployments..."
oc get deployments 2>/dev/null | grep -E "(NAME|webserver|api-server|backend)" || echo -e "${YELLOW}No matching deployments found${NC}"
echo ""

echo "=== STEP 6: Check Pod Labels ==="
echo "Checking labels for webserver pods..."
oc get pods -l io.kompose.service=webserver -o wide 2>/dev/null || echo -e "${YELLOW}No pods with label io.kompose.service=webserver${NC}"
echo ""
oc get pods -l app=webserver -o wide 2>/dev/null || echo -e "${YELLOW}No pods with label app=webserver${NC}"
echo ""

echo "Checking labels for api-server pods..."
oc get pods -l app=api-server -o wide 2>/dev/null || echo -e "${YELLOW}No pods with label app=api-server${NC}"
echo ""

echo "=== STEP 7: DNS Resolution Test ==="
echo "Testing if we can resolve services..."

# Try to run a test pod for DNS resolution
echo "Creating test pod for DNS resolution..."
oc run dns-test --image=busybox:1.35 --rm -i --restart=Never --command -- sh -c "
echo 'Testing DNS resolution...'
echo '1. Short name web-server:'
nslookup web-server 2>&1 || echo 'FAILED'
echo ''
echo '2. Short name api-server:'
nslookup api-server 2>&1 || echo 'FAILED'
echo ''
echo '3. Full DNS web-server.$NAMESPACE.svc.cluster.local:'
nslookup web-server.$NAMESPACE.svc.cluster.local 2>&1 || echo 'FAILED'
echo ''
echo '4. Full DNS api-server.$NAMESPACE.svc.cluster.local:'
nslookup api-server.$NAMESPACE.svc.cluster.local 2>&1 || echo 'FAILED'
" 2>/dev/null || echo -e "${YELLOW}Could not run DNS test pod${NC}"
echo ""

echo "=== STEP 8: Check NGINX Status ==="
if oc get deployment nginx &>/dev/null; then
    echo -e "${GREEN}✓ NGINX deployment exists${NC}"
    echo "NGINX pods:"
    oc get pods -l app=nginx
    echo ""
    
    # Check if NGINX pod is running
    NGINX_POD=$(oc get pods -l app=nginx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$NGINX_POD" ]; then
        echo "NGINX pod: $NGINX_POD"
        echo ""
        echo "InitContainer logs (wait-for-services):"
        oc logs $NGINX_POD -c wait-for-services 2>/dev/null || echo -e "${YELLOW}InitContainer not started yet or already completed${NC}"
        echo ""
        echo "NGINX container logs:"
        oc logs $NGINX_POD -c nginx 2>/dev/null || echo -e "${YELLOW}NGINX container not started yet${NC}"
    else
        echo -e "${YELLOW}No NGINX pods found${NC}"
    fi
else
    echo -e "${RED}✗ NGINX deployment DOES NOT EXIST!${NC}"
fi
echo ""

echo "=== STEP 9: Summary and Recommendations ==="
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check what's missing
MISSING=()

if ! oc get service web-server &>/dev/null; then
    MISSING+=("web-server service")
fi

if ! oc get service api-server &>/dev/null; then
    MISSING+=("api-server service")
fi

WEB_PODS=$(oc get pods -l io.kompose.service=webserver -o name 2>/dev/null | wc -l)
if [ "$WEB_PODS" -eq 0 ]; then
    MISSING+=("webserver pods")
fi

API_PODS=$(oc get pods -l app=api-server -o name 2>/dev/null | wc -l)
if [ "$API_PODS" -eq 0 ]; then
    MISSING+=("api-server pods")
fi

if [ ${#MISSING[@]} -eq 0 ]; then
    echo -e "${GREEN}✓ All required components appear to be present!${NC}"
    echo ""
    echo "If you're still having issues, the problem might be:"
    echo "1. Pods are not in Running state"
    echo "2. Service selectors don't match pod labels"
    echo "3. Pods are not ready/healthy"
    echo ""
    echo "Check pod status with: oc get pods"
    echo "Check pod logs with: oc logs <pod-name>"
else
    echo -e "${RED}✗ MISSING COMPONENTS:${NC}"
    for item in "${MISSING[@]}"; do
        echo -e "  ${RED}- $item${NC}"
    done
    echo ""
    echo -e "${YELLOW}RECOMMENDED ACTIONS:${NC}"
    
    if [[ " ${MISSING[@]} " =~ " web-server service " ]]; then
        echo -e "  ${YELLOW}1. Deploy web-server service:${NC}"
        echo "     oc apply -f 08-web-server-service.yaml"
    fi
    
    if [[ " ${MISSING[@]} " =~ " api-server service " ]]; then
        echo -e "  ${YELLOW}2. Deploy api-server service:${NC}"
        echo "     oc apply -f 07-api-server-service.yaml"
    fi
    
    if [[ " ${MISSING[@]} " =~ " webserver pods " ]]; then
        echo -e "  ${YELLOW}3. Deploy webserver (check your deployment file):${NC}"
        echo "     oc apply -f <your-webserver-deployment.yaml>"
    fi
    
    if [[ " ${MISSING[@]} " =~ " api-server pods " ]]; then
        echo -e "  ${YELLOW}4. Deploy api-server (check your deployment file):${NC}"
        echo "     oc apply -f <your-api-server-deployment.yaml>"
    fi
fi

echo ""
echo "=== DIAGNOSTIC COMPLETE ==="
echo ""
echo "For detailed troubleshooting, check:"
echo "- NGINX-DNS-TROUBLESHOOTING-GUIDE.md"
echo "- MISSING-SERVICES-SOLUTION.md"
echo ""
echo "To save this output to a file:"
echo "  ./diagnose.sh > diagnostic-output.txt"
echo ""
