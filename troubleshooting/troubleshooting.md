# Onyx + Ollama Local Deployment — Troubleshooting Log

This document records every significant technical problem encountered while standing up **Onyx v4.0.5** with a local **Ollama** backend on macOS (Docker Compose), along with root causes, diagnostics, and workarounds applied.

**Environment at time of troubleshooting:**
- Project: `/Users/chihebmhamdi/Desktop/new_onyx/onyx`
- Deployment: `deployment/docker_compose`
- Onyx version in UI: **v4.0.5**
- Ollama on host: `http://127.0.0.1:11434`
- Models available locally: `llama3:latest`, `qwen3.5:0.8b`, `nomic-embed-text:latest`
- App URL: `http://localhost:3000` (nginx maps port 3000 → 80)

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Problem: Web UI Loads but Backend Shows Unavailable](#problem-web-ui-loads-but-backend-shows-unavailable)
3. [Problem: Admin Panel Not Visible](#problem-admin-panel-not-visible)
4. [Problem: Ollama Connection / Bearer Token Errors](#problem-ollama-connection--bearer-token-errors)
5. [Problem: Chat Hangs, Timeouts, or Returns Empty `{}`](#problem-chat-hangs-timeouts-or-returns-empty-)
6. [Problem: Qwen3.5 Specifically Broken](#problem-qwen35-specifically-broken)
7. [Problem: Llama3 + Tools Incompatibility](#problem-llama3--tools-incompatibility)
8. [Problem: Wrong LLM Provider Name in Database](#problem-wrong-llm-provider-name-in-database)
9. [Problem: Memory Tool Auto-Injected Despite Persona Tools Removed](#problem-memory-tool-auto-injected-despite-persona-tools-removed)
10. [Problem: Empty LLM Stream Packets (Streaming Internals)](#problem-empty-llm-stream-packets-streaming-internals)
11. [All Workarounds Applied (Summary)](#all-workarounds-applied-summary)
12. [Recommended Stable Configuration](#recommended-stable-configuration)
13. [Useful Diagnostic Commands](#useful-diagnostic-commands)
14. [What Still Needs a Proper Fix (Not Just Workarounds)](#what-still-needs-a-proper-fix-not-just-workarounds)

---

## Architecture Overview

Understanding the request path is essential for debugging:

```
Browser (localhost:3000)
    → nginx (onyx-nginx-1)
        → web_server (Next.js UI, port 3000 inside container)
        → api_server (FastAPI backend, port 8080 inside container)
            → LiteLLM (Python library inside api_server)
                → Ollama on host (host.docker.internal:11434)
```

**Key insight:** The browser never talks to Ollama directly. Every chat message goes through:
1. Onyx `api_server` chat loop (`llm_loop.py` → `llm_step.py`)
2. Onyx `LitellmLLM` wrapper (`multi_llm.py`)
3. LiteLLM HTTP client to Ollama's `/api/chat` endpoint

If chat fails, the failure can be in **any** of those layers — not just Ollama itself.

---

## Problem: Web UI Loads but Backend Shows Unavailable

### Symptoms
- Browser shows Onyx login or chat shell
- Red banner: **"The backend is currently unavailable"**
- `/api/health`, `/api/me`, `/api/settings` return errors in browser network tab

### Root Cause
**Nginx was proxying to a stale `api_server` container IP.**

When `api_server` is recreated (e.g. after `docker compose up -d` or env changes), Docker assigns a new internal IP. Nginx resolves upstream hostnames **once at startup** and caches the IP. If only `api_server` restarts but `nginx` does not, nginx keeps connecting to the old IP → **502 Bad Gateway**.

Nginx logs showed:
```
connect() failed (111: Connection refused) while connecting to upstream
upstream: "http://172.20.0.9:8080/health"
```
while the new `api_server` was at `172.20.0.10`.

### Workaround
```bash
cd deployment/docker_compose
docker compose restart nginx
```

Or restart the full stack:
```bash
docker compose up -d
```

### Prevention
Whenever you restart **only** `api_server` or `background`, also restart `nginx`:
```bash
docker compose restart api_server nginx
```

### Related Fix (earlier session): `web_server` unhealthy
`web_server` was failing its healthcheck because Next.js bound to the container hostname instead of `0.0.0.0`. Fixed by adding to `docker-compose.yml`:

```yaml
web_server:
  environment:
    - HOSTNAME=0.0.0.0
```

Without a healthy `web_server`, nginx may not start correctly either.

---

## Problem: Admin Panel Not Visible

### Symptoms
- User logged in but no **Admin Panel** link in sidebar
- Direct navigation to `/admin/configuration/language-models` redirects back to chat

### Root Cause
Onyx v4 gates admin UI by **user role**. Only `ADMIN` and `CURATOR` roles see the Admin Panel.

Database users at time of check:

| Email | Role |
|-------|------|
| `chihebmhamdi79@gmail.com` | **ADMIN** |
| `chiheb.mhamdi79@gmail.com` | BASIC |
| `anonymous@onyx.app` | LIMITED |

If logged in as `chiheb.mhamdi79@gmail.com` (BASIC), admin is intentionally hidden.

### Workaround
Log in as `chihebmhamdi79@gmail.com`, or promote the other account:

```sql
UPDATE "user" SET role = 'ADMIN' WHERE email = 'chiheb.mhamdi79@gmail.com';
```

### Admin URLs (admin accounts only)
- Language Models: `http://localhost:3000/admin/configuration/language-models`
- Users: `http://localhost:3000/admin/users`

**Note:** `/app/settings/*` is end-user settings, not admin.

---

## Problem: Ollama Connection / Bearer Token Errors

### Symptoms
```
litellm.APIConnectionError: OllamaException - Illegal header value b'Bearer '
```

### Root Cause
The Ollama provider was saved with an **empty API key** in `custom_config`:

```json
{"OLLAMA_API_KEY": ""}
```

LiteLLM still constructed an HTTP header:
```
Authorization: Bearer 
```
An empty Bearer token is an **illegal HTTP header value** → request fails before reaching Ollama.

This typically happens when the provider is configured via the **Ollama Cloud** tab with a blank API key, instead of **Self-hosted Ollama** with API Base URL only.

### Correct Configuration (Self-Hosted Ollama)
| Field | Value |
|-------|-------|
| Provider type | Self-hosted Ollama (`ollama_chat` in DB) |
| API Base | `http://host.docker.internal:11434` |
| API Key | **Leave blank / NULL** |
| custom_config | **NULL** (not empty string) |

### Workaround Applied (SQL)
```sql
UPDATE llm_provider
SET api_key = NULL, custom_config = NULL
WHERE id = 1;
```

### Why `host.docker.internal` and not `127.0.0.1`
`api_server` runs **inside Docker**. `127.0.0.1` inside the container refers to the container itself, not your Mac. `host.docker.internal` is Docker Desktop's hostname for the host machine.

Verify from inside the container:
```bash
docker exec onyx-api_server-1 curl -s http://host.docker.internal:11434/api/tags
```

---

## Problem: Chat Hangs, Timeouts, or Returns Empty `{}`

This was the most complex issue. Several distinct failures looked similar in the UI.

### Symptom A: Stuck on "Searching internal documents"
```
litellm.Timeout: Connection timed out after 60.0 seconds
Unexpected error running tool internal_search
```

**Cause:** Default assistant had tools enabled (especially `internal_search`). Each tool call triggers another LLM round-trip. Slow models (Qwen) + 60s socket timeout = cascade failure.

### Symptom B: Assistant replies with literal `{}`
- UI shows `{}` or `{ }`
- Database `chat_message.message` stored as `{ }`
- No error banner

**Cause:** Combination of:
1. Wrong provider (`ollama` vs `ollama_chat`)
2. Tools sent to models that don't support them
3. LLM stream returned tokens but Onyx received **empty deltas** (see [Streaming Internals](#problem-empty-llm-stream-packets-streaming-internals))
4. Corrupted chat history from prior failed turns

### Symptom C: Explicit tools error (after provider fix)
```
Ollama_chatException - {"error":"registry.ollama.ai/library/llama3:latest does not support tools"}
```

**Cause:** Onyx still sent tool definitions to Ollama even after persona tools were removed, because the **Memory tool** is auto-injected when `user.enable_memory_tool = true`.

---

## Problem: Qwen3.5 Specifically Broken

### Symptoms
```
LLM packet is empty (no content, reasoning, or tool calls)
completion_tokens=679  (tokens generated, but no visible content)
RuntimeError: LLM did not return an answer
```

### Root Cause 1: "Thinking" output not mapped to chat content
`qwen3.5:0.8b` is a **reasoning/thinking model**. By default, Ollama puts output in a `thinking` field, not `content`. Onyx's chat pipeline expects `content` or `reasoning_content` in LiteLLM stream deltas. Result: tokens are consumed, but the UI sees nothing.

**Direct Ollama test:**
```bash
# Default — often empty content, thinking filled
curl http://127.0.0.1:11434/api/chat -d '{"model":"qwen3.5:0.8b","messages":[{"role":"user","content":"hi"}],"stream":false}'

# Fix at Ollama level — disable thinking
curl http://127.0.0.1:11434/api/chat -d '{"model":"qwen3.5:0.8b","messages":[{"role":"user","content":"hi"}],"stream":false,"think":false}'
```

### Root Cause 2: Extreme slowness on this hardware
Direct benchmarks on the Mac:

| Model | Simple prompt | Result |
|-------|---------------|--------|
| `llama3:latest` | "Say hello" | ~6–12 seconds |
| `qwen3.5:0.8b` | "Say hello" (think:false) | **~68 seconds** for 2 tokens |
| `qwen3.5:0.8b` | default | **>120s timeout** |

Onyx default socket read timeout was **60 seconds** (`LLM_SOCKET_READ_TIMEOUT`). Qwen routinely exceeded this.

### Workarounds Applied
1. Changed default chat model to `llama3:latest` in DB
2. Added to `.env`:
   ```env
   LLM_SOCKET_READ_TIMEOUT=180
   LITELLM_EXTRA_BODY={"think": false}
   ```
3. Recommended: **do not use Qwen3.5 for Onyx agent chat** on this machine

### LLM / env var reference
| Variable | Purpose |
|----------|---------|
| `LLM_SOCKET_READ_TIMEOUT` | Max seconds between stream chunks (not total request time). Default 60. |
| `LITELLM_EXTRA_BODY` | JSON passed to LiteLLM → Ollama. `{"think": false}` disables Qwen thinking. |

These are loaded via `env_file: .env` in `docker-compose.yml` for `api_server` and `background`.

---

## Problem: Llama3 + Tools Incompatibility

### Symptoms
```
llama3:latest does not support tools
```

### Root Cause
Onyx's default **Assistant** persona (id=0) ships with tools:
- `internal_search`
- `web_search`
- `generate_image`
- `open_url`
- `read_file`
- `python`

Onyx sends these as OpenAI-style `tools` in the LiteLLM request. Ollama's native tool API only works on **specific models** (e.g. `gpt-oss`, `deepseek-r1` per Onyx's LiteLLM model map). **`llama3:latest` rejects tools entirely** when using `ollama_chat` provider.

With the legacy `ollama` provider (not `ollama_chat`), Llama3 sometimes returns **fake JSON tool calls as plain text** in `content` instead of real tool call objects — which Onyx may or may not parse correctly.

### Workarounds Applied
```sql
-- Remove all tools from default Assistant persona
DELETE FROM persona__tool WHERE persona_id = 0;

-- Stop auto-injecting Memory tool
UPDATE "user" SET enable_memory_tool = false;
```

After this, simple chat with Llama3 works.

### Trade-off
**Search, web, code interpreter, and memory features are disabled** until you either:
- Use an Ollama model with native tool support, or
- Use a cloud provider (OpenAI, Anthropic, etc.), or
- Re-add tools and accept Llama3 limitations

---

## Problem: Wrong LLM Provider Name in Database

### Symptoms
- Empty stream packets despite Ollama working via direct `curl`
- Broken message history formatting
- Inconsistent tool call behavior

### Root Cause
Onyx v4 UI saves providers as **`ollama_chat`**. The database had **`ollama`** (legacy/wrong value), likely from an earlier manual setup or migration.

Onyx code treats these differently:

| Check | `ollama` | `ollama_chat` |
|-------|----------|---------------|
| `is_ollama` flag in `multi_llm.py` | ❌ false | ✅ true |
| Ollama history message formatter | ❌ default | ✅ `_OllamaHistoryMessageFormatter` |
| `tool_choice` / `allowed_openai_params` | May be sent | Omitted (Ollama rejects them) |
| LiteLLM model string | `ollama/llama3:latest` | `ollama_chat/llama3:latest` |

### Workaround Applied
```sql
UPDATE llm_provider SET provider = 'ollama_chat' WHERE id = 1;
```

### Correct UI path
Admin → Configuration → Language Models → **Self-hosted Ollama** tab (saves as `ollama_chat`).

---

## Problem: Memory Tool Auto-Injected Despite Persona Tools Removed

### Symptoms
After `DELETE FROM persona__tool WHERE persona_id = 0`, chat still failed with **"does not support tools"**.

### Root Cause
`tool_constructor.py` **always injects `MemoryTool`** when `user.enable_memory_tool = true`, bypassing persona tool associations:

```python
# Always inject MemoryTool when the user has the memory tool enabled,
# bypassing persona tool associations and allowed_tool_ids filtering
if user.enable_memory_tool:
    ...
```

All three users had `enable_memory_tool = true` by default.

### Workaround Applied
```sql
UPDATE "user" SET enable_memory_tool = false;
```

### Note
Re-enable memory in user settings only when using a model that supports tools.

---

## Problem: Empty LLM Stream Packets (Streaming Internals)

This section explains the low-level behavior for readers who want LLM/streaming depth.

### What Onyx expects
Onyx chat uses **streaming** via LiteLLM (`stream=True`). Each chunk is a `ModelResponseStream` with:
```python
delta.content          # visible answer text
delta.reasoning_content  # thinking models
delta.tool_calls       # function calling
```

`llm_step.py` iterates these packets. If a packet has none of the above, it logs:
```
LLM packet is empty (no content, reasoning, or tool calls). Skipping
```

If **all** packets are empty but `usage.completion_tokens > 0`, the model generated tokens that never arrived in parseable deltas.

### Observed log pattern (broken chat)
```
LLM packet is empty ... finish_reason=stop ... usage=None
LLM packet is empty ... finish_reason=None ... usage=Usage(completion_tokens=3, ...)
```
Only **2 packets** for the entire response — one stop marker, one usage summary. No content chunks at all.

### Observed log pattern (working chat, after fixes)
No empty-packet warnings; tokens stream as `AgentResponseDelta` content chunks; DB stores full markdown answer.

### Onyx Ollama monkey patch
Onyx patches LiteLLM's `OllamaChatCompletionResponseIterator.chunk_parser` in:
`backend/onyx/llm/litellm_singleton/monkey_patches.py`

This patch:
- Maps Ollama `message.thinking` → `reasoning_content`
- Maps `message.content` → `content`
- Handles `done: true` chunks with `eval_count` usage
- Fixes tool call ID assignment

If Ollama returns content only in the final `done:true` chunk with malformed structure, or thinking-only output, the patch may still yield empty deltas.

### LiteLLM direct test (worked)
From inside `api_server` container:
```python
import litellm
resp = litellm.completion(
    model='ollama_chat/llama3:latest',
    api_base='http://host.docker.internal:11434',
    messages=[{'role':'user','content':'hello'}],
    stream=True,
    extra_body={'think': False},
)
# → content chunks: 'Hello', '!', ' It', ...
```

Same test **with tools** on `ollama_chat/llama3:latest`:
```
Ollama_chatException - llama3:latest does not support tools
```

Same test **with tools** on `ollama/llama3:latest` (legacy provider):
```
content = '{"name": "internal_search", "arguments":{"query": ""}}'
```
Fake JSON in `content` — Onyx may try fallback tool extraction from text.

### Chat loop and tools (high level)
```
User message
  → run_llm_loop()
    → construct_tools()        # builds tool list from persona + memory + search forcing
    → run_llm_step()           # streams LLM response
      → LitellmLLM.stream()    # LiteLLM → Ollama
    → if tool_calls: run_tool_calls()  # e.g. internal_search → another LLM call
    → repeat up to MAX_LLM_CYCLES (default 6)
    → final answer saved to chat_message
```

A single "hello" with tools enabled is **not** one LLM call — it can be search → re-prompt → answer, each with 60–180s timeout budget.

### Corrupted chat history
Failed turns saved `{ }` as assistant messages. Subsequent prompts included that garbage in history, causing unpredictable model behavior. **Always start a new chat** after fixing configuration.

---

## All Workarounds Applied (Summary)

### File changes

**`deployment/docker_compose/docker-compose.yml`**
```yaml
web_server:
  environment:
    - HOSTNAME=0.0.0.0   # fixes healthcheck / nginx dependency
```

**`deployment/docker_compose/.env`**
```env
LLM_SOCKET_READ_TIMEOUT=180
LITELLM_EXTRA_BODY={"think": false}
```

### Database changes

```sql
-- Fix Ollama credentials
UPDATE llm_provider
SET api_key = NULL, custom_config = NULL, provider = 'ollama_chat'
WHERE id = 1;

-- Default model: llama3 instead of qwen
UPDATE llm_provider SET default_model_name = 'llama3:latest' WHERE id = 1;
UPDATE llm_model_flow SET is_default = false WHERE model_configuration_id = 4;
UPDATE llm_model_flow SET is_default = true WHERE model_configuration_id = 3;

-- Disable tools on default Assistant (required for llama3)
DELETE FROM persona__tool WHERE persona_id = 0;

-- Stop auto memory tool injection
UPDATE "user" SET enable_memory_tool = false;
```

### Operational workarounds

| Action | When |
|--------|------|
| `docker compose restart nginx` | After restarting `api_server` alone |
| Start **new chat** | After any LLM config change |
| Hard refresh browser (`Cmd+Shift+R`) | After backend recovery |
| Log in as ADMIN account | To access Admin Panel |

---

## Recommended Stable Configuration

For **reliable local chat** on this Mac with Ollama:

| Setting | Value |
|---------|-------|
| Provider | `ollama_chat` |
| API Base | `http://host.docker.internal:11434` |
| API Key | NULL |
| Default model | `llama3:latest` |
| Persona tools | **Disabled** (for now) |
| Memory tool | **Disabled** |
| Timeout | 180s |
| Extra body | `{"think": false}` |

### Verified working flow
1. New chat
2. Model: **Llama3**
3. Message: `hello`
4. Response in ~20–40 seconds with full text answer

---

## Useful Diagnostic Commands

```bash
# Service status
cd deployment/docker_compose && docker compose ps

# API health through nginx
curl -s http://localhost:3000/api/health

# Ollama from host
curl -s http://127.0.0.1:11434/api/tags

# Ollama from api_server container
docker exec onyx-api_server-1 curl -s http://host.docker.internal:11434/api/tags

# Recent API errors
docker logs onyx-api_server-1 --tail 100 2>&1 | grep -iE "error|timeout|empty|warning"

# Nginx upstream failures
docker logs onyx-nginx-1 --tail 50 2>&1 | grep -i error

# LLM provider config
docker exec onyx-relational_db-1 psql -U postgres -d postgres -c \
  "SELECT id, name, provider, api_base, default_model_name FROM llm_provider;"

# Users and roles
docker exec onyx-relational_db-1 psql -U postgres -d postgres -c \
  "SELECT email, role, enable_memory_tool FROM \"user\";"

# Persona tools
docker exec onyx-relational_db-1 psql -U postgres -d postgres -c \
  "SELECT t.name FROM persona__tool pt JOIN tool t ON pt.tool_id=t.id WHERE pt.persona_id=0;"

# Recent chat messages for a session
docker exec onyx-relational_db-1 psql -U postgres -d postgres -c \
  "SELECT message_type, left(message, 80) FROM chat_message ORDER BY id DESC LIMIT 10;"

# Env vars inside api_server
docker exec onyx-api_server-1 python3 -c \
  "import os; print('timeout', os.getenv('LLM_SOCKET_READ_TIMEOUT')); print('extra', os.getenv('LITELLM_EXTRA_BODY'))"

# Restart api + nginx together (avoid stale upstream)
docker compose restart api_server nginx
```

---

## What Still Needs a Proper Fix (Not Just Workarounds)

These are architectural limitations, not just config typos:

1. **Nginx stale upstream IPs** — Consider Docker DNS resolver with `valid=10s` in nginx config, or always restart nginx with api_server.

2. **Llama3 + Onyx agent loop** — Onyx is designed around tool calling (search, web, python). Llama3 via Ollama cannot participate in that loop natively. Workaround is disabling tools; proper fix is a tool-capable model or cloud API.

3. **Qwen3.5 on CPU Mac** — Too slow for Onyx's multi-step agent (60–180s per LLM call × multiple calls). Not practical for this use case on current hardware.

4. **Provider name mismatch (`ollama` vs `ollama_chat`)** — Re-saving the provider in Admin UI after fresh install prevents this.

5. **Memory tool silent injection** — Surprising that `enable_memory_tool` bypasses persona tool settings; document or disable by default for local Ollama setups.

6. **Empty Bearer from blank Ollama Cloud API key** — UI should not save empty `OLLAMA_API_KEY` into `custom_config`; should be NULL for self-hosted.

7. **Broken chat history** — Failed `{}` responses pollute future turns; users may need to delete bad sessions or Onyx could filter empty assistant messages from history.

---

## Quick Decision Tree

```
Chat not working?
│
├─ UI says "backend unavailable"
│   └─ docker compose restart nginx
│
├─ No Admin Panel
│   └─ Log in as ADMIN user
│
├─ Error: Illegal header value b'Bearer '
│   └─ Clear api_key and custom_config on llm_provider
│
├─ Error: does not support tools
│   └─ Remove persona tools + disable enable_memory_tool
│
├─ Timeout after 60s
│   └─ Increase LLM_SOCKET_READ_TIMEOUT; switch to llama3
│
├─ Empty {} response
│   └─ Fix provider to ollama_chat; disable tools; new chat
│
└─ Qwen-specific empty content
    └─ LITELLM_EXTRA_BODY={"think": false} OR use llama3 instead
```

---

*Document generated from live troubleshooting session — June 2026.*
*Onyx v4.0.5 + Ollama local deployment on macOS Docker Desktop.*
