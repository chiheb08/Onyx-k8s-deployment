# What Production Teaches You About Deploying AI Platforms (That the Tutorial Never Mentioned)

*You followed the docs. The demo worked. Then six people logged in at once—and everything felt like it was falling apart.*

If you have ever shipped a modern application stack to a real cluster—a web UI, an API, background workers, a search engine, object storage, and a large language model behind a gateway—you have probably lived a version of this story. The problems rarely show up in a hello-world tutorial. They show up on a Tuesday afternoon when someone uploads a 200-page PDF while three colleagues ask questions in chat and a fourth deletes an old document.

This article is a field report. Not tied to one product or one company. Just the patterns that repeat when teams move from “it works on my laptop” to “it must work for everyone, every day.”

For each problem: what happened in plain language, why juniors (and honestly, seniors under pressure) walk into it, and what to do instead.

---

## The illusion of the happy path

Most deployment guides optimize for the **happy path**:

1. Install components.
2. Run one test request.
3. Declare victory.

Production optimizes for the **unhappy path at scale**:

- Two users do the same action at once.
- A background job fails halfway.
- A proxy times out while the server is still working.
- A model needs the internet in an environment that has no internet.

The gap between those two worlds is where careers learn fast.

**Analogy:** Building a bridge from a picture of a bridge. The picture shows cars crossing one at a time on a sunny day. Nobody drew the rush hour, the snowplow, or the truck that is too heavy.

---

## Problem 1: The front door looks fine, but the hallway is wrong

### What goes wrong

Users click “upload” or “send.” The browser calls an API path like `/api/something/...`. The gateway (nginx, ingress, route) forwards the request—but **does not rewrite the path correctly**. The API receives a URL it does not recognize. Result: `404 Not Found` even though “the app is up.”

Separately, large uploads fail or hang because the proxy’s **body size limit** or **timeout** is lower than the application’s limit. The API would have accepted the file; the gateway gave up first.

### Why juniors fall into this

- They test with `curl` directly against the API pod, **bypassing the gateway**. It works. They assume production is the same.
- They treat nginx/ingress as “just routing,” not as part of the application contract.
- They raise timeouts in one layer (app) but not in the outer layer (load balancer / cloud route).

### How to avoid it

- **Always test through the same URL users use** (public hostname, TLS, full path).
- Draw one diagram: Browser → Gateway → App. Write the **exact path** at each hop.
- Align three numbers everywhere: max upload size, read timeout, idle timeout (gateway, app, cloud route).
- For streaming responses (chat tokens), disable response buffering on the gateway. A buffer that waits for “the full response” kills streaming.

**Analogy:** The restaurant kitchen is open, but guests are knocking on the loading dock door. Same building, wrong entrance.

---

## Problem 2: One worker wearing every hat

### What goes wrong

Background jobs (file processing, indexing, deletion, sync) share **one worker pool** and **one queue consumer**. Heavy jobs (index a document) run beside urgent small jobs (delete a file). Deletes pile up. Uploads pile up. The UI shows “processing” or “deleting” for hours.

This is not a mystery bug. It is **queue starvation**: one lane of traffic, ambulance and school bus in the same line.

### Why juniors fall into this

- Default docker-compose or Helm chart uses **one generic worker**. It works for one user.
- Redis queue depth is invisible until someone asks “why is it slow?”
- “Async” sounds like magic—teams forget that **someone still has to execute the work**, and capacity is finite.

### How to avoid it

- **Separate queues by job type**: ingestion, deletion, light sync, heavy batch.
- **Dedicated workers** for destructive or latency-sensitive paths (e.g. delete).
- Monitor **queue length**, not only “worker is running.”
- Load-test with 5–10 people doing different actions at once—not one person clicking slowly.

**Analogy:** One cashier for prescriptions, returns, and lottery tickets. Everyone is polite. The line still goes around the block.

---

## Problem 3: The scheduler that cannot write its own notebook

### What goes wrong

A periodic scheduler (Celery Beat, cron sidecar, etc.) tries to write its state file to a **read-only directory** in the container. It crashes or silently fails. Periodic cleanup never runs. Retries never run. Disk or queues fill up over days.

### Why juniors fall into this

- Images run as non-root (good for security) but manifests still assume `/var/lib/...` is writable.
- Beat/cron is deployed last and tested never—“we’ll check later.”
- Logs show permission errors once; nobody connects them to stuck files or growing Redis keys.

### How to avoid it

- Give schedulers a **writable path** (`/tmp`, emptyDir volume) explicitly in the manifest.
- Health-check the scheduler pod the same way you health-check the API.
- After deploy, verify **one scheduled job actually fired** (log line, metric, or test row in DB).

**Analogy:** Hiring a night-shift cleaner and locking the supply closet. The shift is on the roster; the floor stays dirty.

---

## Problem 4: Redis is “just cache” until it is the entire nervous system

### What goes wrong

