#!/usr/bin/env bash
set -euo pipefail

echo "=== SiteLink: Adding RNC Name column to Cell 3G ==="

# ─────────────────────────────────────────────────────────────────────────────
# 1. BACKEND: New model for RNC dropdown table
# ─────────────────────────────────────────────────────────────────────────────

cat > backend/app/models/rnc.py << 'PYEOF'
from sqlalchemy import Column, Integer, String
from app.db.base import Base


class RncName(Base):
    __tablename__ = "rnc_names"

    id     = Column(Integer, primary_key=True, index=True)
    vendor = Column(String(50), nullable=False, index=True)
    name   = Column(String(100), nullable=False)
PYEOF

echo "[1/14] Created backend/app/models/rnc.py"

# ─────────────────────────────────────────────────────────────────────────────
# 2. BACKEND: Update db/base.py to import the new model
# ─────────────────────────────────────────────────────────────────────────────

cat > backend/app/db/base.py << 'PYEOF'
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass


# Import all models so SQLAlchemy registers them
from app.models import (  # noqa
    user, site, cell_3g, cell_4g, cell_5g,
    dropdown, audit_log, antenna,
    site_revision, cell_revision,
    rnc,
)
PYEOF

echo "[2/14] Updated backend/app/db/base.py"

# ─────────────────────────────────────────────────────────────────────────────
# 3. BACKEND: Update Cell3G model to add rnc_name column
# ─────────────────────────────────────────────────────────────────────────────

cat > backend/app/models/cell_3g.py << 'PYEOF'
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
    rnc_name       = Column(String(100), nullable=True)
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
    arfcn          = Column(String(50))
    uarfcn         = Column(String(50))
    lac            = Column(String(50))
    rac            = Column(String(50))
    psc            = Column(String(50))
    ura_id         = Column(String(50))
    mimo           = Column(String(20))
    cell_max_power = Column(String(50))
    cpich_power    = Column(String(50))
    bbu_name       = Column(String(100))
    cell_status    = Column(String(100))
    created_at     = Column(DateTime(timezone=True),
                            default=lambda: datetime.now(timezone.utc))
    updated_at     = Column(DateTime(timezone=True),
                            default=lambda: datetime.now(timezone.utc),
                            onupdate=lambda: datetime.now(timezone.utc))
    created_by     = Column(Integer, ForeignKey("users.id"), nullable=True)

    site = relationship("Site", back_populates="cells_3g")
PYEOF

echo "[3/14] Updated backend/app/models/cell_3g.py"

# ─────────────────────────────────────────────────────────────────────────────
# 4. BACKEND: Update Cell3GRevision model to add rnc_name column
# ─────────────────────────────────────────────────────────────────────────────

cat > backend/app/models/cell_revision.py << 'PYEOF'
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

    mien           = Column(String(10))
    tinh           = Column(String(100))
    phuong_xa      = Column(String(150))
    site_name_old  = Column(String(100))
    cell_name_old  = Column(String(100))
    cell_vip       = Column(String(10))
    moran          = Column(String(50))
    lat            = Column(Float)
    long           = Column(Float)
    vung_phu_song  = Column(String(20))
    vendor         = Column(String(50))
    rnc_name       = Column(String(100))
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
    arfcn          = Column(String(50))
    uarfcn         = Column(String(50))
    lac            = Column(String(50))
    rac            = Column(String(50))
    psc            = Column(String(50))
    ura_id         = Column(String(50))
    mimo           = Column(String(20))
    cell_max_power = Column(String(50))
    cpich_power    = Column(String(50))
    bbu_name       = Column(String(100))
    cell_status    = Column(String(100))

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
    enodeb_id        = Column(String(50))
    cell_id          = Column(String(50))
    earfcn           = Column(String(50))
    tac              = Column(String(50))
    pci              = Column(String(50))
    root_sequence_id = Column(String(50))
    mimo             = Column(String(20))
    bandwidth        = Column(String(50))
    cell_max_power   = Column(String(50))
    eci              = Column(String(50))
    bbu_name         = Column(String(100))
    cell_status      = Column(String(100))

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
    gnodeb_id        = Column(String(50))
    cell_id          = Column(String(50))
    tac              = Column(String(50))
    pci              = Column(String(50))
    root_sequence_id = Column(String(50))
    mimo             = Column(String(20))
    ssb_arfcn        = Column(String(50))
    center_arfcn     = Column(String(50))
    gscn             = Column(String(50))
    bandwidth        = Column(String(50))
    cell_max_power   = Column(String(50))
    nci              = Column(String(50))
    bbu_name         = Column(String(100))
    mu_mimo          = Column(String(20))
    cell_status      = Column(String(100))

    changed_fields = Column(Text)
    created_at     = Column(DateTime(timezone=True),
                            default=lambda: datetime.now(timezone.utc))
PYEOF

echo "[4/14] Updated backend/app/models/cell_revision.py"

# ─────────────────────────────────────────────────────────────────────────────
# 5. BACKEND: Update Cell 3G schema
# ─────────────────────────────────────────────────────────────────────────────

cat > backend/app/schemas/cell.py << 'PYEOF'
from typing import Optional
from pydantic import BaseModel


class CellBase(BaseModel):
    site_id:        int
    site_name:      str
    site_name_old:  Optional[str]   = None
    cell_name:      str
    cell_name_old:  Optional[str]   = None
    mien:           Optional[str]   = None
    tinh:           Optional[str]   = None
    phuong_xa:      Optional[str]   = None
    cell_vip:       Optional[str]   = None
    moran:          Optional[str]   = None
    lat:            Optional[float] = None
    long:           Optional[float] = None
    vung_phu_song:  Optional[str]   = None
    vendor:         Optional[str]   = None
    do_cao_anten:   Optional[float] = None
    azimuth:        Optional[float] = None
    m_tilt:         Optional[float] = None
    e_tilt:         Optional[float] = None
    total_tilt:     Optional[float] = None
    loai_anten:     Optional[str]   = None
    baseband:       Optional[str]   = None
    rf:             Optional[str]   = None
    cell_id:        Optional[str]   = None
    mimo:           Optional[str]   = None
    bbu_name:       Optional[str]   = None
    cell_status:    Optional[str]   = None
    cell_max_power: Optional[str]   = None


# ── 3G ────────────────────────────────────────────────────────────────────────
class Cell3GBase(CellBase):
    chung_anten:    Optional[str] = None
    arfcn:          Optional[str] = None
    uarfcn:         Optional[str] = None
    lac:            Optional[str] = None
    rac:            Optional[str] = None
    psc:            Optional[str] = None
    ura_id:         Optional[str] = None
    cpich_power:    Optional[str] = None
    rnc_name:       Optional[str] = None


class Cell3GCreate(Cell3GBase):
    pass


class Cell3GUpdate(BaseModel):
    cell_name:      Optional[str]   = None
    site_name:      Optional[str]   = None
    site_name_old:  Optional[str]   = None
    cell_name_old:  Optional[str]   = None
    cell_vip:       Optional[str]   = None
    moran:          Optional[str]   = None
    lat:            Optional[float] = None
    long:           Optional[float] = None
    vung_phu_song:  Optional[str]   = None
    vendor:         Optional[str]   = None
    rnc_name:       Optional[str]   = None
    do_cao_anten:   Optional[float] = None
    azimuth:        Optional[float] = None
    m_tilt:         Optional[float] = None
    e_tilt:         Optional[float] = None
    total_tilt:     Optional[float] = None
    loai_anten:     Optional[str]   = None
    chung_anten:    Optional[str]   = None
    baseband:       Optional[str]   = None
    rf:             Optional[str]   = None
    cell_id:        Optional[str]   = None
    arfcn:          Optional[str]   = None
    uarfcn:         Optional[str]   = None
    lac:            Optional[str]   = None
    rac:            Optional[str]   = None
    psc:            Optional[str]   = None
    ura_id:         Optional[str]   = None
    mimo:           Optional[str]   = None
    cell_max_power: Optional[str]   = None
    cpich_power:    Optional[str]   = None
    bbu_name:       Optional[str]   = None
    cell_status:    Optional[str]   = None


class Cell3GRead(Cell3GBase):
    id: int
    class Config:
        from_attributes = True


# ── 4G ────────────────────────────────────────────────────────────────────────
class Cell4GBase(CellBase):
    chung_anten:      Optional[str] = None
    enodeb_id:        Optional[str] = None
    earfcn:           Optional[str] = None
    tac:              Optional[str] = None
    pci:              Optional[str] = None
    root_sequence_id: Optional[str] = None
    bandwidth:        Optional[str] = None
    eci:              Optional[str] = None


class Cell4GCreate(Cell4GBase):
    pass


class Cell4GUpdate(BaseModel):
    cell_name:        Optional[str]   = None
    site_name:        Optional[str]   = None
    site_name_old:    Optional[str]   = None
    cell_name_old:    Optional[str]   = None
    cell_vip:         Optional[str]   = None
    moran:            Optional[str]   = None
    lat:              Optional[float] = None
    long:             Optional[float] = None
    vung_phu_song:    Optional[str]   = None
    vendor:           Optional[str]   = None
    do_cao_anten:     Optional[float] = None
    azimuth:          Optional[float] = None
    m_tilt:           Optional[float] = None
    e_tilt:           Optional[float] = None
    total_tilt:       Optional[float] = None
    loai_anten:       Optional[str]   = None
    chung_anten:      Optional[str]   = None
    baseband:         Optional[str]   = None
    rf:               Optional[str]   = None
    enodeb_id:        Optional[str]   = None
    cell_id:          Optional[str]   = None
    earfcn:           Optional[str]   = None
    tac:              Optional[str]   = None
    pci:              Optional[str]   = None
    root_sequence_id: Optional[str]   = None
    mimo:             Optional[str]   = None
    bandwidth:        Optional[str]   = None
    cell_max_power:   Optional[str]   = None
    eci:              Optional[str]   = None
    bbu_name:         Optional[str]   = None
    cell_status:      Optional[str]   = None


class Cell4GRead(Cell4GBase):
    id: int
    class Config:
        from_attributes = True


# ── 5G ────────────────────────────────────────────────────────────────────────
class Cell5GBase(CellBase):
    gnodeb_id:        Optional[str] = None
    tac:              Optional[str] = None
    pci:              Optional[str] = None
    root_sequence_id: Optional[str] = None
    ssb_arfcn:        Optional[str] = None
    center_arfcn:     Optional[str] = None
    gscn:             Optional[str] = None
    bandwidth:        Optional[str] = None
    nci:              Optional[str] = None
    mu_mimo:          Optional[str] = None


class Cell5GCreate(Cell5GBase):
    pass


class Cell5GUpdate(BaseModel):
    cell_name:        Optional[str]   = None
    site_name:        Optional[str]   = None
    site_name_old:    Optional[str]   = None
    cell_name_old:    Optional[str]   = None
    cell_vip:         Optional[str]   = None
    moran:            Optional[str]   = None
    lat:              Optional[float] = None
    long:             Optional[float] = None
    vung_phu_song:    Optional[str]   = None
    vendor:           Optional[str]   = None
    do_cao_anten:     Optional[float] = None
    azimuth:          Optional[float] = None
    m_tilt:           Optional[float] = None
    e_tilt:           Optional[float] = None
    total_tilt:       Optional[float] = None
    loai_anten:       Optional[str]   = None
    baseband:         Optional[str]   = None
    rf:               Optional[str]   = None
    gnodeb_id:        Optional[str]   = None
    cell_id:          Optional[str]   = None
    tac:              Optional[str]   = None
    pci:              Optional[str]   = None
    root_sequence_id: Optional[str]   = None
    mimo:             Optional[str]   = None
    ssb_arfcn:        Optional[str]   = None
    center_arfcn:     Optional[str]   = None
    gscn:             Optional[str]   = None
    bandwidth:        Optional[str]   = None
    cell_max_power:   Optional[str]   = None
    nci:              Optional[str]   = None
    bbu_name:         Optional[str]   = None
    mu_mimo:          Optional[str]   = None
    cell_status:      Optional[str]   = None


