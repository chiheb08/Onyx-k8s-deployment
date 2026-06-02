import uuid

from fastapi import FastAPI
from fastapi import File
from fastapi import Form
from fastapi import Request
from fastapi import UploadFile
from fastapi.responses import RedirectResponse
from fastapi.templating import Jinja2Templates

from .db import SessionLocal
from .db import init_db
from .minio_client import ensure_bucket_exists
from .minio_client import get_s3_client
from .models import DeleteAudit
from .models import FileRecord
from .models import FileStatus
from .tasks import delete_file_from_storage

app = FastAPI(title="Onyx-like File Lifecycle Demo", version="1.0.0")
templates = Jinja2Templates(directory="app/templates")


@app.on_event("startup")
def startup() -> None:
    init_db()
    ensure_bucket_exists()


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.get("/")
def index(request: Request):
    session = SessionLocal()
    try:
        files = session.query(FileRecord).order_by(FileRecord.created_at.desc()).all()
        audits = session.query(DeleteAudit).order_by(DeleteAudit.created_at.desc()).limit(20).all()
        return templates.TemplateResponse(
            request=request,
            name="index.html",
            context={"files": files, "audits": audits},
        )
    finally:
        session.close()


@app.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    data = await file.read()
    file_id = uuid.uuid4()
    object_key = f"uploads/{file_id}/{file.filename}"

    s3 = get_s3_client()
    s3.put_object(Bucket="demo-files", Key=object_key, Body=data)

    session = SessionLocal()
    try:
        row = FileRecord(
            id=file_id,
            filename=file.filename,
            object_key=object_key,
            status=FileStatus.COMPLETED,
        )
        session.add(row)
        session.commit()
    finally:
        session.close()

    return RedirectResponse(url="/", status_code=303)


@app.post("/files/{file_id}/delete")
def request_delete(file_id: str, reason: str = Form(default="manual_delete")):
    session = SessionLocal()
    try:
        row = session.get(FileRecord, uuid.UUID(file_id))
        if row is None:
            return RedirectResponse(url="/", status_code=303)

        row.status = FileStatus.DELETING
        session.add(
            DeleteAudit(
                file_id=str(row.id),
                filename=row.filename,
                event="DELETE_REQUESTED",
                message=f"API set status=DELETING (reason={reason}) and enqueued Celery task",
            )
        )
        session.commit()
    finally:
        session.close()

    # Queue into dedicated delete queue so queue monitoring is simple.
    task = delete_file_from_storage.apply_async(args=[file_id], queue="file_delete")
    return RedirectResponse(url=f"/?task_id={task.id}", status_code=303)


@app.get("/api/files")
def api_files():
    session = SessionLocal()
    try:
        rows = session.query(FileRecord).order_by(FileRecord.created_at.desc()).all()
        return [
            {
                "id": str(r.id),
                "filename": r.filename,
                "object_key": r.object_key,
                "status": r.status.value,
                "created_at": r.created_at.isoformat() if r.created_at else None,
            }
            for r in rows
        ]
    finally:
        session.close()
