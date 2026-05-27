import json
from sqlalchemy.orm import Session
from app.models.audit_log import AuditLog
from app.models.user import User


def log_action(
    db: Session,
    user: User,
    action: str,
    table_name: str,
    record_id: int,
    old_value: dict = None,
    new_value: dict = None,
):
    entry = AuditLog(
        user_id=user.id,
        username=user.username,
        action=action,
        table_name=table_name,
        record_id=record_id,
        old_value=json.dumps(old_value, ensure_ascii=False, default=str) if old_value else None,
        new_value=json.dumps(new_value, ensure_ascii=False, default=str) if new_value else None,
    )
    db.add(entry)
    db.commit()
