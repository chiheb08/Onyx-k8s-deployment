#!/usr/bin/env python3
"""
SYNC demo — tasks run one after another.

Run: python3 sync_demo.py
Expected: ~6 seconds total (3 tasks × 2 seconds each)
"""

import time

SECONDS_PER_TASK = 2


def make_coffee(customer: str) -> None:
    print(f"  [{customer}] Starting... (brewing {SECONDS_PER_TASK}s)")
    time.sleep(SECONDS_PER_TASK)  # BLOCKS — nothing else runs here
    print(f"  [{customer}] Done!")


def main() -> None:
    print("=" * 50)
    print("SYNC MODE — one customer at a time")
    print("=" * 50)

    start = time.perf_counter()

    make_coffee("Customer A")
    make_coffee("Customer B")
    make_coffee("Customer C")

    elapsed = time.perf_counter() - start
    print()
    print(f"Total time: {elapsed:.1f}s  (expected ~{3 * SECONDS_PER_TASK}s)")
    print("Notice: each 'Done' appears only after the previous one finished.")


if __name__ == "__main__":
    main()
