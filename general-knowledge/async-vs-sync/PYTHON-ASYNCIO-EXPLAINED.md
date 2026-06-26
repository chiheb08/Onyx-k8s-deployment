# Python `asyncio` — Detailed but Very Easy Guide

**Who this is for:** You understand sync vs async in theory, and now you want to know how Python does it with `asyncio`.

**Prerequisite:** [README.md](./README.md) (sync vs async basics)

**Hands-on file:** Run `python3 asyncio_basics_demo.py` after reading Part 1–3.

---

## Part 1 — What is `asyncio`?

`asyncio` is Python’s **built-in library** for writing **async** code.

It gives you:

- `async def` — define a coroutine (a function that can pause)
- `await` — pause here until something finishes, but let other tasks run
- `asyncio.run()` — start the async world from normal sync code
- `asyncio.gather()` — run many tasks concurrently
- `asyncio.sleep()` — non-blocking wait (like `time.sleep` but async-friendly)

**Important:** `asyncio` is great when your program **waits a lot** (network, disk, timers). It is **not magic** for heavy CPU math — that needs threads or multiple processes.

---

## Part 2 — The 5 words you must know

| Word | Simple meaning | Example |
|------|----------------|---------|
| **Coroutine** | An async function you can pause | `async def fetch(): ...` |
| **await** | “Pause me until this is ready” | `await asyncio.sleep(1)` |
| **Event loop** | The boss that switches between tasks | Started by `asyncio.run()` |
| **Task** | A coroutine scheduled to run | `asyncio.create_task(...)` |
| **Concurrent** | Many things in progress, overlapping in time | 3 downloads at once |

### Picture: the event loop

```
┌─────────────────────────────────────────┐
│           EVENT LOOP (the boss)           │
│                                         │
│   Task A: running... await sleep ──► pause
│   Task B: running... await sleep ──► pause
│   Task C: running... done!              │
│   Task A: wake up... done!              │
│   Task B: wake up... done!              │
└─────────────────────────────────────────┘
```

Only **one** task runs Python code at a time (one thread), but while a task is **waiting**, another task can run.

That is why it is fast for I/O (input/output), not for crunching numbers.

---

## Part 3 — Sync code vs async code (side by side)

### Sync

```python
import time

def download(name):
    time.sleep(2)      # BLOCKS — nobody else runs
    print(f"{name} done")

download("file1")
download("file2")
# Total: ~4 seconds
```

### Async

```python
import asyncio

async def download(name):
    await asyncio.sleep(2)   # PAUSES this task, others can run
    print(f"{name} done")

async def main():
    await asyncio.gather(
        download("file1"),
        download("file2"),
    )

asyncio.run(main())
# Total: ~2 seconds
```

### The rules

1. You can only `await` **inside** `async def`.
2. To call async code from normal scripts, use `asyncio.run(main())`.
3. `await` does **not** mean “run in another thread”. It means “I’m waiting; event loop, please run someone else”.

---

## Part 4 — `async def` and coroutines

```python
async def say_hello():
    return "hello"
```

Calling it does **not** run the body immediately:

```python
result = say_hello()   # WRONG if you expect "hello"
# result is a coroutine object, not "hello"
```

You must **await** it (inside async code) or pass it to `asyncio.run()`:

```python
async def main():
    result = await say_hello()   # correct
    print(result)                # hello

asyncio.run(main())
```

**Easy memory trick:**

| | Normal function | Async function |
|---|-----------------|----------------|
| Define | `def f():` | `async def f():` |
| Call | `f()` runs now | `f()` returns a coroutine |
| Get result | `x = f()` | `x = await f()` |

---

## Part 5 — `await` explained like you’re 12

Think of `await` as a **yield sign** for your function:

```
"I'm not finished, but I need to wait for something.
 Event loop, you drive for a while — run other tasks.
 Come back to me when my thing is ready."
```

Good things to `await`:

- `await asyncio.sleep(1)` — pretend network delay
- `await asyncio.gather(...)` — wait for many tasks
- `await some_async_library_call()` — real async HTTP, DB, etc.

**Bad:** `await` on a normal blocking function:

```python
await time.sleep(1)   # ERROR — time.sleep is not awaitable
time.sleep(1)         # BAD in async code — blocks the whole event loop!
```

If you must call blocking code from async, use `asyncio.to_thread()` (Python 3.9+) or a thread pool — advanced topic; avoid blocking in async code when you can.

---

## Part 6 — `asyncio.run()` — the front door

Your `main.py` is usually **sync**. To enter async world:

```python
import asyncio

async def main():
    print("inside async")

asyncio.run(main())   # creates event loop, runs main(), closes loop
```

**Use once** at the top level (e.g. under `if __name__ == "__main__"`). Do not nest `asyncio.run()` inside other `asyncio.run()` calls.

---

## Part 7 — `asyncio.gather()` — run many at once

```python
await asyncio.gather(
    download("a"),
    download("b"),
    download("c"),
)
```

- Starts all three
- Waits until **all** are done
- Returns results as a tuple (in order)

Like telling 3 friends to meet you at the café — you wait until **everyone** arrives.

### If one fails

By default, `gather` stops and raises the error. For production you often use `return_exceptions=True` (see hands-on demo).

---

## Part 8 — `asyncio.create_task()` — fire and forget (almost)

Schedule a coroutine to run **soon**, without waiting yet:

