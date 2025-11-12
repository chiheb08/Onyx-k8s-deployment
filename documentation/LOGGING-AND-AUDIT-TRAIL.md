# Logging & Audit Trail in Onyx

This guide explains how Onyx records application logs, where user prompts and LLM answers are stored, and how you can trace conversations per user.

---

## 1. Logging Stack Overview

### Python logging adapter
- `onyx/utils/logger.py` wraps the standard `logging` module.
- Every module calls `setup_logger(__name__)`, which:
  - Adds a request ID filter (so each log line shows the FastAPI request ID).
  - Annotates logs with tenant ID, indexing attempt ID, or Slack channel if present.
  - Supports a custom **NOTICE** level between INFO and WARNING.

### Outputs
- **stdout / stderr** – default stream handler, used by API server, worker pods, and uvicorn.
- **Rotating log files** (optional) – enabled when either
  - `DEV_LOGGING_ENABLED=true`, or
  - the process runs in a container and `LOG_FILE_NAME` is set.
  - Files live at `/var/log/onyx/<LOG_FILE_NAME>_{debug|info|notice}.log` (or `./log/...` in local dev) with 25 MB rotation and 5 backups.

### Key environment variables
| Variable | Default | Effect |
|----------|---------|--------|
| `LOG_LEVEL` | `info` | Controls minimum severity for all Onyx loggers. Values: debug/info/notice/warning/error. |
| `LOG_FILE_NAME` | `onyx` | Base filename for rotating logs; set empty to disable file outputs. |
| `DEV_LOGGING_ENABLED` | `false` | When true, truncates local log files on start and enables rotating handlers even outside containers. |

### Extras
- Uvicorn access logs use the same request ID filter via `setup_uvicorn_logger`.
- Optional tracing integrations (`onyx/tracing/langfuse_tracing.py`, `braintrust_tracing.py`) can be turned on by providing the respective API keys. These push prompt/answer metadata to Langfuse or Braintrust.

Diagram:
```
FastAPI / Celery code
    │  logger = setup_logger(__name__)
    ▼
Python logging system
    ├─ StreamHandler → stdout/stderr (kubectl logs)
    └─ RotatingFileHandler (if enabled)
            → /var/log/onyx/onyx_info.log (25 MB x5)
```

---

## 2. Where Prompts & Answers Are Stored

All chat messages are saved in Postgres.

### Tables of interest
- `chat_session`
  - `id` (UUID)
  - `user_id` (owner)
  - `persona_id`, timestamps, etc.
- `chat_message`
  - `chat_session_id` (foreign key)
  - `message_type` (`user`, `assistant`, `tool`, `error`, ...)
  - `message` (full text of the prompt or LLM answer)
  - `token_count`, `citations`, `files`, timestamps.
- `chat_message_feedback`, `document_retrieval_feedback` (optional per-message ratings).

The API server writes:
1. A **user** message row when you send a prompt.
2. An **assistant** message row when streaming finishes.

Therefore you already have a complete audit trail by querying these tables.

Example SQL (psql):
```sql
SELECT
    cs.id              AS chat_session_id,
    u.email            AS user_email,
    cm.message_type,
    cm.time_sent,
    cm.message         AS text,
    cm.token_count,
    cm.citations
FROM chat_message AS cm
JOIN chat_session AS cs ON cm.chat_session_id = cs.id
JOIN "user" AS u        ON cs.user_id = u.id
WHERE cs.user_id = '<<USER_UUID>>'
ORDER BY cm.time_sent;
```
Replace `<<USER_UUID>>` with the user’s UUID (or filter by `u.email`). This returns prompt/answer pairs in chronological order.

To export all conversations, simply remove the `WHERE` clause and aggregate by user or session.

### Streaming packets
While LLM responses arrive packet-by-packet over SSE/WebSocket, the final assembled text is stored in `chat_message.message`. You do not need to reconstruct packets manually for auditing.

---

## 3. Capturing Prompts + Answers in Logs

If you need the prompt/answer to appear in the **logs** (rather than querying Postgres):
1. Hook into `onyx/chat/process_message.py` after the prompt is built (before calling the LLM) and log `currMessage` + selected documents.
2. Hook after streaming finishes to log the assistant message.

```python
logger.info(
    "Prompt",
    extra={
        "chat_session_id": str(chat_session_id),
        "user_id": str(chat_session.user_id),
        "message": message_text,
        "documents": [doc.semantic_identifier for doc in documents],
    },
)
```
Because `setup_logger` already injects tenant and request IDs, your log line will carry enough metadata to correlate with database rows. For sensitive deployments ensure logs are sent to a secure sink (e.g., CloudWatch, GCP Logging, ELK).

> ⚠️ Remember to comply with privacy and retention policies when logging raw prompts. Heavy redaction or encryption may be required for PII.

---

## 4. Additional Observability Hooks

- **Language tracing**: Supplying `LANGFUSE_PUBLIC_KEY/SECRET_KEY` or `BRAINTRUST_API_KEY` activates external tracing. These services store prompts/answers with metadata automatically.
- **Token usage logs**: Set `LOG_INDIVIDUAL_MODEL_TOKENS=true` to emit per-request token counts (helpful for cost analysis).
- **Metrics**: Prometheus endpoints (`/metrics`) expose request counts, latency, etc. Combine with log-based exports for full insight.

---

## 5. Summary Cheat Sheet

| Need | Recommended Approach |
|------|----------------------|
| Inspect raw logs | Tail stdout (`kubectl logs`) or check rotating files (if enabled). |
| Audit prompts/answers per user | Query `chat_message` + `chat_session` in Postgres; uses existing schema. |
| Push to external observability | Enable Langfuse / Braintrust integrations. |
| Log prompts for debugging | Add explicit `logger.info` hooks (ensure compliance). |
| Control volume / level | Adjust `LOG_LEVEL`, `LOG_FILE_NAME`, `DEV_LOGGING_ENABLED`. |

With these tools you can trace every prompt and answer, correlate them with specific users or tenants, and route logs to the destinations you need for compliance or debugging.
