from celery import Celery

from .config import settings

celery_app = Celery(
    "onyx_like_lifecycle_demo",
    broker=settings.redis_broker_url,
    backend=settings.redis_result_backend_url,
    include=["app.tasks"],
)

celery_app.conf.update(
    task_default_queue="demo_default",
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone="UTC",
    enable_utc=True,
)