```python
async def main():
    task = asyncio.create_task(download("background"))
    await do_something_else()
    await task   # now wait for download to finish
```

Difference from `gather`:

- `create_task` — you control **when** you await
- `gather` — convenient “run all, wait for all”

---

## Part 9 — `asyncio.sleep()` vs `time.sleep()`

| | `time.sleep(n)` | `await asyncio.sleep(n)` |
|---|-----------------|---------------------------|
| Blocks event loop? | **Yes** — everything freezes | **No** — other tasks run |
| Use in async code? | Avoid | Yes |

In demos, `asyncio.sleep` **simulates** waiting for a network response.

---

## Part 10 — Common patterns (copy-paste starters)

### Pattern A — sequential async (still one after another)

```python
async def main():
    await step1()
    await step2()
    await step3()
# Total time = sum of all steps (no overlap)
```

### Pattern B — concurrent async

```python
async def main():
    await asyncio.gather(step1(), step2(), step3())
# Total time ≈ longest step (overlap while waiting)
```

### Pattern C — timeout

```python
try:
    await asyncio.wait_for(slow_call(), timeout=5.0)
except asyncio.TimeoutError:
    print("too slow!")
```

### Pattern D — simple async HTTP (real world)

Libraries like `httpx` or `aiohttp` provide async clients:

```python
import httpx

async def fetch(url):
    async with httpx.AsyncClient() as client:
        response = await client.get(url)
        return response.status_code
```

You `await` the HTTP call — while waiting for the server, other tasks can run.

---

## Part 11 — What `asyncio` is NOT

| Myth | Truth |
|------|-------|
| “Async = parallel on all CPU cores” | Default asyncio = **one thread**, cooperative switching |
| “Put async on everything” | Only helps when you **wait** (I/O bound) |
| “async is always faster” | Overhead exists; for 1 tiny task, sync can be simpler and fine |
| “await runs in background thread” | No — it yields to the **event loop** |

**CPU-heavy work** (big loops, ML inference on CPU): use `multiprocessing`, GPU, or worker queues — not asyncio alone.

---

## Part 12 — How this connects to Onyx / your job

| Onyx piece | Async idea |
|------------|------------|
| File upload API returns 200 quickly | Async **at system level** — Celery does work later |
| Celery worker | Separate process; inside it code may be sync |
| Chat streaming | Connection stays open; tokens arrive over time (like many small `await`s) |
| `httpx` / LiteLLM calls in API | Can use async HTTP in FastAPI endpoints |

FastAPI loves `async def` endpoints because while one user waits for DB/LLM, another request can be handled.

---

## Part 13 — Mistakes beginners make

### 1. Forgetting `await`

```python
async def main():
    download("x")   # BUG: coroutine never runs!
```

Fix: `await download("x")` or `asyncio.create_task(download("x"))`.

### 2. Blocking the event loop

```python
async def bad():
    time.sleep(10)   # freezes ALL async tasks
```

Fix: `await asyncio.sleep(10)` for demos, or `await asyncio.to_thread(blocking_func)` for real blocking I/O.

### 3. Calling `asyncio.run()` inside async code

```python
async def main():
    asyncio.run(other())   # wrong
```

Fix: `await other()`.

### 4. Mixing sync and async libraries

Many DB drivers are sync only. Calling them directly inside `async def` blocks everyone. Use async drivers (`asyncpg`, `httpx`) or run sync code in a thread pool.

---

## Part 14 — Hands-on: run the demo

```bash
cd general-knowledge/async-vs-sync
python3 asyncio_basics_demo.py
```

The script runs **6 mini-lessons** with printed output:

1. Coroutine vs await  
2. Sequential `await` (slow)  
3. `gather` (fast)  
4. `create_task`  
5. `wait_for` timeout  
6. Blocking mistake vs `asyncio.sleep`

---

## Part 15 — Cheat sheet (print this)

```
┌────────────────────────────────────────────────────────────┐
│  PYTHON ASYNCIO CHEAT SHEET                                │
├────────────────────────────────────────────────────────────┤
│  async def f():     →  coroutine function                  │
│  await f()          →  pause until f done, allow others      │
│  asyncio.run(main()) →  start program (sync entrypoint)      │
│  asyncio.gather()   →  run many coroutines, wait for all   │
│  asyncio.create_task() → schedule coroutine, await later   │
│  asyncio.sleep()    →  non-blocking wait                   │
│  time.sleep()       →  DON'T use inside async code         │
└────────────────────────────────────────────────────────────┘
```

---

## Part 16 — Summary

1. **`asyncio`** = Python’s way to write code that **doesn’t waste time waiting**.
2. **`async def`** + **`await`** = “I can pause here.”
3. **Event loop** = switches between paused tasks.
4. **`gather`** = easiest way to run many waits in parallel.
5. Best for **I/O** (network, files, DB with async drivers), not CPU crunching.
6. Run **`asyncio_basics_demo.py`** to see timings and output order.

---

## Related files

| File | Purpose |
|------|---------|
| [README.md](./README.md) | Sync vs async intro |
| [sync_demo.py](./sync_demo.py) | Blocking demo |
| [async_demo.py](./async_demo.py) | Simple gather demo |
| [asyncio_basics_demo.py](./asyncio_basics_demo.py) | 6 asyncio lessons |

---

*Part of `general-knowledge/` — last updated June 2026*