Redis serves sessions, Celery broker, rate limits, locks—sometimes all on **one small instance** with **aggressive memory limits** and **eviction policies** meant for cache. Under load, memory fills. Keys disappear. Tasks vanish or duplicate. Sessions behave oddly.

Teams also run diagnostics on the **wrong Redis logical database** (db0 vs db15). Queue length shows zero while work is backed up elsewhere.

### Why juniors fall into this

- Tutorial Redis: one port, no password, unlimited memory.
- `maxmemory 400mb` looks fine until file metadata and task payloads add up.
- “Redis is fast” becomes “Redis needs no design.”

### How to avoid it

- Document **which Redis DB** each subsystem uses.
- Size Redis for **broker + peak queue**, not only session cache.
- Avoid eviction policies that drop **queue keys** under pressure.
- Script `LLEN` (or equivalent) on critical queues; run it during incident, not after.

**Analogy:** Using your desk drawer as inbox, filing cabinet, and lunch fridge. It works until Tuesday.

---

## Problem 5: Search index down—and nobody notices until upload day

### What goes wrong

The vector/search service (OpenSearch, Elasticsearch, etc.) is misconfigured: a **one-character typo** in config (`single-nod` instead of `single-node`), or **heap larger than container memory**. The pod enters a restart loop (OOM kill). Uploads “succeed” to object storage but **indexing fails**. Chat may still work for small files; large-document Q&A breaks. Status fields show `FAILED` or stuck `PROCESSING`.

### Why juniors fall into this

- Search is “phase 2”; uploads are tested before search health is verified.
- Cluster health is checked once at install, not continuously.
- Logs are split across API, worker, and search—nobody correlates them.

### How to avoid it

- Gate deploy on **`cluster health` green/yellow**, not only TCP port open.
- API init containers should wait for **search readiness**, not only “port listening.”
- Alert on pod **restart count** for stateful search nodes.
- Treat `FAILED` rows in metadata DB as a first-class metric.

**Analogy:** Books arrive at the warehouse, but the catalog department is closed. Shelves look empty even though boxes are stacked in the back.

---

## Problem 6: The model that needs the internet in a room with no internet

### What goes wrong

At query or index time, the embedding or LLM layer tries to **download weights from the public internet**. Production is air-gapped or egress-restricted. Error: cannot reach hub, file not in cache. Indexing fails; retrieval fails; uploads never complete.

Health endpoint still returns `200` because the **process is alive**, not because the **model is loaded**.

### Why juniors fall into this

- Dev laptop has Hugging Face cache populated from months of experiments.
- `HF_HUB_OFFLINE` and volume mounts are “prod hardening” items skipped for speed.
- Admin UI selects the biggest shiny model without matching hardware or offline cache.

### How to avoid it

- **Pre-load models** to shared storage; mount read-only into inference pods.
- Set offline flags in prod; fail deploy if model path is empty.
- Smoke-test **`/embed` or equivalent** after deploy, not only `/health`.
- Match model size to **GPU/RAM**; an 8B embedding model on a 4Gi pod is a plan, not a deployment.

**Analogy:** Sending a chef to cook a recipe that says “ingredients: download from cloud.” Kitchen has no Wi‑Fi.

---

## Problem 7: LLM timeouts—users see a freeze, logs show success later

### What goes wrong

Chat uses **streaming** or multi-step tool calls. Each step waits on the LLM gateway. Default HTTP read timeout (60s) is shorter than model latency under load. Proxy returns 504; user refreshes; answer appears in history—because the backend finished **after** the client gave up.

### Why juniors fall into this

- Timeouts copied from REST CRUD examples, not from LLM reality.
- Streaming not configured end-to-end (gateway buffers SSE).
- Load test is one user, one short question.

### How to avoid it

- Raise read timeouts on **gateway, route, and HTTP client** together (e.g. 5–30 minutes for long streams, with care).
- Test **six concurrent streams**, not one.
- Put a **gateway** (LiteLLM-style) in front of raw inference for routing, retries, and observability—don’t let every service speak a different dialect to the GPU layer.

**Analogy:** Hanging up the phone at 60 seconds while the other person is still talking. They finish the sentence to an empty line.

---

## Problem 8: Stuck states—`DELETING` forever

### What goes wrong

Delete is implemented as: mark row `DELETING` → enqueue async cleanup → remove from search index and object storage → delete row. Any step fails; row stays `DELETING`. UI looks broken. Retries make it worse if workers are starved.

### Why juniors fall into this

- Happy path tested: delete one small file once.
- No dashboard for **stuck status counts** in the database.
- Delete queue shares workers with heavy indexing.

### How to avoid it

- Dedicated delete workers and queues.
- Metrics: `COUNT(*) WHERE status = 'DELETING'` and age of oldest row.
- Idempotent cleanup jobs and alerts when delete queue age > N minutes.

**Analogy:** Trash marked “taken out” still sitting in the hallway because the truck never came.

---

## Problem 9: Missing one binary in the image—edge format only

### What goes wrong

