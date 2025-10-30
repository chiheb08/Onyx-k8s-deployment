# File Connector Troubleshooting: Stuck “In Progress”

This guide helps you diagnose and fix file connectors that stay in “Syncing / In Progress” and never show “Indexed” or a “Last Indexed” timestamp.

---

## What drives status in Onyx

- Connector pair state: `ConnectorCredentialPair` (status, `last_successful_index_time`, totals)
- Indexing lifecycle: `IndexAttempt` and `IndexAttemptError`
- Generic sync history: `SyncRecord`
- Completion logic: runs in background workers and updates the above

Key code (for reference):
- Sync record updates: `backend/onyx/db/sync_record.py` (`update_sync_record_status`)
- Connector pair updates: `backend/onyx/db/connector_credential_pair.py` (`_update_connector_credential_pair`, `resync_cc_pair`)
- Completion handler: `backend/onyx/background/celery/tasks/docprocessing/tasks.py` (`check_indexing_completion`)
- User files finalized: `backend/onyx/indexing/adapters/user_file_indexing_adapter.py` (`post_index` sets `UserFile.status=COMPLETED`)

---

## Typical root causes

1) Missing workers (Docfetching/Docprocessing/Beat) → pipeline never completes
2) Redis broker/result misconfig or outage → tasks not dispatched/collected
3) Model servers down → embeddings stall → attempt never terminal
4) Index backend (Vespa/pgvector) unreachable → write can’t finish
5) Completion callback didn’t run → no terminal status written
6) S3 (private storage) credentials/endpoint wrong for workers

---

## Kubernetes/OpenShift checklist

- Pods Ready:
  - Celery: Beat, Docfetching, Docprocessing, Primary
  - Model servers (index/inference)
  - Redis, Postgres, Vespa/pgvector
- Logs to tail around the stuck time:
  - Docfetching + Docprocessing workers
  - API server (attempt creation/status)
  - Model servers (embedding requests)
  - Index backend (Vespa/pgvector)

---

## Database queries (read-only) to pinpoint state

- Connector pair:
```sql
SELECT id, status, last_successful_index_time, total_docs_indexed, is_user_file
FROM connector_credential_pair
WHERE /* filter to your pair */ true
ORDER BY id DESC
LIMIT 5;
```

- Latest attempts:
```sql
SELECT id, connector_credential_pair_id, status, time_started, time_updated, search_settings_id
FROM index_attempt
WHERE connector_credential_pair_id = <CC_PAIR_ID>
ORDER BY time_started DESC
LIMIT 5;
```

- Attempt errors:
```sql
SELECT *
FROM index_attempt_error
WHERE index_attempt_id = <LATEST_ATTEMPT_ID>
ORDER BY id DESC
LIMIT 50;
```

- Sync records (if your UI reads these):
```sql
SELECT entity_id, sync_type, sync_status, sync_start_time, sync_end_time, num_docs_synced
FROM sync_record
WHERE entity_id = <CC_PAIR_ID>
ORDER BY sync_start_time DESC
LIMIT 10;
```

Interpretation:
- Attempt never SUCCESS/FAILED + no errors → likely worker/backends blocked
- Attempts SUCCESS but UI still “In Progress” → completion handler not executed; check docprocessing + Beat
- Errors present → fix dependency (model/index/S3/Redis) then re-run

---

## Fast remediation flow

1) Fix underlying dependency (workers/backends) per logs and health checks
2) Resync/reindex the connector pair from the UI (or via API if available)
3) If a hung attempt blocks progress, mark failed via admin tooling and retry (or restart docprocessing + beat only)
4) For user-file connectors, note they auto-pause on success; set ACTIVE or reschedule to re-run

Expected after fix:
- UI: “Indexed” (or “Paused” for user-file connectors) + fresh “Last Indexed” time
- DB: latest `index_attempt` is SUCCESS and `connector_credential_pair.last_successful_index_time` updated

---

## Services involved (high-level)

- API Server: creates attempts, exposes status to UI
- Celery Workers:
  - Docfetching: gathers files, prepares batches
  - Docprocessing: chunk → embed (model servers) → index (Vespa/pgvector)
  - Beat: schedules/monitors coordination tasks
- Redis: task broker + results
- Model services: embeddings/LLM
- Index backend: Vespa/pgvector for search
- Private S3: stores file payloads

---

## Common misconfig checks

- Redis host/port/password consistent across API and workers
- INDEXING_MODEL_SERVER_HOST/PORT resolve from worker pods
- Vespa/pgvector reachable and healthy
- S3 endpoint/credentials accessible from workers (same as API)
- NetworkPolicies allow worker → Redis/Postgres/Vespa/S3/Model servers

---

## If still stuck

Capture:
- Connector pair ID
- Latest `index_attempt` row + any errors
- Docprocessing + Docfetching logs around the run
- Model server logs during embeddings

Then re-run with the dependency fixed; the completion handler should flip statuses automatically.