class Cell5GRead(Cell5GBase):
    id: int
    class Config:
        from_attributes = True
PYEOF

echo "[5/14] Updated backend/app/schemas/cell.py"

# ─────────────────────────────────────────────────────────────────────────────
# 6. BACKEND: Add RNC API route
# ─────────────────────────────────────────────────────────────────────────────

cat > backend/app/api/routes/rnc.py << 'PYEOF'
from typing import List, Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.rnc import RncName
from app.utils.deps import get_current_user

router = APIRouter()


@router.get("/")
def list_rnc_names(
    vendor: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    """Return RNC names, optionally filtered by vendor."""
    q = db.query(RncName)
    if vendor:
        q = q.filter(RncName.vendor == vendor)
    rows = q.order_by(RncName.vendor, RncName.name).all()
    return [{"id": r.id, "vendor": r.vendor, "name": r.name} for r in rows]


@router.get("/all")
def list_all_rnc_names(
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    """Return all RNC names grouped by vendor."""
    rows = db.query(RncName).order_by(RncName.vendor, RncName.name).all()
    result: dict = {}
    for r in rows:
        result.setdefault(r.vendor, []).append(r.name)
    return result
PYEOF

echo "[6/14] Created backend/app/api/routes/rnc.py"

# ─────────────────────────────────────────────────────────────────────────────
# 7. BACKEND: Update main.py to register RNC route and seed RNC data
# ─────────────────────────────────────────────────────────────────────────────

cat > backend/app/main.py << 'PYEOF'
import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.db.session import engine, SessionLocal
from app.db import base  # noqa
from app.db.base import Base
from app.api.routes import (
    auth, users, sites, cells_3g, cells_4g, cells_5g,
    dropdowns, report, audit,
)
from app.api.routes import antenna   as antenna_router
from app.api.routes import templates as templates_router
from app.api.routes import export    as export_router
from app.api.routes import revision  as revision_router
from app.api.routes import rnc       as rnc_router

Base.metadata.create_all(bind=engine)

UPLOAD_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "uploads")
)
os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(os.path.join(UPLOAD_DIR, "antenna_specs"), exist_ok=True)


_RNC_DATA = [
    ("ERICSSON", "RHNCG1E"), ("ERICSSON", "RHNCG2E"), ("ERICSSON", "RHNCG3E"),
    ("ERICSSON", "RHNCG4E"), ("ERICSSON", "RHNHM1E"), ("ERICSSON", "RHNHM2E"),
    ("ERICSSON", "RHNHM3E"), ("ERICSSON", "RQNHL1E"), ("ERICSSON", "RQNHL2E"),
    ("ERICSSON", "RSG103E"), ("ERICSSON", "RSG011E"), ("ERICSSON", "RSG072E"),
    ("ERICSSON", "RSG091E"), ("ERICSSON", "RSG092E"), ("ERICSSON", "RSG093E"),
    ("ERICSSON", "RSG094E"), ("ERICSSON", "RSG095E"), ("ERICSSON", "RSG097E"),
    ("ERICSSON", "RSG104E"), ("ERICSSON", "RSG105E"), ("ERICSSON", "RSGBC2E"),
    ("ERICSSON", "RSGBI2E"), ("ERICSSON", "RSGBT2E"), ("ERICSSON", "RSGHM1E"),
    ("ERICSSON", "RSGTB2E"),
    ("HUAWEI", "iHNCG1H"), ("HUAWEI", "iHNCG3H"), ("HUAWEI", "iHNHM1H"),
    ("HUAWEI", "iHNHM2H"), ("HUAWEI", "iHNHM3H"), ("HUAWEI", "iHNHM5H"),
    ("HUAWEI", "iHNHM6H"), ("HUAWEI", "iHNHM7H"), ("HUAWEI", "iHNHM8H"),
    ("HUAWEI", "RHNCG1H"), ("HUAWEI", "RHNCG3H"), ("HUAWEI", "RHNCG4H"),
    ("HUAWEI", "RHNHM3H"), ("HUAWEI", "RHNHM4H"), ("HUAWEI", "RHNHM5H"),
    ("HUAWEI", "RHNHM6H"), ("HUAWEI", "RHNHM7H"), ("HUAWEI", "RHNHM8H"),
    ("HUAWEI", "RDNG01H"), ("HUAWEI", "RDNG02H"), ("HUAWEI", "RQBDH1H"),
    ("HUAWEI", "RCTCR11H"), ("HUAWEI", "RCTCR12H"),
    ("NOKIA", "RDNCL3N"), ("NOKIA", "RDNCL4N"), ("NOKIA", "RDNCL5N"),
    ("NOKIA", "RDNCL7N"), ("NOKIA", "RDNCL8N"), ("NOKIA", "RDNCL9N"),
    ("NOKIA", "RDNST10N"), ("NOKIA", "RDNST12N"), ("NOKIA", "RDNST13N"),
    ("NOKIA", "RDNST14N"), ("NOKIA", "RDNST15N"), ("NOKIA", "RDNST7N"),
    ("NOKIA", "RCTCR1N"), ("NOKIA", "RCTCR2N"), ("NOKIA", "RCTCR8N"),
    ("NOKIA", "RDNBH5N"), ("NOKIA", "RSG091N"), ("NOKIA", "RSG092N"),
    ("NOKIA", "RSG093N"), ("NOKIA", "RSG094N"), ("NOKIA", "RSG095N"),
    ("NOKIA", "RSG097N"), ("NOKIA", "RSG098N"), ("NOKIA", "RSG099N"),
    ("NOKIA", "RSG105N"), ("NOKIA", "RTGMT3N"),
    ("ZTE", "RCTCR3Z"), ("ZTE", "RCTCR4Z"), ("ZTE", "RCTCR5Z"), ("ZTE", "RCTCR6Z"),
]


def _seed_initial_data():
    db = SessionLocal()
    try:
        from app.models.user import User, UserRole
        from app.core.security import get_password_hash
        from app.models.dropdown import DropdownGeneral, DropdownVendor
        from app.models.rnc import RncName

        if not db.query(User).filter(User.username == "admin").first():
            db.add(User(
                email="admin@sitelink.com",
                username="admin",
                full_name="Administrator",
                hashed_password=get_password_hash("admin"),
                role=UserRole.admin,
            ))
            db.commit()

        def seed_cat(cat, values):
            if db.query(DropdownGeneral).filter(DropdownGeneral.category == cat).count() == 0:
                for v in values:
                    db.add(DropdownGeneral(category=cat, value=v, label=v))
                db.commit()

        seed_cat("moran",          ["VNPT HOST", "MBF HOST"])
        seed_cat("phan_loai_tram", ["IBC", "Macro outdoor", "IBC + Outdoor", "Smallcell", "miniDAS"])
        seed_cat("mien",           ["MB", "MT", "MN"])
        seed_cat("vung_phu_song",  ["Indoor", "Outdoor"])
        seed_cat("mimo",           ["2x2", "4x4", "8x8"])
        seed_cat("site_vip",       ["VIP", "VVIP"])
        seed_cat("csht", [
            "VNPT", "MOBIFONE", "XA HOI HOA", "VIETTEL",
            "LIEN KET", "HA TANG CO SAN", "GTEL", "IBC", "VIETNAMMOBILE",
        ])

        if db.query(DropdownVendor).count() == 0:
            for row in [
                ("Alcatel", "Alcatel", "Nokia",    "Nokia"),
                ("Nokia",   "Nokia",   "Ericsson", "Ericsson"),
                ("Ericsson","Ericsson","Huawei",   "Huawei"),
                ("Huawei",  "Huawei",  "ZTE",      "ZTE"),
                ("ZTE",     "ZTE",     "Samsung",  "Samsung"),
            ]:
                db.add(DropdownVendor(
                    vendor_2g=row[0], vendor_3g=row[1],
                    vendor_4g=row[2], vendor_5g=row[3],
                ))
            db.commit()

        # Seed RNC names
        if db.query(RncName).count() == 0:
            for vendor, name in _RNC_DATA:
                db.add(RncName(vendor=vendor, name=name))
            db.commit()

    finally:
        db.close()


def _generate_templates():
    template_dir = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "templates")
    )
    os.makedirs(template_dir, exist_ok=True)
    required = [
        "template_site.xlsx", "template_cell_3g.xlsx",
        "template_cell_4g.xlsx", "template_cell_5g.xlsx",
    ]
    missing = [f for f in required if not os.path.exists(os.path.join(template_dir, f))]
    if missing:
        try:
            script = os.path.abspath(
                os.path.join(os.path.dirname(__file__), "..", "create_templates.py")
            )
            if os.path.exists(script):
                import importlib.util
                spec = importlib.util.spec_from_file_location("create_templates", script)
                mod  = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(mod)
                mod.create_site_template()
                mod.create_cell3g_template()
                mod.create_cell4g_template()
                mod.create_cell5g_template()
                print("[startup] Excel templates generated.")
        except Exception as exc:
            print(f"[startup] Warning: could not generate templates: {exc}")


app = FastAPI(
    title="SiteLink API",
    version="1.2.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.mount(
    "/uploads",
    StaticFiles(directory=UPLOAD_DIR),
    name="uploads",
)


@app.on_event("startup")
def on_startup():
    _seed_initial_data()
    _generate_templates()


PREFIX = "/api/v1"
app.include_router(auth.router,             prefix=f"{PREFIX}/auth",       tags=["Auth"])
app.include_router(users.router,            prefix=f"{PREFIX}/users",      tags=["Users"])
app.include_router(sites.router,            prefix=f"{PREFIX}/sites",      tags=["Sites"])
app.include_router(cells_3g.router,         prefix=f"{PREFIX}/cells-3g",   tags=["Cells-3G"])
app.include_router(cells_4g.router,         prefix=f"{PREFIX}/cells-4g",   tags=["Cells-4G"])
app.include_router(cells_5g.router,         prefix=f"{PREFIX}/cells-5g",   tags=["Cells-5G"])
app.include_router(dropdowns.router,        prefix=f"{PREFIX}/dropdowns",  tags=["Dropdowns"])
app.include_router(report.router,           prefix=f"{PREFIX}/report",     tags=["Report"])
app.include_router(audit.router,            prefix=f"{PREFIX}/audit",      tags=["Audit"])
app.include_router(antenna_router.router,   prefix=f"{PREFIX}/antennas",   tags=["Antennas"])
app.include_router(templates_router.router, prefix=f"{PREFIX}/templates",  tags=["Templates"])
app.include_router(export_router.router,    prefix=f"{PREFIX}/export",     tags=["Export"])
app.include_router(revision_router.router,  prefix=f"{PREFIX}/revisions",  tags=["Revisions"])
app.include_router(rnc_router.router,       prefix=f"{PREFIX}/rnc",        tags=["RNC"])


@app.get("/health")
def health():
    return {"status": "ok"}
PYEOF

echo "[7/14] Updated backend/app/main.py"

# ─────────────────────────────────────────────────────────────────────────────
# 8. BACKEND: Update revision service to include rnc_name in 3G snapshot
# ─────────────────────────────────────────────────────────────────────────────

cat > backend/app/services/revision.py << 'PYEOF'
"""
revision.py – Service layer for revision history snapshots.
"""
from __future__ import annotations

import json
from typing import Any, Dict, Optional
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.models.site_revision import SiteRevision
from app.models.cell_revision import Cell3GRevision, Cell4GRevision, Cell5GRevision
from app.models.site import Site
from app.models.cell_3g import Cell3G
from app.models.cell_4g import Cell4G
from app.models.cell_5g import Cell5G


