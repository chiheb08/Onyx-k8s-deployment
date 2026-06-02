from celery import Celery

# Use db15 for broker and db16 for result backend to mirror common Onyx layouts.
BROKER_URL = "redis://:redispass@redis:6379/15"
RESULT_BACKEND_URL = "redis://:redispass@redis:6379/16"

celery_app = Celery(
    "demo_celery_app",
    broker=BROKER_URL,
    backend=RESULT_BACKEND_URL,
    include=["app.tasks"],
)

celery_app.conf.update(
    task_default_queue="demo",
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone="UTC",
    enable_utc=True,
)
