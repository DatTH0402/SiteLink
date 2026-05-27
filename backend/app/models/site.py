from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime, Text, ForeignKey
from sqlalchemy.orm import relationship

from app.db.base import Base


class Site(Base):
    __tablename__ = "sites"

    id                   = Column(Integer, primary_key=True, index=True)
    mien                 = Column(String(10), nullable=False)
    tinh                 = Column(String(100), nullable=False)
    phuong_xa            = Column(String(150))
    site_name_cu         = Column(String(100))
    site_name            = Column(String(100), nullable=False, unique=True, index=True)
    site_vip             = Column(String(10))
    lat                  = Column(Float, nullable=False)
    long                 = Column(Float, nullable=False)
    tram_2g              = Column(Boolean, default=False)
    tram_3g              = Column(Boolean, default=False)
    tram_4g              = Column(Boolean, default=False)
    tram_5g              = Column(Boolean, default=False)
    repeater             = Column(Boolean, default=False)
    booster              = Column(Boolean, default=False)
    node_truyen_dan_only = Column(Boolean, default=False)
    phan_loai_tram       = Column(String(100))
    tram_phu_song_tsca   = Column(String(50))
    moran_3g             = Column(String(50))
    moran_4g             = Column(String(50))
    moran_5g             = Column(String(50))
    ma_ptm               = Column(String(100), nullable=False)
    do_cao_dinh_cot_anten = Column(Float)
    do_cao_cot_anten     = Column(Float)
    dia_chi              = Column(Text)
    ghi_chu              = Column(Text)
    created_at           = Column(DateTime(timezone=True),
                                  default=lambda: datetime.now(timezone.utc))
    updated_at           = Column(DateTime(timezone=True),
                                  default=lambda: datetime.now(timezone.utc),
                                  onupdate=lambda: datetime.now(timezone.utc))
    created_by           = Column(Integer, ForeignKey("users.id"), nullable=True)

    cells_3g = relationship("Cell3G", back_populates="site", cascade="all, delete-orphan")
    cells_4g = relationship("Cell4G", back_populates="site", cascade="all, delete-orphan")
    cells_5g = relationship("Cell5G", back_populates="site", cascade="all, delete-orphan")
