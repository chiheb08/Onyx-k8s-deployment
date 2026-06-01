#!/bin/sh
# Run INSIDE an Onyx backend pod terminal (api-server or celery-worker-user-file-processing).
# Does NOT use kubectl/oc. Requires REDIS_* env vars and python3+redis package.
#
# Usage (in pod shell):
#   sh /path/to/in-pod-check-delete-backlog.sh
# Or paste the python block below directly.

echo "=== In-pod delete backlog check ==="
echo "Pod hostname: $(hostname)"
echo "REDIS_HOST=${REDIS_HOST:-<not set>}"
echo "REDIS_PORT=${REDIS_PORT:-6379}"
echo

if [ -z "${REDIS_PASSWORD:-}" ]; then
  echo "WARN: REDIS_PASSWORD not set in this pod. Open redis pod and use redis-cli there."
fi

if command -v redis-cli >/dev/null 2>&1 && [ -n "${REDIS_HOST:-}" ]; then
  echo "--- redis-cli ---"
  redis-cli -h "$REDIS_HOST" -p "${REDIS_PORT:-6379}" -a "$REDIS_PASSWORD" PING 2>/dev/null || true
  for q in user_file_delete user_file_processing user_file_project_sync; do
    echo -n "LLEN $q: "
    redis-cli -h "$REDIS_HOST" -p "${REDIS_PORT:-6379}" -a "$REDIS_PASSWORD" LLEN "$q" 2>/dev/null || echo "?"
  done
  echo
fi

python3 << 'PY' 2>/dev/null || echo "Python/redis check skipped (no python3 or redis module)"
import os
try:
    import redis
except ImportError:
    print("redis Python package not available in this pod")
    raise SystemExit(0)

host = os.environ.get("REDIS_HOST", "redis")
port = int(os.environ.get("REDIS_PORT", "6379"))
password = os.environ.get("REDIS_PASSWORD")
r = redis.Redis(host=host, port=port, password=password, decode_responses=True, socket_connect_timeout=5)
print("--- Python redis ---")
print("PING:", r.ping())
for q in ["user_file_delete", "user_file_processing", "user_file_project_sync"]:
    print(f"LLEN {q}:", r.llen(q))
mem = r.info("memory")
print("used_memory_human:", mem.get("used_memory_human"))
print("evicted_keys:", mem.get("evicted_keys"))
PY

echo
echo "--- Celery inspect (if celery in PATH) ---"
if command -v celery >/dev/null 2>&1; then
  celery -A onyx.background.celery.versioned_apps.user_file_processing inspect active 2>/dev/null | head -40 || echo "(inspect failed)"
else
  echo "celery not in PATH on this pod"
fi

echo
echo "=== Next: postgresql pod -> SELECT COUNT(*) FROM user_file WHERE status='DELETING'; ==="
echo "=== Guide: docs/troubleshooting/IN-POD-REDIS-CELERY-DELETE-CHECKS.md ==="
