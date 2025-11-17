# Tokenizers, Embeddings, Context Windows & Chunking – Junior-Friendly Notes

Hey! Here's a quick informal guide to help you understand the key concepts and how they fit together in Onyx or any LLM pipeline. Let’s go through the terms one by one, then connect them and discuss what happens if stuff doesn’t match.

---

## 🧩 Tokenizer
- It’s the mechanism that chops text into smaller pieces called tokens.
- Different models have different tokenizers (like different scissors). Even slight differences mean the same sentence might produce 480 tokens for one model and 520 for another.
- Why it matters: we use token counts for chunking, cost estimation, pruning, and to stay within model limits.

### Junior Tip
Always know which tokenizer is being used at each step (embedding vs. LLM). Don’t assume they’re the same.

---

## 🎯 Embedding
- It converts text (tokens) into a vector (list of numbers) that represents the meaning.
- Used for semantic search—the closer the vectors, the closer the meaning.
- Embeddings don’t generate text—they help retrieve relevant chunks **before** the LLM answers.
- Embedding model ≠ LLM. They may have different tokenizers, vocab, dimensions, etc.

### Junior Tip
Embedding steps happen offline (file processing) or before you hit the LLM. They do not replace the LLM, they feed it the right info.

---

## 🧠 Context Window
- This is the LLM’s memory limit: how many tokens it can handle per request (prompt + documents + system message + expected answer).
- Example: GPT-4 32k → ~32,000 tokens per request.
- If you exceed it, the request will fail or get truncated.

### Junior Tip
Budget your tokens: system instructions + user prompt + documents to inject + answer headroom.

---

## 📦 Chunking
- Splitting large documents into smaller pieces before embeddings/token counting.
- Usually done using the **embedding model's tokenizer** because that’s what we have at indexing time.
- Helps with:
  - Better semantic retrieval (narrower context chunks)
  - Avoiding giant pieces that blow up memory

### Junior Tip
Chunk sizes are configured (e.g., 500 tokens). If chunk size is too big, retrieval will be coarse and pruning more painful later.

---

## ✂️ Pruning (aka Trimming)
- Happens right before sending stuff to the LLM.
- Onyx re-counts tokens using the **LLM tokenizer** and drops chunks if the total would exceed the context window.
- Essentially: “We thought this chunk was 500 tokens. LLM thinks it’s 650. Drop the extras until we fit.”

### Junior Tip
Pruning is your safety net when tokenizers disagree. Always log what got pruned so you can tune chunk sizes or thresholds later.

---

## ❓What if tokenizers are different?

| Scenario | What Happens |
|----------|---------------|
| **Embedding tokenizer ≠ LLM tokenizer** | Normal. Chunking uses embedding count, pruning re-counts using LLM. Without pruning, you risk overflowing the LLM window. |
| **Embedding tokenizer = LLM tokenizer** | Chunk counts stay accurate; pruning rarely drops data. Still keep pruning as safety. |
| **No pruning + mismatch** | Guaranteed disaster at scale: LLM errors like “context length exceeded” or truncated responses. |

### Junior Tip
Always assume tokenizers differ unless the doc explicitly says they’re the same model family. Pruning is mandatory, not optional.

---

## ✅ Best Practices & Project Tips

1. **Make chunk sizes smaller than the LLM’s comfortable budget.** Example: if you have 32k context, keep chunk batches under ~20k so you leave room for prompts + answer.
2. **Log token counts with both tokenizers.** Helps you see if the mismatch is manageable or huge.
3. **Adjust chunk size for the embedding stage** if pruning is deleting too much. Smaller chunk sizes → finer-grained retrieval and less waste.
4. **Reserve output tokens** in config (e.g., `GEN_AI_NUM_RESERVED_OUTPUT_TOKENS`). If you expect the answer to be long, reduce how many document tokens you allow.
5. **Monitor pruning stats.** If every request drops half the chunks, re-tune your pipeline (smaller chunk size, more aggressive top-k retrieval).
6. **If you control both models**, try using the same tokenizer (e.g., both from the same model family). It’s the easiest long-term fix.

---

## Quick Mental Model

```
Document → Tokenizer (embedding) → Chunk → Embedding → Store Vector

User question → Embedding → Similarity search → Retrieve chunk IDs

Before LLM call:
    Convert chunks back to text
    Tokenizer (LLM) counts again
    If too big: prune

LLM receives: system prompt + question + pruned chunks
```


That's the full flow. Keep pruning on, monitor token logs, and you’ll avoid context limit landmines—even if tokenizers disagree.

