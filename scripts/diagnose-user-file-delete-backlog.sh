#!/usr/bin/env bash
# Diagnose stuck user_file DELETING backlog (Redis + Celery + optional Postgres).
# Usage: ./scripts/diagnose-user-file-delete-backlog.sh [namespace]
set -euo pipefail

NAMESPACE="${1:-onyx-infra}"

echo "=== Onyx user_file delete backlog diagnostic ==="
echo "Namespace: $NAMESPACE"
echo "Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo

if ! command -v oc >/dev/null 2>&1; then
  echo "ERROR: oc not found"
  exit 1
fi

echo "--- Deployments / pods (celery + redis) ---"
oc get deploy,pods -n "$NAMESPACE" 2>/dev/null | grep -E 'celery-worker-user-file|celery-beat|redis' || true
echo

REDIS_POD="$(oc get pod -n "$NAMESPACE" -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -z "$REDIS_POD" ]]; then
  echo "WARN: No redis pod found"
else
  REDIS_PASS="$(oc get secret onyx-redis -n "$NAMESPACE" -o jsonpath='{.data.redis_password}' 2>/dev/null | base64 -d 2>/dev/null || true)"
  echo "--- Redis queues (LLEN) ---"
  for q in user_file_delete user_file_processing user_file_project_sync celery; do
    len="$(oc exec -n "$NAMESPACE" "$REDIS_POD" -- redis-cli -a "$REDIS_PASS" LLEN "$q" 2>/dev/null | tr -d '\r' || echo "?")"
    echo "  $q: $len"
  done
  echo
  echo "--- Redis memory (eviction risk) ---"
  oc exec -n "$NAMESPACE" "$REDIS_POD" -- redis-cli -a "$REDIS_PASS" INFO memory 2>/dev/null | grep -E 'used_memory_human|maxmemory_human|evicted_keys' || true
  echo
fi

echo "--- Recent delete task logs (mixed worker) ---"
oc logs -n "$NAMESPACE" deploy/celery-worker-user-file-processing --tail=80 2>/dev/null | \
  grep -E 'process_single_user_file_delete|ERROR|Error|429|Vespa|Failed' || echo "  (no matches or deployment missing)"
echo

echo "--- Recent delete task logs (dedicated worker, if deployed) ---"
if oc get deploy celery-worker-user-file-delete -n "$NAMESPACE" >/dev/null 2>&1; then
  oc logs -n "$NAMESPACE" deploy/celery-worker-user-file-delete --tail=80 2>/dev/null | \
    grep -E 'process_single_user_file_delete|ERROR|Error|429|Vespa|Failed' || echo "  (no matches)"
else
  echo "  celery-worker-user-file-delete not deployed (optional)"
fi
echo

echo "--- Vespa throttle/errors (last 40 lines) ---"
VESPA_POD="$(oc get pod -n "$NAMESPACE" -l app=vespa -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "$VESPA_POD" ]]; then
  oc logs -n "$NAMESPACE" "$VESPA_POD" --tail=200 2>/dev/null | grep -E '429|throttl|Too Many' | tail -20 || echo "  (no 429/throttle lines)"
else
  echo "  (vespa pod not found)"
fi
echo

echo "--- Postgres DELETING count (if psql available in postgresql pod) ---"
PG_POD="$(oc get pod -n "$NAMESPACE" -l app=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "$PG_POD" ]]; then
  oc exec -n "$NAMESPACE" "$PG_POD" -- psql -U postgres -d postgres -t -c \
    "SELECT COUNT(*) FROM public.user_file WHERE status = 'DELETING';" 2>/dev/null | tr -d ' ' || echo "  (query failed)"
else
  echo "  Run manually: SELECT COUNT(*) FROM public.user_file WHERE status = 'DELETING';"
fi
echo
echo "=== Done. See docs/troubleshooting/DELETING-FILES-STUCK-INVESTIGATION-AND-REMEDIATION.md ==="
