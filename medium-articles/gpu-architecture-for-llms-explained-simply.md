# GPU Architecture for LLMs — Explained So Simply That It Finally Clicks

*If you've ever asked "Why is this model slow even with big VRAM?" this is for you.*

This is a complete, beginner-friendly guide to understanding how GPUs behave in the LLM world.

No vendor marketing. No scary jargon dumps. Just practical mental models, easy math, and the system-level thinking you need to make good engineering decisions.

---

## TL;DR (the 60-second version)

When running LLMs, performance is mostly controlled by three things:

1. **VRAM capacity** — Can the model and KV cache fit?
2. **Memory bandwidth** — How fast can the GPU read/write model data each token?
3. **Compute throughput** — How fast can the GPU do matrix math when data is available?

A lot of "mystery slowness" is simply this:

- **Prefill** (reading long prompts) is often **compute-heavy**.
- **Decode** (generating token by token) is often **memory-bandwidth-heavy**.

So yes, two GPUs with enough VRAM to hold the same model can still differ greatly in token speed.

---

## Before we start: model basics in very simple words

If you are new to LLMs, this section is the foundation.

### What is a model (in one sentence)?

A model is a very large math function that converts input text into next-token predictions.

It learns this behavior during training by adjusting many internal numbers.

### What are \"parameters\"?

Parameters are those internal numbers.

Think of parameters like millions or billions of tiny knobs in a giant sound mixer:

- each knob affects output a little bit
- together they define the model's behavior

When we say:

- **7B model** → about 7 billion parameters
- **13B model** → about 13 billion parameters
- **70B model** → about 70 billion parameters

more parameters usually mean more expressive power, but also more memory and compute cost.

### What is quantization?

Quantization is a compression technique for those parameter values.

Instead of storing each value with high precision (many bits), we store it with lower precision (fewer bits).

This makes the model smaller and cheaper to run.

Simple view:

- higher precision = clearer photo, larger file
- lower precision = slightly less detail, much smaller file

For example, **Q4** roughly means 4-bit style quantized representation (exact storage varies by implementation).

### How is model size calculated?

At planning level, use this simple formula:

```text
Model weight size (bytes) ≈ Number of parameters × Bytes per parameter
```

Examples:

1. If a 13B model were stored at 2 bytes/param:

```text
13e9 × 2 = 26e9 bytes ≈ 26 GB
```

2. If the same 13B model is Q4-like at ~0.7 bytes/param:

```text
13e9 × 0.7 ≈ 9.1e9 bytes ≈ 9.1 GB
```

So quantization can dramatically reduce required VRAM for weights.

### Important beginner note

\"Model size\" usually refers to **weights only**.

But runtime memory needs are bigger because you also need:

- KV cache
- temporary activations/buffers
- framework overhead

That is why a model that \"fits on paper\" can still fail in production if context length and concurrency are high.

---

## 1) Build a mental model first

Imagine an AI factory:

- **VRAM** = warehouse size (how much stuff you can store)
- **Memory bandwidth** = road width to/from warehouse (how fast you move stuff)
- **GPU cores / tensor cores** = workers doing the math
- **PCIe/NVLink** = highways between GPU and CPU or GPU to GPU

You need all of them balanced.

Big warehouse + tiny road = workers waiting for materials.
Huge worker team + small warehouse = not enough model/context fits.

---

## 2) What exactly sits in VRAM during LLM inference?

At runtime, VRAM is not just "the model". It includes:

1. **Model weights** (largest static block)
2. **KV cache** (grows with context and concurrent requests)
3. **Activations / temporary buffers**
4. **Framework overhead** (allocator, CUDA context, fragmentation)
5. **Batching buffers**

This is why a model that "should fit" on paper may still OOM in real workloads.

### Easy formula (rough planning)

```text
Total VRAM needed ≈ Weights + KV Cache + Runtime Overhead
```

---

## 3) Quantization: why Q4 helps and what it does NOT solve

Quantization reduces precision to save memory.

A common rough assumption for Q4 is:

- ~0.5 to 0.8 bytes per parameter depending on format/tooling
- many people use ~0.7 bytes/parameter as a rough planning number

For a model with N parameters:

```text
Weight size ≈ N × bytes_per_param
```

Example for 13B parameters at ~0.7 bytes:

```text
13e9 × 0.7 ≈ 9.1 GB of weights
```

Great — you fit in more GPUs.

