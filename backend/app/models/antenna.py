from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Float, DateTime, Text
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
    h              = Column(String(50),  nullable=True)   # height mm
    w              = Column(String(50),  nullable=True)   # width  mm
    d              = Column(String(50),  nullable=True)   # depth  mm
    weight         = Column(String(50),  nullable=True)
    connector_type = Column(String(100), nullable=True)
    ghi_chu        = Column(Text,        nullable=True)
    created_at     = Column(DateTime(timezone=True),
                            default=lambda: datetime.now(timezone.utc))
    updated_at     = Column(DateTime(timezone=True),
                            default=lambda: datetime.now(timezone.utc),
                            onupdate=lambda: datetime.now(timezone.utc))
