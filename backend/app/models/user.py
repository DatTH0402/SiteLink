from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Boolean, DateTime, Enum as PgEnum
import enum

from app.db.base import Base


class UserRole(str, enum.Enum):
    admin = "admin"
    user = "user"


class UserAuthProvider(str, enum.Enum):
    local = "local"
    sso = "sso"


class User(Base):
    __tablename__ = "users"

    id               = Column(Integer, primary_key=True, index=True)
    email            = Column(String(255), unique=True, index=True, nullable=False)
    username         = Column(String(100), unique=True, index=True, nullable=False)
    full_name        = Column(String(255))
    hashed_password  = Column(String(255), nullable=True)
    role             = Column(PgEnum(UserRole), default=UserRole.user, nullable=False)
    is_active        = Column(Boolean, default=True)
    auth_provider    = Column(PgEnum(UserAuthProvider), default=UserAuthProvider.local)
    sso_subject      = Column(String(255), nullable=True, unique=True)
    created_at       = Column(DateTime(timezone=True),
                              default=lambda: datetime.now(timezone.utc))
    updated_at       = Column(DateTime(timezone=True),
                              default=lambda: datetime.now(timezone.utc),
                              onupdate=lambda: datetime.now(timezone.utc))
