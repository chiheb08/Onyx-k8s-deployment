#!/usr/bin/env python3
"""
Compare SYNC vs ASYNC side by side.

Run: python3 compare_both.py
"""

import asyncio
import time

SECONDS_PER_TASK = 2
TASKS = ["A", "B", "C"]


def sync_run() -> float:
    start = time.perf_counter()
    for name in TASKS:
        time.sleep(SECONDS_PER_TASK)
    return time.perf_counter() - start


async def async_run() -> float:
    start = time.perf_counter()

    async def one(_name: str) -> None:
        await asyncio.sleep(SECONDS_PER_TASK)

    await asyncio.gather(*(one(n) for n in TASKS))
    return time.perf_counter() - start


def main() -> None:
    print("Comparing 3 tasks × 2 second wait each\n")

    sync_time = sync_run()
    print(f"  SYNC:  {sync_time:.2f}s  (sequential)")

    async_time = asyncio.run(async_run())
    print(f"  ASYNC: {async_time:.2f}s  (concurrent)")

    saved = sync_time - async_time
    print()
    print(f"  Async saved ~{saved:.1f}s in this toy example.")
    print("  In production: same idea for API + queues, streaming, parallel HTTP.")


if __name__ == "__main__":
    main()
