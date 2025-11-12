# LLM Tokens – Super Simple Guide for Onyx Beginners

Think of an LLM as a person who reads a piece of paper (the **prompt**) and writes back a response (the **answer**). The paper can only hold so many words. In Onyx we use “**tokens**” to count those words/characters.

- Prompt tokens = what we give to the model (instructions + chat history + attached documents + your latest question).
- Output tokens = what the model writes back.
- Every model has a maximum number of tokens it can handle at once (its “page size”).

To avoid running out of space, we configure some environment variables. Here are the important ones, in plain English.

---

## 1. General LLM Token Settings

### `GEN_AI_MAX_TOKENS`
**Default:** Auto-detected; if not, this value is used.  
**What it means:** Maximum total tokens (prompt + response) the LLM can handle. Imagine the size of the paper. If a provider doesn’t tell us, we set it ourselves with this env var.

### `GEN_AI_NUM_RESERVED_OUTPUT_TOKENS`
**Default:** 1,024  
**What it means:** We reserve this many tokens for the model’s answer so the prompt doesn’t consume everything. Think: “leave some blank space at the bottom of the page for the reply.”  
**Example:** Model page size 8,000 tokens → reserve 1,024 → we only allow 6,976 tokens for the prompt.

### `GEN_AI_MODEL_FALLBACK_MAX_TOKENS`
**Default:** 4,096  
**What it means:** If we fail to detect the model’s page size, we fall back to this number.  
**Good to know:** For very large models (32K, 100K), you’ll want to set this higher.

### `GEN_AI_SINGLE_USER_MESSAGE_EXPECTED_MAX_TOKENS`
**Default:** 512  
**What it means:** Onyx assumes a single user message shouldn’t be longer than this. We subtract this when calculating document space.  
**Tip:** If users often paste long emails or documents directly, consider increasing it.

---

## 2. Token Budgets & Logging

### `TOKEN_BUDGET_GLOBALLY_ENABLED`
**Default:** `false`  
**What it means:** When `true`, Onyx tracks token usage per tenant and can enforce monthly or daily limits. Think of it as a “token meter” to control spend.

### `LOG_INDIVIDUAL_MODEL_TOKENS`
**Default:** `false`  
**What it means:** When `true`, we log how many tokens each request used (input + output). Helps with debugging and cost tracking.

---

## 3. Strict or Loose Context Handling

### `STRICT_CHUNK_TOKEN_LIMIT`
**Default:** `false`  
**What it means:** When `true`, document chunks are strictly cut off at the desired token limit so we never send oversized chunks to the LLM. Keeps prompts predictable but might drop the tail end of a document.

### `MAX_TOKENS_FOR_FULL_INCLUSION`
**Default:** 4096 (from backend)  
**What it means:** If a document is smaller than this many tokens, include it whole. If it’s larger, summarize or truncate.  
**Analogy:** “If the PDF is short, send it all. If it’s long, send only the best parts.”

### `DEFAULT_CONTEXT_TOKENS` (frontend constant)
**Location:** `web/src/app/chat/components/ChatPage.tsx`  
**What it means:** Client-side default context size (120,000) used when backend information isn’t available. Frontend multiplies the backend allowance by 0.5 as an extra safety guard.

---

## 4. Knowledge Graph (KG) and Agent-specific Limits

These settings control specialized features like knowledge graphs and agent workflows. If you’re just running basic chat, you can leave defaults.

| Variable | Default | Meaning |
|----------|---------|---------|
| `KG_SQL_GENERATION_MAX_TOKENS` | 1500 | Max tokens used when generating SQL queries for KG connectors. |
| `KG_MAX_TOKENS_ANSWER_GENERATION` | 1024 | Cap for KG answer generation. |
| `AGENT_MAX_TOKENS_VALIDATION` | 4 | Tokens used to validate agent plans (keep tiny). |
| `AGENT_MAX_TOKENS_SUBANSWER_GENERATION` | 256 | Max tokens for sub-answer steps. |
| `AGENT_MAX_TOKENS_ANSWER_GENERATION` | 1024 | Cap for final agent answer. |
| `AGENT_MAX_TOKENS_SUBQUESTION_GENERATION` | 256 | Limit for generating sub-questions. |
| `AGENT_MAX_TOKENS_ENTITY_TERM_EXTRACTION` | 1024 | Limit when extracting entities. |
| `AGENT_MAX_TOKENS_SUBQUERY_GENERATION` | 64 | Limit for follow-up queries. |
| `AGENT_MAX_TOKENS_HISTORY_SUMMARY` | 128 | Size for summarizing long chat history. |

**Simple rule:** These values control how much each agent sub-task can write. Smaller values mean faster, cheaper, but sometimes less thorough answers; larger values give richer responses but cost more.

---

## 5. Putting It All Together – Simple Example

Let’s say we use a 8,000-token model with the default settings above.

1. **Reserve reply space**: `GEN_AI_NUM_RESERVED_OUTPUT_TOKENS = 1024` → 8,000 − 1,024 = 6,976 tokens left for the prompt.
2. **Subtract prompts & buffer**: (system + task prompts ≈ 500) + expected user message (512) + buffer (40) → 1,052 tokens. 6,976 − 1,052 = **5,924** tokens remain for documents/context.
3. **Frontend guard**: Chat UI uses half of that (2,962 tokens) so users don’t accidentally hit the limit.
4. **During the conversation**: Each user message adds to the history. If it gets too big, Onyx summarizes or drops older bits based on these limits.
5. **Answer generation**: LLM writes up to 1,024 tokens (our reserved space). If it tries to go beyond, provider stops it.

So the environment variables make sure:
- We always save space for answers.
- We never crash the model with oversized prompts.
- We can tune how chat history, documents, and agent steps use the token budget.

---

## ✅ Quick Recommendations for Newbies

1. Leave defaults unless you have a strong reason (e.g., long documents or large models).
2. If you frequently hit “context window exceeded”, increase `GEN_AI_NUM_RESERVED_OUTPUT_TOKENS` (or reduce to allow bigger prompts) and adjust the frontend multiplier.
3. Turn on `LOG_INDIVIDUAL_MODEL_TOKENS` temporarily when debugging cost/latency issues.
4. Use `TOKEN_BUDGET_GLOBALLY_ENABLED` if you need to enforce monthly token quotas per team.
5. Treat agent and KG limits as advanced options—tune them only after the basic chat UX feels good.

With this cheat sheet you can talk tokens with your team, change limits safely, and understand why Onyx sometimes refuses to add more context. Tokens sound scary at first, but they’re just how we keep the conversation page from overflowing.
