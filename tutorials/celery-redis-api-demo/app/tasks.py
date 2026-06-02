import time

from .celery_app import celery_app


@celery_app.task(name="demo.slow_square")
def slow_square(value: int, delay_seconds: int = 5) -> dict:
    """Simple task to show queue -> worker -> result lifecycle."""
    start_ts = time.time()
    time.sleep(delay_seconds)
    result = value * value
    elapsed = round(time.time() - start_ts, 2)
    return {
        "input": value,
        "output": result,
        "delay_seconds": delay_seconds,
        "worker_elapsed_seconds": elapsed,
    }
