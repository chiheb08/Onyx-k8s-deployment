# Vespa 429 “Too Many Requests” – Junior-Friendly Guide

## 🧠 What does 429 mean?
- **HTTP 429** = “Too Many Requests”
- Vespa uses it to say: “I’m already processing as much as I can. Please slow down.”
- Think of it like a small post office with only one clerk. If 50 people drop in with huge boxes, the clerk tells new arrivals to wait outside. That “wait” message is 429.

## 🗂 Why does it happen with large documents?
1. When a user uploads a big file, Onyx splits it into **lots of chunks** (hundreds or thousands).
2. Every chunk gets embedded and then **fed to Vespa** so it can be searched later.
3. If we push all chunks at once, Vespa’s “inbox” (pending queue) fills up.
4. Vespa would rather return **429** than crash. It’s a safety valve that says “I’ll be ready again when my queue empties.”

### Simple analogy
- Imagine Vespa has **20 slots** in its inbox.
- You upload a 200-page PDF → 200 chunks.
- We try to hand Vespa 200 envelopes at once, but it only has 20 slots.
- After the first 20, Vespa says “429” for the remaining 180 until it finishes processing the first batch.

## 📍 What we saw in OpenShift
- Deployment uses **one Vespa pod** (single node).
- Hardware is modest (e.g., 2 CPU / 4GB RAM).
- Large document uploads trigger bursts of feed requests.
- Vespa logs show `too many pending operations` and the API returns 429.

## 🔍 How to confirm
1. `kubectl logs vespa-0 -n <ns>` → Look for messages like:
   - `PendingLids full, throttling`
   - `429 Too Many Requests`
2. Inside the pod: `/opt/vespa/logs/vespa/vespa.log` or `access.log`.
3. Check Onyx worker logs: they’ll show feed errors with HTTP 429.

## ✅ Solutions (from easiest to strongest)

| Action | Explanation |
|--------|-------------|
| **Throttle feed concurrency** | Lower `VESPA_FEED_CONCURRENCY` or limit how many uploads run in parallel so you don’t flood Vespa. |
| **Increase pod resources** | Give Vespa more CPU/RAM so it can drain the queue faster (e.g., 4 CPUs / 16GB RAM). |
| **Tune Vespa queue limits** | In `services.xml`, raise `maxpendingdocs` / feeding threads so Vespa accepts slightly larger bursts. |
| **Add retry/backoff logic** | On feed 429, retry with exponential backoff instead of failing immediately. |
| **Scale horizontally (multi-node)** | Deploy more Vespa content pods. Each node handles part of the data, so the load per node drops. Recommended once you hit 429 regularly. |

### Do we *need* multi-node Vespa?
- Not mandatory for tiny deployments.
- **But** if you ingest large documents often, one pod becomes a bottleneck.
- Multi-node = better throughput and resilience. Vespa was designed for it.

## 🧩 Example fix plan for OpenShift
1. Update the Vespa statefulset:
   - `resources.requests/limits` → e.g., `cpu: 4`, `memory: 16Gi`.
2. Set `VESPA_FEED_CONCURRENCY=2` in Onyx user-file-processing worker.
3. Add a retry decorator to feed operations (retry 3 times on 429 with delay).
4. Long-term: adjust Vespa `services.xml` to run 2+ content nodes and redeploy.

## 📝 Takeaways for junior IT engineers
- 429 isn’t a crash; it’s Vespa protecting itself.
- Large uploads = lots of tiny feed requests.
- Single-node Vespa can’t keep up; it temporarily pushes back.
- Fix options: slow down input, give it more power, or add more Vespa nodes.
- Monitor logs to see how often 429 happens; use that to decide when to scale.

Once you implement throttling + resource tuning, 429 errors drop dramatically. If ingestion demand keeps growing, plan a multi-node Vespa cluster so the load is shared across pods.

