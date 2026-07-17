from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey
from sqlalchemy.orm import relationship

from app.db.base import Base


class Cell3G(Base):
    __tablename__ = "cells_3g"

    id             = Column(Integer, primary_key=True, index=True)
    site_id        = Column(Integer, ForeignKey("sites.id", ondelete="CASCADE"),
                            nullable=False, index=True)
    mien           = Column(String(10))
    tinh           = Column(String(100))
    phuong_xa      = Column(String(150))
    site_name      = Column(String(100), nullable=False, index=True)
    site_name_old  = Column(String(100), nullable=True)
    cell_name      = Column(String(100), nullable=False, index=True)
    cell_name_old  = Column(String(100), nullable=True)
    cell_vip       = Column(String(10))
    moran          = Column(String(50))
    lat            = Column(Float)
    long           = Column(Float)
    vung_phu_song  = Column(String(20))
    vendor         = Column(String(50))
    do_cao_anten   = Column(Float)
    azimuth        = Column(Float)
    m_tilt         = Column(Float)
    e_tilt         = Column(Float)
    total_tilt     = Column(Float)
    loai_anten     = Column(String(200))
    chung_anten    = Column(String(100))
    baseband       = Column(String(100))
    rf             = Column(String(100))
    cell_id        = Column(String(50))
    arfcn          = Column(String(50))   # kept for backward compat
    uarfcn         = Column(String(50))   # UARFCN (3G frequency)
    lac            = Column(String(50))   # Location Area Code
    rac            = Column(String(50))   # Routing Area Code
    psc            = Column(String(50))   # Primary Scrambling Code
    ura_id         = Column(String(50))   # URA ID
    mimo           = Column(String(20))
    cell_max_power = Column(String(50))   # Cell max power (dBm)
    cpich_power    = Column(String(50))   # CPICH power (dBm)
    bbu_name       = Column(String(100))  # BBU name
    cell_status    = Column(String(100))  # Cell status at dump time
    created_at     = Column(DateTime(timezone=True),
                            default=lambda: datetime.now(timezone.utc))
    updated_at     = Column(DateTime(timezone=True),
                            default=lambda: datetime.now(timezone.utc),
                            onupdate=lambda: datetime.now(timezone.utc))
    created_by     = Column(Integer, ForeignKey("users.id"), nullable=True)

    site = relationship("Site", back_populates="cells_3g")
