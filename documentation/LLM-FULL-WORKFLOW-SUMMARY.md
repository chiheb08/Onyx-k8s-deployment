# LLM Workflow in Onyx – Simple, Step-by-Step Summary

This guide explains how Onyx handles a user request from the browser all the way through the Large Language Model (LLM) and back. Each step shows what data flows where, which components are involved, and what token budgeting / security checks happen.

---

## 1. User Sends a Message (Browser)

1. User types a question (optionally attaches files or selects documents).
2. Browser sends the request to Onyx through HTTPS (via NGINX gateway).
3. Request includes:
   - Chat session ID
   - Message text
   - List of document IDs to include
   - User's session token (JWT stored in cookie)

**Tokens affect this step because** the length of the user’s message counts toward the prompt size.

---

## 2. NGINX Gateway (Reverse Proxy)

1. Receives HTTPS request, terminates TLS.
2. Extracts the session token from cookies/headers.
3. Forwards the request to the API server.

No token calculations here, but NGINX guarantees the request is authenticated before it reaches the backend.

---

## 3. API Server (FastAPI)

1. Validates the session token (ensures user is authenticated and verified).
2. Checks access permissions (user can only access their own chat sessions and documents).
3. Retrieves the user profile, tenant settings, and preferences (e.g., max tokens, preferred models).
4. Fetches selected documents from PostgreSQL (metadata) and MinIO (file storage) if needed.

**Token relevance:** API server prepares data but does not yet count tokens – that happens during the prompt building stage.

---

## 4. Retrieval & Chunking

1. Onyx gathers relevant context:
   - Selected documents are pulled from MinIO and split into chunks (based on token limits like `STRICT_CHUNK_TOKEN_LIMIT`).
   - Chat history is loaded (previous turns for the session).
   - System prompts / instructions are prepared.
2. Each document chunk is summarized or trimmed if too large (`MAX_TOKENS_FOR_FULL_INCLUSION` controls whether the whole chunk fits).

**Token relevance:** At this point, Onyx knows roughly how many tokens the context will contribute because each chunk is measured in tokens.

---

## 5. Prompt Builder (Token Accountant)

This is where Onyx puts everything together and ensures it fits the model’s context window.

1. Combine instructions + user message + relevant chat history + document chunks.
2. Count tokens for each piece (using the tokenizer for the selected model).
3. Reserve tokens for the output (`GEN_AI_NUM_RESERVED_OUTPUT_TOKENS`).
4. If total exceeds the model’s max context (e.g., 4K or 8K tokens):
   - Drop lowest-priority chunks (e.g., oldest history or lowest scoring documents).
   - Summarize or truncate remaining content.
5. Build the final prompt to send to the LLM.

**Key environment variables that control this step:**
- `GEN_AI_MAX_TOKENS` – fallback context size.
- `GEN_AI_NUM_RESERVED_OUTPUT_TOKENS` – ensures reply space.
- `MAX_TOKENS_FOR_FULL_INCLUSION` – when to include entire docs versus summary.
- `TOKEN_BUDGET_GLOBALLY_ENABLED` – if enabled, also checks tenant quota.

---

## 6. LLM Call (vLLM or External Provider)

1. API server sends the prompt and `max_tokens` limit to the LLM endpoint.
2. Depending on deployment:
   - **Self-hosted vLLM**: Onyx sends request to the internal model server.
   - **External API**: Onyx sends request to OpenAI, AWS Bedrock, etc., using stored API keys/token.
3. LLM streams response tokens back while Onyx forwards them to the browser via SSE/WebSocket.

**Token relevance:**
- Input tokens = prompt length.
- Output tokens = actual generated text.
- Providers bill on both numbers; Onyx logs them if `LOG_INDIVIDUAL_MODEL_TOKENS` is true.

---

## 7. Post-processing & Citation Merge

1. As tokens arrive, Onyx attaches citations (document IDs + metadata) for each snippet referenced.
2. Applies optional formatting (markdown rendering, bullet lists, etc.).
3. Updates chat session with the new assistant message stored in PostgreSQL.
4. Increments token usage counters in the token budget (if enabled).

**Token relevance:** Output tokens determine how much content is added to the chat history. Future prompts include these tokens unless trimmed.

---

## 8. Response Delivered to User

1. Browser receives streaming tokens and renders the answer in real time.
2. The full response with citations is saved in the chat history.
3. User can continue the conversation, select more files, or end the session.

**Token relevance:** Everything in the final answer becomes part of the history and may contribute to token counts in subsequent turns.

---

## 🔁 Token Budget & Monitoring

1. If `TOKEN_BUDGET_GLOBALLY_ENABLED` is active, Onyx tracks per-tenant token usage.
2. When the budget is close to being exhausted, Onyx can:
   - Log warnings.
   - Block new requests.
   - Provide error messages about exceeded budget.
3. Operators can view token logs (when `LOG_INDIVIDUAL_MODEL_TOKENS=true`) to analyze costs.

---

## ✅ Quick Reference Table

| Step | Component | Token Impact |
|------|-----------|--------------|
| 1 | Browser | User input length becomes prompt tokens. |
| 2 | NGINX | Auth only – no counting. |
| 3 | API | Validates permissions; still no counting. |
| 4 | Retrieval | Chunks documents based on token limits. |
| 5 | Prompt Builder | **Main token accounting** – ensures prompt fits context. |
| 6 | LLM Call | Provider bills for input/output tokens. |
| 7 | Post-processing | Adds generated tokens to chat history. |
| 8 | Browser | Streams answer; tokens become part of future context. |

---

## 🔚 Summary

- Tokens are the “budget” each conversation consumes.
- Onyx manages tokens at multiple points to stay within model limits and budgets.
- You can adjust token behavior using environment variables (`GEN_AI_*`, `AGENT_MAX_TOKENS_*`, `TOKEN_BUDGET_GLOBALLY_ENABLED`, etc.).
- Understanding the flow helps you optimize latency, cost, and retrieval quality.

Use this simple walkthrough when explaining LLM operations to teammates or when tuning token-related settings in your deployment.
