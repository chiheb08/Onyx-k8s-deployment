import time
from uuid import UUID

from celery.utils.log import get_task_logger

from .celery_app import celery_app
from .config import settings
from .db import SessionLocal
from .db import init_db
from .minio_client import get_s3_client
from .models import DeleteAudit
from .models import FileRecord
from .models import FileStatus

task_logger = get_task_logger(__name__)


@celery_app.task(name="demo.delete_file_from_storage")
def delete_file_from_storage(file_id: str) -> dict:
    """
    Onyx-like behavior:
    1) row already set to DELETING by API
    2) worker deletes object from MinIO
    3) worker deletes the row from Postgres (instead of setting DELETED)
    4) worker writes an audit record so we can still inspect history
    """
    init_db()
    session = SessionLocal()
    try:
        record = session.get(FileRecord, UUID(file_id))
        if record is None:
            task_logger.info("File row already gone: %s", file_id)
            return {"file_id": file_id, "result": "already_deleted"}

        if record.status != FileStatus.DELETING:
            task_logger.info("Skipping delete for %s status=%s", file_id, record.status)
            return {"file_id": file_id, "result": f"skipped_status_{record.status.value}"}

        # Delay helps visualize queue + DELETING status.
        time.sleep(settings.simulated_delete_delay_seconds)

        s3 = get_s3_client()
        s3.delete_object(Bucket=settings.minio_bucket, Key=record.object_key)

        audit = DeleteAudit(
            file_id=str(record.id),
            filename=record.filename,
            event="ROW_DELETED",
            message="Object removed from MinIO, then row removed from file_record",
        )
        session.add(audit)
        session.delete(record)
        session.commit()

        task_logger.info("Deleted file_id=%s object_key=%s", file_id, record.object_key)
        return {"file_id": file_id, "result": "deleted"}
    except Exception as exc:
        session.rollback()
        task_logger.exception("Delete failed for %s", file_id)
        raise exc
    finally:
        session.close()
