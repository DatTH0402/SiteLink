#!/usr/bin/env bash
# =============================================================================
# add_feedback.sh  –  adds the "Hỗ trợ & Góp ý" (feedback / ticket) feature
# Usage:  bash add_feedback.sh [project_root]      (default: current dir)
# Safe to re-run (idempotent). Originals of patched files -> .feedback_backup_*
# =============================================================================
set -euo pipefail

ROOT="$(cd "${1:-.}" && pwd)"
[ -d "$ROOT/backend/app" ] && [ -d "$ROOT/frontend/src" ] || {
  echo "✗ '$ROOT' does not look like the SiteLink root (backend/app, frontend/src)"; exit 1; }
command -v python3 >/dev/null || { echo "✗ python3 is required for patching"; exit 1; }

export SL_ROOT="$ROOT"
export SL_BACKUP="$ROOT/.feedback_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$SL_BACKUP" \
         "$ROOT/frontend/src/components/feedback" \
         "$ROOT/frontend/src/pages/feedback" \
         "$ROOT/backend/uploads/feedback"

echo "▶ Writing backend files..."

# ─────────────────────────────────────────────────────────────────────────────
# backend/app/models/feedback.py
# ─────────────────────────────────────────────────────────────────────────────
cat > "$ROOT/backend/app/models/feedback.py" <<'__SL_EOF__'
from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Text, Boolean, DateTime, ForeignKey
from sqlalchemy.orm import relationship

from app.db.base import Base


def _now():
    return datetime.now(timezone.utc)


class FeedbackTicket(Base):
    __tablename__ = "feedback_tickets"

    id          = Column(Integer, primary_key=True, index=True)
    title       = Column(String(255), nullable=False)
    description = Column(Text, nullable=False)
    category    = Column(String(30), nullable=False, default="help", index=True)
    priority    = Column(String(20), nullable=False, default="normal", index=True)
    status      = Column(String(20), nullable=False, default="new", index=True)

    related_ref = Column(String(255))      # free text: site / cell concerned
    page_url    = Column(String(500))      # page the user was on
    user_agent  = Column(String(500))

    created_by       = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    created_by_name  = Column(String(255))
    created_by_email = Column(String(255))
    assignee_id      = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    assignee_name    = Column(String(255))

    due_date    = Column(DateTime(timezone=True))
    resolution  = Column(Text)
    rating         = Column(Integer)
    rating_comment = Column(Text)
    reopen_count   = Column(Integer, nullable=False, default=0, server_default="0")

    first_response_at = Column(DateTime(timezone=True))
    resolved_at       = Column(DateTime(timezone=True))
    closed_at         = Column(DateTime(timezone=True))
    created_at        = Column(DateTime(timezone=True), default=_now)
    updated_at        = Column(DateTime(timezone=True), default=_now, onupdate=_now)
    last_activity_at  = Column(DateTime(timezone=True), default=_now, index=True)

    events = relationship("FeedbackEvent", back_populates="ticket",
                          cascade="all, delete-orphan", order_by="FeedbackEvent.id")
    attachments = relationship("FeedbackAttachment", back_populates="ticket",
                               cascade="all, delete-orphan", order_by="FeedbackAttachment.id")


class FeedbackEvent(Base):
    """Timeline entry: comment / internal note / status change / assignment ..."""
    __tablename__ = "feedback_events"

    id          = Column(Integer, primary_key=True, index=True)
    ticket_id   = Column(Integer, ForeignKey("feedback_tickets.id", ondelete="CASCADE"),
                         nullable=False, index=True)
    user_id     = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    user_name   = Column(String(255))
    user_role   = Column(String(10))            # admin | user | system
    kind        = Column(String(20), nullable=False)
    body        = Column(Text)
    old_value   = Column(String(500))
    new_value   = Column(String(500))
    is_internal = Column(Boolean, nullable=False, default=False, server_default="false")
    created_at  = Column(DateTime(timezone=True), default=_now)

    ticket = relationship("FeedbackTicket", back_populates="events")


class FeedbackAttachment(Base):
    __tablename__ = "feedback_attachments"

    id               = Column(Integer, primary_key=True, index=True)
    ticket_id        = Column(Integer, ForeignKey("feedback_tickets.id", ondelete="CASCADE"),
                              nullable=False, index=True)
    event_id         = Column(Integer, nullable=True, index=True)   # plain int on purpose
    filename         = Column(String(255), nullable=False)
    stored_name      = Column(String(100), nullable=False)
    content_type     = Column(String(100))
    size             = Column(Integer, default=0)
    uploaded_by      = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    uploaded_by_name = Column(String(255))
    created_at       = Column(DateTime(timezone=True), default=_now)

    ticket = relationship("FeedbackTicket", back_populates="attachments")
__SL_EOF__

# ─────────────────────────────────────────────────────────────────────────────
# backend/app/api/routes/feedback.py
# ─────────────────────────────────────────────────────────────────────────────
cat > "$ROOT/backend/app/api/routes/feedback.py" <<'__SL_EOF__'
"""
feedback.py – Support / feedback ticket API   (prefix: /api/v1/feedback)

Users  : create tickets, follow / reply to / close / reopen / rate their own tickets.
Admins : see everything, change status / priority / category / assignee / due date,
         write resolution, internal notes, bulk update, export, delete.
"""
import io
import mimetypes
import os
import re
import uuid
from datetime import date, datetime, time, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Response, UploadFile
from fastapi.responses import FileResponse, StreamingResponse
from pydantic import BaseModel, Field
from sqlalchemy import case, func, or_
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.feedback import FeedbackAttachment, FeedbackEvent, FeedbackTicket
from app.models.user import User, UserRole
from app.utils.audit import log_action
from app.utils.deps import get_current_user, require_admin

router = APIRouter()

VN_TZ = timezone(timedelta(hours=7))

STATUS_LABEL = {
    "new": "Mới", "in_progress": "Đang xử lý", "waiting_user": "Chờ phản hồi",
    "planned": "Đã lên kế hoạch", "resolved": "Đã xử lý", "closed": "Đã đóng", "rejected": "Từ chối",
}
OPEN_STATUSES = ("new", "in_progress", "waiting_user", "planned")
DONE_STATUSES = ("resolved", "closed", "rejected")
CATEGORY_LABEL = {
    "bug": "Báo lỗi", "data": "Sai/thiếu dữ liệu", "change": "Yêu cầu thay đổi",
    "feature": "Đề xuất tính năng", "help": "Cần hỗ trợ / hướng dẫn",
    "account": "Tài khoản / phân quyền", "other": "Khác",
}
PRIORITY_LABEL = {"low": "Thấp", "normal": "Bình thường", "high": "Cao", "urgent": "Khẩn cấp"}
PRIORITY_RANK = {"low": 1, "normal": 2, "high": 3, "urgent": 4}

UPLOAD_ROOT = os.environ.get("FEEDBACK_UPLOAD_DIR") or os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "..", "uploads", "feedback"))
os.makedirs(UPLOAD_ROOT, exist_ok=True)

MAX_FILE_BYTES = 10 * 1024 * 1024
MAX_FILES_PER_REQUEST = 10
MAX_FILES_PER_TICKET = 30
IMAGE_EXT = {".png", ".jpg", ".jpeg", ".gif", ".webp"}
ALLOWED_EXT = IMAGE_EXT | {".pdf", ".txt", ".log", ".csv", ".xlsx", ".xls",
                           ".docx", ".doc", ".pptx", ".zip"}
DAILY_TICKET_LIMIT = 20          # anti-spam for normal users


# ── helpers ───────────────────────────────────────────────────────────────────
def _now():
    return datetime.now(timezone.utc)


def _iso(d):
    return d.isoformat() if d else None


def _is_admin(u: User) -> bool:
    return u.role == UserRole.admin


def _uname(u: User) -> str:
    return u.full_name or u.username


def _code(t: FeedbackTicket) -> str:
    return f"FB-{t.id:05d}"


def _clip(s, n=480):
    if s is None:
        return None
    s = str(s)
    return s if len(s) <= n else s[: n - 1] + "…"


def _check(value, allowed, field):
    if value not in allowed:
        raise HTTPException(status_code=400, detail=f"Giá trị '{field}' không hợp lệ: {value}")
    return value


def _safe_name(name: Optional[str]) -> str:
    n = os.path.basename((name or "file").replace("\\", "/"))
    root, ext = os.path.splitext(n)
    root = re.sub(r"[^\w.\- ()\[\]]", "_", root).strip(" .") or "file"
    ext = re.sub(r"[^\w.]", "", ext)
    return root[:120] + ext[:12]


def _get_ticket(db: Session, ticket_id: int, user: User) -> FeedbackTicket:
    t = db.get(FeedbackTicket, ticket_id)
    if not t or (not _is_admin(user) and t.created_by != user.id):
        raise HTTPException(status_code=404, detail="Không tìm thấy yêu cầu")
    return t


def _event(db, t, user, kind, body=None, old=None, new=None, internal=False):
    ev = FeedbackEvent(
        ticket_id=t.id,
        user_id=user.id if user else None,
        user_name=_uname(user) if user else "Hệ thống",
        user_role=user.role.value if user else "system",
        kind=kind, body=body, old_value=_clip(old), new_value=_clip(new),
        is_internal=internal,
    )
    db.add(ev)
    t.last_activity_at = _now()
    return ev


def _set_status(db, t, new_status, user, body=None):
    old = t.status
    if old == new_status:
        return False
    now = _now()
    t.status = new_status
    if new_status == "resolved":
        t.resolved_at, t.closed_at = now, None
    elif new_status == "rejected":
        t.resolved_at, t.closed_at = now, None
    elif new_status == "closed":
        t.closed_at = now
        t.resolved_at = t.resolved_at or now
    else:
        t.resolved_at, t.closed_at = None, None
    _event(db, t, user, "status", body=body, old=old, new=new_status)
    return True


# ── serialisers ───────────────────────────────────────────────────────────────
def _ticket_dict(t: FeedbackTicket, user: User) -> dict:
    admin = _is_admin(user)
    overdue = bool(t.due_date and t.status in OPEN_STATUSES and t.due_date < _now())
    return {
        "id": t.id, "code": _code(t), "title": t.title,
        "category": t.category, "priority": t.priority, "status": t.status,
        "related_ref": t.related_ref,
        "created_by": t.created_by, "created_by_name": t.created_by_name,
        "created_by_email": t.created_by_email if admin else None,
        "assignee_id": t.assignee_id, "assignee_name": t.assignee_name,
        "due_date": _iso(t.due_date), "overdue": overdue,
        "resolution": t.resolution,
        "rating": t.rating, "rating_comment": t.rating_comment,
        "reopen_count": t.reopen_count or 0, "comment_count": 0,
        "created_at": _iso(t.created_at), "updated_at": _iso(t.updated_at),
        "last_activity_at": _iso(t.last_activity_at),
        "first_response_at": _iso(t.first_response_at),
        "resolved_at": _iso(t.resolved_at), "closed_at": _iso(t.closed_at),
        "is_owner": t.created_by == user.id,
    }


def _event_dict(e: FeedbackEvent) -> dict:
    return {
        "id": e.id, "kind": e.kind, "body": e.body,
        "old_value": e.old_value, "new_value": e.new_value,
        "is_internal": bool(e.is_internal),
        "user_id": e.user_id, "user_name": e.user_name, "user_role": e.user_role,
        "created_at": _iso(e.created_at),
    }


def _att_dict(a: FeedbackAttachment) -> dict:
    ext = os.path.splitext(a.filename or "")[1].lower()
    return {
        "id": a.id, "filename": a.filename, "content_type": a.content_type,
        "size": a.size or 0, "event_id": a.event_id,
        "uploaded_by": a.uploaded_by, "uploaded_by_name": a.uploaded_by_name,
        "created_at": _iso(a.created_at), "is_image": ext in IMAGE_EXT,
    }


def _detail(t: FeedbackTicket, user: User) -> dict:
    admin = _is_admin(user)
    hidden = {e.id for e in t.events if e.is_internal}
    d = _ticket_dict(t, user)
    d.update({
        "description": t.description,
        "page_url": t.page_url,
        "user_agent": t.user_agent if admin else None,
        "events": [_event_dict(e) for e in t.events if admin or not e.is_internal],
        "attachments": [_att_dict(a) for a in t.attachments
                        if admin or a.event_id not in hidden],
    })
    d["comment_count"] = sum(1 for e in t.events if e.kind == "comment")
    return d


