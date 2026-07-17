from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey
from sqlalchemy.orm import relationship

from app.db.base import Base


class Cell4G(Base):
    __tablename__ = "cells_4g"

    id               = Column(Integer, primary_key=True, index=True)
    site_id          = Column(Integer, ForeignKey("sites.id", ondelete="CASCADE"),
                              nullable=False, index=True)
    mien             = Column(String(10))
    tinh             = Column(String(100))
    phuong_xa        = Column(String(150))
    site_name        = Column(String(100), nullable=False, index=True)
    site_name_old    = Column(String(100), nullable=True)
    cell_name        = Column(String(100), nullable=False, index=True)
    cell_name_old    = Column(String(100), nullable=True)
    cell_vip         = Column(String(10))
    moran            = Column(String(50))
    lat              = Column(Float)
    long             = Column(Float)
    vung_phu_song    = Column(String(20))
    vendor           = Column(String(50))
    do_cao_anten     = Column(Float)
    azimuth          = Column(Float)
    m_tilt           = Column(Float)
    e_tilt           = Column(Float)
    total_tilt       = Column(Float)
    loai_anten       = Column(String(200))
    chung_anten      = Column(String(100))
    baseband         = Column(String(100))
    rf               = Column(String(100))
    enodeb_id        = Column(String(50))   # eNodeB ID
    cell_id          = Column(String(50))
    earfcn           = Column(String(50))
    tac              = Column(String(50))   # Tracking Area Code
    pci              = Column(String(50))
    root_sequence_id = Column(String(50))
    mimo             = Column(String(20))
    bandwidth        = Column(String(50))   # Bandwidth (MHz)
    cell_max_power   = Column(String(50))   # Cell max power (dBm)
    eci              = Column(String(50))   # E-UTRAN Cell Identifier
    bbu_name         = Column(String(100))  # BBU name
    cell_status      = Column(String(100))  # Cell status at dump time
    created_at       = Column(DateTime(timezone=True),
                              default=lambda: datetime.now(timezone.utc))
    updated_at       = Column(DateTime(timezone=True),
                              default=lambda: datetime.now(timezone.utc),
                              onupdate=lambda: datetime.now(timezone.utc))
    created_by       = Column(Integer, ForeignKey("users.id"), nullable=True)

    site = relationship("Site", back_populates="cells_4g")