def _safe_bool(v) -> bool:
    if v is None:
        return False
    if isinstance(v, bool):
        return v
    if isinstance(v, int):
        return v != 0
    if isinstance(v, str):
        return v.strip().lower() not in ("false", "0", "no", "off", "")
    return bool(v)


def _normalize_for_diff(v: Any) -> Any:
    if v is None or v == "":
        return None
    if isinstance(v, bool):
        return v
    if isinstance(v, int) and v in (0, 1):
        return bool(v)
    if isinstance(v, str) and v.lower() in ("true", "false"):
        return v.lower() == "true"
    return v


def _diff(old: Dict, new: Dict) -> Dict:
    result = {}
    all_keys = set(old) | set(new)
    for k in all_keys:
        ov = _normalize_for_diff(old.get(k))
        nv = _normalize_for_diff(new.get(k))
        if ov != nv:
            result[k] = [old.get(k), new.get(k)]
    return result


def _next_rev_no_site(db: Session, site_id: int) -> int:
    result = db.query(func.max(SiteRevision.revision_no)).filter(
        SiteRevision.site_id == site_id).scalar()
    return (result or 0) + 1


def _next_rev_no_cell3g(db: Session, cell_id_ref: int) -> int:
    result = db.query(func.max(Cell3GRevision.revision_no)).filter(
        Cell3GRevision.cell_id_ref == cell_id_ref).scalar()
    return (result or 0) + 1


def _next_rev_no_cell4g(db: Session, cell_id_ref: int) -> int:
    result = db.query(func.max(Cell4GRevision.revision_no)).filter(
        Cell4GRevision.cell_id_ref == cell_id_ref).scalar()
    return (result or 0) + 1


def _next_rev_no_cell5g(db: Session, cell_id_ref: int) -> int:
    result = db.query(func.max(Cell5GRevision.revision_no)).filter(
        Cell5GRevision.cell_id_ref == cell_id_ref).scalar()
    return (result or 0) + 1


# ── Snapshot helpers ──────────────────────────────────────────────────────────

def _site_snapshot(site: Site) -> Dict[str, Any]:
    return {
        "mien": site.mien, "tinh": site.tinh, "phuong_xa": site.phuong_xa,
        "site_name_cu": site.site_name_cu, "site_vip": site.site_vip,
        "lat": site.lat, "long": site.long,
        "tram_2g": _safe_bool(site.tram_2g),
        "tram_3g": _safe_bool(site.tram_3g),
        "tram_4g": _safe_bool(site.tram_4g),
        "tram_5g": _safe_bool(site.tram_5g),
        "repeater": _safe_bool(site.repeater),
        "booster": _safe_bool(site.booster),
        "node_truyen_dan_only": _safe_bool(site.node_truyen_dan_only),
        "tram_phu_song_tsca": _safe_bool(site.tram_phu_song_tsca),
        "phan_loai_tram": site.phan_loai_tram,
        "moran_3g": site.moran_3g, "moran_4g": site.moran_4g,
        "moran_5g": site.moran_5g,
        "ma_ptm": site.ma_ptm,
        "do_cao_dinh_cot_anten": site.do_cao_dinh_cot_anten,
        "do_cao_cot_anten": site.do_cao_cot_anten,
        "dia_chi": site.dia_chi, "ghi_chu": site.ghi_chu,
        "site_name": site.site_name,
    }


def _cell3g_snapshot(cell: Cell3G) -> Dict[str, Any]:
    return {
        "site_name": cell.site_name, "site_name_old": cell.site_name_old,
        "cell_name": cell.cell_name, "cell_name_old": cell.cell_name_old,
        "mien": cell.mien, "tinh": cell.tinh, "phuong_xa": cell.phuong_xa,
        "cell_vip": cell.cell_vip, "moran": cell.moran,
        "lat": cell.lat, "long": cell.long,
        "vung_phu_song": cell.vung_phu_song, "vendor": cell.vendor,
        "rnc_name": cell.rnc_name,
        "do_cao_anten": cell.do_cao_anten, "azimuth": cell.azimuth,
        "m_tilt": cell.m_tilt, "e_tilt": cell.e_tilt,
        "total_tilt": cell.total_tilt,
        "loai_anten": cell.loai_anten, "chung_anten": cell.chung_anten,
        "baseband": cell.baseband, "rf": cell.rf, "cell_id": cell.cell_id,
        "arfcn": cell.arfcn, "uarfcn": cell.uarfcn,
        "lac": cell.lac, "rac": cell.rac,
        "psc": cell.psc, "ura_id": cell.ura_id, "mimo": cell.mimo,
        "cell_max_power": cell.cell_max_power, "cpich_power": cell.cpich_power,
        "bbu_name": cell.bbu_name, "cell_status": cell.cell_status,
    }


def _cell4g_snapshot(cell: Cell4G) -> Dict[str, Any]:
    return {
        "site_name": cell.site_name, "site_name_old": cell.site_name_old,
        "cell_name": cell.cell_name, "cell_name_old": cell.cell_name_old,
        "mien": cell.mien, "tinh": cell.tinh, "phuong_xa": cell.phuong_xa,
        "cell_vip": cell.cell_vip, "moran": cell.moran,
        "lat": cell.lat, "long": cell.long,
        "vung_phu_song": cell.vung_phu_song, "vendor": cell.vendor,
        "do_cao_anten": cell.do_cao_anten, "azimuth": cell.azimuth,
        "m_tilt": cell.m_tilt, "e_tilt": cell.e_tilt,
        "total_tilt": cell.total_tilt,
        "loai_anten": cell.loai_anten, "chung_anten": cell.chung_anten,
        "baseband": cell.baseband, "rf": cell.rf,
        "enodeb_id": cell.enodeb_id, "cell_id": cell.cell_id,
        "earfcn": cell.earfcn, "tac": cell.tac,
        "pci": cell.pci, "root_sequence_id": cell.root_sequence_id,
        "mimo": cell.mimo, "bandwidth": cell.bandwidth,
        "cell_max_power": cell.cell_max_power, "eci": cell.eci,
        "bbu_name": cell.bbu_name, "cell_status": cell.cell_status,
    }


def _cell5g_snapshot(cell: Cell5G) -> Dict[str, Any]:
    return {
        "site_name":        cell.site_name,
        "site_name_old":    cell.site_name_old,
        "cell_name":        cell.cell_name,
        "cell_name_old":    cell.cell_name_old,
        "mien":             cell.mien,
        "tinh":             cell.tinh,
        "phuong_xa":        cell.phuong_xa,
        "cell_vip":         cell.cell_vip,
        "moran":            cell.moran,
        "lat":              cell.lat,
        "long":             cell.long,
        "vung_phu_song":    cell.vung_phu_song,
        "vendor":           cell.vendor,
        "do_cao_anten":     cell.do_cao_anten,
        "azimuth":          cell.azimuth,
        "m_tilt":           cell.m_tilt,
        "e_tilt":           cell.e_tilt,
        "total_tilt":       cell.total_tilt,
        "loai_anten":       cell.loai_anten,
        "baseband":         cell.baseband,
        "rf":               cell.rf,
        "gnodeb_id":        cell.gnodeb_id,
        "cell_id":          cell.cell_id,
        "tac":              cell.tac,
        "pci":              cell.pci,
        "root_sequence_id": cell.root_sequence_id,
        "mimo":             cell.mimo,
        "ssb_arfcn":        cell.ssb_arfcn,
        "center_arfcn":     cell.center_arfcn,
        "gscn":             cell.gscn,
        "bandwidth":        cell.bandwidth,
        "cell_max_power":   cell.cell_max_power,
        "nci":              cell.nci,
        "bbu_name":         cell.bbu_name,
        "mu_mimo":          cell.mu_mimo,
        "cell_status":      cell.cell_status,
    }


# ── Public record_* functions ─────────────────────────────────────────────────

def record_site_revision(
    db: Session, site: Site, old_snapshot: Optional[Dict],
    changed_by_id: Optional[int], changed_by_name: Optional[str],
    change_source: str = "form", change_note: Optional[str] = None,
    site_name_old_ref: Optional[str] = None,
) -> Optional[SiteRevision]:
    new_snap = _site_snapshot(site)
    if old_snapshot is None:
        diff: Dict = {}
    else:
        diff = _diff(old_snapshot, new_snap)
        if not diff:
            return None

    rev = SiteRevision(
        site_id=site.id, site_name=site.site_name,
        revision_no=_next_rev_no_site(db, site.id),
        changed_by=changed_by_id, changed_by_name=changed_by_name,
        change_source=change_source, change_note=change_note,
        site_name_old_ref=site_name_old_ref,
        mien=site.mien, tinh=site.tinh, phuong_xa=site.phuong_xa,
        site_name_cu=site.site_name_cu, site_vip=site.site_vip,
        lat=site.lat, long=site.long,
        tram_2g=_safe_bool(site.tram_2g), tram_3g=_safe_bool(site.tram_3g),
        tram_4g=_safe_bool(site.tram_4g), tram_5g=_safe_bool(site.tram_5g),
        repeater=_safe_bool(site.repeater), booster=_safe_bool(site.booster),
        node_truyen_dan_only=_safe_bool(site.node_truyen_dan_only),
        tram_phu_song_tsca=_safe_bool(site.tram_phu_song_tsca),
        phan_loai_tram=site.phan_loai_tram,
        moran_3g=site.moran_3g, moran_4g=site.moran_4g,
        moran_5g=site.moran_5g, ma_ptm=site.ma_ptm,
        do_cao_dinh_cot_anten=site.do_cao_dinh_cot_anten,
        do_cao_cot_anten=site.do_cao_cot_anten,
        dia_chi=site.dia_chi, ghi_chu=site.ghi_chu,
        changed_fields=json.dumps(diff, ensure_ascii=False, default=str),
    )
    db.add(rev)
    return rev


def record_cell3g_revision(
    db: Session, cell: Cell3G, old_snapshot: Optional[Dict],
    changed_by_id: Optional[int], changed_by_name: Optional[str],
    change_source: str = "form", change_note: Optional[str] = None,
) -> Optional[Cell3GRevision]:
    new_snap = _cell3g_snapshot(cell)
    if old_snapshot is None:
        diff: Dict = {}
    else:
        diff = _diff(old_snapshot, new_snap)
        if not diff:
            return None

    rev = Cell3GRevision(
        cell_id_ref=cell.id, site_id=cell.site_id,
        site_name=cell.site_name, cell_name=cell.cell_name,
        revision_no=_next_rev_no_cell3g(db, cell.id),
        changed_by=changed_by_id, changed_by_name=changed_by_name,
        change_source=change_source, change_note=change_note,
        mien=cell.mien, tinh=cell.tinh, phuong_xa=cell.phuong_xa,
        site_name_old=cell.site_name_old, cell_name_old=cell.cell_name_old,
        cell_vip=cell.cell_vip, moran=cell.moran,
        lat=cell.lat, long=cell.long,
        vung_phu_song=cell.vung_phu_song, vendor=cell.vendor,
        rnc_name=cell.rnc_name,
        do_cao_anten=cell.do_cao_anten, azimuth=cell.azimuth,
        m_tilt=cell.m_tilt, e_tilt=cell.e_tilt, total_tilt=cell.total_tilt,
        loai_anten=cell.loai_anten, chung_anten=cell.chung_anten,
        baseband=cell.baseband, rf=cell.rf, cell_id=cell.cell_id,
        arfcn=cell.arfcn, uarfcn=cell.uarfcn,
        lac=cell.lac, rac=cell.rac,
        psc=cell.psc, ura_id=cell.ura_id, mimo=cell.mimo,
        cell_max_power=cell.cell_max_power, cpich_power=cell.cpich_power,
        bbu_name=cell.bbu_name, cell_status=cell.cell_status,
        changed_fields=json.dumps(diff, ensure_ascii=False, default=str),
    )
    db.add(rev)
    return rev