But quantization does **not** remove memory traffic needs. You still read lots of weight data every token.

---

## 4) The critical insight: per-token generation is often memory-movement limited

A practical rule of thumb used in engineering discussions:

- each generated token may require reading on the order of ~2 × weight size (effective movement across layers and passes)

Using the same 13B Q4 example:

- weight size ~9.1 GB
- effective read per token ~18 GB

Now time per token lower bound from memory bandwidth is roughly:

```text
ms_per_token_theoretical ≈ (GB_per_token / GBps) × 1000
```

If GB/token ≈ 18:

- 960 GB/s → ~19 ms/token
- 504 GB/s → ~36 ms/token
- 256 GB/s → ~70 ms/token

That alone is ~2.8× spread — same model fit, very different speed.

This is why "I have enough VRAM" is only half the story.

---

## 5) Prefill vs Decode (must understand)

LLM inference has two different phases:

## A) Prefill (prompt processing)

You feed the full input context (maybe 2k, 8k, 32k tokens).

- Work is dense and parallel.
- Usually more compute utilization.
- Throughput (tokens/sec) can look strong.

## B) Decode (generation)

Now model generates **one token at a time** repeatedly.

- Work becomes sequential across time.
- Often memory-bound.
- Latency per token dominates user experience.

### Why users feel slowness here

Users judge chat by "how quickly tokens appear" (decode speed), not by how fast your prefill benchmark looked in slides.

---

## 6) KV cache: the hidden VRAM eater

For transformer attention, past keys/values are stored so model doesn't recompute everything.

This **KV cache** grows with:

- context length
- batch/concurrent requests
- layers / heads / hidden size
- dtype

### Simple intuition

- Long contexts and many simultaneous chats can consume more memory than expected.
- OOM or aggressive eviction can suddenly crush latency.

### Real-world symptom

"It works with 1 user, gets unstable with 8 users."  
Usually not magic. KV cache pressure + scheduling + memory fragmentation.

---

## 7) Throughput vs latency vs concurrency

These 3 are related but not identical.

- **Latency**: time for one user's response (or first token)
- **Throughput**: total tokens/sec across all users
- **Concurrency**: how many active requests at once

You can optimize one while hurting another.

Example:

- Big batch improves throughput
- But may increase first-token latency for interactive chat

For chat products, first-token latency and stability often matter more than peak benchmark throughput.

---

## 8) Batching and continuous batching (scheduler behavior)

Modern inference servers use dynamic/continuous batching.

Think of a bus system:

- If you wait to fill the bus, efficiency rises (throughput)
- But first passenger waits longer (latency)

Good schedulers try to balance this in real time.

### Practical takeaway

When tuning LLM serving, don't ask only:

"How many tokens/sec can we get?"

Also ask:

"What happens to p95 first-token latency with real user traffic?"

---

## 9) Why model size alone is not enough for sizing

Two models can both be "13B" and still behave differently due to:

- architecture differences
- attention implementation
- quantization backend
- context length configuration
- serving engine optimizations

So capacity planning must use **measured** results, not just parameter count.

---

## 10) Single GPU vs multi-GPU: when scale-out helps (and hurts)

Multi-GPU can help with larger models or more throughput, but introduces communication costs.

Key links:

- **PCIe**: common, slower than on-package memory bandwidth
- **NVLink / high-speed interconnect**: much faster GPU-GPU transfer

If tensor/model parallelism requires frequent cross-GPU sync, interconnect becomes a bottleneck.

Analogy:

- One kitchen with one team (single GPU) can be very fast if recipe fits.
- Splitting one dish across 4 kitchens needs runners between kitchens (communication overhead).

---

## 11) CPU, RAM, disk, and network still matter

GPU is central, but the full system can bottleneck elsewhere:

- tokenizer on CPU
- request orchestration in API/gateway
- model load from disk
- cross-node network hops
- queueing delays

Classic failure mode:

GPU utilization looks low, but users still wait. Why? Data pipeline and scheduling overhead upstream.

---

## 12) Core metrics to monitor in production

If you run LLM services, watch these continuously:

1. **Time to first token (TTFT)** p50/p95
2. **Decode tokens/sec** per model
3. **Request queue depth** and waiting time
4. **GPU memory used / free** and OOM events
5. **GPU utilization** (compute) vs memory utilization
6. **Batch size distribution**
7. **Gateway/API timeout rates**
8. **Error rates by phase** (prefill, decode, tool calls)

