# Context Handling in Onyx – Buffers, Headroom, and Personas

## 🧠 Key Terms

### Buffer
A **buffer** is a small token allowance the system subtracts to stay safe. Onyx pulls a few extra tokens off the top so minor counting errors or unexpected formatting do not overflow the model’s limit.

- In `compute_max_document_tokens()`, the buffer is **40 tokens** (`_MISC_BUFFER`).
- Example: Model context = 8,000 tokens. After subtracting prompts/user message, 7,200 tokens remain. Subtract 40-token buffer → **7,160 tokens** for documents. That little cushion prevents a “context length exceeded” error.

### Headroom
**Headroom** is the free space that remains after placing the prompt and expected response inside the model’s context window. It’s the same idea as buffer but usually larger—extra breathing room.

- Backend headroom: reserving 1,024 tokens for the answer (`GEN_AI_NUM_RESERVED_OUTPUT_TOKENS`).
- Frontend headroom: halving the allowance `(maxTokens * 0.5)` so users can’t unintentionally select too much context.
- Think of headroom as the part you leave blank so the LLM has room to reply.

### Persona
A **persona** is the configuration for an assistant. It bundles system prompt, tools, and model settings (including token-related values).

- `PromptConfig.from_model(persona)` loads the persona’s system prompt.
- `get_llms_for_persona(persona)` returns the LLM + configuration (e.g., max input tokens).
- Personas let different teams use different limits: the “Finance” persona could use a 32K model, the “Support Bot” a 4K model.

---

## 🔄 How Onyx Handles Context (Step by Step)

### Example Setup
- Model context window: **8,000 tokens**
- Reserved output tokens: **1,024**
- System prompt: **300** tokens
- Task prompt (persona instructions): **200** tokens
- Expected user message: **512** tokens
- Buffer: **40** tokens

**Backend calculation (`compute_max_document_tokens()`):**
```
Available = 8,000 (model limit)
          - 1,024 (reserved answer space)
          - (300 + 200) (prompts)
          - 512 (expected user input)
          - 40 (buffer)
          = 5,924 tokens
```

So the backend tells the frontend: “You can safely use **5,924** tokens for documents.”

### Frontend adjustments
1. **Additional headroom**: `ChatPage.tsx` multiplies by 0.5 → 2,962 tokens offered to the UI.
2. **Document selection guard**: `DocumentResults.tsx` disables the “Select” button once document tokens exceed `maxTokens - 75`.
3. **File upload guard**: `ChatInputBar.tsx` compares total attached file tokens to the halved allowance to hide the “still processing” banner.

### Full walk-through
1. **User selects persona “Legal Analyst”** (8K model, reserved output 1,024).
2. **Backend** → `/max-selected-document-tokens` returns **5,924**.
3. **Frontend** sets `availableContextTokens = 2,962` (50% of backend value).
4. User attaches documents: contract (2,000 tokens) + policy memo (600 tokens).
   - Total 2,600 tokens < 2,962 → allowed.
5. User attaches third doc (800 tokens): total = 3,400 tokens > 2,962 → selector greys out; hover message says “LLM context limit reached 😔”.
6. User removes policy memo; total = 2,800 tokens → button re-enables.
7. Prompt builder combines:
   - System prompt (300) + task prompt (200)
   - User message (actual size, say 250 tokens)
   - Document chunks (2,800 tokens in this example)
   - Adds buffer (40) → total ≈ 3,590 tokens
   - Leaves 1,024 tokens headroom for the answer.
8. LLM responds within the reserved space, no overflow.

---

## 🛠️ Adjusting the Numbers

| Goal | Change |
|------|--------|
| Use full backend allowance | Remove `* 0.5` multiplier in `ChatPage.tsx`. |
| Keep a smaller safety margin | Change multiplier to 0.7 or 0.8. |
| Change buffer size | Modify `_MISC_BUFFER` in `citations_prompt.py`. |
| Reserve more/less reply tokens | Update `GEN_AI_NUM_RESERVED_OUTPUT_TOKENS`. |
| Persona-specific rules | Create/adjust personas to use models with different context windows. |

---

## ✅ Key Takeaways

- **Buffer** ≈ small safety subtraction (40 tokens).
- **Headroom** ≈ the leftover space for the model to answer (backend + frontend guards).
- **Persona** ≈ assistant profile that defines prompts and model limits.
- Onyx applies token rules in layers: backend safe limits → frontend extra guard → prompt builder ensures room for user message + output.

Use these knobs to balance reliability (no context overflow) with flexibility (give users as much context as you trust). When adjusting limits, rebuild the web app so the new behavior is visible immediately.