def record_cell4g_revision(
    db: Session, cell: Cell4G, old_snapshot: Optional[Dict],
    changed_by_id: Optional[int], changed_by_name: Optional[str],
    change_source: str = "form", change_note: Optional[str] = None,
) -> Optional[Cell4GRevision]:
    new_snap = _cell4g_snapshot(cell)
    if old_snapshot is None:
        diff: Dict = {}
    else:
        diff = _diff(old_snapshot, new_snap)
        if not diff:
            return None

    rev = Cell4GRevision(
        cell_id_ref=cell.id, site_id=cell.site_id,
        site_name=cell.site_name, cell_name=cell.cell_name,
        revision_no=_next_rev_no_cell4g(db, cell.id),
        changed_by=changed_by_id, changed_by_name=changed_by_name,
        change_source=change_source, change_note=change_note,
        mien=cell.mien, tinh=cell.tinh, phuong_xa=cell.phuong_xa,
        site_name_old=cell.site_name_old, cell_name_old=cell.cell_name_old,
        cell_vip=cell.cell_vip, moran=cell.moran,
        lat=cell.lat, long=cell.long,
        vung_phu_song=cell.vung_phu_song, vendor=cell.vendor,
        do_cao_anten=cell.do_cao_anten, azimuth=cell.azimuth,
        m_tilt=cell.m_tilt, e_tilt=cell.e_tilt, total_tilt=cell.total_tilt,
        loai_anten=cell.loai_anten, chung_anten=cell.chung_anten,
        baseband=cell.baseband, rf=cell.rf,
        enodeb_id=cell.enodeb_id, cell_id=cell.cell_id,
        earfcn=cell.earfcn, tac=cell.tac,
        pci=cell.pci, root_sequence_id=cell.root_sequence_id,
        mimo=cell.mimo, bandwidth=cell.bandwidth,
        cell_max_power=cell.cell_max_power, eci=cell.eci,
        bbu_name=cell.bbu_name, cell_status=cell.cell_status,
        changed_fields=json.dumps(diff, ensure_ascii=False, default=str),
    )
    db.add(rev)
    return rev


def record_cell5g_revision(
    db: Session, cell: Cell5G, old_snapshot: Optional[Dict],
    changed_by_id: Optional[int], changed_by_name: Optional[str],
    change_source: str = "form", change_note: Optional[str] = None,
) -> Optional[Cell5GRevision]:
    new_snap = _cell5g_snapshot(cell)
    if old_snapshot is None:
        diff: Dict = {}
    else:
        diff = _diff(old_snapshot, new_snap)
        if not diff:
            return None

    rev = Cell5GRevision(
        cell_id_ref=cell.id, site_id=cell.site_id,
        site_name=cell.site_name, cell_name=cell.cell_name,
        revision_no=_next_rev_no_cell5g(db, cell.id),
        changed_by=changed_by_id, changed_by_name=changed_by_name,
        change_source=change_source, change_note=change_note,
        mien=cell.mien, tinh=cell.tinh, phuong_xa=cell.phuong_xa,
        site_name_old=cell.site_name_old, cell_name_old=cell.cell_name_old,
        cell_vip=cell.cell_vip, moran=cell.moran,
        lat=cell.lat, long=cell.long,
        vung_phu_song=cell.vung_phu_song, vendor=cell.vendor,
        do_cao_anten=cell.do_cao_anten, azimuth=cell.azimuth,
        m_tilt=cell.m_tilt, e_tilt=cell.e_tilt, total_tilt=cell.total_tilt,
        loai_anten=cell.loai_anten,
        baseband=cell.baseband, rf=cell.rf,
        gnodeb_id=cell.gnodeb_id, cell_id=cell.cell_id,
        tac=cell.tac, pci=cell.pci,
        root_sequence_id=cell.root_sequence_id, mimo=cell.mimo,
        ssb_arfcn=cell.ssb_arfcn, center_arfcn=cell.center_arfcn,
        gscn=cell.gscn, bandwidth=cell.bandwidth,
        cell_max_power=cell.cell_max_power, nci=cell.nci,
        bbu_name=cell.bbu_name, mu_mimo=cell.mu_mimo,
        cell_status=cell.cell_status,
        changed_fields=json.dumps(diff, ensure_ascii=False, default=str),
    )
    db.add(rev)
    return rev
PYEOF

echo "[8/14] Updated backend/app/services/revision.py"

# ─────────────────────────────────────────────────────────────────────────────
# 9. BACKEND: Update export route to include rnc_name in 3G export
# ─────────────────────────────────────────────────────────────────────────────

cat > backend/app/api/routes/export.py << 'PYEOF'
"""
export.py – Excel export endpoints (Sites, Cells 3G/4G/5G, Antennas)
Token can be passed as Bearer header OR ?token= query param.
"""
from __future__ import annotations

import io
from typing import List, Optional

import openpyxl
from openpyxl.styles import PatternFill, Font, Alignment, Border, Side
from openpyxl.utils import get_column_letter
from fastapi import APIRouter, Depends, Query, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.site import Site
from app.models.cell_3g import Cell3G
from app.models.cell_4g import Cell4G
from app.models.cell_5g import Cell5G
from app.models.antenna import Antenna
from app.models.user import User
from app.core.security import decode_access_token

router = APIRouter()

HEADER_FILL = PatternFill("solid", fgColor="1F4E79")
HEADER_FONT = Font(color="FFFFFF", bold=True, size=10)
CENTER      = Alignment(horizontal="center", vertical="center", wrap_text=True)
LEFT        = Alignment(horizontal="left",   vertical="center")
THIN        = Side(style="thin", color="D0D0D0")
BORDER      = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)
ALT_FILL    = PatternFill("solid", fgColor="EBF3FB")


def _make_wb(headers):
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.row_dimensions[1].height = 30
    ws.freeze_panes = "A2"
    for col_idx, (header, width) in enumerate(headers, start=1):
        cell = ws.cell(row=1, column=col_idx, value=header)
        cell.fill = HEADER_FILL; cell.font = HEADER_FONT
        cell.alignment = CENTER; cell.border = BORDER
        ws.column_dimensions[get_column_letter(col_idx)].width = width
    return wb, ws


def _style_row(ws, row_idx, num_cols, alternate):
    fill = ALT_FILL if alternate else None
    for col_idx in range(1, num_cols + 1):
        cell = ws.cell(row=row_idx, column=col_idx)
        cell.alignment = LEFT; cell.border = BORDER
        if fill: cell.fill = fill


