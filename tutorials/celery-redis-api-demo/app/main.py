from celery.result import AsyncResult
from fastapi import FastAPI
from pydantic import BaseModel, Field

from .celery_app import celery_app
from .tasks import slow_square

app = FastAPI(title="Celery + Redis Demo API", version="1.0.0")


class TaskRequest(BaseModel):
    value: int = Field(..., ge=0, le=1000000)
    delay_seconds: int = Field(default=5, ge=0, le=60)


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/tasks/square")
def enqueue_square_task(payload: TaskRequest) -> dict:
    task = slow_square.delay(payload.value, payload.delay_seconds)
    return {
        "message": "Task enqueued",
        "task_id": task.id,
        "queue": "demo",
        "broker_db": 15,
        "result_backend_db": 16,
    }


@app.get("/tasks/{task_id}")
def get_task_status(task_id: str) -> dict:
    task: AsyncResult = AsyncResult(task_id, app=celery_app)
    response = {"task_id": task.id, "state": task.state}
    if task.successful():
        response["result"] = task.result
    elif task.failed():
        response["error"] = str(task.result)
    return response
