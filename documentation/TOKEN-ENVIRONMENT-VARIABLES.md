# Token Environment Variables in Onyx

## 🎯 Purpose

Onyx uses environment variables containing the word “token” in two ways:

- **Security / Authentication tokens** – secrets or endpoints used to issue, verify, or exchange authentication tokens for users and external OAuth flows.
- **Token budgets / LLM limits** – numeric values that cap the number of LLM tokens consumed when generating answers.

The table below lists every token-related environment variable present in the repository, explains what it controls, and points to the relevant source files.

---

## 🔐 Authentication & Verification Tokens

| Environment Variable | Source File | Purpose | Notes |
|----------------------|-------------|---------|-------|
| `USER_AUTH_SECRET` | `backend/onyx/configs/app_configs.py` | Secret key used by FastAPI Users to sign password reset, email verification, and invitation tokens. | **Required** in production. Store securely (Kubernetes Secret, Vault, etc.). |
| `WEB_CONNECTOR_OAUTH_TOKEN_URL` | `backend/onyx/configs/app_configs.py` | Overrides the OAuth token-exchange endpoint for the Web connector. | Optional; only set if your OAuth provider uses a custom token URL. |
| `AWS_BEARER_TOKEN_BEDROCK` | Set dynamically in `backend/onyx/server/manage/llm/api.py` | Temporary bearer token injected when administrators call Amazon Bedrock through the admin API. | Usually passed per-request; not a static deployment variable. |

### Session Token Concept
- Login requests use `USER_AUTH_SECRET` to sign short-lived session tokens stored in Redis or Postgres.
- Email verification and password reset links embed tokens derived from the same secret.
- Invited-user flows check the whitelist before issuing verification tokens.

---

## 🌐 Connector Access Tokens

These environment variables are used by connectors (especially in tests or local development) to authenticate against third-party services. In production, store them in the Onyx credential store or an external secret manager.

| Connector / Service | Environment Variable(s) |
|---------------------|-------------------------|
| Atlassian Confluence | `CONFLUENCE_ACCESS_TOKEN`, `CONFLUENCE_ACCESS_TOKEN_SCOPED` |
| Jira | `JIRA_API_TOKEN`, `JIRA_API_TOKEN_SCOPED` |
| Slack | `SLACK_BOT_TOKEN` (bot token prefix `xoxb-` enforced) |
| Zendesk | `ZENDESK_TOKEN` |
| Salesforce | `SF_SECURITY_TOKEN` |
| Notion | `NOTION_INTEGRATION_TOKEN` |
| GitHub | `ACCESS_TOKEN_GITHUB`, `GITHUB_ACCESS_TOKEN` |
| GitLab | `GITLAB_ACCESS_TOKEN` |
| Bitbucket | `BITBUCKET_API_TOKEN` |
| Airtable | `AIRTABLE_ACCESS_TOKEN` |
| HubSpot | `HUBSPOT_ACCESS_TOKEN` |
| Discord | `DISCORD_BOT_TOKEN` |
| Egnyte | `EGNYTE_ACCESS_TOKEN` |
| Dropbox | `DROPBOX_ACCESS_TOKEN` |
| Document360 | `DOCUMENT360_API_TOKEN` |
| Productboard | `PRODUCTBOARD_ACCESS_TOKEN` |
| Guru | `GURU_USER_TOKEN` |
| Loopio | `LOOPIO_CLIENT_TOKEN` |
| Slab | `SLAB_BOT_TOKEN` |
| Outline | `OUTLINE_API_TOKEN` |
| Axero | `AXERO_API_TOKEN` |
| Asana (tests) | `API_TOKEN` |

> These tokens grant access to external systems. Never commit values to source control. Inject them via secrets at deployment time or through the Onyx admin UI.

---

## 🧠 LLM Token Budgets & Generation Limits

| Environment Variable | Source File | Description |
|----------------------|-------------|-------------|
| `GEN_AI_MAX_TOKENS` | `backend/onyx/configs/model_configs.py` | Overrides the maximum token context length when the LLM provider does not report it. |
| `GEN_AI_NUM_RESERVED_OUTPUT_TOKENS` | `model_configs.py` | Number of tokens reserved for the LLM's response so prompts do not consume the entire context (default `1024`). |
| `GEN_AI_MODEL_FALLBACK_MAX_TOKENS` | `model_configs.py` | Fallback total context size (default `4096`). |
| `GEN_AI_SINGLE_USER_MESSAGE_EXPECTED_MAX_TOKENS` | `model_configs.py` | Expected maximum length of a single user message when sizing prompts. |
| `KG_SQL_GENERATION_MAX_TOKENS` | `backend/onyx/configs/kg_configs.py` | Caps tokens used when generating SQL for knowledge-graph connectors. |
| `KG_MAX_TOKENS_ANSWER_GENERATION` | `kg_configs.py` | Token budget for knowledge-graph answer generation. |
| `AGENT_MAX_TOKENS_*` family | `backend/onyx/configs/agent_configs.py` | Series of limits for agent subtasks (validation, subanswers, answer generation, subquestions, entity extraction, history summary). Each has a default if the variable is unset. |
| `STRICT_CHUNK_TOKEN_LIMIT` | `shared_configs/configs.py` | Forces document chunking to respect strict token limits when enabled. |
| `MAX_TOKENS_FOR_FULL_INCLUSION` | `backend/onyx/configs/app_configs.py` | Threshold deciding when entire documents can be inserted into prompts without truncation. |
| `TOKEN_BUDGET_GLOBALLY_ENABLED` | `app_configs.py` | Enables tenant-wide token usage tracking and enforcement. |
| `LOG_INDIVIDUAL_MODEL_TOKENS` | `app_configs.py` | Logs per-request token counts for observability when set to `true`. |

### Token Budget Concept
- Onyx tracks how many LLM tokens are consumed per request.
- `TOKEN_BUDGET_GLOBALLY_ENABLED` toggles the quota system; useful for multi-tenant deployments.
- Logging (`LOG_INDIVIDUAL_MODEL_TOKENS`) helps operators understand usage patterns.

---

## 🧾 Token Prefixes & Validation

| Constant | Location | Purpose |
|----------|----------|---------|
| `SLACK_USER_TOKEN_PREFIX` (`xoxp-`) | `backend/onyx/configs/constants.py` | Ensures Slack user tokens match the expected pattern. |
| `SLACK_BOT_TOKEN_PREFIX` (`xoxb-`) | Same file | Validates Slack bot tokens before use. |

While not environment variables, these constants explain format checks applied to provided tokens.

---

## ✅ Key Takeaways

1. **Session Security** – `USER_AUTH_SECRET` underpins all user-facing tokens (sessions, verifications, invites). Protect it carefully.
2. **Connector Access** – A large collection of `*_TOKEN` or `*_ACCESS_TOKEN` variables provide credentials to external systems. Store them securely and inject at runtime.
3. **LLM Budgeting** – `GEN_AI_*`, `KG_*`, and `AGENT_MAX_TOKENS_*` variables fine-tune how many tokens the model can consume per task.
4. **Operational Controls** – Flags like `TOKEN_BUDGET_GLOBALLY_ENABLED` and `LOG_INDIVIDUAL_MODEL_TOKENS` help operators enforce quotas and observe usage.

Use this document as a checklist when configuring deployments, writing infrastructure scripts, or auditing secret usage across the Onyx platform.
