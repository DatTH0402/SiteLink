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