# ── filters / sorting ─────────────────────────────────────────────────────────
class TicketFilters:
    def __init__(
        self,
        status: Optional[List[str]] = Query(None),
        category: Optional[List[str]] = Query(None),
        priority: Optional[List[str]] = Query(None),
        assignee_id: Optional[int] = Query(None),
        unassigned: Optional[bool] = Query(None),
        assigned_to_me: Optional[bool] = Query(None),
        mine: Optional[bool] = Query(None),
        overdue: Optional[bool] = Query(None),
        scope: Optional[str] = Query(None),            # open | done
        search: Optional[str] = Query(None),
        date_from: Optional[date] = Query(None),
        date_to: Optional[date] = Query(None),
    ):
        self.status, self.category, self.priority = status, category, priority
        self.assignee_id, self.unassigned = assignee_id, unassigned
        self.assigned_to_me, self.mine, self.overdue = assigned_to_me, mine, overdue
        self.scope, self.search = scope, search
        self.date_from, self.date_to = date_from, date_to


_T = FeedbackTicket
_SORT_COLS = {
    "id": _T.id, "created_at": _T.created_at, "updated_at": _T.updated_at,
    "last_activity_at": _T.last_activity_at, "title": _T.title, "status": _T.status,
    "category": _T.category, "due_date": _T.due_date,
    "created_by_name": _T.created_by_name, "assignee_name": _T.assignee_name,
}


def _filtered(db: Session, user: User, f: TicketFilters):
    admin = _is_admin(user)
    q = db.query(_T)
    if not admin or f.mine:
        q = q.filter(_T.created_by == user.id)
    if f.status:
        q = q.filter(_T.status.in_(f.status))
    if f.category:
        q = q.filter(_T.category.in_(f.category))
    if f.priority:
        q = q.filter(_T.priority.in_(f.priority))
    if admin:
        if f.unassigned:
            q = q.filter(_T.assignee_id.is_(None))
        if f.assigned_to_me:
            q = q.filter(_T.assignee_id == user.id)
        if f.assignee_id:
            q = q.filter(_T.assignee_id == f.assignee_id)
    if f.scope == "open":
        q = q.filter(_T.status.in_(OPEN_STATUSES))
    elif f.scope == "done":
        q = q.filter(_T.status.in_(DONE_STATUSES))
    if f.overdue:
        q = q.filter(_T.due_date.isnot(None), _T.due_date < _now(), _T.status.in_(OPEN_STATUSES))
    if f.date_from:
        q = q.filter(_T.created_at >= datetime.combine(f.date_from, time.min, tzinfo=VN_TZ))
    if f.date_to:
        q = q.filter(_T.created_at < datetime.combine(f.date_to + timedelta(days=1), time.min, tzinfo=VN_TZ))
    if f.search and f.search.strip():
        s = f.search.strip()
        like = f"%{s}%"
        conds = [_T.title.ilike(like), _T.description.ilike(like), _T.related_ref.ilike(like),
                 _T.created_by_name.ilike(like), _T.assignee_name.ilike(like)]
        m = re.fullmatch(r"(?i)(?:fb-?)?0*(\d+)", s)
        if m:
            conds.append(_T.id == int(m.group(1)))
        q = q.filter(or_(*conds))
    return q


def _sorted(q, sort_by: Optional[str], sort_dir: str):
    if sort_by == "priority":
        col = case(*[(_T.priority == k, v) for k, v in PRIORITY_RANK.items()], else_=0)
    else:
        col = _SORT_COLS.get(sort_by or "", _T.last_activity_at)
    col = (col.asc() if sort_dir == "asc" else col.desc()).nulls_last()
    return q.order_by(col, _T.id.desc())


# ── apply changes (shared by PATCH and bulk-update) ──────────────────────────
def _apply_changes(db: Session, t: FeedbackTicket, user: User, data: dict, note: str = ""):
    admin = _is_admin(user)
    changed = []

    for f in ("title", "description", "related_ref"):
        if f in data:
            new = (data[f] or "").strip() or None
            if f in ("title", "description") and not new:
                raise HTTPException(400, f"'{f}' không được để trống")
            old = getattr(t, f)
            if new != old:
                setattr(t, f, new)
                _event(db, t, user, "edit", body=f, old=_clip(old, 200), new=_clip(new, 200))
                changed.append(f)

    if "category" in data:
        new = _check(data["category"], CATEGORY_LABEL, "category")
        if new != t.category:
            _event(db, t, user, "category", old=t.category, new=new)
            t.category = new
            changed.append("category")

    if admin and "priority" in data:
        new = _check(data["priority"], PRIORITY_LABEL, "priority")
        if new != t.priority:
            _event(db, t, user, "priority", old=t.priority, new=new)
            t.priority = new
            changed.append("priority")

    if admin and "assignee_id" in data:
        aid = data["assignee_id"]
        if aid is None:
            if t.assignee_id is not None:
                _event(db, t, user, "assign", old=t.assignee_name, new="")
                t.assignee_id, t.assignee_name = None, None
                changed.append("assignee_id")
        elif aid != t.assignee_id:
            a = db.get(User, aid)
            if not a or not a.is_active or a.role != UserRole.admin:
                raise HTTPException(400, "Người xử lý phải là quản trị viên đang hoạt động")
            _event(db, t, user, "assign", old=t.assignee_name, new=_uname(a))
            t.assignee_id, t.assignee_name = a.id, _uname(a)
            changed.append("assignee_id")
            if t.status == "new" and "status" not in data:
                _set_status(db, t, "in_progress", None, body="Tự động: đã có người nhận xử lý")

    if admin and "status" in data:
        new = _check(data["status"], STATUS_LABEL, "status")
        if _set_status(db, t, new, user, body=note or None):
            changed.append("status")

    if admin and "due_date" in data:
        new = data["due_date"]
        if _iso(new) != _iso(t.due_date):
            _event(db, t, user, "due", old=_iso(t.due_date), new=_iso(new))
            t.due_date = new
            changed.append("due_date")

    if admin and "resolution" in data:
        new = (data["resolution"] or "").strip() or None
        if new != t.resolution:
            t.resolution = new
            if new:
                _event(db, t, user, "resolution", body=new)
            changed.append("resolution")

    if admin and changed and t.first_response_at is None and t.created_by != user.id:
        t.first_response_at = _now()
    return changed


# ── payloads ──────────────────────────────────────────────────────────────────
class TicketCreate(BaseModel):
    title: str = Field(..., min_length=3, max_length=255)
    description: str = Field(..., min_length=5, max_length=20000)
    category: str = "help"
    priority: str = "normal"
    related_ref: Optional[str] = Field(None, max_length=255)
    page_url: Optional[str] = Field(None, max_length=500)
    user_agent: Optional[str] = Field(None, max_length=500)


class TicketUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    category: Optional[str] = None
    priority: Optional[str] = None
    related_ref: Optional[str] = None
    status: Optional[str] = None
    assignee_id: Optional[int] = None
    due_date: Optional[datetime] = None
    resolution: Optional[str] = None
    note: Optional[str] = None


class CommentCreate(BaseModel):
    body: str = Field(..., min_length=1, max_length=20000)
    is_internal: bool = False


class ReasonPayload(BaseModel):
    reason: Optional[str] = Field(None, max_length=2000)


class RatePayload(BaseModel):
    rating: int = Field(..., ge=1, le=5)
    comment: Optional[str] = Field(None, max_length=2000)


class BulkUpdatePayload(BaseModel):
    ids: List[int]
    changes: dict


class BulkDeletePayload(BaseModel):
    ids: List[int]


