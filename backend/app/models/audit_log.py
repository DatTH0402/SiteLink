from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, DateTime, Text, ForeignKey

from app.db.base import Base


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id         = Column(Integer, primary_key=True, index=True)
    user_id    = Column(Integer, ForeignKey("users.id"), nullable=True)
    username   = Column(String(100))
    action     = Column(String(20))
    table_name = Column(String(100))
    record_id  = Column(Integer)
    old_value  = Column(Text)
    new_value  = Column(Text)
    timestamp  = Column(DateTime(timezone=True),
                        default=lambda: datetime.now(timezone.utc))