If you only monitor "GPU utilization %", you'll miss many real user problems.

---

## 13) The easy math toolkit (copy this)

## A) Weight memory estimate

```text
weights_GB ≈ params × bytes_per_param / 1e9
```

## B) Bandwidth lower bound token latency

```text
token_ms_lower_bound ≈ (GB_per_token / bandwidth_GBps) × 1000
```

## C) Rough throughput upper bound from latency

```text
tokens_per_sec_upper_bound ≈ 1000 / token_ms
```

If token_ms ~36, upper bound ~27.8 tok/s before scheduler/overhead effects.

## D) Capacity sanity check

```text
required_tok_s = concurrent_users × avg_tok_s_per_user
```

If required_tok_s > stable served tok/s, queue grows and latency explodes.

---

## 14) Why "crashes under 5–10 users" happens

Common chain:

1. Prompt sizes increase + multiple uploads/chat sessions
2. KV cache grows
3. Batch/scheduler queues requests
4. decode gets memory-bound
5. gateway/api hits timeout before completion
6. users retry, increasing load (feedback loop)

This is a traffic jam, not one bug.

---

## 15) Practical architecture pattern for stable LLM serving

A robust pattern many teams use:

```text
Client
  ↓
API / Gateway (auth, rate limits, routing, retries)
  ↓
LLM Gateway (OpenAI-compatible abstraction, model policy)
  ↓
Inference Engine (vLLM/TGI/etc.)
  ↓
GPU pool
```

Why this helps:

- routing/fallback without changing app code
- central observability
- per-model policy and quotas
- easier multi-model operations

---

## 16) Sizing strategy that actually works

Don't start with "largest model we can fit." Start with SLOs.

1. Define target SLOs:
   - TTFT p95
   - response completion p95
   - max concurrent active users
2. Benchmark realistic prompts and output lengths.
3. Test mixed traffic (short + long prompts).
4. Add 30–40% headroom for spikes.
5. Re-test after every model/context change.

Model or context changes can invalidate old sizing immediately.

---

## 17) Frequently misunderstood points

## "More VRAM always means faster"
No. More VRAM means bigger fit. Speed often comes from bandwidth and scheduling.

## "Utilization 99% means healthy"
Not always. You can be efficiently overloaded with terrible p95 latency.

## "Quantization solves everything"
It helps fit and cost. It doesn't remove all memory movement constraints.

## "One benchmark number is enough"
No. Separate prefill, decode, TTFT, throughput, and tail latency.

---

## 18) A beginner-friendly analogy summary

- **VRAM** = pantry size
- **Bandwidth** = width of kitchen counter where ingredients move
- **Compute cores** = chefs
- **KV cache** = prepared ingredients kept on side tables
- **Batching** = cooking many orders together

If your side tables (KV cache) are full and counter is narrow (bandwidth), adding more chefs (compute) won't fix dinner service.

---

## 19) A concrete mini example (easy numbers)

Assume:

- model effective movement per generated token: ~18 GB
- GPU A bandwidth: 900 GB/s
- GPU B bandwidth: 300 GB/s

Lower-bound token times:

- A: 18/900 × 1000 ≈ 20 ms/token
- B: 18/300 × 1000 ≈ 60 ms/token

If each answer is 120 tokens:

- A decode time floor ≈ 2.4 s
- B decode time floor ≈ 7.2 s

Before any extra overhead.

Same model. Very different user experience.

---

## 20) Final checklist before publishing an LLM service

- [ ] Model fits with KV cache for target context and concurrency
- [ ] Prefill and decode measured separately
- [ ] TTFT p95 and completion p95 meet product goal
- [ ] Timeout chain aligned (client, gateway, API, inference)
- [ ] Queue depth alerts configured
- [ ] OOM/restart alerts configured
- [ ] Fallback model and backpressure policy defined
- [ ] Capacity test with real traffic shape completed

---

## Visual Summary: All Concepts in Simple Diagrams

Use this section as a one-page recap. Each diagram maps to one idea from the article.

---

### Diagram 1 — What is inside a model?

