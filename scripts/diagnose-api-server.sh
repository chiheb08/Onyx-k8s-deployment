#!/bin/bash

echo "╔═══════════════════════════════════════════════════════════════════════════╗"
echo "║              API SERVER ALEMBIC/REDIS DIAGNOSTIC TOOL                    ║"
echo "╚═══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE=$(oc project -q 2>/dev/null || echo "default")
echo -e "${GREEN}Working in namespace: $NAMESPACE${NC}"
echo ""

echo "=== STEP 1: Check Redis Pod ==="
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if oc get pods -l app=redis &>/dev/null; then
    echo -e "${GREEN}✓ Redis pod exists${NC}"
    oc get pods -l app=redis
    
    REDIS_POD=$(oc get pods -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$REDIS_POD" ]; then
        REDIS_STATUS=$(oc get pod $REDIS_POD -o jsonpath='{.status.phase}')
        if [ "$REDIS_STATUS" = "Running" ]; then
            echo -e "${GREEN}✓ Redis pod is Running${NC}"
        else
            echo -e "${RED}✗ Redis pod status: $REDIS_STATUS${NC}"
        fi
    fi
else
    echo -e "${RED}✗ Redis pod NOT found!${NC}"
    echo -e "${YELLOW}Action: Deploy Redis first${NC}"
fi
echo ""

echo "=== STEP 2: Check Redis Service ==="
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if oc get service cache &>/dev/null; then
    echo -e "${GREEN}✓ Redis service 'cache' exists${NC}"
    oc get service cache
    
    echo ""
    echo "Redis endpoints:"
    ENDPOINTS=$(oc get endpoints cache -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
    if [ -n "$ENDPOINTS" ]; then
        echo -e "${GREEN}✓ Service has endpoints: $ENDPOINTS${NC}"
    else
        echo -e "${RED}✗ Service has NO endpoints (no pods)${NC}"
    fi
else
    echo -e "${RED}✗ Redis service 'cache' NOT found!${NC}"
    echo -e "${YELLOW}Action: Deploy Redis service${NC}"
fi
echo ""

echo "=== STEP 3: Check PostgreSQL ==="
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if oc get pods -l app=postgresql &>/dev/null; then
    echo -e "${GREEN}✓ PostgreSQL pod exists${NC}"
    oc get pods -l app=postgresql
    
    POSTGRES_POD=$(oc get pods -l app=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$POSTGRES_POD" ]; then
        POSTGRES_STATUS=$(oc get pod $POSTGRES_POD -o jsonpath='{.status.phase}')
        if [ "$POSTGRES_STATUS" = "Running" ]; then
            echo -e "${GREEN}✓ PostgreSQL pod is Running${NC}"
        else
            echo -e "${RED}✗ PostgreSQL pod status: $POSTGRES_STATUS${NC}"
        fi
    fi
else
    echo -e "${RED}✗ PostgreSQL pod NOT found!${NC}"
fi

if oc get service relational-db &>/dev/null; then
    echo -e "${GREEN}✓ PostgreSQL service exists${NC}"
    POSTGRES_ENDPOINTS=$(oc get endpoints relational-db -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
    if [ -n "$POSTGRES_ENDPOINTS" ]; then
        echo -e "${GREEN}✓ Service has endpoints${NC}"
    else
        echo -e "${RED}✗ Service has NO endpoints${NC}"
    fi
else
    echo -e "${RED}✗ PostgreSQL service NOT found!${NC}"
fi
echo ""

echo "=== STEP 4: Check API Server Pod ==="
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if oc get pods -l app=api-server &>/dev/null; then
    echo -e "${GREEN}✓ API server pod exists${NC}"
    oc get pods -l app=api-server
    
    API_POD=$(oc get pods -l app=api-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$API_POD" ]; then
        echo ""
        echo -e "${BLUE}API Pod: $API_POD${NC}"
        
        API_STATUS=$(oc get pod $API_POD -o jsonpath='{.status.phase}')
        echo -e "Status: ${YELLOW}$API_STATUS${NC}"
        
        # Check if initContainer is present
        INIT_CONTAINER=$(oc get pod $API_POD -o jsonpath='{.spec.initContainers[*].name}' 2>/dev/null)
        if [ -n "$INIT_CONTAINER" ]; then
            echo -e "${GREEN}✓ Has initContainer: $INIT_CONTAINER${NC}"
        else
            echo -e "${YELLOW}⚠ No initContainer found${NC}"
        fi
    fi
else
    echo -e "${RED}✗ API server pod NOT found!${NC}"
fi
echo ""

echo "=== STEP 5: Check API Server Environment Variables ==="
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -n "$API_POD" ]; then
    echo "Checking Redis environment variables..."
    REDIS_HOST=$(oc exec $API_POD -- env 2>/dev/null | grep REDIS_HOST | cut -d'=' -f2)
    REDIS_PORT=$(oc exec $API_POD -- env 2>/dev/null | grep REDIS_PORT | cut -d'=' -f2)
    
    if [ -n "$REDIS_HOST" ]; then
        echo -e "${GREEN}✓ REDIS_HOST=$REDIS_HOST${NC}"
    else
        echo -e "${RED}✗ REDIS_HOST not set!${NC}"
    fi
    
    if [ -n "$REDIS_PORT" ]; then
        echo -e "${GREEN}✓ REDIS_PORT=$REDIS_PORT${NC}"
    else
        echo -e "${RED}✗ REDIS_PORT not set!${NC}"
    fi
    
    echo ""
    echo "Checking PostgreSQL environment variables..."
    POSTGRES_HOST=$(oc exec $API_POD -- env 2>/dev/null | grep POSTGRES_HOST | cut -d'=' -f2)
    POSTGRES_PORT=$(oc exec $API_POD -- env 2>/dev/null | grep POSTGRES_PORT | cut -d'=' -f2)
    
    if [ -n "$POSTGRES_HOST" ]; then
        echo -e "${GREEN}✓ POSTGRES_HOST=$POSTGRES_HOST${NC}"
    else
        echo -e "${RED}✗ POSTGRES_HOST not set!${NC}"
    fi
    
    if [ -n "$POSTGRES_PORT" ]; then
        echo -e "${GREEN}✓ POSTGRES_PORT=$POSTGRES_PORT${NC}"
    else
        echo -e "${RED}✗ POSTGRES_PORT not set!${NC}"
    fi
else
    echo -e "${YELLOW}⚠ API pod not running, skipping env check${NC}"
fi
echo ""

echo "=== STEP 6: Test Connectivity from API Pod ==="
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -n "$API_POD" ] && [ "$API_STATUS" = "Running" ]; then
    echo "Testing DNS resolution..."
    
    if oc exec $API_POD -- nslookup cache &>/dev/null; then
        echo -e "${GREEN}✓ Can resolve 'cache' DNS${NC}"
    else
        echo -e "${RED}✗ Cannot resolve 'cache' DNS${NC}"
    fi
    
    if oc exec $API_POD -- nslookup relational-db &>/dev/null; then
        echo -e "${GREEN}✓ Can resolve 'relational-db' DNS${NC}"
    else
        echo -e "${RED}✗ Cannot resolve 'relational-db' DNS${NC}"
    fi
    
    echo ""
    echo "Testing port connectivity..."
    
    if oc exec $API_POD -- sh -c "nc -zv cache 6379" &>/dev/null; then
        echo -e "${GREEN}✓ Can connect to Redis (cache:6379)${NC}"
    else
        echo -e "${RED}✗ Cannot connect to Redis (cache:6379)${NC}"
    fi
    
    if oc exec $API_POD -- sh -c "nc -zv relational-db 5432" &>/dev/null; then
        echo -e "${GREEN}✓ Can connect to PostgreSQL (relational-db:5432)${NC}"
    else
        echo -e "${RED}✗ Cannot connect to PostgreSQL (relational-db:5432)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ API pod not running, skipping connectivity test${NC}"
fi
echo ""

echo "=== STEP 7: Check API Server Logs ==="
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -n "$API_POD" ]; then
    echo "Recent logs from API server pod:"
    echo ""
    oc logs $API_POD --tail=20 2>/dev/null || echo -e "${YELLOW}⚠ No logs available${NC}"
    
    echo ""
    echo "Checking for 'Starting Onyx' message..."
    if oc logs $API_POD 2>/dev/null | grep -i "Starting Onyx" &>/dev/null; then
        echo -e "${GREEN}✓ Found 'Starting Onyx' message - API server started successfully!${NC}"
    else
        echo -e "${RED}✗ 'Starting Onyx' message NOT found - startup may have failed${NC}"
    fi
    
    echo ""
    echo "Checking for Redis errors..."
    if oc logs $API_POD 2>/dev/null | grep -i "redis" &>/dev/null; then
        echo -e "${YELLOW}Found Redis-related log entries:${NC}"
        oc logs $API_POD 2>/dev/null | grep -i "redis" | tail -5
    fi
    
    echo ""
    echo "Checking for Alembic errors..."
    if oc logs $API_POD 2>/dev/null | grep -i "alembic" &>/dev/null; then
        echo -e "${YELLOW}Found Alembic-related log entries:${NC}"
        oc logs $API_POD 2>/dev/null | grep -i "alembic" | tail -5
    fi
else
    echo -e "${YELLOW}⚠ API pod not found, skipping log check${NC}"
fi
echo ""

echo "=== STEP 8: Summary & Recommendations ==="
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Collect issues
ISSUES=()

if ! oc get pods -l app=redis &>/dev/null || [ "$REDIS_STATUS" != "Running" ]; then
    ISSUES+=("Redis pod not running")
fi

if ! oc get service cache &>/dev/null; then
    ISSUES+=("Redis service 'cache' missing")
fi

if ! oc get pods -l app=postgresql &>/dev/null || [ "$POSTGRES_STATUS" != "Running" ]; then
    ISSUES+=("PostgreSQL pod not running")
fi

if [ -n "$API_POD" ]; then
    if [ -z "$REDIS_HOST" ]; then
        ISSUES+=("REDIS_HOST not set in API pod")
    fi
    
    if [ -z "$POSTGRES_HOST" ]; then
        ISSUES+=("POSTGRES_HOST not set in API pod")
    fi
fi

if [ ${#ISSUES[@]} -eq 0 ]; then
    echo -e "${GREEN}✓ No critical issues detected!${NC}"
    echo ""
    echo "If API server still has issues, check:"
    echo "1. Full logs: oc logs $API_POD"
    echo "2. Try running Alembic manually: oc exec $API_POD -- alembic upgrade head"
    echo "3. Check API server events: oc describe pod $API_POD"
else
    echo -e "${RED}✗ Issues detected:${NC}"
    for issue in "${ISSUES[@]}"; do
        echo -e "  ${RED}- $issue${NC}"
    done
    echo ""
    echo -e "${YELLOW}Recommended Actions:${NC}"
    echo ""
    echo "1. Deploy infrastructure first:"
    echo "   oc apply -f manifests/02-postgresql.yaml"
    echo "   oc apply -f manifests/04-redis.yaml"
    echo ""
    echo "2. Wait for them to be ready:"
    echo "   oc wait --for=condition=ready pod -l app=postgresql --timeout=300s"
    echo "   oc wait --for=condition=ready pod -l app=redis --timeout=300s"
    echo ""
    echo "3. Then deploy API server:"
    echo "   oc apply -f manifests/07-api-server.yaml"
    echo ""
    echo "4. Check troubleshooting guide:"
    echo "   cat troubleshooting/API-SERVER-ALEMBIC-REDIS-ERROR.md"
fi

echo ""
echo "=== DIAGNOSTIC COMPLETE ==="
echo ""
