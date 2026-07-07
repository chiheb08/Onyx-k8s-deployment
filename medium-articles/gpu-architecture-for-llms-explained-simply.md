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

## Closing

LLM infrastructure feels mysterious until you reduce it to movement, math, and queues.

The key is to stop asking only:

"Can this GPU run the model?"

and start asking:

"At my target concurrency and context length, can this system move data fast enough to keep latency stable?"

Once you ask that question, architecture decisions become much clearer.

---

*If you're publishing this on Medium, consider adding a short personal intro at the top: where you saw these patterns and what scale you were targeting. Readers connect faster when they see the operating context.*