```text
┌─────────────────────────────────────────────────────────────┐
│                     LARGE LANGUAGE MODEL                    │
│                                                             │
│   Input text:  "What is machine learning?"                  │
│        │                                                    │
│        ▼                                                    │
│   ┌─────────────────────────────────────────────────────┐   │
│   │  PARAMETERS (billions of tiny numbers / "knobs")   │   │
│   │  • learned during training                         │   │
│   │  • define how model behaves                        │   │
│   └─────────────────────────────────────────────────────┘   │
│        │                                                    │
│        ▼                                                    │
│   Output: next token prediction → "Machine" → "learning"…   │
└─────────────────────────────────────────────────────────────┘

7B model  ≈ 7 billion parameters
13B model ≈ 13 billion parameters
70B model ≈ 70 billion parameters
```

**Remember:** More parameters = usually smarter, but heavier (more VRAM + compute).

---

### Diagram 2 — Quantization (smaller storage, same idea)

```text
FULL PRECISION (e.g. FP16)          QUANTIZED (e.g. Q4)
┌──────────────────────┐            ┌──────────────────────┐
│ Each number: 16 bits │            │ Each number: ~4 bits │
│ High detail          │   ───►     │ Smaller file         │
│ Bigger file          │  compress  │ Slightly less detail │
└──────────────────────┘            └──────────────────────┘

13B model example:
  FP16-ish (~2 bytes/param)  →  ~26 GB weights
  Q4-ish   (~0.7 bytes/param) →  ~9 GB weights
```

**Remember:** Quantization helps **fit** the model. It does not remove all memory **traffic** at inference time.

---

### Diagram 3 — VRAM vs bandwidth vs compute

```text
                    THE AI FACTORY

   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
   │    VRAM     │     │  BANDWIDTH  │     │   COMPUTE   │
   │  (warehouse)│◄───►│  (road width)│◄───►│  (workers)  │
   │             │     │             │     │             │
   │ How MUCH    │     │ How FAST    │     │ How FAST    │
   │ can we store│     │ data moves  │     │ math runs   │
   └─────────────┘     └─────────────┘     └─────────────┘

Question 1: Does the model + KV cache FIT?     → VRAM
Question 2: Can we MOVE data fast per token?   → Bandwidth (decode)
Question 3: Can we DO math fast on big prompts? → Compute (prefill)
```

**Kitchen analogy:**

| Concept | Analogy |
|---------|---------|
| VRAM | Pantry size |
| Bandwidth | Width of counter where ingredients slide |
| Compute | Number of chefs |

---

### Diagram 4 — What sits in VRAM at runtime?

```text
┌──────────────────────────────── GPU VRAM ────────────────────────────────┐
│                                                                          │
│  ┌────────────────────────┐  ┌──────────────────┐  ┌────────────────┐ │
│  │ MODEL WEIGHTS          │  │ KV CACHE           │  │ RUNTIME        │ │
│  │ (static, big)          │  │ (grows with        │  │ (buffers,      │ │
│  │                        │  │  context + users)  │  │  framework)    │ │
│  └────────────────────────┘  └──────────────────┘  └────────────────┘ │
│                                                                          │
│  Total ≈ Weights + KV Cache + Overhead                                   │
│                                                                          │
│  "Fits on paper" ≠ "stable under 10 concurrent long chats"               │
└──────────────────────────────────────────────────────────────────────────┘
```

---

### Diagram 5 — Prefill vs decode (two phases)

```text
USER SENDS LONG PROMPT                    MODEL GENERATES ANSWER
        │                                          │
        ▼                                          ▼
   ┌─────────┐                              ┌─────────┐
   │ PREFILL │                              │ DECODE  │
   │         │                              │         │
   │ Process │                              │ 1 token │
   │ ALL     │                              │ at a    │
   │ prompt  │                              │ a time  │
   │ tokens  │                              │         │
   │ at once │                              │ repeat… │
   └─────────┘                              └─────────┘
        │                                          │
   Often COMPUTE-heavy                      Often BANDWIDTH-heavy
   (parallel math)                          (read weights every token)

Users feel DECODE speed in chat ("how fast tokens appear").
```

---

### Diagram 6 — Why bandwidth dominates decode

```text
Per generated token (rough planning):

   read ≈ 2 × model weight size  (effective memory movement)

Example: 13B Q4 weights ~9 GB  →  ~18 GB read per token

Time floor ≈ (GB per token / bandwidth) × 1000 ms

   960 GB/s  →  ~19 ms/token
   504 GB/s  →  ~36 ms/token
   256 GB/s  →  ~70 ms/token

Same model fits on all three GPUs.
Different roads → ~2.8× speed spread from bandwidth alone.
```

```text
     GPU A (wide road)          GPU B (narrow road)
   ████ token every ~19ms     ████ token every ~70ms
```

