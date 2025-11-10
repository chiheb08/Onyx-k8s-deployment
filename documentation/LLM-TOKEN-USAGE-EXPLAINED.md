# LLM Tokens in Onyx – Concepts, Effects, and Examples

## 🎯 What is a Token?

A *token* is the smallest unit of text that a Large Language Model (LLM) processes. Tokens usually represent short fragments – from single characters to entire words – depending on the language and tokenizer. Onyx interacts with LLMs (vLLM, OpenAI-compatible, Bedrock, etc.) using token counts for prompt construction, budgeting, and cost tracking.

- **1 token ≠ 1 word**: “Onyx” is one token, “internationalization” can be three tokens.
- **LLMs have context limits**: e.g., a 4K model accepts ~4,096 tokens total (prompt + response).
- **Tokens cost time and money**: Many providers bill per thousand tokens and latency rises linearly with token count.

---

## ⚙️ Token Flow Inside Onyx

```
User Prompt → Tokenizer → Prompt Builder → LLM (vLLM / External API)
                                 ↓
       Token Budgets · Chunk Limits · Response Token Reservation
```

1. **Tokenizer**: Splits user input and selected documents into tokens.
2. **Prompt Builder**: Counts tokens to decide how much context fits. Uses settings like `GEN_AI_MAX_TOKENS`, `MAX_TOKENS_FOR_FULL_INCLUSION`, and agent-specific budgets.
3. **LLM Call**: Onyx sends the prompt with a `max_tokens` (generation limit). The model returns streamed output token-by-token.
4. **Budgets & Logging**: If `TOKEN_BUDGET_GLOBALLY_ENABLED` is true, Onyx records token usage for each tenant and can reject over-budget requests.

---

## 📈 Why Token Counts Matter

| Effect | Description | Example |
|--------|-------------|---------|
| **Context Fit** | Prompts must stay within model context limits. Onyx trims or summarizes context when the limit is near. | Model with 8K limit: user prompt (1K tokens) + documents (6K) + system prompts (0.5K) = 7.5K tokens → only 0.5K left for output. |
| **Response Length** | `GEN_AI_NUM_RESERVED_OUTPUT_TOKENS` reserves output space. Prevents the prompt from consuming all tokens. | Reserve 1024 tokens ⇒ Onyx only sends 3K prompt tokens to a 4K model, guaranteeing the response has room to stream. |
| **Latency** | More tokens → longer generation time. | 300 prompt tokens + 700 output tokens ≈ 1000 tokens processed. If model generates ~50 tokens/sec, response arrives in ~14s. |
| **Cost** | Providers bill per input/output token. | OpenAI GPT-4o (example): $5 / 1M input tokens. A 1,000-token prompt costs ~$0.005. Onyx’s token logs help forecast spend. |
| **Retrieval Quality** | Chunking ensures documents fit into budgets. Very large documents get split so only the most relevant tokens are sent. | `STRICT_CHUNK_TOKEN_LIMIT` forces 512-token chunks. Each chunk adds to prompt until the limit is reached; remainder is skipped. |

---

## 📏 Example Calculations

### 1. Chat Request with Documents
- **User message**: 120 tokens
- **Selected documents**: 5 chunks × 350 tokens = 1,750 tokens
- **System prompt + instructions**: 200 tokens
- **Total prompt tokens**: 2,070 tokens
- **Reserved output** (`GEN_AI_NUM_RESERVED_OUTPUT_TOKENS` = 1024)
- **Model**: 4K context

➡️ Onyx sends 2,070 tokens, leaves 1,024 tokens for generation, and still has 906 tokens of unused headroom for follow-up instructions or intermediate prompts.

### 2. Long Document Upload
- **Original file**: 40,000 words (~60,000 tokens)
- **Chunking** (`DOC_EMBEDDING_CONTEXT_SIZE` = 512, overlap 50)
- **Chunks produced**: ≈ 120 chunks
- **Indexing**: Each chunk embedding call processes 512 tokens; total embedding tokens ≈ 61,440 tokens.
- **Budget impact**: If token budget is 3M/month, this upload consumes ~2% of monthly allowance.

### 3. Agent Workflow
- **Task**: Retrieve data and compose answer with sub-questions.
- **Env**: `AGENT_MAX_TOKENS_SUBQUESTION_GENERATION` = 128, `AGENT_MAX_TOKENS_ANSWER_GENERATION` = 1024.
- **Flow**:
  1. Validation: `AGENT_MAX_TOKENS_VALIDATION` (= 4) ensures only a few tokens used to confirm planning.
  2. Sub-questions: Each sub-question capped at 128 tokens.
  3. Final answer: Hard limit of 1024 tokens.
- **Effect**: Prevents agents from spiraling into lengthy prompts that exceed cost or latency budgets.

---

## 🛠️ Controlling Token Usage in Onyx

| Setting | Type | How it affects tokens |
|---------|------|-----------------------|
| `GEN_AI_MAX_TOKENS` | Prompt limit | Upper bound on prompt + response tokens when provider metadata missing. |
| `GEN_AI_NUM_RESERVED_OUTPUT_TOKENS` | Response reservation | Guarantees output space; increases prompt trimming if set high. |
| `MAX_TOKENS_FOR_FULL_INCLUSION` | Retrieval | If document < threshold, include entire doc; else summarize/truncate. |
| `STRICT_CHUNK_TOKEN_LIMIT` | Chunking | Forces each chunk to respect token count; prevents large blobs from entering prompt. |
| `TOKEN_BUDGET_GLOBALLY_ENABLED` | Budgeting | Activates per-tenant quota enforcement. Requests exceeding budget are rejected with clear errors. |
| `LOG_INDIVIDUAL_MODEL_TOKENS` | Observability | Logs input/output token counts for tracking cost and estimating throughput. |
| `AGENT_MAX_TOKENS_*` / `KG_*` | Specialized | Finely tune tokens for agent steps and KG answer generation. |

### Adjusting Limits
- **Reducing latency/cost**: Lower `GEN_AI_NUM_RESERVED_OUTPUT_TOKENS`, shrink agent budgets, or enable `STRICT_CHUNK_TOKEN_LIMIT`.
- **Allowing longer answers**: Increase `GEN_AI_NUM_RESERVED_OUTPUT_TOKENS`, ensure model context (4K/8K/32K) is sufficient, adjust chunk thresholds.
- **Enforcing budgets**: Turn on `TOKEN_BUDGET_GLOBALLY_ENABLED`, set per-tenant budgets in the admin UI (Enterprise feature).

---

## 🔍 Practical Tips

1. **Monitor token logs** when launching a new tenant. Large token spikes often indicate users pasting entire documents into the chat.
2. **Educate users**: Explain that prompt length and number of attachments affect latency and cost.
3. **Use summarization** for oversized documents. Onyx can summarize automatically, but curated summaries save budget.
4. **Benchmark models**: A 70B model may have 8K context but generate slower. Balance token limits with user experience.
5. **Cache embeddings**: Document indexing consumes tokens; avoid re-ingesting unchanged files.

---

## ✅ Key Takeaways

- Tokens are the core accounting unit for both cost and latency in LLM workflows.
- Onyx provides environment variables and safeguards to keep token usage within predictable limits.
- Proper configuration ensures users receive high-quality answers without exceeding budgets.
- Monitoring and adjusting token settings is essential for scaling Onyx deployments efficiently.

Use this guide when tuning deployments, onboarding new tenants, or auditing token consumption.
