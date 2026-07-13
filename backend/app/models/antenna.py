from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime, Text
from app.db.base import Base


class Antenna(Base):
    __tablename__ = "antennas"

    id             = Column(Integer, primary_key=True, index=True)
    name           = Column(String(300), nullable=False, unique=True, index=True)
    no_of_ports    = Column(Integer,     nullable=True)
    band           = Column(String(100), nullable=True)
    no_of_beam     = Column(Integer,     nullable=True)
    horizontal_bw  = Column(String(50),  nullable=True)
    vertical_bw    = Column(String(50),  nullable=True)
    gain           = Column(String(50),  nullable=True)
    etilt          = Column(String(50),  nullable=True)
    h              = Column(String(50),  nullable=True)
    w              = Column(String(50),  nullable=True)
    d              = Column(String(50),  nullable=True)
    weight         = Column(String(50),  nullable=True)
    connector_type = Column(String(100), nullable=True)
    ghi_chu        = Column(Text,        nullable=True)
    is_5g_aau      = Column(Boolean,     default=False, nullable=False)
    spec_file_path = Column(String(500), nullable=True)   # relative path under uploads/
    spec_file_name = Column(String(255), nullable=True)   # original filename shown to user
    created_at     = Column(DateTime(timezone=True),
                            default=lambda: datetime.now(timezone.utc))
    updated_at     = Column(DateTime(timezone=True),
                            default=lambda: datetime.now(timezone.utc),
                            onupdate=lambda: datetime.now(timezone.utc))
