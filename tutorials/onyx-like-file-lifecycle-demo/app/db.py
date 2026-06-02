from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase
from sqlalchemy.orm import sessionmaker

from .config import settings


class Base(DeclarativeBase):
    pass


engine = create_engine(settings.postgres_url, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


def init_db() -> None:
    # Import models before create_all so metadata is populated.
    from . import models  # noqa: F401

    Base.metadata.create_all(bind=engine)