PDF pipeline fails on specific files (e.g. JBIG2-compressed scans). Base image lacks a system dependency (`jbig2dec`, `tesseract`, etc.). Small test PDFs pass; one real customer document fails. Error looks like “application bug,” root cause is **Dockerfile**.

### Why juniors fall into this

- CI tests sample files, not production corpus.
- “It worked in dev” with a fatter local image.
- Assume Python package alone handles all formats.

### How to avoid it

- Collect **real failed files** (redacted) into a regression set.
- Extend image `FROM upstream:tag` + `apt-get install` missing tools.
- Log **parser dependency errors** clearly at ingest time.

**Analogy:** A car wash that handles dust but not mud because nobody installed the underbody spray.

---

## Problem 10: Six users felt like a DDoS—capacity was never budgeted together

### What goes wrong

Each component passed its individual smoke test. Nobody tested **combined** load: chat + upload + delete + search. CPU requests sum above node capacity; workers throttle; GPUs serialize; everything feels like a crash.

### Why juniors fall into this

- Sizing docs read but treated as “future problem.”
- Horizontal scale only on the API, not on workers or inference.
- No single diagram of **who calls whom under load**.

### How to avoid it

- Run a **30-minute multi-user script**: N people chat, M upload, K delete.
- Watch queue depth, pod restarts, GPU utilization, p95 latency **during** the test.
- Scale the bottleneck you measure, not the one you guess.

**Analogy:** Every room passed fire inspection alone; nobody checked what happens when 500 people are in the building at once.

---

## Problem 11: Authentication stored in three places—debugging the wrong one

### What goes wrong

Login issues send juniors to grep the wrong layer: password in Postgres, session in Redis, token in browser cookie, signing key in Kubernetes secret. `psql` without host connects to local socket and shows “role does not exist.” Hours lost.

### Why juniors fall into this

- Auth taught as “JWT tutorial,” not as **distributed state**.
- Shell into wrong pod; env vars differ from laptop `.env`.

### How to avoid it

- One-page map: **where credentials live, where session lives, where permissions live**.
- Standard debug recipe: validate token → check session store → check user row → check ownership query.
- Always connect to DB with **explicit host** inside the cluster.

**Analogy:** Looking for your keys in the jacket while they are in the car. Same person, wrong pocket.

---

## Problem 12: RAG vs “paste the whole file”—debugging the wrong pipeline

### What goes wrong

Small file works in chat; large file fails after delete. Team assumes “upload broken.” Actually **two pipelines** exist: full text in prompt vs search-index retrieval. Large files need indexing; indexing needs search + embeddings. Delete leaves **conversation history** that still references old filenames; model emits raw tool markup when tool routing breaks.

### Why juniors fall into this

- “File upload” and “question answering” taught as one feature.
- `FAILED` on file row interpreted as “unusable everywhere,” but small-file path may still use object storage directly.

### How to avoid it

- Document **which path** each file size takes.
- After delete, test in a **new conversation**.
- Separate alerts for **ingest failure** vs **chat failure**.

**Analogy:** Two doors into the library—express lane for pamphlets, catalog desk for encyclopedias. Complaining the express lane won’t fit an encyclopedia is the wrong complaint.

---

## A junior-friendly checklist before you call production “done”

Print this. Check boxes in order.

1. **User path test** — Hit the public URL, not internal service DNS.
2. **Gateway alignment** — Paths, upload size, timeouts, streaming headers.
3. **Background capacity** — Queue depths visible; workers split by job type.
4. **Scheduler writable** — Beat/cron actually ran once post-deploy.
5. **Search health** — Cluster green; no restart loops; sample index + query.
6. **Models offline-ready** — Weights on disk; embed smoke test passes.
7. **LLM path under load** — N concurrent chats; timeouts aligned.
8. **Delete path** — No growing `DELETING` (or equivalent) population.
9. **Real files** — At least one nasty PDF from the wild in CI.
10. **Six-user soak** — Mixed actions for 30 minutes; watch restarts and queues.

---

## What seniors know that juniors learn the hard way

Production failures are usually **boring**:

- Wrong path at the proxy.
- Not enough workers.
- One dependency restarted.
- Timeout too short.
- Disk or memory too small.
- Async job never consumed.

They are rarely “the framework is broken.” They are almost always **integration and capacity** under constraints you did not simulate.

The tutorial showed you how to start the orchestra. Production asks whether the violins can still be heard when the drums, the choir, and the fire alarm go off at the same time.

---

## Closing thought

If you are early in your career and this list feels overwhelming—good. That means you are thinking at the right altitude. You do not need to memorize every tool. You need habits:

- Test the **full path** users take.
- Measure **queues and stuck states**, not only HTTP 200.
- Draw **one diagram** before you change timeouts or replicas.
- Run **small multi-user tests** before the big demo.

The goal is not zero incidents. The goal is incidents that are **boring, short, and diagnosable**—because you already know which hallway the problem lives in.

---

*Written for engineers shipping AI-backed platforms to Kubernetes-class environments. Names, products, and customers intentionally omitted—only patterns remain.*
