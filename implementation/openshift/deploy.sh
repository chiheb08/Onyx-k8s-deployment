#!/usr/bin/env bash
# Deploy Onyx to OpenShift
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Validating manifests..."
kubectl kustomize . > /dev/null

echo "==> Applying manifests..."
oc apply -k .

echo "==> Granting anyuid SCC to onyx ServiceAccount (model servers)..."
oc adm policy add-scc-to-user anyuid -z onyx -n onyx 2>/dev/null || true

echo "==> Waiting for core rollouts..."
oc rollout status deployment/onyx-api-server -n onyx --timeout=600s
oc rollout status deployment/onyx-background -n onyx --timeout=600s
oc rollout status deployment/onyx-nginx -n onyx --timeout=300s

echo ""
echo "==> Route URL:"
oc get route onyx -n onyx -o jsonpath='https://{.spec.host}{"\n"}'

echo ""
echo "NEXT STEPS:"
echo "  1. Edit manifests/configmap-env.yaml — set DOMAIN and WEB_DOMAIN to route host, then re-apply"
echo "  2. Configure vLLM in Admin UI (provider: openai_compatible)"
echo "  3. See README.md and docs/ARCHITECTURE.md"