---

### Diagram 7 — KV cache grows with context and users

```text
One short chat:
  KV cache:  ▓▓░░░░░░░░  (small)

One long document + long thread:
  KV cache:  ▓▓▓▓▓▓▓▓░░  (bigger)

Many users at once:
  KV cache:  ▓▓▓▓▓▓▓▓▓▓  (can OOM even if weights "fit")

More context length + more concurrent chats = more VRAM pressure
```

---

### Diagram 8 — Throughput vs latency vs concurrency

```text
                    THREE DIFFERENT GOALS

   LATENCY                    THROUGHPUT                 CONCURRENCY
   (one user waits)           (total tokens/sec)         (how many users)

   "How fast is MY answer?"   "How much can the          "How many active
                               cluster serve total?"       chats at once?"

        │                           │                          │
        └──────── trade-offs ───────┴──────────────────────────┘

   Bigger batches → higher throughput, sometimes worse first-token latency
```

---

### Diagram 9 — End-to-end LLM serving stack

```text
┌──────────┐    ┌──────────┐    ┌──────────────┐    ┌─────────────┐    ┌──────────┐
│  Client  │───►│ API /    │───►│ LLM Gateway  │───►│ Inference   │───►│ GPU pool │
│  (chat)  │    │ Ingress  │    │ (routing,    │    │ engine      │    │          │
└──────────┘    └──────────┘    │  retries)    │    │ (batching)  │    └──────────┘
                                └──────────────┘    └─────────────┘
                                       │
                    Bottleneck can be HERE, not only on GPU
                    (timeouts, queues, scheduling)
```

---

### Diagram 10 — Master cheat sheet (print this)

```text
┌────────────────────────────────────────────────────────────────────────┐
│                    LLM + GPU — ONE-PAGE SUMMARY                        │
├────────────────────────────────────────────────────────────────────────┤
│ PARAMETERS     │ Internal numbers that define the model               │
│ QUANTIZATION   │ Store numbers with fewer bits → smaller weights      │
│ MODEL SIZE     │ params × bytes_per_param (weights only)              │
│ VRAM           │ Can it FIT? (weights + KV cache + overhead)          │
│ BANDWIDTH      │ How fast per TOKEN in decode? (often the limit)      │
│ COMPUTE        │ How fast on long PROMPT in prefill?                  │
│ PREFILL        │ Eat whole prompt — parallel, compute-heavy           │
│ DECODE         │ Generate token-by-token — often memory-bound         │
│ KV CACHE       │ Memory of past tokens — grows with context + users   │
│ TTFT           │ Time to first token — user-perceived "snappiness"    │
├────────────────────────────────────────────────────────────────────────┤
│ KEY FORMULAS                                                           │
│   weight_GB ≈ N × bytes_per_param / 1e9                                │
│   token_ms ≈ (GB_per_token / GBps) × 1000                              │
│   total_VRAM ≈ weights + KV_cache + overhead                           │
├────────────────────────────────────────────────────────────────────────┤
│ BEFORE YOU SHIP                                                        │
│   □ Model + KV fits at target context & concurrency                    │
│   □ Measure prefill AND decode separately                              │
│   □ Align timeouts (client → gateway → inference)                      │
│   □ Load-test mixed traffic, not one short prompt                      │
└────────────────────────────────────────────────────────────────────────┘
```

---

### Diagram 11 — Decision flow (which bottleneck am I hitting?)

```text
                         START: "LLM feels slow"
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
              OOM / restarts   Queue growing    Tokens slow but
              on GPU?          on gateway?      GPU not full?
                    │               │               │
                    ▼               ▼               ▼
              VRAM + KV        API/gateway      Bandwidth or
              cache issue      scheduling       decode bound
                    │               │               │
                    ▼               ▼               ▼
              Reduce context   Scale routing/    Faster GPU memory
              or concurrency  batch policy      or smaller model
              or quantize     or timeouts       or better quantization
```

---

## Closing

LLM infrastructure feels mysterious until you reduce it to movement, math, and queues.

The key is to stop asking only:

"Can this GPU run the model?"

and start asking:

"At my target concurrency and context length, can this system move data fast enough to keep latency stable?"

Once you ask that question, architecture decisions become much clearer.

---

*If you're publishing this on Medium, consider adding a short personal intro at the top: where you saw these patterns and what scale you were targeting. Readers connect faster when they see the operating context.*