# ═════════════════════════════════════════════════════════════════════════════
# STATIC ROUTES (must be declared before /{ticket_id})
# ═════════════════════════════════════════════════════════════════════════════
@router.get("/stats")
def stats(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    admin = _is_admin(user)
    base = db.query(_T)
    if not admin:
        base = base.filter(_T.created_by == user.id)
    now = _now()

    def grouped(col, q=None):
        qq = (q if q is not None else base).with_entities(col, func.count(_T.id)).group_by(col)
        return {k: v for k, v in qq.all()}

    by_status = grouped(_T.status)
    rows = base.filter(_T.created_at >= now - timedelta(days=90)).with_entities(
        _T.created_at, _T.first_response_at, _T.resolved_at).all()
    fr = [(b - a).total_seconds() for a, b, _ in rows if b]
    rs = [(c - a).total_seconds() for a, _, c in rows if c]

    def avg_h(xs):
        return round(sum(xs) / len(xs) / 3600, 1) if xs else None

    return {
        "total": sum(by_status.values()),
        "open": sum(v for k, v in by_status.items() if k in OPEN_STATUSES),
        "by_status": by_status,
        "by_category": grouped(_T.category),
        "by_priority_open": grouped(_T.priority, base.filter(_T.status.in_(OPEN_STATUSES))),
        "unassigned": base.filter(_T.assignee_id.is_(None), _T.status.in_(OPEN_STATUSES)).count(),
        "overdue": base.filter(_T.due_date.isnot(None), _T.due_date < now,
                               _T.status.in_(OPEN_STATUSES)).count(),
        "avg_first_response_h": avg_h(fr),
        "avg_resolution_h": avg_h(rs),
    }


@router.get("/badge")
def badge(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """admin: number of NEW tickets;  user: own tickets waiting for the user's reply."""
    if _is_admin(user):
        n = db.query(_T).filter(_T.status == "new").count()
    else:
        n = db.query(_T).filter(_T.created_by == user.id, _T.status == "waiting_user").count()
    return {"count": n}


@router.get("/assignees")
def assignees(db: Session = Depends(get_db), _=Depends(require_admin)):
    rows = (db.query(User).filter(User.role == UserRole.admin, User.is_active.is_(True))
            .order_by(User.full_name, User.username).all())
    return [{"id": u.id, "name": _uname(u)} for u in rows]


def _xl(v):
    """neutralise spreadsheet formula injection"""
    if isinstance(v, str) and v[:1] in ("=", "+", "-", "@"):
        return "'" + v
    return v


def _vn(d):
    return d.astimezone(VN_TZ).strftime("%Y-%m-%d %H:%M") if d else ""


@router.get("/export")
def export_tickets(
    f: TicketFilters = Depends(),
    sort_by: Optional[str] = Query(None),
    sort_dir: str = Query("desc"),
    db: Session = Depends(get_db),
    user: User = Depends(require_admin),
):
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Font, PatternFill
    from openpyxl.utils import get_column_letter

    rows = _sorted(_filtered(db, user, f), sort_by, sort_dir).limit(20000).all()
    wb = Workbook()
    ws = wb.active
    ws.title = "Feedback"
    head = ["Mã", "Tiêu đề", "Loại", "Ưu tiên", "Trạng thái", "Người gửi", "Email", "Người xử lý",
            "Tạo lúc", "Cập nhật", "Hạn xử lý", "Phản hồi đầu", "Đã xử lý lúc", "Kết quả xử lý",
            "Site/Cell liên quan", "Trang", "Mở lại", "Đánh giá", "Mô tả"]
    ws.append(head)
    for c in ws[1]:
        c.font = Font(bold=True, color="FFFFFF")
        c.fill = PatternFill("solid", fgColor="1677FF")
        c.alignment = Alignment(vertical="center", wrap_text=True)
    for t in rows:
        ws.append([_xl(x) for x in [
            _code(t), t.title, CATEGORY_LABEL.get(t.category, t.category),
            PRIORITY_LABEL.get(t.priority, t.priority), STATUS_LABEL.get(t.status, t.status),
            t.created_by_name or "", t.created_by_email or "", t.assignee_name or "",
            _vn(t.created_at), _vn(t.updated_at), _vn(t.due_date), _vn(t.first_response_at),
            _vn(t.resolved_at), t.resolution or "", t.related_ref or "", t.page_url or "",
            t.reopen_count or 0, t.rating or "", t.description or "",
        ]])
    widths = [11, 40, 22, 14, 16, 22, 28, 22, 17, 17, 17, 17, 17, 40, 28, 28, 8, 9, 60]
    for i, w in enumerate(widths, 1):
        ws.column_dimensions[get_column_letter(i)].width = w
    ws.freeze_panes = "C2"
    buf = io.BytesIO()
    wb.save(buf)
    buf.seek(0)
    name = f"Feedback_{datetime.now(VN_TZ):%Y%m%d_%H%M}.xlsx"
    return StreamingResponse(
        buf, media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{name}"'})


@router.get("/")
def list_tickets(
    response: Response,
    f: TicketFilters = Depends(),
    sort_by: Optional[str] = Query(None),
    sort_dir: str = Query("desc"),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=1000),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    q = _filtered(db, user, f)
    response.headers["X-Total-Count"] = str(q.count())
    rows = _sorted(q, sort_by, sort_dir).offset(skip).limit(limit).all()
    ids = [r.id for r in rows]
    counts = {}
    if ids:
        counts = dict(
            db.query(FeedbackEvent.ticket_id, func.count(FeedbackEvent.id))
            .filter(FeedbackEvent.ticket_id.in_(ids), FeedbackEvent.kind == "comment")
            .group_by(FeedbackEvent.ticket_id).all())
    out = []
    for r in rows:
        d = _ticket_dict(r, user)
        d["comment_count"] = counts.get(r.id, 0)
        out.append(d)
    return out


@router.post("/", status_code=201)
def create_ticket(
    payload: TicketCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    cat = _check(payload.category, CATEGORY_LABEL, "category")
    pri = _check(payload.priority, PRIORITY_LABEL, "priority")
    if not _is_admin(user):
        recent = db.query(_T).filter(_T.created_by == user.id,
                                     _T.created_at >= _now() - timedelta(days=1)).count()
        if recent >= DAILY_TICKET_LIMIT:
            raise HTTPException(429, "Bạn đã gửi quá nhiều yêu cầu trong 24 giờ qua")
    t = FeedbackTicket(
        title=payload.title.strip(), description=payload.description.strip(),
        category=cat, priority=pri, status="new",
        related_ref=(payload.related_ref or "").strip() or None,
        page_url=payload.page_url, user_agent=payload.user_agent,
        created_by=user.id, created_by_name=_uname(user), created_by_email=user.email,
        last_activity_at=_now(),
    )
    db.add(t)
    db.commit()
    db.refresh(t)
    try:
        log_action(db, user, "CREATE", "feedback_tickets", t.id,
                   new_value={"title": t.title, "category": cat, "priority": pri})
    except Exception:
        pass
    return _detail(t, user)


@router.post("/bulk-update")
def bulk_update(payload: BulkUpdatePayload, db: Session = Depends(get_db),
                user: User = Depends(require_admin)):
    allowed = {"status", "priority", "assignee_id", "category"}
    data = {k: v for k, v in payload.changes.items() if k in allowed}
    if not payload.ids or not data:
        raise HTTPException(400, "Thiếu danh sách yêu cầu hoặc nội dung thay đổi")
    updated, errors = 0, []
    for tid in payload.ids[:500]:
        t = db.get(_T, tid)
        if not t:
            errors.append(f"#{tid}: không tồn tại")
            continue
        try:
            if _apply_changes(db, t, user, data):
                updated += 1
            db.commit()
        except HTTPException as e:
            db.rollback()
            errors.append(f"{_code(t)}: {e.detail}")
        except Exception as e:  # noqa
            db.rollback()
            errors.append(f"#{tid}: {e}")
    return {"updated": updated, "errors": errors}


@router.post("/bulk-delete")
def bulk_delete(payload: BulkDeletePayload, db: Session = Depends(get_db),
                user: User = Depends(require_admin)):
    deleted = 0
    for tid in payload.ids[:500]:
        t = db.get(_T, tid)
        if not t:
            continue
        files = [a.stored_name for a in t.attachments]
        db.delete(t)
        db.commit()
        for fn in files:
            try:
                os.remove(os.path.join(UPLOAD_ROOT, fn))
            except OSError:
                pass
        try:
            log_action(db, user, "DELETE", "feedback_tickets", tid)
        except Exception:
            pass
        deleted += 1
    return {"deleted": deleted}


# ── attachments (static prefix, before /{ticket_id}) ─────────────────────────
@router.get("/attachments/{att_id}/download")
def download_attachment(att_id: int, db: Session = Depends(get_db),
                        user: User = Depends(get_current_user)):
    a = db.get(FeedbackAttachment, att_id)
    if not a:
        raise HTTPException(404, "Không tìm thấy tệp")
    _get_ticket(db, a.ticket_id, user)                       # 404 if not allowed
    if not _is_admin(user) and a.event_id:
        ev = db.get(FeedbackEvent, a.event_id)
        if ev and ev.is_internal:
            raise HTTPException(404, "Không tìm thấy tệp")
    path = os.path.join(UPLOAD_ROOT, a.stored_name)
    if not os.path.isfile(path):
        raise HTTPException(404, "Tệp không còn trên máy chủ")
    return FileResponse(
        path, filename=a.filename,
        media_type=a.content_type or "application/octet-stream",
        headers={"X-Content-Type-Options": "nosniff"})


@router.delete("/attachments/{att_id}")
def delete_attachment(att_id: int, db: Session = Depends(get_db),
                      user: User = Depends(get_current_user)):
    a = db.get(FeedbackAttachment, att_id)
    if not a:
        raise HTTPException(404, "Không tìm thấy tệp")
    _get_ticket(db, a.ticket_id, user)
    if not _is_admin(user) and a.uploaded_by != user.id:
        raise HTTPException(403, "Bạn chỉ có thể xóa tệp do mình tải lên")
    try:
        os.remove(os.path.join(UPLOAD_ROOT, a.stored_name))
    except OSError:
        pass
    db.delete(a)
    db.commit()
    return {"message": "Deleted"}


# ═════════════════════════════════════════════════════════════════════════════
# PER-TICKET ROUTES
# ═════════════════════════════════════════════════════════════════════════════
@router.get("/{ticket_id}")
def get_ticket(ticket_id: int, db: Session = Depends(get_db),
               user: User = Depends(get_current_user)):
    return _detail(_get_ticket(db, ticket_id, user), user)


@router.patch("/{ticket_id}")
def update_ticket(ticket_id: int, payload: TicketUpdate, db: Session = Depends(get_db),
                  user: User = Depends(get_current_user)):
    t = _get_ticket(db, ticket_id, user)
    admin = _is_admin(user)
    data = payload.model_dump(exclude_unset=True)
    note = (data.pop("note", None) or "").strip()
    owner_fields = {"title", "description", "category", "related_ref"}
    allowed = (owner_fields | {"priority", "status", "assignee_id", "due_date", "resolution"}
               if admin else owner_fields)
    bad = [k for k in data if k not in allowed]
    if bad:
        raise HTTPException(403, f"Bạn không có quyền sửa: {', '.join(bad)}")
    if not admin and t.status != "new":
        raise HTTPException(403, "Chỉ có thể chỉnh sửa khi yêu cầu còn ở trạng thái 'Mới'")
    if "status" in data and data["status"] is None:
        raise HTTPException(400, "Trạng thái không hợp lệ")
    _apply_changes(db, t, user, data, note)
    db.commit()
    db.refresh(t)
    return _detail(t, user)


@router.post("/{ticket_id}/comments", status_code=201)
def add_comment(ticket_id: int, payload: CommentCreate, db: Session = Depends(get_db),
                user: User = Depends(get_current_user)):
    t = _get_ticket(db, ticket_id, user)
    admin = _is_admin(user)
    internal = bool(payload.is_internal) and admin
    if t.status == "closed":
        raise HTTPException(400, "Yêu cầu đã đóng – hãy mở lại để tiếp tục trao đổi")
    ev = _event(db, t, user, "note" if internal else "comment",
                body=payload.body.strip(), internal=internal)
    if not internal:
        if admin and t.created_by != user.id:
            if t.first_response_at is None:
                t.first_response_at = _now()
            if t.assignee_id is None:
                _event(db, t, user, "assign", old="", new=_uname(user))
                t.assignee_id, t.assignee_name = user.id, _uname(user)
            if t.status == "new":
                _set_status(db, t, "in_progress", None, body="Tự động: đã được phản hồi")
        elif t.created_by == user.id and t.status == "waiting_user":
            _set_status(db, t, "in_progress", None, body="Tự động: người gửi đã phản hồi")
    db.commit()
    db.refresh(ev)
    return _event_dict(ev)


@router.post("/{ticket_id}/attachments", status_code=201)
def upload_attachments(
    ticket_id: int,
    files: List[UploadFile] = File(...),
    event_id: Optional[int] = Form(None),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    t = _get_ticket(db, ticket_id, user)
    admin = _is_admin(user)
    if t.status == "closed":
        raise HTTPException(400, "Yêu cầu đã đóng")
    if len(files) > MAX_FILES_PER_REQUEST:
        raise HTTPException(400, f"Tối đa {MAX_FILES_PER_REQUEST} tệp mỗi lần tải lên")
    existing = db.query(func.count(FeedbackAttachment.id)).filter(
        FeedbackAttachment.ticket_id == t.id).scalar() or 0
    if existing + len(files) > MAX_FILES_PER_TICKET:
        raise HTTPException(400, f"Mỗi yêu cầu tối đa {MAX_FILES_PER_TICKET} tệp đính kèm")
    if event_id:
        ev = db.get(FeedbackEvent, event_id)
        if not ev or ev.ticket_id != t.id or (ev.user_id != user.id and not admin):
            raise HTTPException(400, "event_id không hợp lệ")

    saved, created = [], []
    try:
        for f in files:
            name = _safe_name(f.filename)
            ext = os.path.splitext(name)[1].lower()
            if ext not in ALLOWED_EXT:
                raise HTTPException(400, f"Loại tệp không được hỗ trợ: {name}")
            stored = uuid.uuid4().hex + ext
            path = os.path.join(UPLOAD_ROOT, stored)
            size = 0
            with open(path, "wb") as out:
                saved.append(path)
                while True:
                    chunk = f.file.read(1024 * 1024)
                    if not chunk:
                        break
                    size += len(chunk)
                    if size > MAX_FILE_BYTES:
                        raise HTTPException(413, f"{name} vượt quá {MAX_FILE_BYTES // 1024 // 1024} MB")
                    out.write(chunk)
            if size == 0:
                raise HTTPException(400, f"Tệp rỗng: {name}")
            a = FeedbackAttachment(
                ticket_id=t.id, event_id=event_id or None, filename=name, stored_name=stored,
                content_type=mimetypes.guess_type(name)[0] or "application/octet-stream",
                size=size, uploaded_by=user.id, uploaded_by_name=_uname(user))
            db.add(a)
            created.append(a)
        t.last_activity_at = _now()
        db.commit()
    except Exception:
        db.rollback()
        for p in saved:
            try:
                os.remove(p)
            except OSError:
                pass
        raise
    return [_att_dict(a) for a in created]


@router.post("/{ticket_id}/reopen")
def reopen_ticket(ticket_id: int, payload: Optional[ReasonPayload] = None,
                  db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    t = _get_ticket(db, ticket_id, user)
    if t.status not in DONE_STATUSES:
        raise HTTPException(400, "Chỉ mở lại được yêu cầu đã xử lý / đã đóng / bị từ chối")
    old, new = t.status, ("in_progress" if t.assignee_id else "new")
    t.status, t.resolved_at, t.closed_at = new, None, None
    t.reopen_count = (t.reopen_count or 0) + 1
    t.rating, t.rating_comment = None, None
    _event(db, t, user, "reopen", body=((payload.reason if payload else None) or "").strip() or None,
           old=old, new=new)
    db.commit()
    db.refresh(t)
    return _detail(t, user)


@router.post("/{ticket_id}/close")
def close_ticket(ticket_id: int, payload: Optional[ReasonPayload] = None,
                 db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    t = _get_ticket(db, ticket_id, user)
    if t.status == "closed":
        raise HTTPException(400, "Yêu cầu đã đóng")
    old = t.status
    t.status, t.closed_at = "closed", _now()
    t.resolved_at = t.resolved_at or t.closed_at
    _event(db, t, user, "close", body=((payload.reason if payload else None) or "").strip() or None,
           old=old, new="closed")
    db.commit()
    db.refresh(t)
    return _detail(t, user)


@router.post("/{ticket_id}/rate")
def rate_ticket(ticket_id: int, payload: RatePayload, db: Session = Depends(get_db),
                user: User = Depends(get_current_user)):
    t = _get_ticket(db, ticket_id, user)
    if t.created_by != user.id:
        raise HTTPException(403, "Chỉ người gửi mới được đánh giá")
    if t.status not in ("resolved", "closed"):
        raise HTTPException(400, "Chỉ đánh giá được khi yêu cầu đã xử lý / đã đóng")
    t.rating, t.rating_comment = payload.rating, (payload.comment or "").strip() or None
    _event(db, t, user, "rate", body=t.rating_comment, new=str(payload.rating))
    db.commit()
    db.refresh(t)
    return _detail(t, user)


@router.delete("/{ticket_id}")
def delete_ticket(ticket_id: int, db: Session = Depends(get_db),
                  user: User = Depends(require_admin)):
    t = db.get(_T, ticket_id)
    if not t:
        raise HTTPException(404, "Không tìm thấy yêu cầu")
    files = [a.stored_name for a in t.attachments]
    db.delete(t)
    db.commit()
    for fn in files:
        try:
            os.remove(os.path.join(UPLOAD_ROOT, fn))
        except OSError:
            pass
    try:
        log_action(db, user, "DELETE", "feedback_tickets", ticket_id)
    except Exception:
        pass
    return {"message": "Deleted"}
__SL_EOF__

echo "▶ Writing frontend files..."

# ─────────────────────────────────────────────────────────────────────────────
# frontend/src/api/feedback.ts
# ─────────────────────────────────────────────────────────────────────────────
cat > "$ROOT/frontend/src/api/feedback.ts" <<'__SL_EOF__'
import dayjs from 'dayjs'
import api from './client'
import { pagedGet } from './listing'

export type FbStatus = 'new' | 'in_progress' | 'waiting_user' | 'planned' | 'resolved' | 'closed' | 'rejected'
export type FbCategory = 'bug' | 'data' | 'change' | 'feature' | 'help' | 'account' | 'other'
export type FbPriority = 'low' | 'normal' | 'high' | 'urgent'

export interface FbTicket {
  id: number
  code: string
  title: string
  category: FbCategory
  priority: FbPriority
  status: FbStatus
  related_ref?: string | null
  created_by?: number | null
  created_by_name?: string | null
  created_by_email?: string | null
  assignee_id?: number | null
  assignee_name?: string | null
  due_date?: string | null
  overdue: boolean
  resolution?: string | null
  rating?: number | null
  rating_comment?: string | null
  reopen_count: number
  comment_count: number
  created_at: string
  updated_at?: string | null
  last_activity_at?: string | null
  first_response_at?: string | null
  resolved_at?: string | null
  closed_at?: string | null
  is_owner: boolean
}

export interface FbEvent {
  id: number
  kind: string
  body?: string | null
  old_value?: string | null
  new_value?: string | null
  is_internal: boolean
  user_id?: number | null
  user_name?: string | null
  user_role?: string | null
  created_at: string
}

export interface FbAttachment {
  id: number
  filename: string
  content_type?: string | null
  size: number
  event_id?: number | null
  uploaded_by?: number | null
  uploaded_by_name?: string | null
  created_at: string
  is_image: boolean
}

export interface FbDetail extends FbTicket {
  description: string
  page_url?: string | null
  user_agent?: string | null
  events: FbEvent[]
  attachments: FbAttachment[]
}

export interface FbStats {
  total: number
  open: number
  by_status: Record<string, number>
  by_category: Record<string, number>
  by_priority_open: Record<string, number>
  unassigned: number
  overdue: number
  avg_first_response_h: number | null
  avg_resolution_h: number | null
}

const B = '/api/v1/feedback'
export const FEEDBACK_CHANGED = 'feedback:changed'
export const notifyFeedbackChanged = () => window.dispatchEvent(new Event(FEEDBACK_CHANGED))

export const errText = (e: any, fallback = 'Có lỗi xảy ra'): string => {
  const d = e?.response?.data?.detail
  if (typeof d === 'string') return d
  if (Array.isArray(d)) return d.map((x: any) => x?.msg).filter(Boolean).join('; ') || fallback
  return e?.message || fallback
}

export const listTickets = (params?: Record<string, unknown>) => pagedGet<FbTicket>(`${B}/`, params)
export const getStats = () => api.get<FbStats>(`${B}/stats`).then((r) => r.data)
export const getBadge = () => api.get<{ count: number }>(`${B}/badge`).then((r) => r.data.count)
export const getAssignees = () =>
  api.get<{ id: number; name: string }[]>(`${B}/assignees`).then((r) => r.data)
export const getTicket = (id: number) => api.get<FbDetail>(`${B}/${id}`).then((r) => r.data)
export const createTicket = (data: Record<string, unknown>) =>
  api.post<FbDetail>(`${B}/`, data).then((r) => r.data)
export const updateTicket = (id: number, data: Record<string, unknown>) =>
  api.patch<FbDetail>(`${B}/${id}`, data).then((r) => r.data)
export const addComment = (id: number, data: { body: string; is_internal?: boolean }) =>
  api.post<FbEvent>(`${B}/${id}/comments`, data).then((r) => r.data)
export const uploadAttachments = (id: number, files: File[], eventId?: number) => {
  const form = new FormData()
  files.forEach((f) => form.append('files', f))
  if (eventId) form.append('event_id', String(eventId))
  return api.post<FbAttachment[]>(`${B}/${id}/attachments`, form).then((r) => r.data)
}
export const deleteAttachment = (attId: number) => api.delete(`${B}/attachments/${attId}`)
export const reopenTicket = (id: number, reason?: string) =>
  api.post<FbDetail>(`${B}/${id}/reopen`, { reason }).then((r) => r.data)
export const closeTicket = (id: number, reason?: string) =>
  api.post<FbDetail>(`${B}/${id}/close`, { reason }).then((r) => r.data)
export const rateTicket = (id: number, rating: number, comment?: string) =>
  api.post<FbDetail>(`${B}/${id}/rate`, { rating, comment }).then((r) => r.data)
export const deleteTicket = (id: number) => api.delete(`${B}/${id}`)
export const bulkUpdateTickets = (ids: number[], changes: Record<string, unknown>) =>
  api.post<{ updated: number; errors: string[] }>(`${B}/bulk-update`, { ids, changes }).then((r) => r.data)
export const bulkDeleteTickets = (ids: number[]) =>
  api.post<{ deleted: number }>(`${B}/bulk-delete`, { ids }).then((r) => r.data)

export async function exportTickets(params: Record<string, unknown>) {
  const r = await api.get(`${B}/export`, { params, responseType: 'blob' })
  const url = URL.createObjectURL(r.data as Blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `Feedback_${dayjs().format('YYYYMMDD_HHmm')}.xlsx`
  a.click()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}

/** download a file, or (images, download=false) open it in a new tab */
export async function openAttachment(att: FbAttachment, download = true) {
  const r = await api.get(`${B}/attachments/${att.id}/download`, { responseType: 'blob' })
  const url = URL.createObjectURL(r.data as Blob)
  if (!download && att.is_image) {
    window.open(url, '_blank')
    setTimeout(() => URL.revokeObjectURL(url), 60_000)
    return
  }
  const a = document.createElement('a')
  a.href = url
  a.download = att.filename
  a.click()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}
__SL_EOF__

# ─────────────────────────────────────────────────────────────────────────────
# frontend/src/hooks/useFeedbackBadge.ts
# ─────────────────────────────────────────────────────────────────────────────
cat > "$ROOT/frontend/src/hooks/useFeedbackBadge.ts" <<'__SL_EOF__'
import { useEffect, useState } from 'react'
import { getBadge, FEEDBACK_CHANGED } from '@/api/feedback'

/** number shown next to the "Hỗ trợ / Góp ý" menu item (polls every 60s) */
export function useFeedbackBadge(): number {
  const [n, setN] = useState(0)
  useEffect(() => {
    let stopped = false
    const tick = () => {
      if (document.hidden) return
      getBadge().then((c) => { if (!stopped) setN(c) }).catch(() => {})
    }
    tick()
    const id = window.setInterval(tick, 60_000)
    const onVis = () => { if (!document.hidden) tick() }
    document.addEventListener('visibilitychange', onVis)
    window.addEventListener(FEEDBACK_CHANGED, tick)
    return () => {
      stopped = true
      window.clearInterval(id)
      document.removeEventListener('visibilitychange', onVis)
      window.removeEventListener(FEEDBACK_CHANGED, tick)
    }
  }, [])
  return n
}
__SL_EOF__

# ─────────────────────────────────────────────────────────────────────────────
# frontend/src/components/feedback/meta.tsx
# ─────────────────────────────────────────────────────────────────────────────
cat > "$ROOT/frontend/src/components/feedback/meta.tsx" <<'__SL_EOF__'
import React from 'react'
import { Tag } from 'antd'
import type { FbCategory, FbEvent, FbPriority, FbStatus } from '@/api/feedback'

export const STATUS_META: Record<FbStatus, { label: string; color: string }> = {
  new:          { label: 'Mới',             color: 'blue' },
  in_progress:  { label: 'Đang xử lý',      color: 'processing' },
  waiting_user: { label: 'Chờ phản hồi',    color: 'warning' },
  planned:      { label: 'Đã lên kế hoạch', color: 'purple' },
  resolved:     { label: 'Đã xử lý',        color: 'success' },
  closed:       { label: 'Đã đóng',         color: 'default' },
  rejected:     { label: 'Từ chối',         color: 'error' },
}

export const CATEGORY_META: Record<FbCategory, { label: string; color: string }> = {
  bug:     { label: '🐞 Báo lỗi',               color: 'red' },
  data:    { label: '🗂 Sai/thiếu dữ liệu',     color: 'volcano' },
  change:  { label: '🔧 Yêu cầu thay đổi',      color: 'geekblue' },
  feature: { label: '💡 Đề xuất tính năng',     color: 'cyan' },
  help:    { label: '❓ Cần hỗ trợ / hướng dẫn', color: 'blue' },
  account: { label: '🔑 Tài khoản / phân quyền', color: 'purple' },
  other:   { label: '📌 Khác',                  color: 'default' },
}

export const PRIORITY_META: Record<FbPriority, { label: string; color: string }> = {
  low:    { label: 'Thấp',        color: 'default' },
  normal: { label: 'Bình thường', color: 'blue' },
  high:   { label: 'Cao',         color: 'orange' },
  urgent: { label: 'Khẩn cấp',    color: 'red' },
}

const toOptions = (m: Record<string, { label: string }>) =>
  Object.entries(m).map(([value, v]) => ({ value, label: v.label }))
export const statusOptions   = toOptions(STATUS_META)
export const categoryOptions = toOptions(CATEGORY_META)
export const priorityOptions = toOptions(PRIORITY_META)

export const StatusTag = ({ v }: { v: string }) => {
  const m = (STATUS_META as Record<string, { label: string; color: string }>)[v]
  return <Tag color={m?.color}>{m?.label ?? v}</Tag>
}
export const PriorityTag = ({ v }: { v: string }) => {
  const m = (PRIORITY_META as Record<string, { label: string; color: string }>)[v]
  return <Tag color={m?.color}>{m?.label ?? v}</Tag>
}
export const CategoryTag = ({ v }: { v: string }) => {
  const m = (CATEGORY_META as Record<string, { label: string; color: string }>)[v]
  return <Tag color={m?.color}>{m?.label ?? v}</Tag>
}

export const fmtDt = (v?: string | null) => (v ? new Date(v).toLocaleString('vi-VN') : '-')
export const fmtSize = (n: number) =>
  n >= 1048576 ? `${(n / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(n / 1024))} KB`

const FIELD_LABEL: Record<string, string> = {
  title: 'tiêu đề', description: 'mô tả', related_ref: 'site/cell liên quan',
}

/** one-line description of a non-comment timeline event */
export function describeEvent(e: FbEvent): string {
  const lab = (m: Record<string, { label: string }>, v?: string | null) =>
    (v && m[v]?.label) || v || '—'
  switch (e.kind) {
    case 'status':
      return `đổi trạng thái: ${lab(STATUS_META, e.old_value)} → ${lab(STATUS_META, e.new_value)}`
    case 'assign':
      return e.new_value
        ? `giao cho ${e.new_value}${e.old_value ? ` (trước đó: ${e.old_value})` : ''}`
        : `bỏ phân công${e.old_value ? ` (${e.old_value})` : ''}`
    case 'priority':
      return `đổi mức ưu tiên: ${lab(PRIORITY_META, e.old_value)} → ${lab(PRIORITY_META, e.new_value)}`
    case 'category':
      return `đổi phân loại: ${lab(CATEGORY_META, e.old_value)} → ${lab(CATEGORY_META, e.new_value)}`
    case 'due':
      return `đặt hạn xử lý: ${e.new_value ? fmtDt(e.new_value) : 'bỏ hạn'}`
    case 'edit':
      return `sửa ${FIELD_LABEL[e.body || ''] || e.body}`
    case 'resolution': return 'cập nhật kết quả xử lý'
    case 'reopen': return 'mở lại yêu cầu'
    case 'close': return 'đóng yêu cầu'
    case 'rate': return `đánh giá ${e.new_value}/5 ⭐`
    default: return e.kind
  }
}
__SL_EOF__

# ─────────────────────────────────────────────────────────────────────────────
# frontend/src/components/feedback/AttachmentPicker.tsx
# ─────────────────────────────────────────────────────────────────────────────
cat > "$ROOT/frontend/src/components/feedback/AttachmentPicker.tsx" <<'__SL_EOF__'
import React from 'react'
import { Button, Typography, Upload, message } from 'antd'
import type { UploadFile } from 'antd/es/upload/interface'
import { PaperClipOutlined } from '@ant-design/icons'

export const MAX_FILES = 5
export const MAX_MB = 10
const ACCEPT = '.png,.jpg,.jpeg,.gif,.webp,.pdf,.txt,.log,.csv,.xlsx,.xls,.docx,.doc,.pptx,.zip'

/** images pasted (Ctrl+V) into a text box -> UploadFile[] */
export function filesFromPaste(e: React.ClipboardEvent): UploadFile[] {
  const out: UploadFile[] = []
  Array.from(e.clipboardData?.files ?? []).forEach((f, i) => {
    if (f.type.startsWith('image/')) {
      out.push({
        uid: `paste-${Date.now()}-${i}`,
        name: f.name && f.name !== 'image.png' ? f.name : `screenshot-${Date.now()}-${i}.png`,
        status: 'done',
        originFileObj: f as any,
      })
    }
  })
  return out
}

export const toRawFiles = (files: UploadFile[]): File[] =>
  files.map((f) => f.originFileObj as File | undefined).filter((f): f is File => !!f)

interface Props {
  files: UploadFile[]
  onChange: (f: UploadFile[]) => void
  disabled?: boolean
}

export function AttachmentPicker({ files, onChange, disabled }: Props) {
  return (
    <div>
      <Upload
        multiple
        disabled={disabled}
        accept={ACCEPT}
        fileList={files}
        beforeUpload={() => false}
        onChange={({ fileList }) => {
          const ok = fileList.filter((f) => {
            const sz = f.size ?? (f.originFileObj as File | undefined)?.size ?? 0
            if (sz > MAX_MB * 1024 * 1024) {
              message.warning(`${f.name}: vượt quá ${MAX_MB} MB`)
              return false
            }
            return true
          })
          if (ok.length > MAX_FILES) message.warning(`Tối đa ${MAX_FILES} tệp mỗi lần gửi`)
          onChange(ok.slice(0, MAX_FILES))
        }}
      >
        <Button size="small" icon={<PaperClipOutlined />} disabled={disabled}>Đính kèm tệp</Button>
      </Upload>
      <Typography.Text type="secondary" style={{ fontSize: 11 }}>
        Có thể dán ảnh chụp màn hình (Ctrl+V) vào ô nội dung · tối đa {MAX_FILES} tệp, {MAX_MB} MB/tệp
        (ảnh, pdf, excel, word, zip, txt/log)
      </Typography.Text>
    </div>
  )
}
__SL_EOF__

# ─────────────────────────────────────────────────────────────────────────────
# frontend/src/components/feedback/FeedbackFormModal.tsx
# ─────────────────────────────────────────────────────────────────────────────
cat > "$ROOT/frontend/src/components/feedback/FeedbackFormModal.tsx" <<'__SL_EOF__'
import React, { useState } from 'react'
import { Alert, Col, Form, Input, Modal, Row, Select, message } from 'antd'
import type { UploadFile } from 'antd/es/upload/interface'
import { useLocation } from 'react-router-dom'
import {
  createTicket, uploadAttachments, notifyFeedbackChanged, errText, FbDetail,
} from '@/api/feedback'
import { categoryOptions, priorityOptions } from './meta'
import { AttachmentPicker, MAX_FILES, filesFromPaste, toRawFiles } from './AttachmentPicker'

interface Props {
  open: boolean
  onClose: () => void
  onCreated?: (t: FbDetail) => void
}

export default function FeedbackFormModal({ open, onClose, onCreated }: Props) {
  const [form] = Form.useForm()
  const [files, setFiles] = useState<UploadFile[]>([])
  const [busy, setBusy] = useState(false)
  const loc = useLocation()

  const reset = () => { form.resetFields(); setFiles([]) }
  const cancel = () => { reset(); onClose() }

  const submit = async () => {
    let v: Record<string, unknown>
    try { v = await form.validateFields() } catch { return }
    setBusy(true)
    try {
      const t = await createTicket({
        ...v,
        page_url: (loc.pathname + loc.search).slice(0, 480),
        user_agent: navigator.userAgent.slice(0, 480),
      })
      const raw = toRawFiles(files)
      if (raw.length) {
        try { await uploadAttachments(t.id, raw) }
        catch { message.warning('Yêu cầu đã được tạo nhưng tải tệp đính kèm thất bại – bạn có thể đính kèm lại trong trang chi tiết') }
      }
      notifyFeedbackChanged()
      reset()
      onClose()
      onCreated?.(t)
    } catch (e: any) {
      message.error(errText(e, 'Gửi yêu cầu thất bại'))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal
      title="📝 Gửi yêu cầu hỗ trợ / góp ý"
      open={open} onCancel={cancel} onOk={submit}
      okText="Gửi yêu cầu" cancelText="Hủy" confirmLoading={busy} width={720}
    >
      <Alert type="info" showIcon style={{ marginBottom: 12 }}
        message="Mô tả càng cụ thể (site/cell nào, thao tác nào, báo lỗi gì), chúng tôi xử lý càng nhanh. Trang bạn đang xem sẽ được đính kèm tự động." />
      <Form form={form} layout="vertical" initialValues={{ category: 'help', priority: 'normal' }}>
        <Row gutter={12}>
          <Col span={12}>
            <Form.Item name="category" label="Loại yêu cầu" rules={[{ required: true }]}>
              <Select options={categoryOptions} />
            </Form.Item>
          </Col>
          <Col span={12}>
            <Form.Item name="priority" label="Mức độ khẩn cấp" rules={[{ required: true }]}>
              <Select options={priorityOptions} />
            </Form.Item>
          </Col>
        </Row>
        <Form.Item name="title" label="Tiêu đề"
          rules={[{ required: true, message: 'Nhập tiêu đề' }, { min: 3, message: 'Tối thiểu 3 ký tự' }]}>
          <Input maxLength={255} placeholder="Tóm tắt ngắn gọn vấn đề / yêu cầu" />
        </Form.Item>
        <Form.Item name="description" label="Nội dung chi tiết"
          rules={[{ required: true, message: 'Nhập nội dung' }, { min: 5, message: 'Tối thiểu 5 ký tự' }]}>
          <Input.TextArea rows={6} placeholder="Mô tả các bước thực hiện, kết quả mong muốn, kết quả thực tế..."
            onPaste={(e) => {
              const add = filesFromPaste(e)
              if (add.length) setFiles((p) => [...p, ...add].slice(0, MAX_FILES))
            }} />
        </Form.Item>
        <Form.Item name="related_ref" label="Site / Cell liên quan (không bắt buộc)">
          <Input maxLength={255} placeholder="vd: HNI001 hoặc HNI001_3G_A" />
        </Form.Item>
        <AttachmentPicker files={files} onChange={setFiles} />
      </Form>
    </Modal>
  )
}
__SL_EOF__

# ─────────────────────────────────────────────────────────────────────────────
# frontend/src/components/feedback/FeedbackFab.tsx
# ─────────────────────────────────────────────────────────────────────────────
cat > "$ROOT/frontend/src/components/feedback/FeedbackFab.tsx" <<'__SL_EOF__'
import React, { useState } from 'react'
import { FloatButton, message } from 'antd'
import { CustomerServiceOutlined } from '@ant-design/icons'
import { useLocation, useNavigate } from 'react-router-dom'
import FeedbackFormModal from './FeedbackFormModal'

/** floating "send feedback" button available on every page (hidden on /feedback*) */
export default function FeedbackFab() {
  const [open, setOpen] = useState(false)
  const navigate = useNavigate()
  const { pathname } = useLocation()
  if (pathname.startsWith('/feedback')) return null

  return (
    <>
      <FloatButton
        type="primary" icon={<CustomerServiceOutlined />}
        tooltip="Gửi góp ý / yêu cầu hỗ trợ"
        style={{ right: 24, bottom: 24 }}
        onClick={() => setOpen(true)}
      />
      <FeedbackFormModal
        open={open}
        onClose={() => setOpen(false)}
        onCreated={(t) =>
          message.success({
            content: (
              <span>
                Đã gửi <b>{t.code}</b>.{' '}
                <a onClick={() => navigate(`/feedback/${t.id}`)}>Xem chi tiết</a>
              </span>
            ),
            duration: 6,
          })}
      />
    </>
  )
}
__SL_EOF__

# ─────────────────────────────────────────────────────────────────────────────
# frontend/src/pages/feedback/FeedbackPage.tsx   (list + dashboard)
# ─────────────────────────────────────────────────────────────────────────────
cat > "$ROOT/frontend/src/pages/feedback/FeedbackPage.tsx" <<'__SL_EOF__'
import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Button, Card, Col, DatePicker, Input, Popconfirm, Row, Segmented, Select, Space,
  Statistic, Switch, Table, Typography, message,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import type { TableRowSelection } from 'antd/es/table/interface'
import {
  CommentOutlined, DeleteOutlined, DownloadOutlined, PlusOutlined,
  ReloadOutlined, SearchOutlined,
} from '@ant-design/icons'
import { useAuthStore } from '@/store/auth'
import { useDebouncedValue } from '@/hooks/useDebouncedValue'
import {
  FbStats, FbTicket, bulkDeleteTickets, bulkUpdateTickets, errText, exportTickets,
  getAssignees, getStats, listTickets, notifyFeedbackChanged, FEEDBACK_CHANGED,
} from '@/api/feedback'
import {
  CategoryTag, PriorityTag, StatusTag, categoryOptions, fmtDt, priorityOptions, statusOptions,
} from '@/components/feedback/meta'
import FeedbackFormModal from '@/components/feedback/FeedbackFormModal'

const { RangePicker } = DatePicker

const StatCard = ({ title, value, color, onClick }: {
  title: string; value: number | string; color?: string; onClick?: () => void
}) => (
  <Card size="small" hoverable={!!onClick} onClick={onClick}
        style={{ cursor: onClick ? 'pointer' : 'default' }}>
    <Statistic title={title} value={value} valueStyle={{ color, fontSize: 22 }} />
  </Card>
)

export default function FeedbackPage() {
  const navigate = useNavigate()
  const user = useAuthStore((s) => s.user)
  const isAdmin = user?.role === 'admin'

  const [rows, setRows] = useState<FbTicket[]>([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(false)
  const [stats, setStats] = useState<FbStats | null>(null)
  const [assignees, setAssignees] = useState<{ id: number; name: string }[]>([])
  const [formOpen, setFormOpen] = useState(false)
  const [exporting, setExporting] = useState(false)
  const [selectedIds, setSelectedIds] = useState<number[]>([])

  const [scope, setScope] = useState<'open' | 'done' | 'all'>('open')
  const [status, setStatus] = useState<string[]>([])
  const [category, setCategory] = useState<string[]>([])
  const [priority, setPriority] = useState<string[]>([])
  const [assignee, setAssignee] = useState<string | undefined>()
  const [range, setRange] = useState<any>(null)
  const [overdue, setOverdue] = useState(false)
  const [search, setSearch] = useState('')
  const dSearch = useDebouncedValue(search, 400)
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(20)
  const [sort, setSort] = useState<{ field: string; order: 'ascend' | 'descend' } | null>(null)
  const reqRef = useRef(0)

  const filterParams = useMemo(() => {
    const p: Record<string, unknown> = {}
    if (scope !== 'all') p.scope = scope
    if (status.length) p.status = status
    if (category.length) p.category = category
    if (priority.length) p.priority = priority
    if (isAdmin) {
      if (assignee === 'none') p.unassigned = true
      else if (assignee === 'me') p.assigned_to_me = true
      else if (assignee) p.assignee_id = Number(assignee)
    }
    if (range?.[0]) p.date_from = range[0].format('YYYY-MM-DD')
    if (range?.[1]) p.date_to = range[1].format('YYYY-MM-DD')
    if (overdue) p.overdue = true
    if (dSearch.trim()) p.search = dSearch.trim()
    return p
  }, [scope, status, category, priority, assignee, range, overdue, dSearch, isAdmin])

  useEffect(() => { setPage(1) }, [filterParams])

  const sortParams = useMemo(
    () => (sort ? { sort_by: sort.field, sort_dir: sort.order === 'ascend' ? 'asc' : 'desc' } : {}),
    [sort])

  const load = useCallback(async () => {
    const id = ++reqRef.current
    setLoading(true)
    try {
      const res = await listTickets({
        ...filterParams, ...sortParams, skip: (page - 1) * pageSize, limit: pageSize,
      })
      if (id !== reqRef.current) return
      setRows(res.items)
      setTotal(res.total)
    } catch (e: any) {
      if (id === reqRef.current) message.error(errText(e, 'Không tải được danh sách'))
    } finally {
      if (id === reqRef.current) setLoading(false)
    }
  }, [filterParams, sortParams, page, pageSize])

  const loadStats = useCallback(() => { getStats().then(setStats).catch(() => {}) }, [])
  const refreshAll = useCallback(() => { load(); loadStats() }, [load, loadStats])

  useEffect(() => { load() }, [load])
  useEffect(() => { loadStats() }, [loadStats])
  useEffect(() => { if (isAdmin) getAssignees().then(setAssignees).catch(() => {}) }, [isAdmin])
  useEffect(() => {
    window.addEventListener(FEEDBACK_CHANGED, loadStats)
    return () => window.removeEventListener(FEEDBACK_CHANGED, loadStats)
  }, [loadStats])

  const applyQuick = (q: { status?: string[]; assignee?: string; overdue?: boolean; scope?: 'open' | 'done' | 'all' }) => {
    setStatus(q.status ?? []); setAssignee(q.assignee); setOverdue(!!q.overdue)
    setScope(q.scope ?? 'all'); setCategory([]); setPriority([]); setRange(null)
    setSearch(''); setPage(1)
  }
  const clearFilters = () => applyQuick({ scope: 'open' })

  const bulk = async (changes: Record<string, unknown>) => {
    try {
      const r = await bulkUpdateTickets(selectedIds, changes)
      if (r.updated) message.success(`Đã cập nhật ${r.updated} yêu cầu`)
      if (r.errors.length) message.warning(r.errors.slice(0, 3).join('; '))
      setSelectedIds([]); refreshAll(); notifyFeedbackChanged()
    } catch (e: any) { message.error(errText(e)) }
  }
  const bulkDelete = async () => {
    try {
      const r = await bulkDeleteTickets(selectedIds)
      message.success(`Đã xóa ${r.deleted} yêu cầu`)
      setSelectedIds([]); refreshAll(); notifyFeedbackChanged()
    } catch (e: any) { message.error(errText(e)) }
  }
  const doExport = async () => {
    setExporting(true)
    try { await exportTickets({ ...filterParams, ...sortParams }) }
    catch (e: any) { message.error(errText(e, 'Xuất thất bại')) }
    finally { setExporting(false) }
  }

  const so = (f: string) => (sort?.field === f ? sort.order : null)
  const colCreator: ColumnsType<FbTicket>[number] = {
    title: 'Người gửi', dataIndex: 'created_by_name', key: 'created_by_name', width: 150,
    sorter: true, sortOrder: so('created_by_name'), ellipsis: true,
  }
  const colAssignee: ColumnsType<FbTicket>[number] = {
    title: 'Người xử lý', dataIndex: 'assignee_name', key: 'assignee_name', width: 150,
    sorter: true, sortOrder: so('assignee_name'),
    render: (v: string | null) => v || <span style={{ color: '#bbb' }}>Chưa phân công</span>,
  }
  const columns: ColumnsType<FbTicket> = [
    { title: 'Mã', dataIndex: 'id', key: 'id', width: 95, sorter: true, sortOrder: so('id'),
      render: (_: unknown, r: FbTicket) => <Typography.Link>{r.code}</Typography.Link> },
    { title: 'Tiêu đề', dataIndex: 'title', key: 'title', width: 340, sorter: true, sortOrder: so('title'),
      render: (_: unknown, r: FbTicket) => (
        <div>
          <strong>{r.title}</strong>
          {r.comment_count > 0 && (
            <span style={{ color: '#999', marginLeft: 8 }}><CommentOutlined /> {r.comment_count}</span>
          )}
          {r.related_ref && <div style={{ fontSize: 12, color: '#888' }}>{r.related_ref}</div>}
        </div>
      ) },
    { title: 'Loại', dataIndex: 'category', key: 'category', width: 190, sorter: true, sortOrder: so('category'),
      render: (v: string) => <CategoryTag v={v} /> },
    { title: 'Ưu tiên', dataIndex: 'priority', key: 'priority', width: 110, sorter: true, sortOrder: so('priority'),
      render: (v: string) => <PriorityTag v={v} /> },
    { title: 'Trạng thái', dataIndex: 'status', key: 'status', width: 130, sorter: true, sortOrder: so('status'),
      render: (v: string) => <StatusTag v={v} /> },
    ...(isAdmin ? [colCreator] : []),
    colAssignee,
    { title: 'Tạo lúc', dataIndex: 'created_at', key: 'created_at', width: 150, sorter: true, sortOrder: so('created_at'),
      render: (v: string) => fmtDt(v) },
    { title: 'Cập nhật', dataIndex: 'last_activity_at', key: 'last_activity_at', width: 150, sorter: true,
      sortOrder: so('last_activity_at'), render: (v: string) => fmtDt(v) },
    { title: 'Hạn xử lý', dataIndex: 'due_date', key: 'due_date', width: 150, sorter: true, sortOrder: so('due_date'),
      render: (v: string | null, r: FbTicket) =>
        v ? <span style={{ color: r.overdue ? '#cf1322' : undefined, fontWeight: r.overdue ? 700 : 400 }}>
              {fmtDt(v)}{r.overdue ? ' ⚠' : ''}</span> : '-' },
  ]
  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  const rowSelection: TableRowSelection<FbTicket> = {
    selectedRowKeys: selectedIds, preserveSelectedRowKeys: true,
    onChange: (keys) => setSelectedIds(keys as number[]),
  }

  const bs = stats?.by_status ?? {}
  const adminCards = [
    { title: 'Mới', value: bs.new ?? 0, color: '#1677ff', on: () => applyQuick({ status: ['new'] }) },
    { title: 'Đang xử lý', value: bs.in_progress ?? 0, color: '#13a8a8', on: () => applyQuick({ status: ['in_progress'] }) },
    { title: 'Chờ phản hồi', value: bs.waiting_user ?? 0, color: '#d48806', on: () => applyQuick({ status: ['waiting_user'] }) },
    { title: 'Chưa phân công', value: stats?.unassigned ?? 0, color: '#d46b08', on: () => applyQuick({ assignee: 'none', scope: 'open' }) },
    { title: 'Quá hạn', value: stats?.overdue ?? 0, color: '#cf1322', on: () => applyQuick({ overdue: true }) },
    { title: 'TB phản hồi đầu (giờ)', value: stats?.avg_first_response_h ?? '-', color: undefined, on: undefined },
    { title: 'TB xử lý xong (giờ)', value: stats?.avg_resolution_h ?? '-', color: undefined, on: undefined },
  ]
  const userCards = [
    { title: 'Tổng yêu cầu', value: stats?.total ?? 0, color: undefined, on: () => applyQuick({ scope: 'all' }) },
    { title: 'Đang mở', value: stats?.open ?? 0, color: '#1677ff', on: () => applyQuick({ scope: 'open' }) },
    { title: 'Chờ bạn phản hồi', value: bs.waiting_user ?? 0, color: '#d48806', on: () => applyQuick({ status: ['waiting_user'] }) },
    { title: 'Đã xử lý', value: (bs.resolved ?? 0) + (bs.closed ?? 0), color: '#389e0d', on: () => applyQuick({ status: ['resolved', 'closed'] }) },
  ]
  const cards = isAdmin ? adminCards : userCards

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>
          {isAdmin ? 'Hỗ trợ & Góp ý – Tất cả yêu cầu' : 'Hỗ trợ & Góp ý – Yêu cầu của tôi'}
        </Typography.Title>
        <Space>
          {isAdmin && (
            <Button icon={<DownloadOutlined />} loading={exporting} onClick={doExport}
                    style={{ borderColor: '#52c41a', color: '#52c41a' }}>Xuất Excel</Button>
          )}
          <Button icon={<ReloadOutlined />} onClick={refreshAll}>Làm mới</Button>
          <Button type="primary" icon={<PlusOutlined />} onClick={() => setFormOpen(true)}>
            Tạo yêu cầu mới
          </Button>
        </Space>
      </Row>

      <Row gutter={[8, 8]} style={{ marginBottom: 12 }}>
        {cards.map((c) => (
          <Col key={c.title} flex="1 1 140px">
            <StatCard title={c.title} value={c.value} color={c.color} onClick={c.on} />
          </Col>
        ))}
      </Row>

      <Row gutter={[8, 8]} style={{ marginBottom: 8 }} align="middle">
        <Col>
          <Segmented value={scope} onChange={(v) => setScope(v as any)}
            options={[{ label: 'Đang mở', value: 'open' }, { label: 'Đã hoàn tất', value: 'done' }, { label: 'Tất cả', value: 'all' }]} />
        </Col>
        <Col flex="260px">
          <Input prefix={<SearchOutlined />} allowClear value={search}
                 placeholder="Tìm mã, tiêu đề, nội dung, site/cell..."
                 onChange={(e) => setSearch(e.target.value)} />
        </Col>
        <Col flex="190px">
          <Select mode="multiple" allowClear maxTagCount={1} placeholder="Trạng thái" style={{ width: '100%' }}
                  value={status} onChange={setStatus} options={statusOptions} />
        </Col>
        <Col flex="190px">
          <Select mode="multiple" allowClear maxTagCount={1} placeholder="Loại" style={{ width: '100%' }}
                  value={category} onChange={setCategory} options={categoryOptions} />
        </Col>
        <Col flex="170px">
          <Select mode="multiple" allowClear maxTagCount={1} placeholder="Ưu tiên" style={{ width: '100%' }}
                  value={priority} onChange={setPriority} options={priorityOptions} />
        </Col>
        {isAdmin && (
          <Col flex="200px">
            <Select allowClear placeholder="Người xử lý" style={{ width: '100%' }} value={assignee}
                    onChange={(v) => setAssignee(v)}
                    options={[
                      { value: 'me', label: '👤 Của tôi' },
                      { value: 'none', label: '⚪ Chưa phân công' },
                      ...assignees.map((a) => ({ value: String(a.id), label: a.name })),
                    ]} />
          </Col>
        )}
        <Col><RangePicker value={range} onChange={(v) => setRange(v)} format="DD/MM/YYYY"
                          placeholder={['Từ ngày', 'Đến ngày']} /></Col>
        <Col><Space size={4}><Switch size="small" checked={overdue} onChange={setOverdue} />Quá hạn</Space></Col>
        <Col><Button onClick={clearFilters}>Xóa lọc</Button></Col>
      </Row>

      {isAdmin && selectedIds.length > 0 && (
        <Space wrap style={{ background: '#e6f7ff', border: '1px solid #91d5ff', borderRadius: 6,
                             padding: '8px 16px', marginBottom: 12 }}>
          <Typography.Text strong>Đã chọn {selectedIds.length} yêu cầu</Typography.Text>
          <Select placeholder="Đổi trạng thái" style={{ width: 160 }} value={undefined}
                  options={statusOptions} onChange={(v) => bulk({ status: v })} />
          <Select placeholder="Giao cho" style={{ width: 170 }} value={undefined}
                  options={assignees.map((a) => ({ value: a.id, label: a.name }))}
                  onChange={(v) => bulk({ assignee_id: v })} />
          <Select placeholder="Đổi ưu tiên" style={{ width: 140 }} value={undefined}
                  options={priorityOptions} onChange={(v) => bulk({ priority: v })} />
          <Popconfirm title={`Xóa ${selectedIds.length} yêu cầu?`} description="Không thể hoàn tác."
                      onConfirm={bulkDelete}>
            <Button danger icon={<DeleteOutlined />}>Xóa</Button>
          </Popconfirm>
          <Button onClick={() => setSelectedIds([])}>Bỏ chọn</Button>
        </Space>
      )}

      <Table<FbTicket>
        rowKey="id" size="small" bordered loading={loading}
        columns={columns} dataSource={rows}
        rowSelection={isAdmin ? rowSelection : undefined}
        scroll={{ x: scrollX }}
        onChange={(_p, _f, s: any, extra) => {
          if (extra.action !== 'sort') return
          const one = Array.isArray(s) ? s[0] : s
          setSort(one?.order ? { field: String(one.columnKey ?? one.field), order: one.order } : null)
          setPage(1)
        }}
        pagination={{
          current: page, pageSize, total, showSizeChanger: true,
          pageSizeOptions: [10, 20, 50, 100],
          showTotal: (t) => `${t.toLocaleString('vi-VN')} yêu cầu`,
          onChange: (p, s) => { setPage(p); setPageSize(s) },
        }}
        onRow={(r) => ({
          style: { cursor: 'pointer' },
          onClick: (e) => {
            if ((e.target as HTMLElement).closest('.ant-checkbox-wrapper, .ant-table-selection-column')) return
            navigate(`/feedback/${r.id}`)
          },
        })}
      />

      <FeedbackFormModal
        open={formOpen} onClose={() => setFormOpen(false)}
        onCreated={(t) => { message.success(`Đã gửi yêu cầu ${t.code}`); refreshAll(); navigate(`/feedback/${t.id}`) }}
      />
    </div>
  )
}
__SL_EOF__

# ─────────────────────────────────────────────────────────────────────────────
# frontend/src/pages/feedback/FeedbackDetailPage.tsx
# ─────────────────────────────────────────────────────────────────────────────
cat > "$ROOT/frontend/src/pages/feedback/FeedbackDetailPage.tsx" <<'__SL_EOF__'
import React, { useCallback, useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import {
  Alert, Avatar, Button, Card, Checkbox, Col, DatePicker, Descriptions, Input, Modal,
  Popconfirm, Rate, Row, Select, Space, Spin, Tag, Typography, message,
} from 'antd'
import type { UploadFile } from 'antd/es/upload/interface'
import {
  ArrowLeftOutlined, DeleteOutlined, LockOutlined, PaperClipOutlined, ReloadOutlined, SendOutlined,
} from '@ant-design/icons'
import dayjs from 'dayjs'
import { useAuthStore } from '@/store/auth'
import {
  FbAttachment, FbDetail, FbEvent, addComment, closeTicket, deleteAttachment, deleteTicket,
  errText, getAssignees, getTicket, notifyFeedbackChanged, openAttachment, rateTicket,
  reopenTicket, updateTicket, uploadAttachments,
} from '@/api/feedback'
import {
  CategoryTag, PriorityTag, StatusTag, categoryOptions, describeEvent, fmtDt, fmtSize,
  priorityOptions, statusOptions,
} from '@/components/feedback/meta'
import { AttachmentPicker, MAX_FILES, filesFromPaste, toRawFiles } from '@/components/feedback/AttachmentPicker'

function Attachments({ items, canDelete, onDeleted }: {
  items: FbAttachment[]; canDelete: (a: FbAttachment) => boolean; onDeleted: () => void
}) {
  if (!items.length) return null
  return (
    <Space size={[6, 6]} wrap style={{ marginTop: 8 }}>
      {items.map((a) => (
        <Tag key={a.id} icon={<PaperClipOutlined />} style={{ padding: '2px 8px' }}
             closable={canDelete(a)}
             onClose={(e) => {
               e.preventDefault()
               Modal.confirm({
                 title: 'Xóa tệp đính kèm?', content: a.filename, okText: 'Xóa', cancelText: 'Hủy',
                 onOk: async () => {
                   try { await deleteAttachment(a.id); onDeleted() }
                   catch (err: any) { message.error(errText(err)) }
                 },
               })
             }}>
          <a onClick={() => openAttachment(a, !a.is_image).catch(() => message.error('Không tải được tệp'))}>
            {a.filename}
          </a>
          <span style={{ color: '#999', marginLeft: 4 }}>({fmtSize(a.size)})</span>
        </Tag>
      ))}
    </Space>
  )
}

export default function FeedbackDetailPage() {
  const { id } = useParams()
  const tid = Number(id)
  const navigate = useNavigate()
  const user = useAuthStore((s) => s.user)
  const isAdmin = user?.role === 'admin'

  const [t, setT] = useState<FbDetail | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [assignees, setAssignees] = useState<{ id: number; name: string }[]>([])
  const busyRef = useRef(false)
  const replyBox = useRef<any>(null)

  // reply box
  const [reply, setReply] = useState('')
  const [internal, setInternal] = useState(false)
  const [rfiles, setRfiles] = useState<UploadFile[]>([])
  const [sending, setSending] = useState(false)

  // admin panel
  const [pStatus, setPStatus] = useState('new')
  const [pPriority, setPPriority] = useState('normal')
  const [pCategory, setPCategory] = useState('help')
  const [pAssignee, setPAssignee] = useState<number | null>(null)
  const [pDue, setPDue] = useState<dayjs.Dayjs | null>(null)
  const [pResolution, setPResolution] = useState('')
  const [saving, setSaving] = useState(false)

  // owner actions
  const [reopenOpen, setReopenOpen] = useState(false)
  const [reopenReason, setReopenReason] = useState('')
  const [rating, setRating] = useState(0)
  const [ratingText, setRatingText] = useState('')

  const load = useCallback(async (silent = false) => {
    if (!silent) setLoading(true)
    try {
      setT(await getTicket(tid))
      setError('')
    } catch (e: any) {
      if (!silent) setError(errText(e, 'Không tải được yêu cầu'))
    } finally {
      if (!silent) setLoading(false)
    }
  }, [tid])

  useEffect(() => { load() }, [load])
  useEffect(() => { if (isAdmin) getAssignees().then(setAssignees).catch(() => {}) }, [isAdmin])
  useEffect(() => {
    const h = window.setInterval(() => { if (!document.hidden && !busyRef.current) load(true) }, 30_000)
    return () => window.clearInterval(h)
  }, [load])

  // keep the admin panel in sync with the server state
  const syncKey = t ? `${t.status}|${t.priority}|${t.category}|${t.assignee_id}|${t.due_date}|${t.resolution}` : ''
  useEffect(() => {
    if (!t) return
    setPStatus(t.status); setPPriority(t.priority); setPCategory(t.category)
    setPAssignee(t.assignee_id ?? null); setPDue(t.due_date ? dayjs(t.due_date) : null)
    setPResolution(t.resolution || '')
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [syncKey])

  const after = async () => { await load(true); notifyFeedbackChanged() }

  const send = async () => {
    if (!reply.trim()) { message.warning('Vui lòng nhập nội dung'); return }
    setSending(true); busyRef.current = true
    try {
      const ev = await addComment(tid, { body: reply.trim(), is_internal: isAdmin && internal })
      const raw = toRawFiles(rfiles)
      if (raw.length) {
        try { await uploadAttachments(tid, raw, ev.id) }
        catch { message.warning('Đã gửi phản hồi nhưng tải tệp đính kèm thất bại') }
      }
      setReply(''); setRfiles([]); setInternal(false)
      await after()
    } catch (e: any) { message.error(errText(e)) }
    finally { setSending(false); busyRef.current = false }
  }

  const saveAdmin = async () => {
    if (!t) return
    const ch: Record<string, unknown> = {}
    if (pStatus !== t.status) ch.status = pStatus
    if (pPriority !== t.priority) ch.priority = pPriority
    if (pCategory !== t.category) ch.category = pCategory
    if ((pAssignee ?? null) !== (t.assignee_id ?? null)) ch.assignee_id = pAssignee
    const dueNew = pDue ? pDue.format('YYYY-MM-DD') : null
    const dueOld = t.due_date ? dayjs(t.due_date).format('YYYY-MM-DD') : null
    if (dueNew !== dueOld) ch.due_date = pDue ? pDue.endOf('day').toISOString() : null
    if (pResolution.trim() !== (t.resolution || '').trim()) ch.resolution = pResolution
    if (!Object.keys(ch).length) { message.info('Không có thay đổi'); return }
    if ((ch.status === 'resolved' || ch.status === 'rejected') && !pResolution.trim()) {
      message.warning('Vui lòng nhập kết quả xử lý / lý do để người gửi biết'); return
    }
    setSaving(true); busyRef.current = true
    try { setT(await updateTicket(tid, ch)); message.success('Đã cập nhật'); notifyFeedbackChanged() }
    catch (e: any) { message.error(errText(e)) }
    finally { setSaving(false); busyRef.current = false }
  }

  const quick = async (changes: Record<string, unknown>, focus = false) => {
    try {
      setT(await updateTicket(tid, changes)); notifyFeedbackChanged()
      if (focus) replyBox.current?.focus?.()
    } catch (e: any) { message.error(errText(e)) }
  }

  const doClose = async () => {
    try { setT(await closeTicket(tid)); notifyFeedbackChanged() } catch (e: any) { message.error(errText(e)) }
  }
  const doReopen = async () => {
    try {
      setT(await reopenTicket(tid, reopenReason.trim() || undefined))
      setReopenOpen(false); setReopenReason(''); notifyFeedbackChanged()
    } catch (e: any) { message.error(errText(e)) }
  }
  const doRate = async () => {
    if (!rating) { message.warning('Hãy chọn số sao'); return }
    try { setT(await rateTicket(tid, rating, ratingText.trim() || undefined)); message.success('Cảm ơn bạn đã đánh giá!') }
    catch (e: any) { message.error(errText(e)) }
  }
  const doDelete = async () => {
    try { await deleteTicket(tid); notifyFeedbackChanged(); navigate('/feedback') }
    catch (e: any) { message.error(errText(e)) }
  }

  if (loading) return <div style={{ textAlign: 'center', padding: 60 }}><Spin size="large" /></div>
  if (error || !t) {
    return (
      <div>
        <Alert type="error" showIcon message={error || 'Không tìm thấy yêu cầu'} style={{ marginBottom: 12 }} />
        <Button icon={<ArrowLeftOutlined />} onClick={() => navigate('/feedback')}>Quay lại danh sách</Button>
      </div>
    )
  }

  const isDone = ['resolved', 'closed', 'rejected'].includes(t.status)
  const canDeleteAtt = (a: FbAttachment) => isAdmin || a.uploaded_by === user?.id
  const ticketLevelAtts = t.attachments.filter((a) => !a.event_id)

  const renderEvent = (e: FbEvent) => {
    if (e.kind === 'comment' || e.kind === 'note') {
      const fromAdmin = e.user_role === 'admin'
      const note = e.kind === 'note'
      return (
        <div key={e.id} style={{ display: 'flex', gap: 10, marginBottom: 12 }}>
          <Avatar style={{ background: fromAdmin ? '#1677ff' : '#8c8c8c', flexShrink: 0 }}>
            {(e.user_name || '?').charAt(0).toUpperCase()}
          </Avatar>
          <div style={{
            flex: 1, borderRadius: 8, padding: '8px 12px',
            background: note ? '#fffbe6' : fromAdmin ? '#e6f4ff' : '#fafafa',
            border: `1px solid ${note ? '#ffe58f' : fromAdmin ? '#91caff' : '#f0f0f0'}`,
          }}>
            <Space size={8} wrap>
              <strong>{e.user_name}</strong>
              {fromAdmin && <Tag color="blue" style={{ margin: 0 }}>Hỗ trợ</Tag>}
              {note && <Tag color="gold" icon={<LockOutlined />} style={{ margin: 0 }}>Ghi chú nội bộ</Tag>}
              <Typography.Text type="secondary" style={{ fontSize: 12 }}>{fmtDt(e.created_at)}</Typography.Text>
            </Space>
            <div style={{ whiteSpace: 'pre-wrap', wordBreak: 'break-word', marginTop: 4 }}>{e.body}</div>
            <Attachments items={t.attachments.filter((a) => a.event_id === e.id)}
                         canDelete={canDeleteAtt} onDeleted={() => load(true)} />
          </div>
        </div>
      )
    }
    return (
      <div key={e.id} style={{ textAlign: 'center', margin: '8px 0', fontSize: 12, color: '#8c8c8c' }}>
        <b>{e.user_name}</b> {describeEvent(e)} · {fmtDt(e.created_at)}
        {e.body && e.kind !== 'edit' && (
          <div style={{ fontStyle: 'italic', whiteSpace: 'pre-wrap' }}>“{e.body}”</div>
        )}
      </div>
    )
  }

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 12 }} gutter={[8, 8]}>
        <Col>
          <Space align="center" wrap>
            <Button icon={<ArrowLeftOutlined />} onClick={() => navigate('/feedback')}>Danh sách</Button>
            <Typography.Title level={4} style={{ margin: 0 }}>{t.code} · {t.title}</Typography.Title>
            <StatusTag v={t.status} /><PriorityTag v={t.priority} /><CategoryTag v={t.category} />
            {t.overdue && <Tag color="red">Quá hạn</Tag>}
          </Space>
        </Col>
        <Col>
          <Space wrap>
            <Button icon={<ReloadOutlined />} onClick={() => load(true)} />
            {isDone && (t.is_owner || isAdmin) && (
              <Button onClick={() => setReopenOpen(true)}>Mở lại</Button>
            )}
            {t.status === 'resolved' && t.is_owner && (
              <Button type="primary" onClick={doClose}>Xác nhận đã xong & đóng</Button>
            )}
            {!isDone && t.is_owner && (
              <Popconfirm title="Đóng yêu cầu này?" okText="Đóng" cancelText="Hủy" onConfirm={doClose}>
                <Button>Đóng yêu cầu</Button>
              </Popconfirm>
            )}
            {isAdmin && (
              <Popconfirm title="Xóa vĩnh viễn yêu cầu này?" okText="Xóa" cancelText="Hủy" onConfirm={doDelete}>
                <Button danger icon={<DeleteOutlined />} />
              </Popconfirm>
            )}
          </Space>
        </Col>
      </Row>

      <Row gutter={16}>
        <Col xs={24} lg={16}>
          <Card size="small" title="Nội dung yêu cầu" style={{ marginBottom: 12 }}>
            <div style={{ whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>{t.description}</div>
            <Attachments items={ticketLevelAtts} canDelete={canDeleteAtt} onDeleted={() => load(true)} />
          </Card>

          {t.resolution && (
            <Alert type={t.status === 'rejected' ? 'error' : 'success'} showIcon style={{ marginBottom: 12 }}
              message={t.status === 'rejected' ? 'Lý do từ chối' : 'Kết quả xử lý'}
              description={<span style={{ whiteSpace: 'pre-wrap' }}>{t.resolution}</span>} />
          )}

          {t.is_owner && ['resolved', 'closed'].includes(t.status) && (
            <Card size="small" style={{ marginBottom: 12 }} title="Đánh giá kết quả xử lý">
              {t.rating ? (
                <Space direction="vertical" size={2}>
                  <Rate disabled value={t.rating} />
                  {t.rating_comment && <Typography.Text type="secondary">{t.rating_comment}</Typography.Text>}
                </Space>
              ) : (
                <Space direction="vertical" style={{ width: '100%' }}>
                  <Rate value={rating} onChange={setRating} />
                  <Input.TextArea rows={2} value={ratingText} onChange={(e) => setRatingText(e.target.value)}
                                  placeholder="Nhận xét thêm (không bắt buộc)" />
                  <Button type="primary" size="small" onClick={doRate}>Gửi đánh giá</Button>
                </Space>
              )}
            </Card>
          )}

          <Card size="small" title={`Trao đổi & lịch sử xử lý (${t.events.length})`} style={{ marginBottom: 12 }}>
            {t.events.length === 0 && <Typography.Text type="secondary">Chưa có trao đổi nào.</Typography.Text>}
            {t.events.map(renderEvent)}
          </Card>

          <Card size="small" title="Phản hồi">
            {t.status === 'closed' ? (
              <Alert type="info" showIcon message="Yêu cầu đã đóng. Bấm 'Mở lại' nếu bạn cần tiếp tục trao đổi." />
            ) : (
              <Space direction="vertical" style={{ width: '100%' }}>
                {t.status === 'waiting_user' && t.is_owner && (
                  <Alert type="warning" showIcon message="Bộ phận hỗ trợ đang chờ thông tin từ bạn. Hãy trả lời bên dưới." />
                )}
                <Input.TextArea ref={replyBox} rows={4} value={reply}
                  onChange={(e) => setReply(e.target.value)}
                  placeholder={internal ? 'Ghi chú nội bộ – người gửi sẽ KHÔNG nhìn thấy' : 'Nhập nội dung phản hồi...'}
                  style={internal ? { background: '#fffbe6' } : undefined}
                  onPaste={(e) => {
                    const add = filesFromPaste(e)
                    if (add.length) setRfiles((p) => [...p, ...add].slice(0, MAX_FILES))
                  }} />
                <AttachmentPicker files={rfiles} onChange={setRfiles} />
                <Space>
                  <Button type="primary" icon={<SendOutlined />} loading={sending} onClick={send}>Gửi</Button>
                  {isAdmin && (
                    <Checkbox checked={internal} onChange={(e) => setInternal(e.target.checked)}>
                      <LockOutlined /> Ghi chú nội bộ
                    </Checkbox>
                  )}
                </Space>
              </Space>
            )}
          </Card>
        </Col>

        <Col xs={24} lg={8}>
          {isAdmin && (
            <Card size="small" title="Xử lý yêu cầu" style={{ marginBottom: 12 }}>
              <Space wrap style={{ marginBottom: 8 }}>
                <Button size="small" onClick={() => user && quick({ assignee_id: user.id })}
                        disabled={t.assignee_id === user?.id}>Nhận xử lý</Button>
                <Button size="small" onClick={() => quick({ status: 'waiting_user' }, true)}
                        disabled={t.status === 'waiting_user'}>Cần thêm thông tin</Button>
              </Space>
              <Space direction="vertical" style={{ width: '100%' }} size={8}>
                <div><Typography.Text type="secondary">Trạng thái</Typography.Text>
                  <Select style={{ width: '100%' }} value={pStatus} onChange={setPStatus} options={statusOptions} /></div>
                <div><Typography.Text type="secondary">Ưu tiên</Typography.Text>
                  <Select style={{ width: '100%' }} value={pPriority} onChange={setPPriority} options={priorityOptions} /></div>
                <div><Typography.Text type="secondary">Phân loại</Typography.Text>
                  <Select style={{ width: '100%' }} value={pCategory} onChange={setPCategory} options={categoryOptions} /></div>
                <div><Typography.Text type="secondary">Người xử lý</Typography.Text>
                  <Select style={{ width: '100%' }} allowClear placeholder="Chưa phân công" value={pAssignee ?? undefined}
                          onChange={(v) => setPAssignee(v ?? null)}
                          options={assignees.map((a) => ({ value: a.id, label: a.name }))} /></div>
                <div><Typography.Text type="secondary">Hạn xử lý</Typography.Text>
                  <DatePicker style={{ width: '100%' }} value={pDue} onChange={(v) => setPDue(v)} format="DD/MM/YYYY" /></div>
                <div><Typography.Text type="secondary">Kết quả xử lý / lý do (người gửi sẽ thấy)</Typography.Text>
                  <Input.TextArea rows={3} value={pResolution} onChange={(e) => setPResolution(e.target.value)} /></div>
                <Button type="primary" block loading={saving} onClick={saveAdmin}>Lưu thay đổi</Button>
              </Space>
            </Card>
          )}

          <Card size="small" title="Thông tin">
            <Descriptions column={1} size="small" colon={false}
              items={[
                { key: 'by', label: 'Người gửi', children: <>{t.created_by_name}{isAdmin && t.created_by_email ? ` (${t.created_by_email})` : ''}</> },
                { key: 'as', label: 'Người xử lý', children: t.assignee_name || <span style={{ color: '#bbb' }}>Chưa phân công</span> },
                { key: 'cat', label: 'Loại', children: <CategoryTag v={t.category} /> },
                { key: 'pri', label: 'Ưu tiên', children: <PriorityTag v={t.priority} /> },
                { key: 'ref', label: 'Site/Cell liên quan', children: t.related_ref || '-' },
                { key: 'cr', label: 'Tạo lúc', children: fmtDt(t.created_at) },
                { key: 'fr', label: 'Phản hồi đầu', children: fmtDt(t.first_response_at) },
                { key: 'due', label: 'Hạn xử lý', children: <span style={{ color: t.overdue ? '#cf1322' : undefined }}>{fmtDt(t.due_date)}</span> },
                { key: 'rs', label: 'Xử lý xong', children: fmtDt(t.resolved_at) },
                { key: 'ro', label: 'Số lần mở lại', children: t.reopen_count },
                { key: 'pg', label: 'Trang gửi từ', children: t.page_url || '-' },
                ...(isAdmin ? [{ key: 'ua', label: 'Trình duyệt', children: <span style={{ fontSize: 11, wordBreak: 'break-all' }}>{t.user_agent || '-'}</span> }] : []),
              ]} />
          </Card>
        </Col>
      </Row>

      <Modal title="Mở lại yêu cầu" open={reopenOpen} onOk={doReopen} onCancel={() => setReopenOpen(false)}
             okText="Mở lại" cancelText="Hủy">
        <Input.TextArea rows={3} value={reopenReason} onChange={(e) => setReopenReason(e.target.value)}
                        placeholder="Lý do mở lại (không bắt buộc)" />
      </Modal>
    </div>
  )
}
__SL_EOF__

echo "▶ Patching existing files (originals saved in $SL_BACKUP)..."

python3 - <<'__SL_PY__'
import os, pathlib, re, shutil

root = pathlib.Path(os.environ["SL_ROOT"])
bk = pathlib.Path(os.environ["SL_BACKUP"])
failed = []


def load(rel):
    p = root / rel
    return p, p.read_text(encoding="utf-8")


def save(p, rel, new):
    dst = bk / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(p, dst)
    p.write_text(new, encoding="utf-8")


def sub1(text, pattern, fn, flags=0):
    return re.subn(pattern, fn, text, count=1, flags=flags)


# ── backend/app/main.py ──────────────────────────────────────────────────────
rel = "backend/app/main.py"
p, s = load(rel)
if "feedback_router" in s:
    print(f"  = {rel}: already patched")
else:
    ok = True
    s, n = sub1(s, r"^from app\.api\.routes import sync\s+as sync_router[^\n]*$",
                lambda m: m.group(0) + "\nfrom app.api.routes import feedback as feedback_router", re.M)
    ok &= n == 1
    s, n = sub1(s, r"^app\.include_router\(sync_router\.router[^\n]*$",
                lambda m: m.group(0) + '\napp.include_router(feedback_router.router,     prefix=f"{PREFIX}/feedback",   tags=["Feedback"])', re.M)
    ok &= n == 1

    helper = '''def _ensure_feedback_tables():
    """Create feedback_* tables if missing (idempotent; advisory lock = safe with N workers)."""
    from sqlalchemy import text
    from app.models.feedback import FeedbackTicket, FeedbackEvent, FeedbackAttachment
    with engine.begin() as conn:
        conn.execute(text("SELECT pg_advisory_xact_lock(7294001)"))
        Base.metadata.create_all(
            bind=conn,
            tables=[FeedbackTicket.__table__, FeedbackEvent.__table__, FeedbackAttachment.__table__],
            checkfirst=True,
        )


'''
    s, n = sub1(s, r"^def _seed_initial_data\(\):\n",
                lambda m: helper + m.group(0) + "    _ensure_feedback_tables()\n", re.M)
    ok &= n == 1

    mw = '''@app.middleware("http")
async def _block_private_feedback_uploads(request, call_next):
    # feedback attachments are only served by the authenticated /api/v1/feedback endpoints
    if request.url.path.startswith("/uploads/feedback"):
        from fastapi.responses import JSONResponse
        return JSONResponse({"detail": "Not found"}, status_code=404)
    return await call_next(request)


'''
    s, n = sub1(s, r"^app\.mount\(", lambda m: mw + m.group(0), re.M)
    ok &= n == 1
    if ok:
        save(p, rel, s); print(f"  ✓ {rel}")
    else:
        failed.append(rel)

# ── backend/app/db/base.py ───────────────────────────────────────────────────
rel = "backend/app/db/base.py"
p, s = load(rel)
if "feedback" in s:
    print(f"  = {rel}: already patched")
else:
    s, n = sub1(s, r"(\n[ \t]*)rnc,([ \t]*\n\))",
                lambda m: m.group(1) + "rnc," + m.group(1) + "feedback," + m.group(2))
    if n == 1:
        save(p, rel, s); print(f"  ✓ {rel}")
    else:
        failed.append(rel)

# ── frontend/src/App.tsx ─────────────────────────────────────────────────────
rel = "frontend/src/App.tsx"
p, s = load(rel)
if "FeedbackPage" in s:
    print(f"  = {rel}: already patched")
else:
    ok = True
    s, n = sub1(s, r"^import RevisionPage[^\n]*$",
                lambda m: m.group(0)
                + "\nimport FeedbackPage       from '@/pages/feedback/FeedbackPage'"
                + "\nimport FeedbackDetailPage from '@/pages/feedback/FeedbackDetailPage'", re.M)
    ok &= n == 1
    s, n = sub1(s, r"^([ \t]*)<Route path=\"revision\"[^\n]*$",
                lambda m: m.group(0)
                + f"\n{m.group(1)}<Route path=\"feedback\"     element={{<FeedbackPage />}} />"
                + f"\n{m.group(1)}<Route path=\"feedback/:id\" element={{<FeedbackDetailPage />}} />", re.M)
    ok &= n == 1
    if ok:
        save(p, rel, s); print(f"  ✓ {rel}")
    else:
        failed.append(rel)

# ── frontend/src/components/layout/MainLayout.tsx ────────────────────────────
rel = "frontend/src/components/layout/MainLayout.tsx"
p, s = load(rel)
if "useFeedbackBadge" in s:
    print(f"  = {rel}: already patched")
else:
    ok = True
    s, n = sub1(s, r"^import \{ ssoLogout \} from '@/api/auth'[^\n]*$",
                lambda m: m.group(0)
                + "\nimport { Badge } from 'antd'"
                + "\nimport { CustomerServiceOutlined } from '@ant-design/icons'"
                + "\nimport { useFeedbackBadge } from '@/hooks/useFeedbackBadge'"
                + "\nimport FeedbackFab from '@/components/feedback/FeedbackFab'", re.M)
    ok &= n == 1
    s, n = sub1(s, r"const \{ user, logout, idToken \} = useAuthStore\(\)",
                lambda m: m.group(0) + "\n  const fbBadge = useFeedbackBadge()")
    ok &= n == 1
    item = ("\n    { key: '/feedback', icon: <CustomerServiceOutlined />, label: (\n"
            "      <span>Hỗ trợ / Góp ý{fbBadge > 0 && <Badge count={fbBadge} size=\"small\" style={{ marginLeft: 8 }} />}</span>\n"
            "    ) },")
    s, n = sub1(s, r"\{\s*key:\s*'/revision'[^}]*\},", lambda m: m.group(0) + item)
    ok &= n == 1
    s, n = sub1(s, r"selectedKeys=\{\[location\.pathname\]\}",
                lambda m: "selectedKeys={[location.pathname.startsWith('/feedback') ? '/feedback' : location.pathname]}")
    ok &= n == 1
    s, n = sub1(s, r"<Outlet />", lambda m: "<Outlet />\n          <FeedbackFab />")
    ok &= n == 1
    if ok:
        save(p, rel, s); print(f"  ✓ {rel}")
    else:
        failed.append(rel)

if failed:
    print("\n  ✗ Could not auto-patch (anchor not found, file left UNCHANGED):")
    for f in failed:
        print("    -", f)
    print("    → apply the manual steps listed in the README block below.")
    raise SystemExit(2)
__SL_PY__

echo
echo "✅ Feedback feature installed.   Backups: $SL_BACKUP"
cat <<'__SL_EOF__'

Next steps
  1. Review the changes :  git status && git diff
  2. (optional) type-check:  cd frontend && npx tsc --noEmit
  3. Rebuild & restart   :  docker compose up -d --build        (tables are created automatically)
  4. Open the app → menu "Hỗ trợ / Góp ý", or the floating blue button on any page.

Notes
  • Attachments live in backend/uploads/feedback – make sure /app/uploads is a persistent volume.
  • If your outer nginx limits uploads, set  client_max_body_size 12m;  for the /api location.
  • Handlers = users with role "admin".  Optional env var: FEEDBACK_UPLOAD_DIR.
__SL_EOF__