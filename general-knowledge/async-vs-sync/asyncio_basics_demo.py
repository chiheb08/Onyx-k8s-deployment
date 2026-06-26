#!/usr/bin/env python3
"""
Python asyncio — 6 mini lessons with printed output.

Run: python3 asyncio_basics_demo.py

Read PYTHON-ASYNCIO-EXPLAINED.md for the full guide.
"""

import asyncio
import time


def header(n: int, title: str) -> None:
    print()
    print("=" * 60)
    print(f"LESSON {n}: {title}")
    print("=" * 60)


async def lesson1_coroutine_basics() -> None:
    header(1, "Coroutine — calling async def without await")

    async def greet() -> str:
        return "hello from coroutine"

    coro = greet()
    print(f"  greet() returned type: {type(coro).__name__}")
    print("  (not the string yet — you must await it)")
    coro.close()  # demo only: we showed the coroutine object without running it

    result = await greet()
    print(f"  await greet() => {result!r}")


async def lesson2_sequential_await() -> None:
    header(2, "Sequential await — slow (one after another)")

    async def step(name: str, seconds: float) -> None:
        print(f"  [{name}] start")
        await asyncio.sleep(seconds)
        print(f"  [{name}] done")

    start = time.perf_counter()
    await step("A", 1)
    await step("B", 1)
    elapsed = time.perf_counter() - start
    print(f"  Total: {elapsed:.1f}s (expected ~2s)")


async def lesson3_gather() -> None:
    header(3, "asyncio.gather — fast (overlapping waits)")

    async def step(name: str, seconds: float) -> None:
        print(f"  [{name}] start")
        await asyncio.sleep(seconds)
        print(f"  [{name}] done")

    start = time.perf_counter()
    await asyncio.gather(step("A", 1), step("B", 1))
    elapsed = time.perf_counter() - start
    print(f"  Total: {elapsed:.1f}s (expected ~1s, not ~2s)")


async def lesson4_create_task() -> None:
    header(4, "create_task — start now, await later")

    async def background_job() -> None:
        print("  [background] working...")
        await asyncio.sleep(1)
        print("  [background] finished")

    print("  main: starting background task")
    task = asyncio.create_task(background_job())
    print("  main: doing other work while background runs")
    await asyncio.sleep(0.3)
    print("  main: now waiting for background")
    await task
    print("  main: all done")


async def lesson5_timeout() -> None:
    header(5, "wait_for — timeout if too slow")

    async def slow() -> None:
        await asyncio.sleep(5)

    try:
        await asyncio.wait_for(slow(), timeout=0.5)
    except asyncio.TimeoutError:
        print("  Caught TimeoutError — slow() took too long (good!)")


async def lesson6_blocking_mistake() -> None:
    header(6, "DON'T block the event loop with time.sleep")

    async def good_wait() -> None:
        await asyncio.sleep(0.5)

    async def task(name: str, use_blocking: bool) -> None:
        print(f"  [{name}] start")
        if use_blocking:
            time.sleep(0.5)  # blocks entire event loop
        else:
            await asyncio.sleep(0.5)
        print(f"  [{name}] done")

    print("  Bad: two tasks with time.sleep — run one at a time")
    start = time.perf_counter()
    await asyncio.gather(task("X", True), task("Y", True))
    bad = time.perf_counter() - start
    print(f"  Bad total: {bad:.1f}s (~1s sequential)")

    print()
    print("  Good: two tasks with await asyncio.sleep — overlap")
    start = time.perf_counter()
    await asyncio.gather(task("X", False), task("Y", False))
    good = time.perf_counter() - start
    print(f"  Good total: {good:.1f}s (~0.5s concurrent)")


async def main() -> None:
    print("PYTHON ASYNCIO — HANDS-ON DEMO")
    print("Read PYTHON-ASYNCIO-EXPLAINED.md for full explanations.")

    await lesson1_coroutine_basics()
    await lesson2_sequential_await()
    await lesson3_gather()
    await lesson4_create_task()
    await lesson5_timeout()
    await lesson6_blocking_mistake()

    print()
    print("=" * 60)
    print("All lessons complete.")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(main())
