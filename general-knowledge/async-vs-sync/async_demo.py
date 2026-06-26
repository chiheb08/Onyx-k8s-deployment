#!/usr/bin/env python3
"""
ASYNC demo — tasks overlap while waiting.

Run: python3 async_demo.py
Expected: ~2 seconds total (3 tasks × 2 seconds, but concurrent)
"""

import asyncio
import time

SECONDS_PER_TASK = 2


async def make_coffee(customer: str) -> None:
    print(f"  [{customer}] Starting... (brewing {SECONDS_PER_TASK}s)")
    await asyncio.sleep(SECONDS_PER_TASK)  # yields — other tasks can run
    print(f"  [{customer}] Done!")


async def main_async() -> None:
    print("=" * 50)
    print("ASYNC MODE — all customers at once (while waiting)")
    print("=" * 50)

    start = time.perf_counter()

    await asyncio.gather(
        make_coffee("Customer A"),
        make_coffee("Customer B"),
        make_coffee("Customer C"),
    )

    elapsed = time.perf_counter() - start
    print()
    print(f"Total time: {elapsed:.1f}s  (expected ~{SECONDS_PER_TASK}s, not ~{3 * SECONDS_PER_TASK}s)")
    print("Notice: all 'Starting' lines appear first, then all 'Done' lines together.")


def main() -> None:
    asyncio.run(main_async())


if __name__ == "__main__":
    main()
