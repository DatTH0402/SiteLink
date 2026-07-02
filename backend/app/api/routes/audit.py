from typing import Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.audit_log import AuditLog
from app.models.user import User
from app.utils.deps import require_admin

router = APIRouter()


@router.get("/")
def list_audit_logs(
    skip: int = 0,
    limit: int = 100,
    table_name: Optional[str] = Query(None),
    action:     Optional[str] = Query(None),
    db: Session = Depends(get_db),
    _=Depends(require_admin),
):
    q = (
        db.query(AuditLog, User.full_name, User.email)
        .outerjoin(User, AuditLog.user_id == User.id)
        .order_by(AuditLog.timestamp.desc())
    )
    if table_name:
        q = q.filter(AuditLog.table_name == table_name)
    if action:
        q = q.filter(AuditLog.action == action)

    rows = q.offset(skip).limit(limit).all()

    return [
        {
            "id":         log.id,
            "username":   log.username,
            "full_name":  full_name or "",
            "email":      email or "",
            "action":     log.action,
            "table_name": log.table_name,
            "record_id":  log.record_id,
            "old_value":  log.old_value,
            "new_value":  log.new_value,
            "timestamp":  log.timestamp.isoformat() if log.timestamp else None,
        }
        for log, full_name, email in rows
    ]
