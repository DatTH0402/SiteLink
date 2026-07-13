from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime, Text, ForeignKey
from app.db.base import Base


class Cell3GRevision(Base):
    __tablename__ = "cell_3g_revisions"

    id              = Column(Integer, primary_key=True, index=True)
    cell_id_ref     = Column(Integer, nullable=False, index=True)
    site_id         = Column(Integer, nullable=False)
    site_name       = Column(String(100), nullable=False, index=True)
    cell_name       = Column(String(100), nullable=False, index=True)
    revision_no     = Column(Integer, nullable=False, default=1)
    changed_by      = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    changed_by_name = Column(String(100))
    change_source   = Column(String(20), default="form")
    change_note     = Column(Text)

    mien          = Column(String(10))
    tinh          = Column(String(100))
    phuong_xa     = Column(String(150))
    site_name_old = Column(String(100))
    cell_name_old = Column(String(100))
    cell_vip      = Column(String(10))
    moran         = Column(String(50))
    lat           = Column(Float)
    long          = Column(Float)
    vung_phu_song = Column(String(20))
    vendor        = Column(String(50))
    do_cao_anten  = Column(Float)
    azimuth       = Column(Float)
    m_tilt        = Column(Float)
    e_tilt        = Column(Float)
    total_tilt    = Column(Float)
    loai_anten    = Column(String(200))
    chung_anten   = Column(String(100))
    baseband      = Column(String(100))
    rf            = Column(String(100))
    cell_id       = Column(String(50))
    arfcn         = Column(String(50))
    psc           = Column(String(50))
    mimo          = Column(String(20))

    changed_fields = Column(Text)
    created_at     = Column(DateTime(timezone=True),
                            default=lambda: datetime.now(timezone.utc))


class Cell4GRevision(Base):
    __tablename__ = "cell_4g_revisions"

    id              = Column(Integer, primary_key=True, index=True)
    cell_id_ref     = Column(Integer, nullable=False, index=True)
    site_id         = Column(Integer, nullable=False)
    site_name       = Column(String(100), nullable=False, index=True)
    cell_name       = Column(String(100), nullable=False, index=True)
    revision_no     = Column(Integer, nullable=False, default=1)
    changed_by      = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    changed_by_name = Column(String(100))
    change_source   = Column(String(20), default="form")
    change_note     = Column(Text)

    mien             = Column(String(10))
    tinh             = Column(String(100))
    phuong_xa        = Column(String(150))
    site_name_old    = Column(String(100))
    cell_name_old    = Column(String(100))
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
    cell_id          = Column(String(50))
    earfcn           = Column(String(50))
    pci              = Column(String(50))
    root_sequence_id = Column(String(50))
    mimo             = Column(String(20))

    changed_fields = Column(Text)
    created_at     = Column(DateTime(timezone=True),
                            default=lambda: datetime.now(timezone.utc))


class Cell5GRevision(Base):
    __tablename__ = "cell_5g_revisions"

    id              = Column(Integer, primary_key=True, index=True)
    cell_id_ref     = Column(Integer, nullable=False, index=True)
    site_id         = Column(Integer, nullable=False)
    site_name       = Column(String(100), nullable=False, index=True)
    cell_name       = Column(String(100), nullable=False, index=True)
    revision_no     = Column(Integer, nullable=False, default=1)
    changed_by      = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    changed_by_name = Column(String(100))
    change_source   = Column(String(20), default="form")
    change_note     = Column(Text)

    mien             = Column(String(10))
    tinh             = Column(String(100))
    phuong_xa        = Column(String(150))
    site_name_old    = Column(String(100))
    cell_name_old    = Column(String(100))
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

    changed_fields = Column(Text)
    created_at     = Column(DateTime(timezone=True),
                            default=lambda: datetime.now(timezone.utc))
