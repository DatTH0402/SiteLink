from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey
from sqlalchemy.orm import relationship

from app.db.base import Base


class Cell5G(Base):
    __tablename__ = "cells_5g"

    id               = Column(Integer, primary_key=True, index=True)
    site_id          = Column(Integer, ForeignKey("sites.id", ondelete="CASCADE"),
                              nullable=False, index=True)
    mien             = Column(String(10))
    tinh             = Column(String(100))
    phuong_xa        = Column(String(150))
    site_name        = Column(String(100), nullable=False, index=True)
    cell_name        = Column(String(100), nullable=False, index=True)
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
    baseband         = Column(String(100))
    rf               = Column(String(100))
    cell_id          = Column(String(50))
    nr_arfcn         = Column(String(50))
    pci              = Column(String(50))
    root_sequence_id = Column(String(50))
    mimo             = Column(String(20))
    created_at       = Column(DateTime(timezone=True),
                              default=lambda: datetime.now(timezone.utc))
    updated_at       = Column(DateTime(timezone=True),
                              default=lambda: datetime.now(timezone.utc),
                              onupdate=lambda: datetime.now(timezone.utc))
    created_by       = Column(Integer, ForeignKey("users.id"), nullable=True)

    site = relationship("Site", back_populates="cells_5g")