def _stream(wb, filename):
    buf = io.BytesIO()
    wb.save(buf); buf.seek(0)
    return StreamingResponse(
        iter([buf.read()]),
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


from fastapi.security import OAuth2PasswordBearer
oauth2_optional = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login", auto_error=False)


def get_optional_user(
    token_header: Optional[str] = Depends(oauth2_optional),
    token_param:  Optional[str] = Query(None, alias="token"),
    db: Session = Depends(get_db),
) -> User:
    raw = token_header or token_param
    if not raw:
        raise HTTPException(status_code=401, detail="Not authenticated")
    payload = decode_access_token(raw)
    if not payload:
        raise HTTPException(status_code=401, detail="Invalid token")
    user = db.query(User).filter(User.username == payload.get("sub")).first()
    if not user or not user.is_active:
        raise HTTPException(status_code=401, detail="User inactive")
    return user


@router.get("/sites")
def export_sites(
    search:       Optional[str]        = Query(None),
    site_name_cu: Optional[str]        = Query(None),
    mien:         Optional[List[str]]  = Query(None),
    tinh:         Optional[List[str]]  = Query(None),
    phuong_xa:    Optional[List[str]]  = Query(None),
    tram_3g:      Optional[bool]       = Query(None),
    tram_4g:      Optional[bool]       = Query(None),
    tram_5g:      Optional[bool]       = Query(None),
    db:           Session              = Depends(get_db),
    _:            User                 = Depends(get_optional_user),
):
    q = db.query(Site)
    if search:       q = q.filter(Site.site_name.ilike(f"%{search}%"))
    if site_name_cu: q = q.filter(Site.site_name_cu.ilike(f"%{site_name_cu}%"))
    if mien:         q = q.filter(Site.mien.in_(mien))
    if tinh:         q = q.filter(Site.tinh.in_(tinh))
    if phuong_xa:    q = q.filter(Site.phuong_xa.in_(phuong_xa))
    if tram_3g is not None: q = q.filter(Site.tram_3g == tram_3g)
    if tram_4g is not None: q = q.filter(Site.tram_4g == tram_4g)
    if tram_5g is not None: q = q.filter(Site.tram_5g == tram_5g)
    sites = q.order_by(Site.mien, Site.tinh, Site.site_name).all()

    headers = [
        ("STT", 6), ("Mien", 8), ("Tinh", 22), ("Phuong xa", 22),
        ("Site name (cu)", 22), ("Site name", 25), ("Site VIP", 10),
        ("Lat", 14), ("Long", 14), ("Tram 2G", 10), ("Tram 3G", 10),
        ("Tram 4G", 10), ("Tram 5G", 10), ("Repeater", 10), ("Booster", 10),
        ("Node truyen dan only", 20), ("Tram phu song TSCA", 18),
        ("Phan loai tram", 22), ("MORAN 3G", 15), ("MORAN 4G", 15),
        ("MORAN 5G", 15), ("Ma PTM", 14), ("Do cao dinh cot anten (m)", 22),
        ("Do cao cot anten (m)", 20), ("Dia chi", 30), ("Ghi chu", 30),
    ]
    wb, ws = _make_wb(headers)

    def _safe_bool_export(v) -> bool:
        if v is None: return False
        if isinstance(v, bool): return v
        if isinstance(v, int): return v != 0
        if isinstance(v, str): return v.strip().lower() not in ("false", "0", "no", "off", "")
        return bool(v)

    def b(val): return "x" if _safe_bool_export(val) else ""
    for idx, s in enumerate(sites, start=1):
        row = idx + 1
        values = [
            idx, s.mien, s.tinh, s.phuong_xa, s.site_name_cu, s.site_name,
            s.site_vip, s.lat, s.long,
            b(s.tram_2g), b(s.tram_3g), b(s.tram_4g), b(s.tram_5g),
            b(s.repeater), b(s.booster), b(s.node_truyen_dan_only), b(s.tram_phu_song_tsca),
            s.phan_loai_tram, s.moran_3g, s.moran_4g, s.moran_5g, s.ma_ptm,
            s.do_cao_dinh_cot_anten, s.do_cao_cot_anten, s.dia_chi, s.ghi_chu,
        ]
        for col_idx, val in enumerate(values, start=1):
            ws.cell(row=row, column=col_idx, value=val)
        _style_row(ws, row, len(headers), idx % 2 == 0)
    ws.auto_filter.ref = f"A1:{get_column_letter(len(headers))}1"
    return _stream(wb, "Sites_Export.xlsx")


@router.get("/cells-3g")
def export_cells_3g(
    search:        Optional[str]       = Query(None),
    cell_name_old: Optional[str]       = Query(None),
    mien:          Optional[List[str]] = Query(None),
    tinh:          Optional[List[str]] = Query(None),
    phuong_xa:     Optional[List[str]] = Query(None),
    vendor:        Optional[List[str]] = Query(None),
    mimo:          Optional[List[str]] = Query(None),
    vung_phu_song: Optional[List[str]] = Query(None),
    db:    Session = Depends(get_db),
    _:     User    = Depends(get_optional_user),
):
    q = db.query(Cell3G)
    if search:        q = q.filter(Cell3G.cell_name.ilike(f"%{search}%") | Cell3G.site_name.ilike(f"%{search}%"))
    if cell_name_old: q = q.filter(Cell3G.cell_name_old.ilike(f"%{cell_name_old}%"))
    if mien:          q = q.filter(Cell3G.mien.in_(mien))
    if tinh:          q = q.filter(Cell3G.tinh.in_(tinh))
    if phuong_xa:     q = q.filter(Cell3G.phuong_xa.in_(phuong_xa))
    if vendor:        q = q.filter(Cell3G.vendor.in_(vendor))
    if mimo:          q = q.filter(Cell3G.mimo.in_(mimo))
    if vung_phu_song: q = q.filter(Cell3G.vung_phu_song.in_(vung_phu_song))
    cells = q.order_by(Cell3G.mien, Cell3G.tinh, Cell3G.site_name, Cell3G.cell_name).all()
    headers = [
        ("STT", 6), ("Mien", 8), ("Tinh", 22), ("Phuong xa", 22),
        ("Site Name", 25), ("Site Name Old", 22), ("Cell Name", 25), ("Cell Name Old", 22),
        ("Cell VIP", 10), ("MORAN", 15), ("Lat", 14), ("Long", 14),
        ("Vung phu song", 15), ("Vendor", 14), ("RNC Name", 18),
        ("Do cao anten", 15),
        ("Azimuth", 10), ("M-tilt", 10), ("E-Tilt", 10), ("Total Tilt", 12),
        ("Loai Anten", 30), ("Chung anten", 18), ("Baseband", 18), ("RF", 14),
        ("Cell ID", 14), ("UARFCN", 12), ("LAC", 10), ("RAC", 10),
        ("PSC", 10), ("MIMO", 10), ("URAId", 10),
        ("Cell max power (dBm)", 20), ("CPICH power (dBm)", 18),
        ("BBUname", 16), ("Cell status (at dump time)", 24),
    ]
    wb, ws = _make_wb(headers)
    for idx, c in enumerate(cells, start=1):
        row = idx + 1
        values = [
            idx, c.mien, c.tinh, c.phuong_xa,
            c.site_name, c.site_name_old, c.cell_name, c.cell_name_old,
            c.cell_vip, c.moran, c.lat, c.long,
            c.vung_phu_song, c.vendor, c.rnc_name, c.do_cao_anten,
            c.azimuth, c.m_tilt, c.e_tilt, c.total_tilt,
            c.loai_anten, c.chung_anten, c.baseband, c.rf,
            c.cell_id, c.uarfcn, c.lac, c.rac,
            c.psc, c.mimo, c.ura_id,
            c.cell_max_power, c.cpich_power, c.bbu_name, c.cell_status,
        ]
        for col_idx, val in enumerate(values, start=1):
            ws.cell(row=row, column=col_idx, value=val)
        _style_row(ws, row, len(headers), idx % 2 == 0)
    ws.auto_filter.ref = f"A1:{get_column_letter(len(headers))}1"
    return _stream(wb, "Cells_3G_Export.xlsx")


@router.get("/cells-4g")
def export_cells_4g(
    search:        Optional[str]       = Query(None),
    cell_name_old: Optional[str]       = Query(None),
    mien:          Optional[List[str]] = Query(None),
    tinh:          Optional[List[str]] = Query(None),
    phuong_xa:     Optional[List[str]] = Query(None),
    vendor:        Optional[List[str]] = Query(None),
    mimo:          Optional[List[str]] = Query(None),
    vung_phu_song: Optional[List[str]] = Query(None),
    db:    Session = Depends(get_db),
    _:     User    = Depends(get_optional_user),
):
    q = db.query(Cell4G)
    if search:        q = q.filter(Cell4G.cell_name.ilike(f"%{search}%") | Cell4G.site_name.ilike(f"%{search}%"))
    if cell_name_old: q = q.filter(Cell4G.cell_name_old.ilike(f"%{cell_name_old}%"))
    if mien:          q = q.filter(Cell4G.mien.in_(mien))
    if tinh:          q = q.filter(Cell4G.tinh.in_(tinh))
    if phuong_xa:     q = q.filter(Cell4G.phuong_xa.in_(phuong_xa))
    if vendor:        q = q.filter(Cell4G.vendor.in_(vendor))
    if mimo:          q = q.filter(Cell4G.mimo.in_(mimo))
    if vung_phu_song: q = q.filter(Cell4G.vung_phu_song.in_(vung_phu_song))
    cells = q.order_by(Cell4G.mien, Cell4G.tinh, Cell4G.site_name, Cell4G.cell_name).all()
    headers = [
        ("STT", 6), ("Mien", 8), ("Tinh", 22), ("Phuong xa", 22),
        ("Site Name", 25), ("Site Name Old", 22), ("Cell Name", 25), ("Cell Name Old", 22),
        ("Cell VIP", 10), ("MORAN", 15), ("Lat", 14), ("Long", 14),
        ("Vung phu song", 15), ("Vendor", 14), ("Do cao anten", 15),
        ("Azimuth", 10), ("M-tilt", 10), ("E-Tilt", 10), ("Total Tilt", 12),
        ("Loai Anten", 30), ("Chung anten", 18), ("Baseband", 18), ("RF", 14),
        ("EnodeB ID", 14), ("Cell ID", 14), ("EARFCN", 12), ("TAC", 10),
        ("PCI", 10), ("Root Sequence ID", 18), ("MIMO", 10), ("Bandwidth", 12),
        ("Cell max power (dBm)", 20), ("ECI", 12),
        ("BBUname", 16), ("Cell status (at dump time)", 24),
    ]
    wb, ws = _make_wb(headers)
    for idx, c in enumerate(cells, start=1):
        row = idx + 1
        values = [
            idx, c.mien, c.tinh, c.phuong_xa,
            c.site_name, c.site_name_old, c.cell_name, c.cell_name_old,
            c.cell_vip, c.moran, c.lat, c.long,
            c.vung_phu_song, c.vendor, c.do_cao_anten,
            c.azimuth, c.m_tilt, c.e_tilt, c.total_tilt,
            c.loai_anten, c.chung_anten, c.baseband, c.rf,
            c.enodeb_id, c.cell_id, c.earfcn, c.tac,
            c.pci, c.root_sequence_id, c.mimo, c.bandwidth,
            c.cell_max_power, c.eci, c.bbu_name, c.cell_status,
        ]
        for col_idx, val in enumerate(values, start=1):
            ws.cell(row=row, column=col_idx, value=val)
        _style_row(ws, row, len(headers), idx % 2 == 0)
    ws.auto_filter.ref = f"A1:{get_column_letter(len(headers))}1"
    return _stream(wb, "Cells_4G_Export.xlsx")


@router.get("/cells-5g")
def export_cells_5g(
    search:        Optional[str]       = Query(None),
    cell_name_old: Optional[str]       = Query(None),
    mien:          Optional[List[str]] = Query(None),
    tinh:          Optional[List[str]] = Query(None),
    phuong_xa:     Optional[List[str]] = Query(None),
    vendor:        Optional[List[str]] = Query(None),
    mimo:          Optional[List[str]] = Query(None),
    vung_phu_song: Optional[List[str]] = Query(None),
    db:    Session = Depends(get_db),
    _:     User    = Depends(get_optional_user),
):
    q = db.query(Cell5G)
    if search:        q = q.filter(Cell5G.cell_name.ilike(f"%{search}%") | Cell5G.site_name.ilike(f"%{search}%"))
    if cell_name_old: q = q.filter(Cell5G.cell_name_old.ilike(f"%{cell_name_old}%"))
    if mien:          q = q.filter(Cell5G.mien.in_(mien))
    if tinh:          q = q.filter(Cell5G.tinh.in_(tinh))
    if phuong_xa:     q = q.filter(Cell5G.phuong_xa.in_(phuong_xa))
    if vendor:        q = q.filter(Cell5G.vendor.in_(vendor))
    if mimo:          q = q.filter(Cell5G.mimo.in_(mimo))
    if vung_phu_song: q = q.filter(Cell5G.vung_phu_song.in_(vung_phu_song))
    cells = q.order_by(Cell5G.mien, Cell5G.tinh, Cell5G.site_name, Cell5G.cell_name).all()
    headers = [
        ("STT", 6), ("Mien", 8), ("Tinh", 22), ("Phuong xa", 22),
        ("Site Name", 25), ("Site Name Old", 22), ("Cell Name", 25), ("Cell Name Old", 22),
        ("Cell VIP", 10), ("MORAN", 15), ("Lat", 14), ("Long", 14),
        ("Vung phu song", 15), ("Vendor", 14), ("Do cao anten", 15),
        ("Azimuth", 10), ("M-tilt", 10), ("E-Tilt", 10), ("Total Tilt", 12),
        ("Loai Anten", 30), ("Baseband", 18), ("RF", 14),
        ("gNodeB ID", 14), ("Cell ID", 14), ("TAC", 10),
        ("PCI", 10), ("Root Sequence ID", 18), ("MIMO", 10),
        ("SSB-ARFCN", 12), ("Center-ARFCN", 14), ("GSCN", 10),
        ("Bandwidth (MHz)", 14), ("Cell max power (dBm)", 20), ("NCI", 12),
        ("BBUname", 16), ("MU-MIMO", 10), ("Cell status (at dump time)", 24),
    ]
    wb, ws = _make_wb(headers)
    for idx, c in enumerate(cells, start=1):
        row = idx + 1
        values = [
            idx, c.mien, c.tinh, c.phuong_xa,
            c.site_name, c.site_name_old, c.cell_name, c.cell_name_old,
            c.cell_vip, c.moran, c.lat, c.long,
            c.vung_phu_song, c.vendor, c.do_cao_anten,
            c.azimuth, c.m_tilt, c.e_tilt, c.total_tilt,
            c.loai_anten, c.baseband, c.rf,
            c.gnodeb_id, c.cell_id, c.tac,
            c.pci, c.root_sequence_id, c.mimo,
            c.ssb_arfcn, c.center_arfcn, c.gscn,
            c.bandwidth, c.cell_max_power, c.nci,
            c.bbu_name, c.mu_mimo, c.cell_status,
        ]
        for col_idx, val in enumerate(values, start=1):
            ws.cell(row=row, column=col_idx, value=val)
        _style_row(ws, row, len(headers), idx % 2 == 0)
    ws.auto_filter.ref = f"A1:{get_column_letter(len(headers))}1"
    return _stream(wb, "Cells_5G_Export.xlsx")


@router.get("/antennas")
def export_antennas(
    search:    Optional[str]  = Query(None),
    band:      Optional[str]  = Query(None),
    is_5g_aau: Optional[bool] = Query(None),
    db:        Session        = Depends(get_db),
    _:         User           = Depends(get_optional_user),
):
    q = db.query(Antenna)
    if search:    q = q.filter(Antenna.name.ilike(f"%{search}%"))
    if band:      q = q.filter(Antenna.band.ilike(f"%{band}%"))
    if is_5g_aau is not None: q = q.filter(Antenna.is_5g_aau == is_5g_aau)
    antennas = q.order_by(Antenna.name).all()
    headers = [
        ("STT", 6), ("Name", 35), ("Band", 20), ("5G AAU", 10),
        ("No of Ports", 12), ("No of Beam", 12), ("Horizontal BW", 14),
        ("Vertical BW", 12), ("Gain (dBi)", 12), ("Etilt range", 14),
        ("H (mm)", 10), ("W (mm)", 10), ("D (mm)", 10),
        ("Weight (kg)", 12), ("Connector type", 18),
        ("Spec File", 30), ("Ghi chu", 30),
    ]
    wb, ws = _make_wb(headers)
    for idx, a in enumerate(antennas, start=1):
        row = idx + 1
        values = [
            idx, a.name, a.band, "x" if a.is_5g_aau else "",
            a.no_of_ports, a.no_of_beam, a.horizontal_bw, a.vertical_bw,
            a.gain, a.etilt, a.h, a.w, a.d, a.weight, a.connector_type,
            a.spec_file_name or "", a.ghi_chu,
        ]
        for col_idx, val in enumerate(values, start=1):
            ws.cell(row=row, column=col_idx, value=val)
        _style_row(ws, row, len(headers), idx % 2 == 0)
    ws.auto_filter.ref = f"A1:{get_column_letter(len(headers))}1"
    return _stream(wb, "Antennas_Export.xlsx")
PYEOF

echo "[9/14] Updated backend/app/api/routes/export.py"

# ─────────────────────────────────────────────────────────────────────────────
# 10. BACKEND: Update import_excel.py to handle rnc_name column
# ─────────────────────────────────────────────────────────────────────────────

# We patch only the parse_cell3g_excel function's extra fields
# by replacing the entire function at the bottom of import_excel.py
# We rewrite the file with the rnc_name addition in the extra() lambda

python3 - << 'PYEOF'
import re

with open("backend/app/services/import_excel.py", "r") as f:
    content = f.read()

old_fn = '''def parse_cell3g_excel(file_bytes, db=None, dry_run=False):
    from app.models.cell_3g import Cell3G
    def extra(row, excel_cols):
        return {
            "chung_anten": _v_aware(row, excel_cols, "Chung anten", "chung_anten"),
            "arfcn":       _v_aware(row, excel_cols, "ARFCN", "arfcn"),
            "uarfcn":      _v_aware(row, excel_cols, "UARFCN", "uarfcn"),
            "lac":         _v_aware(row, excel_cols, "LAC", "lac"),
            "rac":         _v_aware(row, excel_cols, "RAC", "rac"),
            "psc":         _v_aware(row, excel_cols, "PSC", "psc"),
            "ura_id":      _v_aware(row, excel_cols, "URAId", "URA ID", "ura_id"),
            "cpich_power": _v_aware(row, excel_cols, "CPICH power (dBm)",
                                     "CPICH power", "cpich_power"),
        }
    return _parse_cell_excel(file_bytes, Cell3G, extra, db=db, dry_run=dry_run)'''

new_fn = '''def parse_cell3g_excel(file_bytes, db=None, dry_run=False):
    from app.models.cell_3g import Cell3G
    def extra(row, excel_cols):
        return {
            "chung_anten": _v_aware(row, excel_cols, "Chung anten", "chung_anten"),
            "arfcn":       _v_aware(row, excel_cols, "ARFCN", "arfcn"),
            "uarfcn":      _v_aware(row, excel_cols, "UARFCN", "uarfcn"),
            "lac":         _v_aware(row, excel_cols, "LAC", "lac"),
            "rac":         _v_aware(row, excel_cols, "RAC", "rac"),
            "psc":         _v_aware(row, excel_cols, "PSC", "psc"),
            "ura_id":      _v_aware(row, excel_cols, "URAId", "URA ID", "ura_id"),
            "cpich_power": _v_aware(row, excel_cols, "CPICH power (dBm)",
                                     "CPICH power", "cpich_power"),
            "rnc_name":    _v_aware(row, excel_cols, "RNC Name", "RNC name",
                                     "RNCNAME", "rnc_name"),
        }
    return _parse_cell_excel(file_bytes, Cell3G, extra, db=db, dry_run=dry_run)'''

if old_fn in content:
    content = content.replace(old_fn, new_fn)
    with open("backend/app/services/import_excel.py", "w") as f:
        f.write(content)
    print("Patched parse_cell3g_excel in import_excel.py")
else:
    print("WARNING: Could not find parse_cell3g_excel to patch - check manually")
PYEOF

echo "[10/14] Updated backend/app/services/import_excel.py"

# ─────────────────────────────────────────────────────────────────────────────
# 11. BACKEND: Update revision route to include rnc_name in 3G revisions
# ─────────────────────────────────────────────────────────────────────────────

python3 - << 'PYEOF'
with open("backend/app/api/routes/revision.py", "r") as f:
    content = f.read()

# Add rnc_name after vendor in the cell3g revision response
old_block = '''            "vendor":        r.vendor,
            "do_cao_anten":  r.do_cao_anten,
            "azimuth":       r.azimuth,
            "m_tilt":        r.m_tilt,
            "e_tilt":        r.e_tilt,
            "total_tilt":    r.total_tilt,
            "loai_anten":    r.loai_anten,
            "chung_anten":   r.chung_anten,
            "baseband":      r.baseband,
            "rf":            r.rf,
            "cell_id":       r.cell_id,
            # 3G-specific
            "arfcn":         r.arfcn,'''

new_block = '''            "vendor":        r.vendor,
            "rnc_name":      r.rnc_name,
            "do_cao_anten":  r.do_cao_anten,
            "azimuth":       r.azimuth,
            "m_tilt":        r.m_tilt,
            "e_tilt":        r.e_tilt,
            "total_tilt":    r.total_tilt,
            "loai_anten":    r.loai_anten,
            "chung_anten":   r.chung_anten,
            "baseband":      r.baseband,
            "rf":            r.rf,
            "cell_id":       r.cell_id,
            # 3G-specific
            "arfcn":         r.arfcn,'''

if old_block in content:
    content = content.replace(old_block, new_block)
    with open("backend/app/api/routes/revision.py", "w") as f:
        f.write(content)
    print("Patched revision.py with rnc_name")
else:
    print("WARNING: Could not patch revision.py - check manually")
PYEOF

echo "[11/14] Updated backend/app/api/routes/revision.py"

# ─────────────────────────────────────────────────────────────────────────────
# 12. FRONTEND: Add RNC API client
# ─────────────────────────────────────────────────────────────────────────────

cat > frontend/src/api/rnc.ts << 'TSEOF'
import api from './client'

export interface RncEntry {
  id: number
  vendor: string
  name: string
}

/** Fetch all RNC names, optionally filtered by vendor */
export const getRncNames = (vendor?: string): Promise<RncEntry[]> => {
  const params: Record<string, string> = {}
  if (vendor) params.vendor = vendor
  return api.get<RncEntry[]>('/api/v1/rnc/', { params }).then((r) => r.data)
}

/** Fetch all RNC names grouped by vendor: { ERICSSON: [...], HUAWEI: [...] } */
export const getRncNamesGrouped = (): Promise<Record<string, string[]>> =>
  api.get<Record<string, string[]>>('/api/v1/rnc/all').then((r) => r.data)
TSEOF

echo "[12/14] Created frontend/src/api/rnc.ts"

# ─────────────────────────────────────────────────────────────────────────────
# 13. FRONTEND: Update types/index.ts to add rnc_name to Cell3G
# ─────────────────────────────────────────────────────────────────────────────

python3 - << 'PYEOF'
with open("frontend/src/types/index.ts", "r") as f:
    content = f.read()

old_cell3g = '''export interface Cell3G extends CellBase {
  chung_anten?: string
  arfcn?: string
  uarfcn?: string
  lac?: string
  rac?: string
  psc?: string
  ura_id?: string
  cpich_power?: string
}'''

new_cell3g = '''export interface Cell3G extends CellBase {
  chung_anten?: string
  arfcn?: string
  uarfcn?: string
  lac?: string
  rac?: string
  psc?: string
  ura_id?: string
  cpich_power?: string
  rnc_name?: string
}'''

if old_cell3g in content:
    content = content.replace(old_cell3g, new_cell3g)
    with open("frontend/src/types/index.ts", "w") as f:
        f.write(content)
    print("Patched Cell3G type in types/index.ts")
else:
    print("WARNING: Could not patch Cell3G type - check manually")
PYEOF

echo "[13/14] Updated frontend/src/types/index.ts"

# ─────────────────────────────────────────────────────────────────────────────
# 14. FRONTEND: Rewrite Cells3GPage.tsx with full rnc_name support
# ─────────────────────────────────────────────────────────────────────────────

cat > frontend/src/pages/cells/Cells3GPage.tsx << 'TSEOF'
import React, { useEffect, useState, useCallback } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, message, Row, Col, Tooltip,
  Modal, Form, InputNumber,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import type { TableRowSelection } from 'antd/es/table/interface'
import {
  PlusOutlined, SearchOutlined, UploadOutlined,
  EditOutlined, DeleteOutlined, DownloadOutlined,
} from '@ant-design/icons'
import { cells3gApi } from '@/api/cells'
import { exportCells3G } from '@/api/export'
import { getRncNamesGrouped } from '@/api/rnc'
import type { Cell3G, Site, AntennaItem, TinhItem } from '@/types'
import { getSites } from '@/api/sites'
import { getAntennaList, getTinhList, getPhuongXaList } from '@/api/report'
import DryRunModal from '@/components/shared/DryRunModal'
import CellBulkEditModal from '@/components/shared/CellBulkEditModal'
import { latValidator, lonValidator, azimuthValidator } from '@/utils/validators'

const CHUNG_ANTEN_3G = ['3G', '3G/4G', '2G/3G/4G', '3G/4G/5G', '3G/5G']

export default function Cells3GPage() {
  const [data,          setData]          = useState<Cell3G[]>([])
  const [loading,       setLoading]       = useState(false)
  const [exporting,     setExporting]     = useState(false)
  const [search,        setSearch]        = useState('')
  const [cellNameOld,   setCellNameOld]   = useState('')
  const [mien,          setMien]          = useState<string[]>([])
  const [tinh,          setTinh]          = useState<string[]>([])
  const [phuongXa,      setPhuongXa]      = useState<string[]>([])
  const [phuongXaOpts,  setPhuongXaOpts]  = useState<string[]>([])
  const [vendor,        setVendor]        = useState<string[]>([])
  const [sites,         setSites]         = useState<Site[]>([])
  const [antennaList,   setAntennaList]   = useState<AntennaItem[]>([])
  const [tinhList,      setTinhList]      = useState<TinhItem[]>([])
  const [rncGrouped,    setRncGrouped]    = useState<Record<string, string[]>>({})
  const [rncOptions,    setRncOptions]    = useState<string[]>([])
  const [modalOpen,     setModalOpen]     = useState(false)
  const [editing,       setEditing]       = useState<Cell3G | null>(null)
  const [dryRunOpen,    setDryRunOpen]    = useState(false)
  const [selectedIds,   setSelectedIds]   = useState<number[]>([])
  const [bulkEditOpen,  setBulkEditOpen]  = useState(false)
  const [form] = Form.useForm()

  const tinhOptions   = tinhList.length > 0
    ? tinhList.map(t => t.ten_tinh)
    : [...new Set(data.map(c => c.tinh).filter(Boolean))].sort() as string[]
  const vendorOptions = [...new Set(data.map(c => c.vendor).filter(Boolean))].sort() as string[]

  useEffect(() => {
    setPhuongXa([])
    setPhuongXaOpts([])
    if (tinh.length === 1) {
      getPhuongXaList(tinh[0]).then(setPhuongXaOpts)
    }
  }, [tinh])

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const params: Record<string, unknown> = { limit: 1000 }
      if (search)          params.search        = search
      if (cellNameOld)     params.cell_name_old = cellNameOld
      if (mien.length)     params.mien          = mien
      if (tinh.length)     params.tinh          = tinh
      if (phuongXa.length) params.phuong_xa     = phuongXa
      if (vendor.length)   params.vendor        = vendor
      setData(await cells3gApi.list(params))
    } finally { setLoading(false) }
  }, [search, cellNameOld, mien, tinh, phuongXa, vendor])

  useEffect(() => {
    load()
    getSites({ limit: 2000 }).then(setSites)
    getTinhList().then(setTinhList)
    getAntennaList().then((list: AntennaItem[]) => {
      const sorted = [...list].sort((a, b) => {
        const aU = a.name.toUpperCase().includes('CHƯA XÁC ĐỊNH') || a.name.toUpperCase().includes('CHUA XAC DINH')
        const bU = b.name.toUpperCase().includes('CHƯA XÁC ĐỊNH') || b.name.toUpperCase().includes('CHUA XAC DINH')
        if (aU) return -1; if (bU) return 1; return 0
      })
      setAntennaList(sorted)
    })
    getRncNamesGrouped().then(setRncGrouped)
  }, [load])

  // When vendor field changes in the form, update RNC options
  const handleVendorChange = (value: string | undefined) => {
    form.setFieldValue('rnc_name', undefined)
    if (value && rncGrouped[value]) {
      setRncOptions(rncGrouped[value])
    } else {
      setRncOptions([])
    }
  }

  // When opening edit modal, populate RNC options based on existing vendor
  const openEdit = (r: Cell3G) => {
    setEditing(r)
    form.setFieldsValue(r)
    if (r.vendor && rncGrouped[r.vendor]) {
      setRncOptions(rncGrouped[r.vendor])
    } else {
      setRncOptions([])
    }
    setModalOpen(true)
  }

  const openCreate = () => {
    setEditing(null)
    form.resetFields()
    setRncOptions([])
    setModalOpen(true)
  }

  const handleExport = async () => {
    setExporting(true)
    try {
      await exportCells3G({
        search:        search || undefined,
        cell_name_old: cellNameOld || undefined,
        mien:          mien.length ? mien : undefined,
        tinh:          tinh.length ? tinh : undefined,
        phuong_xa:     phuongXa.length ? phuongXa : undefined,
        vendor:        vendor.length ? vendor : undefined,
      })
      message.success(`Xuất Excel thành công (${data.length} cells)`)
    } catch (e: any) { message.error(e?.message || 'Xuất thất bại')
    } finally { setExporting(false) }
  }

  const clearFilters = () => {
    setSearch(''); setCellNameOld(''); setMien([]); setTinh([]); setPhuongXa([]); setVendor([])
  }

  const handleSiteSelect = (siteId: number) => {
    const site = sites.find(s => s.id === siteId)
    if (site) form.setFieldValue('site_name', site.site_name)
  }

  const handleSave = async () => {
    const values = await form.validateFields()
    try {
      if (editing) { await cells3gApi.update(editing.id, values); message.success('Cập nhật thành công') }
      else         { await cells3gApi.create(values);             message.success('Tạo cell thành công') }
      setModalOpen(false); load()
    } catch (e: any) { message.error(e.response?.data?.detail || 'Có lỗi xảy ra') }
  }

  const handleDelete = async (id: number) => {
    await cells3gApi.remove(id); message.success('Đã xóa')
    setSelectedIds(prev => prev.filter(x => x !== id)); load()
  }

  const handleBulkDelete = async () => {
    const result = await cells3gApi.bulkDelete(selectedIds)
    if (result.deleted) message.success(`Đã xóa ${result.deleted} cell`)
    if (result.errors.length > 0) message.warning(`${result.errors.length} lỗi`)
    setSelectedIds([]); load()
  }

  const handleBulkEdit = async (changes: Record<string, unknown>) => {
    const result = await cells3gApi.bulkUpdate(selectedIds, changes)
    if (result.updated) message.success(`Đã cập nhật ${result.updated} cell`)
    if (result.errors && result.errors.length > 0) message.warning(`${result.errors.length} lỗi`)
    setSelectedIds([]); load()
  }

  const rowSelection: TableRowSelection<Cell3G> = {
    selectedRowKeys: selectedIds,
    onChange: keys => setSelectedIds(keys as number[]),
    selections: [Table.SELECTION_ALL, Table.SELECTION_INVERT, Table.SELECTION_NONE],
  }

  const columns: ColumnsType<Cell3G> = [
    { title: 'Hành động', key: 'action', fixed: 'left', width: 90,
      render: (_: unknown, r: Cell3G) => (
        <Space size={4}>
          <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(r)} />
          <Popconfirm title="Xóa cell này?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      )},
    { title: 'Miền',          dataIndex: 'mien',          fixed: 'left', width: 70 },
    { title: 'Tỉnh',          dataIndex: 'tinh',          fixed: 'left', width: 160 },
    { title: 'Phường/Xã',     dataIndex: 'phuong_xa',     width: 160 },
    { title: 'Site Name Old', dataIndex: 'site_name_old', width: 200, ellipsis: { showTitle: true } },
    { title: 'Cell Name Old', dataIndex: 'cell_name_old', width: 200, ellipsis: { showTitle: true } },
    { title: 'Site Name', dataIndex: 'site_name', fixed: 'left', width: 220,
      ellipsis: { showTitle: true }, render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell Name', dataIndex: 'cell_name', fixed: 'left', width: 220,
      ellipsis: { showTitle: true }, render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell VIP',  dataIndex: 'cell_vip',  width: 90,
      render: (v: string) => v ? <Tag color="gold">{v}</Tag> : '-' },
    { title: 'MORAN',    dataIndex: 'moran',         width: 120 },
    { title: 'Lat',      dataIndex: 'lat',           width: 110 },
    { title: 'Long',     dataIndex: 'long',          width: 110 },
    { title: 'Vùng phủ sóng', dataIndex: 'vung_phu_song', width: 120 },
    { title: 'Vendor',        dataIndex: 'vendor',         width: 100 },
    { title: 'RNC Name',      dataIndex: 'rnc_name',       width: 130,
      render: (v: string) => v ? <Tag color="cyan">{v}</Tag> : '-' },
    { title: 'Độ cao anten',  dataIndex: 'do_cao_anten',   width: 120 },
    { title: 'Azimuth',       dataIndex: 'azimuth',        width: 90 },
    { title: 'M-tilt',        dataIndex: 'm_tilt',         width: 80 },
    { title: 'E-Tilt',        dataIndex: 'e_tilt',         width: 80 },
    { title: 'Total Tilt',    dataIndex: 'total_tilt',     width: 100 },
    { title: 'Loại Anten',    dataIndex: 'loai_anten',     width: 250, ellipsis: { showTitle: true } },
    { title: 'Chung anten',   dataIndex: 'chung_anten',    width: 120 },
    { title: 'Baseband',      dataIndex: 'baseband',       width: 120 },
    { title: 'RF',            dataIndex: 'rf',             width: 100 },
    { title: 'Cell ID',       dataIndex: 'cell_id',        width: 100 },
    { title: 'UARFCN',        dataIndex: 'uarfcn',         width: 100 },
    { title: 'LAC',           dataIndex: 'lac',            width: 80 },
    { title: 'RAC',           dataIndex: 'rac',            width: 80 },
    { title: 'PSC',           dataIndex: 'psc',            width: 80 },
    { title: 'MIMO',          dataIndex: 'mimo',           width: 80,
      render: (v: string) => v ? <Tag color="blue">{v}</Tag> : '-' },
    { title: 'URAId',         dataIndex: 'ura_id',         width: 80 },
    { title: 'Cell max power (dBm)', dataIndex: 'cell_max_power', width: 160 },
    { title: 'CPICH power (dBm)',    dataIndex: 'cpich_power',    width: 150 },
    { title: 'BBUname',       dataIndex: 'bbu_name',       width: 130 },
    { title: 'Cell status',   dataIndex: 'cell_status',    width: 140 },
  ]

  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Cell 3G</Typography.Title>
        <Space>
          <Tooltip title="Xuất dữ liệu hiện tại ra Excel">
            <Button icon={<DownloadOutlined />} loading={exporting} onClick={handleExport}
                    style={{ borderColor: '#52c41a', color: '#52c41a' }}>
              Xuất Excel ({data.length})
            </Button>
          </Tooltip>
          <Button icon={<UploadOutlined />} onClick={() => setDryRunOpen(true)}>Import Excel</Button>
          <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>Thêm mới</Button>
        </Space>
      </Row>

      <Row gutter={8} style={{ marginBottom: 8 }}>
        <Col flex="240px">
          <Input prefix={<SearchOutlined />} placeholder="Tìm cell / site name..."
                 value={search} onChange={e => setSearch(e.target.value)} allowClear />
        </Col>
        <Col flex="240px">
          <Input prefix={<SearchOutlined />} placeholder="Tìm cell name (cũ)..."
                 value={cellNameOld} onChange={e => setCellNameOld(e.target.value)} allowClear />
        </Col>
        <Col flex="150px">
          <Select mode="multiple" placeholder="Miền" allowClear maxTagCount={2}
                  style={{ width: '100%' }} value={mien} onChange={setMien}>
            {['MB','MT','MN'].map(m => <Select.Option key={m} value={m}>{m}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="240px">
          <Select mode="multiple" placeholder="Tỉnh" allowClear showSearch maxTagCount={2}
                  style={{ width: '100%' }} value={tinh} onChange={setTinh}
                  filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
            {tinhOptions.map(t => <Select.Option key={t} value={t}>{t}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="200px">
          <Select mode="multiple" placeholder="Vendor" allowClear maxTagCount={2}
                  style={{ width: '100%' }} value={vendor} onChange={setVendor}>
            {vendorOptions.map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}
          </Select>
        </Col>
      </Row>

      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="320px">
          <Select
            mode="multiple"
            placeholder={
              tinh.length === 0
                ? 'Chọn tỉnh trước để lọc phường/xã'
                : tinh.length > 1
                ? 'Chọn 1 tỉnh để lọc phường/xã'
                : 'Lọc theo Phường/Xã...'
            }
            allowClear showSearch maxTagCount={3}
            style={{ width: '100%' }}
            value={phuongXa} onChange={setPhuongXa}
            disabled={tinh.length !== 1}
            filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}
          >
            {phuongXaOpts.map(p => <Select.Option key={p} value={p}>{p}</Select.Option>)}
          </Select>
        </Col>
        <Col>
          <Button onClick={clearFilters}>Xóa lọc</Button>
        </Col>
      </Row>

      {selectedIds.length > 0 && (
        <Row style={{ marginBottom: 12 }}>
          <Col>
            <Space style={{ background: '#e6f7ff', border: '1px solid #91d5ff', borderRadius: 6, padding: '8px 16px' }}>
              <Typography.Text strong>Đã chọn {selectedIds.length} cell</Typography.Text>
              <Button type="primary" icon={<EditOutlined />} onClick={() => setBulkEditOpen(true)}>Sửa hàng loạt</Button>
              <Popconfirm title={`Xóa ${selectedIds.length} cell đã chọn?`} onConfirm={handleBulkDelete}>
                <Button danger icon={<DeleteOutlined />}>Xóa hàng loạt</Button>
              </Popconfirm>
              <Button onClick={() => setSelectedIds([])}>Bỏ chọn</Button>
            </Space>
          </Col>
        </Row>
      )}

      <Table rowSelection={rowSelection} columns={columns} dataSource={data} rowKey="id"
             loading={loading} size="small" scroll={{ x: scrollX, y: 600 }} bordered
             pagination={{ pageSize: 50, showTotal: t => `${t} cells`, showSizeChanger: true }} />

      {/* ── Create / Edit Modal ── */}
      <Modal title={editing ? 'Chỉnh sửa Cell 3G' : 'Thêm Cell 3G mới'}
             open={modalOpen} onOk={handleSave} onCancel={() => { setModalOpen(false); setRncOptions([]) }}
             width={900} okText="Lưu" destroyOnClose>
        <Form form={form} layout="vertical">
          <Row gutter={12}>
            <Col span={12}>
              <Form.Item name="site_id" label="Site" rules={[{ required: !editing }]}>
                <Select showSearch optionFilterProp="children" allowClear placeholder="Chọn site..."
                        onChange={handleSiteSelect} disabled={Boolean(editing)}
                        filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                  {sites.map(s => <Select.Option key={s.id} value={s.id}>{s.site_name}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="site_name_old" label="Site Name Old"><Input /></Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="site_name" label="Site Name">
                <Input readOnly={!editing} style={!editing ? { background: '#f5f5f5' } : {}} />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="cell_name_old" label="Cell Name Old"><Input /></Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="cell_name" label="Cell Name" rules={[{ required: true }]}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="cell_vip" label="Cell VIP">
                <Select allowClear>
                  <Select.Option value="VIP">VIP</Select.Option>
                  <Select.Option value="VVIP">VVIP</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item name="moran" label="MORAN">
                <Select allowClear>
                  <Select.Option value="VNPT HOST">VNPT HOST</Select.Option>
                  <Select.Option value="MBF HOST">MBF HOST</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="lat" label="Lat" rules={[{ validator: latValidator }]}>
                <InputNumber style={{ width: '100%' }} precision={5} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="long" label="Long" rules={[{ validator: lonValidator }]}>
                <InputNumber style={{ width: '100%' }} precision={5} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="vung_phu_song" label="Vùng phủ sóng">
                <Select allowClear>
                  <Select.Option value="Indoor">Indoor</Select.Option>
                  <Select.Option value="Outdoor">Outdoor</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            {/* Vendor + RNC Name: cascading like province/ward */}
            <Col span={8}>
              <Form.Item name="vendor" label="Vendor">
                <Select allowClear onChange={handleVendorChange}>
                  {['Ericsson','Nokia','Huawei','ZTE','Samsung'].map(v => (
                    <Select.Option key={v} value={v}>{v}</Select.Option>
                  ))}
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="rnc_name" label="RNC Name">
                <Select
                  allowClear
                  showSearch
                  placeholder={
                    !form.getFieldValue('vendor')
                      ? 'Chọn Vendor trước'
                      : rncOptions.length === 0
                      ? 'Không có RNC cho vendor này'
                      : 'Chọn RNC Name...'
                  }
                  disabled={rncOptions.length === 0 && !form.getFieldValue('vendor')}
                  filterOption={(input, option) =>
                    String(option?.children ?? '').toLowerCase().includes(input.toLowerCase())
                  }
                >
                  {rncOptions.map(n => (
                    <Select.Option key={n} value={n}>{n}</Select.Option>
                  ))}
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="do_cao_anten" label="Độ cao anten (m)">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="azimuth" label="Azimuth (0–359)" rules={[{ validator: azimuthValidator }]}>
                <InputNumber style={{ width: '100%' }} min={0} max={359} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="m_tilt" label="M-tilt">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="e_tilt" label="E-Tilt">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="total_tilt" label="Total Tilt">
                <InputNumber style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={24}>
              <Form.Item name="loai_anten" label="Loại Anten">
                <Select showSearch allowClear
                        filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                  {antennaList.map(a => <Select.Option key={a.id} value={a.name}>{a.name}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}><Form.Item name="baseband" label="Baseband"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="rf" label="RF"><Input /></Form.Item></Col>
            <Col span={12}>
              <Form.Item name="chung_anten" label="Chung anten">
                <Select allowClear>
                  {CHUNG_ANTEN_3G.map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}><Form.Item name="cell_id" label="Cell ID"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="uarfcn" label="UARFCN"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="lac" label="LAC"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="rac" label="RAC"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="psc" label="PSC"><Input /></Form.Item></Col>
            <Col span={8}>
              <Form.Item name="mimo" label="MIMO">
                <Select allowClear>
                  {['2x2','4x4','8x8'].map(m => <Select.Option key={m} value={m}>{m}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}><Form.Item name="ura_id" label="URAId"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="cell_max_power" label="Cell max power (dBm)"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="cpich_power" label="CPICH power (dBm)"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="bbu_name" label="BBUname"><Input /></Form.Item></Col>
            <Col span={16}><Form.Item name="cell_status" label="Cell status (at dump time)"><Input /></Form.Item></Col>
          </Row>
        </Form>
      </Modal>

      <CellBulkEditModal
        open={bulkEditOpen}
        onClose={() => setBulkEditOpen(false)}
        count={selectedIds.length}
        tech="3g"
        antennaList={antennaList}
        onConfirm={handleBulkEdit}
      />

      <DryRunModal open={dryRunOpen} onClose={() => setDryRunOpen(false)}
        title="Import Cell 3G từ Excel" templateKey="cell-3g"
        dryRunFn={cells3gApi.dryRunExcel} importFn={cells3gApi.importExcel} onSuccess={load} />
    </div>
  )
}
TSEOF

echo "[14/14] Updated frontend/src/pages/cells/Cells3GPage.tsx"

# ─────────────────────────────────────────────────────────────────────────────
# 15. DATABASE: Apply schema changes via Docker exec
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "=== Applying database schema changes ==="

# Wait for postgres to be available
echo "Checking postgres container..."
if docker ps --format '{{.Names}}' | grep -q "sitelink_postgres"; then
    echo "Postgres container is running. Applying DDL..."

    docker exec sitelink_postgres psql \
        -U sitelink \
        -d sitelink_db \
        -c "
-- Add rnc_name to cells_3g if not exists
DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name='cells_3g' AND column_name='rnc_name'
    ) THEN
        ALTER TABLE cells_3g ADD COLUMN rnc_name VARCHAR(100);
    END IF;
END
\$\$;

-- Add rnc_name to cell_3g_revisions if not exists
DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name='cell_3g_revisions' AND column_name='rnc_name'
    ) THEN
        ALTER TABLE cell_3g_revisions ADD COLUMN rnc_name VARCHAR(100);
    END IF;
END
\$\$;

-- Create rnc_names table if not exists
CREATE TABLE IF NOT EXISTS rnc_names (
    id     SERIAL PRIMARY KEY,
    vendor VARCHAR(50) NOT NULL,
    name   VARCHAR(100) NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_rnc_names_vendor ON rnc_names(vendor);

-- Seed RNC data (only if empty)
INSERT INTO rnc_names (vendor, name)
SELECT v.vendor, v.name FROM (VALUES
    ('Ericsson','RHNCG1E'),('Ericsson','RHNCG2E'),('Ericsson','RHNCG3E'),
    ('Ericsson','RHNCG4E'),('Ericsson','RHNHM1E'),('Ericsson','RHNHM2E'),
    ('Ericsson','RHNHM3E'),('Ericsson','RQNHL1E'),('Ericsson','RQNHL2E'),
    ('Ericsson','RSG103E'),('Ericsson','RSG011E'),('Ericsson','RSG072E'),
    ('Ericsson','RSG091E'),('Ericsson','RSG092E'),('Ericsson','RSG093E'),
    ('Ericsson','RSG094E'),('Ericsson','RSG095E'),('Ericsson','RSG097E'),
    ('Ericsson','RSG104E'),('Ericsson','RSG105E'),('Ericsson','RSGBC2E'),
    ('Ericsson','RSGBI2E'),('Ericsson','RSGBT2E'),('Ericsson','RSGHM1E'),
    ('Ericsson','RSGTB2E'),
    ('Huawei','iHNCG1H'),('Huawei','iHNCG3H'),('Huawei','iHNHM1H'),
    ('Huawei','iHNHM2H'),('Huawei','iHNHM3H'),('Huawei','iHNHM5H'),
    ('Huawei','iHNHM6H'),('Huawei','iHNHM7H'),('Huawei','iHNHM8H'),
    ('Huawei','RHNCG1H'),('Huawei','RHNCG3H'),('Huawei','RHNCG4H'),
    ('Huawei','RHNHM3H'),('Huawei','RHNHM4H'),('Huawei','RHNHM5H'),
    ('Huawei','RHNHM6H'),('Huawei','RHNHM7H'),('Huawei','RHNHM8H'),
    ('Huawei','RDNG01H'),('Huawei','RDNG02H'),('Huawei','RQBDH1H'),
    ('Huawei','RCTCR11H'),('Huawei','RCTCR12H'),
    ('Nokia','RDNCL3N'),('Nokia','RDNCL4N'),('Nokia','RDNCL5N'),
    ('Nokia','RDNCL7N'),('Nokia','RDNCL8N'),('Nokia','RDNCL9N'),
    ('Nokia','RDNST10N'),('Nokia','RDNST12N'),('Nokia','RDNST13N'),
    ('Nokia','RDNST14N'),('Nokia','RDNST15N'),('Nokia','RDNST7N'),
    ('Nokia','RCTCR1N'),('Nokia','RCTCR2N'),('Nokia','RCTCR8N'),
    ('Nokia','RDNBH5N'),('Nokia','RSG091N'),('Nokia','RSG092N'),
    ('Nokia','RSG093N'),('Nokia','RSG094N'),('Nokia','RSG095N'),
    ('Nokia','RSG097N'),('Nokia','RSG098N'),('Nokia','RSG099N'),
    ('Nokia','RSG105N'),('Nokia','RTGMT3N'),
    ('ZTE','RCTCR3Z'),('ZTE','RCTCR4Z'),('ZTE','RCTCR5Z'),('ZTE','RCTCR6Z')
) AS v(vendor, name)
WHERE NOT EXISTS (SELECT 1 FROM rnc_names LIMIT 1);
"
    echo "Database schema updated successfully."
else
    echo "WARNING: sitelink_postgres container not running."
    echo "The DDL SQL above will be applied automatically when the backend starts"
    echo "via SQLAlchemy Base.metadata.create_all() and the seed function."
    echo "The ALTER TABLE statements need to be run manually if the DB already exists."
    echo ""
    echo "Run manually when postgres is available:"
    echo "  docker exec sitelink_postgres psql -U sitelink -d sitelink_db -c \"ALTER TABLE cells_3g ADD COLUMN IF NOT EXISTS rnc_name VARCHAR(100);\""
    echo "  docker exec sitelink_postgres psql -U sitelink -d sitelink_db -c \"ALTER TABLE cell_3g_revisions ADD COLUMN IF NOT EXISTS rnc_name VARCHAR(100);\""
fi

# ─────────────────────────────────────────────────────────────────────────────
# 16. Rebuild Docker containers
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "=== Rebuilding Docker containers ==="
docker compose build --no-cache backend frontend
docker compose up -d

echo ""
echo "=== All done! Summary of changes ==="
echo "Backend:"
echo "  - backend/app/models/rnc.py                   [NEW] RncName model"
echo "  - backend/app/models/cell_3g.py               [UPDATED] +rnc_name column"
echo "  - backend/app/models/cell_revision.py         [UPDATED] +rnc_name in Cell3GRevision"
echo "  - backend/app/schemas/cell.py                 [UPDATED] +rnc_name in Cell3G schemas"
echo "  - backend/app/api/routes/rnc.py               [NEW] RNC API endpoints"
echo "  - backend/app/api/routes/export.py            [UPDATED] +rnc_name in 3G export"
echo "  - backend/app/api/routes/revision.py          [UPDATED] +rnc_name in 3G revision response"
echo "  - backend/app/services/revision.py            [UPDATED] +rnc_name in 3G snapshot/record"
echo "  - backend/app/services/import_excel.py        [UPDATED] +rnc_name in cell3g extra fields"
echo "  - backend/app/db/base.py                      [UPDATED] imports rnc model"
echo "  - backend/app/main.py                         [UPDATED] registers /rnc route + seeds RNC data"
echo "Frontend:"
echo "  - frontend/src/api/rnc.ts                     [NEW] RNC API client"
echo "  - frontend/src/types/index.ts                 [UPDATED] +rnc_name in Cell3G type"
echo "  - frontend/src/pages/cells/Cells3GPage.tsx    [UPDATED] vendor->rnc cascading select"
echo "Database:"
echo "  - rnc_names table created and seeded"
echo "  - cells_3g.rnc_name column added"
echo "  - cell_3g_revisions.rnc_name column added"