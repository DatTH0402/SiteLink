import os

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.core.config import settings

_stmt_timeout = int(os.environ.get("DB_STATEMENT_TIMEOUT_MS", "300000"))

# Pool is per gunicorn worker:  workers x (pool_size + max_overflow)  must stay
# below postgres max_connections (200 in docker-compose.yml).
engine = create_engine(
    settings.DATABASE_URL,
    pool_pre_ping=True,
    pool_size=int(os.environ.get("DB_POOL_SIZE", "8")),
    max_overflow=int(os.environ.get("DB_MAX_OVERFLOW", "12")),
    pool_timeout=int(os.environ.get("DB_POOL_TIMEOUT", "30")),
    pool_recycle=int(os.environ.get("DB_POOL_RECYCLE", "1800")),
    connect_args={"options": f"-c statement_timeout={_stmt_timeout}"} if _stmt_timeout > 0 else {},
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
