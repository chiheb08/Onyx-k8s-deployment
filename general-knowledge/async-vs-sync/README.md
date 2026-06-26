# Sync vs Async — Very Easy Explanation + Hands-On

**Goal:** Understand the difference in 5 minutes and *see* it with your own eyes.

---

## The coffee shop analogy

Imagine you are a barista with **3 customers**. Each order takes **3 seconds** to make.

### Sync (synchronous) — one at a time

You finish customer 1 completely, then customer 2, then customer 3.

```
Customer 1 ████████ 3s
Customer 2         ████████ 3s
Customer 3                 ████████ 3s
────────────────────────────────────► time
Total: 9 seconds
```

You **wait** while each coffee is brewing. You do nothing else during that wait.

### Async (asynchronous) — start many, wait smartly

You start all 3 coffees (they brew in parallel), and you do other useful work while waiting.

```
Customer 1 ████████ 3s
Customer 2 ████████ 3s  (overlapping)
Customer 3 ████████ 3s  (overlapping)
────────────────────────────────────► time
Total: ~3 seconds
```

You don't stand still staring at one machine. You **switch** while things are waiting.

---

## One sentence each

| | Sync | Async |
|---|------|-------|
| **Meaning** | Do step 1, **wait until done**, then step 2 | Start step 1, **while waiting** start step 2 |
| **Waiting** | Blocking — you are stuck | Non-blocking — you can do other work |
| **Like** | Single lane road | Multiple lanes / roundabout |

---

## When does this matter in real systems?

| Sync example | Async example |
|--------------|---------------|
| `psql` query — API waits for DB answer before continuing | Celery worker — API returns "upload accepted", worker indexes in background |
| One HTTP call to vLLM — thread blocked until full response | Streaming chat — tokens arrive while connection stays open |
| Read a file line by line, process, then next file | Process 10 file uploads with a job queue |

**Onyx examples:**

- **Sync:** User asks a question → API waits for LLM → returns answer (HTTP request open the whole time).
- **Async:** User uploads PDF → API says OK immediately → Celery worker indexes in background (Redis queue).

---

## Hands-on: run the demos

You need **Python 3.8+** (already on most Mac/Linux machines).

### Demo 1 — Sync (slow, one after another)

```bash
cd general-knowledge/async-vs-sync
python3 sync_demo.py
```

**What you will see:** 3 tasks × 2 seconds = **~6 seconds total**. Each task finishes before the next starts.

### Demo 2 — Async (fast, overlapping)

```bash
python3 async_demo.py
```

**What you will see:** 3 tasks × 2 seconds but **~2 seconds total** because they run concurrently.

### Demo 3 — Side by side comparison

```bash
python3 compare_both.py
```

Prints both timings so you can compare numbers on one screen.

---

## What the code does (super simple)

### Sync (`sync_demo.py`)

```python
def make_coffee(name):
    time.sleep(2)   # pretend brewing — BLOCKS here
    print(f"{name} done")

make_coffee("A")    # wait 2s
make_coffee("B")    # wait 2s
make_coffee("C")    # wait 2s
# Total ~6s
```

`sleep` = **you stand still and wait**.

### Async (`async_demo.py`)

```python
async def make_coffee(name):
    await asyncio.sleep(2)   # pretend brewing — OTHER tasks can run
    print(f"{name} done")

await asyncio.gather(
    make_coffee("A"),
    make_coffee("B"),
    make_coffee("C"),
)
# Total ~2s
```

`await` = **"I'm waiting for this, but the program can work on other tasks meanwhile"**.

---

## Common mistakes beginners make

| Wrong idea | Truth |
|------------|-------|
| "Async is always faster" | Only faster when you **wait** a lot (I/O: network, disk, DB). CPU-heavy math often needs threads/processes, not async alone. |
| "Async means multithreading" | Not always. Python `asyncio` is usually **one thread**, switching between tasks. |
| "Background job = async" | Close! Celery is **async at system level** (API doesn't wait), but each worker may run tasks **sync** inside. |

---

## Quick reference card

```
SYNC                          ASYNC
────                          ─────
Call → wait → result          Call → continue other work → result later

HTTP: request blocks          HTTP: return 202 + job id, poll later
DB:   query blocks thread     Queue: Redis + Celery worker
LLM:  wait for full answer    Stream: tokens arrive over time
```

---

## Files in this folder

| File | Purpose |
|------|---------|
| `README.md` | Sync vs async intro |
| [PYTHON-ASYNCIO-EXPLAINED.md](./PYTHON-ASYNCIO-EXPLAINED.md) | **Detailed asyncio guide** |
| `sync_demo.py` | Blocking demo |
| `async_demo.py` | Concurrent demo |
| `compare_both.py` | Run both and print timings |
| `asyncio_basics_demo.py` | 6 asyncio lessons (hands-on) |

---

*Part of `general-knowledge/` — concepts that apply beyond Onyx/K8s.*
