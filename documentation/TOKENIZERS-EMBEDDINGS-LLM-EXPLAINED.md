# Tokenizers, Embeddings, and LLMs: A Complete Guide

This document explains how tokenizers, embeddings, and LLMs work together in Onyx, why tokenizer mismatches matter, and how document pruning prevents errors.

---

## Table of Contents

1. [What is a Tokenizer?](#what-is-a-tokenizer)
2. [What are Embeddings?](#what-are-embeddings)
3. [How LLMs Use Tokens](#how-llms-use-tokens)
4. [The Tokenizer Mismatch Problem](#the-tokenizer-mismatch-problem)
5. [How Onyx Handles This](#how-onyx-handles-this)
6. [Real-World Example](#real-world-example)
7. [Troubleshooting](#troubleshooting)

---

## What is a Tokenizer?

### Simple Explanation

A **tokenizer** is like a translator that converts human-readable text into a format that AI models can understand. Think of it as breaking down a sentence into smaller, manageable pieces.

### How It Works

**Step 1: Input Text**
```
"The quick brown fox jumps over the lazy dog"
```

**Step 2: Tokenization Process**

The tokenizer splits this into "tokens" (pieces). Different tokenizers split differently:

**Example A: Word-based tokenizer**
```
["The", "quick", "brown", "fox", "jumps", "over", "the", "lazy", "dog"]
→ 9 tokens
```

**Example B: Subword tokenizer (like BPE - Byte Pair Encoding)**
```
["The", "quick", "brown", "fox", "jumps", "over", "the", "lazy", "dog"]
→ 9 tokens (same in this case, but handles unknown words better)
```

**Example C: Character-based tokenizer**
```
["T", "h", "e", " ", "q", "u", "i", "c", "k", ...]
→ 44 tokens (one per character including spaces)
```

### Visual Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    INPUT TEXT                            │
│  "The quick brown fox jumps over the lazy dog"          │
└──────────────────────┬────────────────────────────────────┘
                       │
                       ▼
            ┌──────────────────────┐
            │     TOKENIZER         │
            │  (Splits text into    │
            │   smaller pieces)     │
            └──────────┬────────────┘
                       │
                       ▼
        ┌───────────────────────────────┐
        │      TOKENIZED OUTPUT         │
        │  ["The", "quick", "brown",    │
        │   "fox", "jumps", "over",     │
        │   "the", "lazy", "dog"]       │
        │                               │
        │  Total: 9 tokens              │
        └───────────────────────────────┘
```

### Why Different Tokenizers Exist

1. **Word-based**: Simple, but fails on unknown words
2. **Subword-based (BPE)**: Handles unknown words by breaking them into known subwords
   - Example: "jumping" → ["jump", "ing"] (if "jumping" isn't in vocabulary)
3. **Character-based**: Very flexible, but creates many tokens

### Common Tokenizers in AI

| Model Type | Tokenizer | Example |
|------------|-----------|---------|
| **GPT-3/GPT-4** | tiktoken (BPE-based) | "hello" → ["hello"] (1 token) |
| **BERT** | WordPiece | "running" → ["run", "##ning"] (2 tokens) |
| **T5** | SentencePiece | "Hello world" → ["▁Hello", "▁world"] (2 tokens) |
| **Embedding Models** | Varies by model | Often uses SentencePiece or similar |

---

## What are Embeddings?

### Simple Explanation

An **embedding** is a way to convert text into a list of numbers (a vector) that captures the **meaning** of the text. Think of it as creating a "fingerprint" or "DNA sequence" for words or sentences.

### How It Works

**Step 1: Tokenized Text**
```
["The", "quick", "brown", "fox"]
```

**Step 2: Embedding Model Converts to Numbers**

Each token (or the whole sentence) gets converted into a vector of numbers:

```
"The quick brown fox" → [0.23, -0.45, 0.67, 0.12, ..., 0.89]
                        ↑
                    A list of numbers (usually 384, 512, or 768 numbers)
```

### Visual Diagram

```
┌─────────────────────────────────────────────────────────┐
│              TOKENIZED TEXT                              │
│  ["The", "quick", "brown", "fox"]                       │
└──────────────────────┬──────────────────────────────────┘
                        │
                        ▼
            ┌──────────────────────┐
            │   EMBEDDING MODEL    │
            │  (Converts text to   │
            │   numerical vectors) │
            └──────────┬───────────┘
                       │
                       ▼
        ┌───────────────────────────────┐
        │      EMBEDDING VECTOR         │
        │  [0.23, -0.45, 0.67, 0.12,   │
        │   0.34, -0.56, 0.78, ...,    │
        │   0.89]                      │
        │                               │
        │  Dimensions: 384 or 512       │
        │  (depends on model)           │
        └───────────────────────────────┘
```

### Why Embeddings Matter

1. **Similar meanings = similar numbers**
   - "dog" and "puppy" → vectors that are close together
   - "dog" and "airplane" → vectors that are far apart

2. **Enables semantic search**
   - You can search for "canine" and find documents about "dogs"
   - The numbers capture meaning, not just exact word matches

3. **Used for retrieval**
   - Onyx stores document embeddings in Vespa/Postgres
   - When you ask a question, Onyx finds the most relevant chunks by comparing embedding vectors

### Example: Embedding Similarity

```
Text 1: "I love dogs"
Embedding: [0.2, -0.3, 0.5, ...]

Text 2: "I adore canines"
Embedding: [0.21, -0.29, 0.51, ...]  ← Very similar numbers!

Text 3: "I hate airplanes"
Embedding: [-0.8, 0.6, -0.4, ...]    ← Very different numbers!
```

**Distance calculation:**
- Text 1 vs Text 2: Distance = 0.05 (very similar!)
- Text 1 vs Text 3: Distance = 1.8 (very different!)

---

## How LLMs Use Tokens

### Simple Explanation

An **LLM (Large Language Model)** like GPT-4, Claude, or vLLM reads text that has been **tokenized**, processes it, and generates new text. It has a **context window** (a maximum number of tokens it can handle at once).

### The Context Window

Think of it like a **memory limit**:

```
┌─────────────────────────────────────────────────────────┐
│              LLM CONTEXT WINDOW                         │
│  Maximum: 32,000 tokens (example for GPT-4)            │
│                                                          │
│  ┌────────────────────────────────────────────┐         │
│  │ Your prompt: 500 tokens                  │         │
│  │ System instructions: 200 tokens           │         │
│  │ Document chunks: 20,000 tokens            │         │
│  │ Reserved for response: 11,300 tokens     │         │
│  └────────────────────────────────────────────┘         │
│                                                          │
│  Total used: 32,000 tokens                              │
└─────────────────────────────────────────────────────────┘
```

### How LLMs Process Tokens

**Step 1: Tokenization**
```
Input: "What is artificial intelligence?"
Tokens: ["What", "is", "artificial", "intelligence", "?"]
```

**Step 2: LLM Processing**
- The LLM reads each token sequentially
- It predicts the next token based on previous tokens
- It generates a response token by token

**Step 3: Output**
```
Generated tokens: ["Artificial", "intelligence", "is", "the", "simulation", ...]
Final text: "Artificial intelligence is the simulation of human intelligence..."
```

### Visual Flow

```
┌─────────────────────────────────────────────────────────┐
│                    USER PROMPT                           │
│  "What is AI?"                                           │
└──────────────────────┬───────────────────────────────────┘
                        │
                        ▼
            ┌──────────────────────┐
            │   LLM TOKENIZER       │
            │  (Splits prompt)     │
            └──────────┬───────────┘
                       │
                       ▼
        ┌───────────────────────────────┐
        │      TOKENIZED PROMPT         │
        │  ["What", "is", "AI", "?"]    │
        └──────────┬────────────────────┘
                   │
                   ▼
        ┌───────────────────────────────┐
        │         LLM PROCESSING         │
        │  Reads tokens → Predicts      │
        │  next tokens → Generates       │
        │  response                     │
        └──────────┬────────────────────┘
                   │
                   ▼
        ┌───────────────────────────────┐
        │      GENERATED RESPONSE        │
        │  ["Artificial", "intelligence",│
        │   "is", "the", ...]            │
        └───────────────────────────────┘
```

---

## The Tokenizer Mismatch Problem

### The Core Issue

**Problem:** Embedding models and LLMs often use **different tokenizers**. This means the same text can have different token counts depending on which tokenizer you use!

### Example: Same Text, Different Token Counts

Let's say you have this text:
```
"The artificial intelligence system processes natural language effectively."
```

**Using Embedding Model Tokenizer (e.g., SentencePiece):**
```
Tokens: ["The", "artificial", "intelligence", "system", "processes", 
         "natural", "language", "effectively", "."]
Count: 9 tokens
```

**Using LLM Tokenizer (e.g., tiktoken for GPT-4):**
```
Tokens: ["The", "artificial", "intelligence", "system", "processes",
         "natural", "language", "effectively", "."]
Count: 9 tokens (same in this case, but often different!)
```

**But with a longer, more complex text:**

**Embedding Model Tokenizer:**
```
"Supercalifragilisticexpialidocious artificial intelligence"
→ 3 tokens: ["Supercalifragilisticexpialidocious", "artificial", "intelligence"]
```

**LLM Tokenizer (tiktoken):**
```
"Supercalifragilisticexpialidocious artificial intelligence"
→ 5 tokens: ["Super", "califragil", "isticexp", "ialidocious", "artificial", "intelligence"]
```

### Why This Causes Problems

**Scenario: Document Chunking**

1. **Step 1: Onyx chunks your document**
   - Uses embedding model tokenizer to count tokens
   - Creates chunks of ~500 tokens each (using embedding tokenizer)

2. **Step 2: User asks a question**
   - Onyx retrieves relevant chunks
   - Prepares to send them to the LLM

3. **Step 3: LLM tokenizes the chunks**
   - Uses **its own tokenizer** (different from embedding model!)
   - The same text might now be 600 tokens instead of 500!

4. **Step 4: Problem!**
   - LLM context window: 32,000 tokens
   - Your prompt: 1,000 tokens
   - Document chunks: 35,000 tokens (when counted with LLM tokenizer)
   - **Total: 36,000 tokens → EXCEEDS LIMIT!**

### Visual Diagram of the Problem

```
┌─────────────────────────────────────────────────────────┐
│              DOCUMENT CHUNKING                          │
│  Using: Embedding Model Tokenizer                       │
│                                                          │
│  Chunk 1: 500 tokens ✓                                  │
│  Chunk 2: 500 tokens ✓                                  │
│  Chunk 3: 500 tokens ✓                                  │
│  ...                                                     │
│  Total: 5,000 tokens (looks safe!)                      │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
        ┌───────────────────────────────┐
        │    SEND TO LLM                 │
        │  Using: LLM Tokenizer          │
        │                                 │
        │  Chunk 1: 600 tokens ✗         │
        │  Chunk 2: 600 tokens ✗         │
        │  Chunk 3: 600 tokens ✗         │
        │  ...                            │
        │  Total: 6,000 tokens            │
        │                                 │
        │  LLM Limit: 5,000 tokens       │
        │  Result: ERROR! ✗               │
        └───────────────────────────────┘
```

---

## How Onyx Handles This

### The Pruning Solution

Onyx uses a process called **"pruning"** to prevent token limit errors. Here's how it works:

### Step-by-Step Process

**Step 1: Count tokens using LLM tokenizer**
- Before sending to LLM, Onyx re-counts tokens using the **LLM's tokenizer**
- This ensures accurate token counts

**Step 2: Check against token limit**
```python
if total_tokens > token_limit:
    # Stop adding more chunks
    final_section_ind = ind
    break
```

**Step 3: Prune (remove) excess chunks**
- If chunks exceed the limit, Onyx removes the last chunks
- Keeps only the chunks that fit within the limit

**Step 4: Log the results**
```python
logger.debug(f"Number of documents after pruning: {ind + 1}")
logger.debug("Number of tokens per document (pruned):")
logger.debug(f"Tokens per document: {log_tokens_per_document}")
```

### Visual Flow of Pruning

```
┌─────────────────────────────────────────────────────────┐
│         INITIAL CHUNKS (from embedding model)           │
│                                                          │
│  Chunk 1: "Introduction to AI..."                      │
│  Chunk 2: "Machine learning basics..."                  │
│  Chunk 3: "Deep learning concepts..."                   │
│  Chunk 4: "Neural networks explained..."                │
│  Chunk 5: "Advanced topics..."                          │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
        ┌───────────────────────────────┐
        │   RE-COUNT WITH LLM TOKENIZER  │
        │                                 │
        │  Chunk 1: 1,200 tokens         │
        │  Chunk 2: 1,100 tokens         │
        │  Chunk 3: 1,300 tokens         │
        │  Chunk 4: 1,000 tokens         │
        │  Chunk 5: 1,200 tokens         │
        │                                 │
        │  Total: 5,800 tokens           │
        │  Limit: 5,000 tokens           │
        │  Status: EXCEEDS LIMIT! ✗       │
        └──────────┬──────────────────────┘
                   │
                   ▼
        ┌───────────────────────────────┐
        │         PRUNING PROCESS        │
        │                                 │
        │  Add Chunk 1: 1,200 tokens ✓   │
        │  Add Chunk 2: 2,300 tokens ✓   │
        │  Add Chunk 3: 3,600 tokens ✓   │
        │  Add Chunk 4: 4,600 tokens ✓   │
        │  Try Chunk 5: 5,800 tokens ✗  │
        │                                 │
        │  Decision: Stop at Chunk 4     │
        └──────────┬──────────────────────┘
                   │
                   ▼
        ┌───────────────────────────────┐
        │      FINAL CHUNKS SENT         │
        │                                 │
        │  Chunk 1: 1,200 tokens ✓       │
        │  Chunk 2: 1,100 tokens ✓       │
        │  Chunk 3: 1,300 tokens ✓       │
        │  Chunk 4: 1,000 tokens ✓       │
        │                                 │
        │  Total: 4,600 tokens           │
        │  Status: WITHIN LIMIT! ✓        │
        └───────────────────────────────┘
```

### The `apply_pruning` Function Explained

```python
# This function ensures chunks don't exceed the LLM's token limit

# Step 1: Iterate through document chunks
for ind, section in enumerate(document_sections):
    # Count tokens using LLM tokenizer (not embedding tokenizer!)
    section_tokens = count_tokens_with_llm_tokenizer(section)
    total_tokens += section_tokens
    
    # Step 2: Check if we've exceeded the limit
    if total_tokens > token_limit:
        # Stop here! Don't add more chunks
        final_section_ind = ind
        break
    
    # Step 3: Keep track of token counts per document
    section_idx_token_count[ind] = section_tokens

# Step 4: Log the results for debugging
try:
    logger.debug(f"Number of documents after pruning: {ind + 1}")
    logger.debug("Number of tokens per document (pruned):")
    log_tokens_per_document: dict[int, int] = {}
    for x, y in section_idx_token_count.items():
        log_tokens_per_document[x + 1] = y
    logger.debug(f"Tokens per document: {log_tokens_per_document}")
except Exception as e:
    # Handle any logging errors gracefully
    pass
```

---

## Real-World Example

### Scenario: User Uploads a Large PDF

**Step 1: Document Processing**
```
User uploads: "AI_Research_Paper.pdf" (50 pages)
```

**Step 2: Chunking (using embedding model tokenizer)**
```
Onyx creates chunks:
- Chunk 1: "Introduction..." (500 tokens - embedding count)
- Chunk 2: "Methodology..." (500 tokens - embedding count)
- Chunk 3: "Results..." (500 tokens - embedding count)
- ... (100 chunks total)
```

**Step 3: Embedding Generation**
```
Each chunk is converted to embeddings and stored in Vespa:
- Chunk 1 → [0.23, -0.45, 0.67, ...] (384-dimensional vector)
- Chunk 2 → [0.34, -0.56, 0.78, ...]
- ...
```

**Step 4: User Asks Question**
```
User: "What are the main findings?"
```

**Step 5: Retrieval**
```
Onyx searches embeddings and finds:
- Chunk 15: "Main findings section..." (most relevant)
- Chunk 23: "Discussion of results..." (second most relevant)
- Chunk 8: "Summary of key points..." (third most relevant)
```

**Step 6: Pruning Before Sending to LLM**
```
Onyx re-counts tokens using LLM tokenizer:

Chunk 15: 600 tokens (was 500 with embedding tokenizer!)
Chunk 23: 550 tokens (was 500 with embedding tokenizer!)
Chunk 8: 580 tokens (was 500 with embedding tokenizer!)

Total: 1,730 tokens
LLM context limit: 32,000 tokens
User prompt: 50 tokens
System instructions: 200 tokens
Reserved for response: 11,000 tokens

Available for documents: 20,750 tokens
Status: 1,730 < 20,750 → SAFE! ✓
```

**Step 7: Send to LLM**
```
Final prompt sent to LLM:
- System instructions: 200 tokens
- User prompt: 50 tokens
- Document chunks: 1,730 tokens
- Reserved for response: 11,000 tokens
Total: 12,980 tokens (well within 32,000 limit)
```

**Step 8: LLM Generates Response**
```
LLM processes the tokens and generates:
"Based on the research paper, the main findings are:
1. AI models show significant improvement...
2. The methodology demonstrates...
..."
```

### What If Pruning Wasn't There?

**Without pruning:**
```
Chunk 15: 600 tokens
Chunk 23: 550 tokens
Chunk 8: 580 tokens
Chunk 45: 620 tokens (also relevant)
Chunk 67: 590 tokens (also relevant)
... (keeps adding chunks)

Total: 15,000 tokens
LLM limit: 32,000 tokens
Status: Still safe, but what if we had 50 chunks?

Total: 30,000 tokens
Status: Getting close to limit!

Total: 35,000 tokens
Status: EXCEEDS LIMIT! → ERROR! ✗
```

**With pruning:**
```
Onyx stops adding chunks when it reaches the limit:
- Adds chunks until total = 20,000 tokens
- Next chunk would make it 21,000 tokens
- Pruning stops here
- Result: Always within limit! ✓
```

---

## Troubleshooting

### Common Issues and Solutions

#### Issue 1: "Chunks are being pruned too aggressively"

**Symptoms:**
- Logs show: `Number of documents after pruning: 2` (but you expected 10)
- LLM responses are incomplete

**Cause:**
- Tokenizer mismatch is severe
- Chunks are much larger when counted with LLM tokenizer

**Solution:**
1. Check logs: `Tokens per document: {1: 1200, 2: 1100}`
2. If chunks are too large, consider:
   - Using smaller chunk sizes during indexing
   - Using a different embedding model that matches LLM tokenizer better
   - Adjusting the token limit in configuration

#### Issue 2: "Embedding model and LLM tokenizer are different"

**How to Check:**
```python
# In Onyx codebase, check:
# 1. Embedding model tokenizer (in indexing pipeline)
# 2. LLM tokenizer (in chat/query pipeline)

# Example check:
from transformers import AutoTokenizer

embedding_tokenizer = AutoTokenizer.from_pretrained("embedding-model-name")
llm_tokenizer = AutoTokenizer.from_pretrained("llm-model-name")

text = "The quick brown fox jumps over the lazy dog"
embedding_tokens = len(embedding_tokenizer.encode(text))
llm_tokens = len(llm_tokenizer.encode(text))

print(f"Embedding tokenizer: {embedding_tokens} tokens")
print(f"LLM tokenizer: {llm_tokens} tokens")
print(f"Difference: {abs(embedding_tokens - llm_tokens)} tokens")
```

**If they're different:**
- This is normal! Onyx handles it with pruning
- Make sure pruning is enabled and working correctly
- Monitor logs to see how many chunks are being pruned

#### Issue 3: "LLM is rejecting requests with 'token limit exceeded'"

**Symptoms:**
- Error: `Token limit exceeded`
- Requests fail even after pruning

**Cause:**
- Pruning might not be working correctly
- Token counting might be inaccurate
- Reserved tokens for response might be too large

**Solution:**
1. Check pruning logs:
   ```
   Number of documents after pruning: X
   Tokens per document: {...}
   ```
2. Verify token counting:
   - Ensure LLM tokenizer is being used for counting
   - Check that `token_limit` is set correctly
3. Adjust configuration:
   - Reduce `GEN_AI_NUM_RESERVED_OUTPUT_TOKENS` if too large
   - Increase chunk size limits if appropriate

---

## Key Takeaways

1. **Tokenizers convert text to tokens** - Different models use different tokenizers
2. **Embeddings convert text to numbers** - Used for semantic search and retrieval
3. **LLMs process tokens** - They have a maximum context window (token limit)
4. **Tokenizer mismatch is common** - Embedding models and LLMs often use different tokenizers
5. **Pruning prevents errors** - Onyx re-counts tokens with LLM tokenizer and removes excess chunks
6. **Monitor logs** - Check `apply_pruning` logs to see how many chunks survive pruning

---

## Summary Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    DOCUMENT                             │
│  "AI Research Paper..."                                 │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
        ┌───────────────────────────────┐
        │   CHUNKING                    │
        │  (Using embedding tokenizer) │
        │                               │
        │  Chunk 1: 500 tokens          │
        │  Chunk 2: 500 tokens          │
        │  ...                          │
        └──────────┬────────────────────┘
                   │
                   ▼
        ┌───────────────────────────────┐
        │   EMBEDDING GENERATION         │
        │  (Convert to vectors)          │
        │                               │
        │  Chunk 1 → [0.23, -0.45, ...] │
        │  Chunk 2 → [0.34, -0.56, ...] │
        │  ...                          │
        └──────────┬────────────────────┘
                   │
                   ▼
        ┌───────────────────────────────┐
        │   STORAGE (Vespa/Postgres)    │
        │  (Embeddings stored for        │
        │   semantic search)             │
        └──────────┬────────────────────┘
                   │
        ┌──────────┴──────────┐
        │                     │
        ▼                     ▼
┌───────────────┐    ┌──────────────────┐
│ USER QUESTION │    │  RETRIEVAL       │
│ "What are...?"│    │  (Find relevant  │
└───────┬───────┘    │   chunks)        │
        │            └────────┬─────────┘
        │                     │
        └──────────┬──────────┘
                   │
                   ▼
        ┌───────────────────────────────┐
        │   PRUNING                     │
        │  (Re-count with LLM tokenizer)│
        │                               │
        │  Chunk 1: 600 tokens          │
        │  Chunk 2: 550 tokens          │
        │  ...                          │
        │                               │
        │  Check: total < limit?        │
        │  Remove excess if needed      │
        └──────────┬────────────────────┘
                   │
                   ▼
        ┌───────────────────────────────┐
        │   SEND TO LLM                 │
        │  (With pruned chunks)          │
        │                               │
        │  Prompt + Chunks = Safe! ✓    │
        └──────────┬────────────────────┘
                   │
                   ▼
        ┌───────────────────────────────┐
        │   LLM GENERATES RESPONSE      │
        │  "Based on the research..."   │
        └───────────────────────────────┘
```

---

This document explains the complete flow from document processing to LLM response generation, with special focus on how tokenizer mismatches are handled through pruning. If you have questions or need clarification on any section, refer to the troubleshooting section or check the Onyx logs for specific error messages.

