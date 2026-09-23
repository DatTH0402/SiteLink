#!/usr/bin/env bash
# apply_float_to_string.sh
# Converts float columns to string in all backend/frontend code.
set -euo pipefail

BACKEND="backend/app"
FRONTEND="frontend/src"

echo "=== SiteLink: Float → String column migration ==="

# ─────────────────────────────────────────────────────────────────────────────
# 1. BACKEND MODELS
# ─────────────────────────────────────────────────────────────────────────────

echo "[1/10] Patching backend models..."

# ── site.py ──────────────────────────────────────────────────────────────────
cat > "${BACKEND}/models/site.py" << 'PYEOF'
from datetime import datetime, timezone
from sqlalchemy import (
    Column, Integer, String, Float, Boolean,
    DateTime, Text, ForeignKey,
)
from sqlalchemy.orm import relationship
from app.db.base import Base


class Site(Base):
    __tablename__ = "sites"

    id                    = Column(Integer, primary_key=True, index=True)
    mien                  = Column(String(10),  nullable=True)
    tinh                  = Column(String(100), nullable=True)
    phuong_xa             = Column(String(150))
    site_name_cu          = Column(String(100))
    site_name             = Column(String(100), nullable=False, unique=True, index=True)
    site_vip              = Column(String(10))
    lat                   = Column(Float, nullable=True)
    long                  = Column(Float, nullable=True)
    tram_2g               = Column(Boolean, default=False, server_default='false')
    tram_3g               = Column(Boolean, default=False, server_default='false')
    tram_4g               = Column(Boolean, default=False, server_default='false')
    tram_5g               = Column(Boolean, default=False, server_default='false')
    repeater              = Column(Boolean, default=False, server_default='false')
    booster               = Column(Boolean, default=False, server_default='false')
    node_truyen_dan_only  = Column(Boolean, default=False, server_default='false')
    tram_phu_song_tsca    = Column(Boolean, default=False, server_default='false')
    phan_loai_tram        = Column(String(100))
    moran_3g              = Column(String(50))
    moran_4g              = Column(String(50))
    moran_5g              = Column(String(50))
    ma_ptm                = Column(String(100), nullable=True)
    do_cao_dinh_cot_anten = Column(String(50))   # changed: Float → String
    do_cao_cot_anten      = Column(String(50))   # changed: Float → String
    dia_chi               = Column(Text)
    ghi_chu               = Column(Text)
    created_at            = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
    )
    updated_at            = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )
    created_by            = Column(Integer, ForeignKey("users.id"), nullable=True)

    cells_3g = relationship(
        "Cell3G", back_populates="site", cascade="all, delete-orphan")
    cells_4g = relationship(
        "Cell4G", back_populates="site", cascade="all, delete-orphan")
    cells_5g = relationship(
        "Cell5G", back_populates="site", cascade="all, delete-orphan")
PYEOF

# ── cell_3g.py ───────────────────────────────────────────────────────────────
cat > "${BACKEND}/models/cell_3g.py" << 'PYEOF'
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
    do_cao_anten   = Column(String(50))   # changed: Float → String
    azimuth        = Column(String(50))   # changed: Float → String
    m_tilt         = Column(String(50))   # changed: Float → String
    e_tilt         = Column(String(50))   # changed: Float → String
    total_tilt     = Column(String(50))   # changed: Float → String
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

# ── cell_4g.py ───────────────────────────────────────────────────────────────
cat > "${BACKEND}/models/cell_4g.py" << 'PYEOF'
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
    do_cao_anten     = Column(String(50))   # changed: Float → String
    azimuth          = Column(String(50))   # changed: Float → String
    m_tilt           = Column(String(50))   # changed: Float → String
    e_tilt           = Column(String(50))   # changed: Float → String
    total_tilt       = Column(String(50))   # changed: Float → String
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
    created_at       = Column(DateTime(timezone=True),
                              default=lambda: datetime.now(timezone.utc))
    updated_at       = Column(DateTime(timezone=True),
                              default=lambda: datetime.now(timezone.utc),
                              onupdate=lambda: datetime.now(timezone.utc))
    created_by       = Column(Integer, ForeignKey("users.id"), nullable=True)

    site = relationship("Site", back_populates="cells_4g")
PYEOF

# ── cell_5g.py ───────────────────────────────────────────────────────────────
cat > "${BACKEND}/models/cell_5g.py" << 'PYEOF'
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
    site_name_old    = Column(String(100), nullable=True)
    cell_name        = Column(String(100), nullable=False, index=True)
    cell_name_old    = Column(String(100), nullable=True)
    cell_vip         = Column(String(10))
    moran            = Column(String(50))
    lat              = Column(Float)
    long             = Column(Float)
    vung_phu_song    = Column(String(20))
    vendor           = Column(String(50))
    do_cao_anten     = Column(String(50))   # changed: Float → String
    azimuth          = Column(String(50))   # changed: Float → String
    m_tilt           = Column(String(50))   # changed: Float → String
    e_tilt           = Column(String(50))   # changed: Float → String
    total_tilt       = Column(String(50))   # changed: Float → String
    loai_anten       = Column(String(200))
    baseband         = Column(String(100))
    rf               = Column(String(100))
    gnodeb_id        = Column(String(50))
    cell_id          = Column(String(50))
    tac              = Column(String(50))
    pci              = Column(String(50))
    root_sequence_id = Column(String(50))
    mimo             = Column(String(100))
    ssb_arfcn        = Column(String(50))
    center_arfcn     = Column(String(50))
    gscn             = Column(String(50))
    bandwidth        = Column(String(50))
    cell_max_power   = Column(String(50))
    nci              = Column(String(50))
    bbu_name         = Column(String(100))
    mu_mimo          = Column(String(20))
    cell_status      = Column(String(100))
    created_at       = Column(DateTime(timezone=True),
                              default=lambda: datetime.now(timezone.utc))
    updated_at       = Column(DateTime(timezone=True),
                              default=lambda: datetime.now(timezone.utc),
                              onupdate=lambda: datetime.now(timezone.utc))
    created_by       = Column(Integer, ForeignKey("users.id"), nullable=True)

    site = relationship("Site", back_populates="cells_5g")
PYEOF

# ── cell_revision.py ──────────────────────────────────────────────────────────
cat > "${BACKEND}/models/cell_revision.py" << 'PYEOF'
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
    do_cao_anten   = Column(String(50))   # changed: Float → String
    azimuth        = Column(String(50))   # changed: Float → String
    m_tilt         = Column(String(50))   # changed: Float → String
    e_tilt         = Column(String(50))   # changed: Float → String
    total_tilt     = Column(String(50))   # changed: Float → String
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
    do_cao_anten     = Column(String(50))   # changed: Float → String
    azimuth          = Column(String(50))   # changed: Float → String
    m_tilt           = Column(String(50))   # changed: Float → String
    e_tilt           = Column(String(50))   # changed: Float → String
    total_tilt       = Column(String(50))   # changed: Float → String
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
    do_cao_anten     = Column(String(50))   # changed: Float → String
    azimuth          = Column(String(50))   # changed: Float → String
    m_tilt           = Column(String(50))   # changed: Float → String
    e_tilt           = Column(String(50))   # changed: Float → String
    total_tilt       = Column(String(50))   # changed: Float → String
    loai_anten       = Column(String(200))
    baseband         = Column(String(100))
    rf               = Column(String(100))
    gnodeb_id        = Column(String(50))
    cell_id          = Column(String(50))
    tac              = Column(String(50))
    pci              = Column(String(50))
    root_sequence_id = Column(String(50))
    mimo             = Column(String(50))
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

# ── site_revision.py ──────────────────────────────────────────────────────────
cat > "${BACKEND}/models/site_revision.py" << 'PYEOF'
from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime, Text, ForeignKey
from app.db.base import Base


class SiteRevision(Base):
    __tablename__ = "site_revisions"

    id              = Column(Integer, primary_key=True, index=True)
    site_id         = Column(Integer, nullable=False, index=True)
    site_name       = Column(String(100), nullable=False, index=True)
    revision_no     = Column(Integer, nullable=False, default=1)
    changed_by      = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    changed_by_name = Column(String(100), nullable=True)
    change_source   = Column(String(20), default="form")
    change_note     = Column(Text, nullable=True)

    mien                    = Column(String(10))
    tinh                    = Column(String(100))
    phuong_xa               = Column(String(150))
    site_name_cu            = Column(String(100))
    site_name_old_ref       = Column(String(100))
    site_vip                = Column(String(10))
    lat                     = Column(Float)
    long                    = Column(Float)
    tram_2g                 = Column(Boolean, default=False)
    tram_3g                 = Column(Boolean, default=False)
    tram_4g                 = Column(Boolean, default=False)
    tram_5g                 = Column(Boolean, default=False)
    repeater                = Column(Boolean, default=False)
    booster                 = Column(Boolean, default=False)
    node_truyen_dan_only    = Column(Boolean, default=False)
    tram_phu_song_tsca      = Column(Boolean, default=False)
    phan_loai_tram          = Column(String(100))
    moran_3g                = Column(String(50))
    moran_4g                = Column(String(50))
    moran_5g                = Column(String(50))
    ma_ptm                  = Column(String(100))
    do_cao_dinh_cot_anten   = Column(String(50))   # changed: Float → String
    do_cao_cot_anten        = Column(String(50))   # changed: Float → String
    dia_chi                 = Column(Text)
    ghi_chu                 = Column(Text)

    changed_fields  = Column(Text)
    created_at      = Column(DateTime(timezone=True),
                             default=lambda: datetime.now(timezone.utc))
PYEOF

# ─────────────────────────────────────────────────────────────────────────────
# 2. BACKEND SCHEMAS
# ─────────────────────────────────────────────────────────────────────────────

echo "[2/10] Patching backend schemas..."

cat > "${BACKEND}/schemas/site.py" << 'PYEOF'
"""
schemas/site.py
"""
from __future__ import annotations
from typing import Optional
from pydantic import BaseModel, model_validator


class SiteBase(BaseModel):
    mien:                   Optional[str] = None
    tinh:                   Optional[str] = None
    phuong_xa:              Optional[str] = None
    site_name_cu:           Optional[str] = None
    site_name:              Optional[str] = None
    site_vip:               Optional[str] = None
    lat:                    Optional[float] = None
    long:                   Optional[float] = None
    tram_2g:                Optional[bool] = False
    tram_3g:                Optional[bool] = False
    tram_4g:                Optional[bool] = False
    tram_5g:                Optional[bool] = False
    repeater:               Optional[bool] = False
    booster:                Optional[bool] = False
    node_truyen_dan_only:   Optional[bool] = False
    tram_phu_song_tsca:     Optional[bool] = False
    phan_loai_tram:         Optional[str] = None
    moran_3g:               Optional[str] = None
    moran_4g:               Optional[str] = None
    moran_5g:               Optional[str] = None
    ma_ptm:                 Optional[str] = None
    do_cao_dinh_cot_anten:  Optional[str] = None   # changed: float → str
    do_cao_cot_anten:       Optional[str] = None   # changed: float → str
    dia_chi:                Optional[str] = None
    ghi_chu:                Optional[str] = None

    model_config = {"from_attributes": True}


class SiteCreate(SiteBase):
    @model_validator(mode="after")
    def check_required_fields(self) -> "SiteCreate":
        errors = []

        if not self.site_name or not str(self.site_name).strip():
            errors.append("'site_name' là trường bắt buộc.")

        if self.lat is None:
            errors.append("'lat' là trường bắt buộc.")
        elif not (8.33 <= self.lat <= 23.39):
            errors.append(
                f"'lat' = {self.lat} nằm ngoài phạm vi Việt Nam (8.33 – 23.39)."
            )

        if self.long is None:
            errors.append("'long' là trường bắt buộc.")
        elif not (102.14 <= self.long <= 109.47):
            errors.append(
                f"'long' = {self.long} nằm ngoài phạm vi Việt Nam (102.14 – 109.47)."
            )

        if not self.dia_chi or not str(self.dia_chi).strip():
            errors.append("'dia_chi' (Địa chỉ) là trường bắt buộc.")

        if not self.do_cao_dinh_cot_anten or not str(self.do_cao_dinh_cot_anten).strip():
            errors.append("'do_cao_dinh_cot_anten' (Độ cao đỉnh cột anten) là trường bắt buộc.")

        if errors:
            raise ValueError("; ".join(errors))
        return self


class SiteUpdate(BaseModel):
    mien:                   Optional[str] = None
    tinh:                   Optional[str] = None
    phuong_xa:              Optional[str] = None
    site_name_cu:           Optional[str] = None
    site_name:              Optional[str] = None
    site_vip:               Optional[str] = None
    lat:                    Optional[float] = None
    long:                   Optional[float] = None
    tram_2g:                Optional[bool] = None
    tram_3g:                Optional[bool] = None
    tram_4g:                Optional[bool] = None
    tram_5g:                Optional[bool] = None
    repeater:               Optional[bool] = None
    booster:                Optional[bool] = None
    node_truyen_dan_only:   Optional[bool] = None
    tram_phu_song_tsca:     Optional[bool] = None
    phan_loai_tram:         Optional[str] = None
    moran_3g:               Optional[str] = None
    moran_4g:               Optional[str] = None
    moran_5g:               Optional[str] = None
    ma_ptm:                 Optional[str] = None
    do_cao_dinh_cot_anten:  Optional[str] = None   # changed: float → str
    do_cao_cot_anten:       Optional[str] = None   # changed: float → str
    dia_chi:                Optional[str] = None
    ghi_chu:                Optional[str] = None

    model_config = {"from_attributes": True}


class SiteRead(SiteBase):
    id: int
    model_config = {"from_attributes": True}
PYEOF

cat > "${BACKEND}/schemas/cell.py" << 'PYEOF'
"""
schemas/cell.py
"""
from __future__ import annotations
from typing import Optional
from pydantic import BaseModel, model_validator


class CellBase(BaseModel):
    site_id:        Optional[int]   = None
    site_name:      Optional[str]   = None
    site_name_old:  Optional[str]   = None
    cell_name:      Optional[str]   = None
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
    do_cao_anten:   Optional[str]   = None   # changed: float → str
    azimuth:        Optional[str]   = None   # changed: float → str
    m_tilt:         Optional[str]   = None   # changed: float → str
    e_tilt:         Optional[str]   = None   # changed: float → str
    total_tilt:     Optional[str]   = None   # changed: float → str
    loai_anten:     Optional[str]   = None
    baseband:       Optional[str]   = None
    rf:             Optional[str]   = None
    cell_id:        Optional[str]   = None
    mimo:           Optional[str]   = None
    bbu_name:       Optional[str]   = None
    cell_status:    Optional[str]   = None
    cell_max_power: Optional[str]   = None

    model_config = {"from_attributes": True}


_ALLOWED_VENDORS = {"Ericsson", "Nokia", "Huawei", "ZTE", "Samsung"}


class CellCreate(CellBase):
    """Required-field validation – only runs on write path (POST/PUT)."""

    @model_validator(mode="after")
    def check_required_fields(self) -> "CellCreate":
        errors = []

        if not self.site_name or not str(self.site_name).strip():
            errors.append("'site_name' là trường bắt buộc.")
        if not self.cell_name or not str(self.cell_name).strip():
            errors.append("'cell_name' là trường bắt buộc.")

        if not self.vendor or not str(self.vendor).strip():
            errors.append("'vendor' là trường bắt buộc.")
        elif self.vendor not in _ALLOWED_VENDORS:
            errors.append(
                f"'vendor' = '{self.vendor}' không hợp lệ. "
                f"Các giá trị cho phép: {sorted(_ALLOWED_VENDORS)}."
            )

        if self.lat is None:
            errors.append("'lat' là trường bắt buộc.")
        elif not (8.33 <= self.lat <= 23.39):
            errors.append(
                f"'lat' = {self.lat} nằm ngoài phạm vi Việt Nam (8.33 – 23.39)."
            )

        if self.long is None:
            errors.append("'long' là trường bắt buộc.")
        elif not (102.14 <= self.long <= 109.47):
            errors.append(
                f"'long' = {self.long} nằm ngoài phạm vi Việt Nam (102.14 – 109.47)."
            )

        # azimuth, do_cao_anten, m_tilt, e_tilt: required, now strings
        if not self.azimuth or not str(self.azimuth).strip():
            errors.append("'azimuth' là trường bắt buộc.")

        if not self.do_cao_anten or not str(self.do_cao_anten).strip():
            errors.append("'do_cao_anten' (Độ cao anten) là trường bắt buộc.")

        if not self.m_tilt or not str(self.m_tilt).strip():
            errors.append("'m_tilt' (M-tilt) là trường bắt buộc.")

        if not self.e_tilt or not str(self.e_tilt).strip():
            errors.append("'e_tilt' (E-Tilt) là trường bắt buộc.")

        if errors:
            raise ValueError("; ".join(errors))
        return self


class CellUpdate(BaseModel):
    site_id:        Optional[int]   = None
    site_name:      Optional[str]   = None
    site_name_old:  Optional[str]   = None
    cell_name:      Optional[str]   = None
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
    do_cao_anten:   Optional[str]   = None   # changed: float → str
    azimuth:        Optional[str]   = None   # changed: float → str
    m_tilt:         Optional[str]   = None   # changed: float → str
    e_tilt:         Optional[str]   = None   # changed: float → str
    total_tilt:     Optional[str]   = None   # changed: float → str
    loai_anten:     Optional[str]   = None
    baseband:       Optional[str]   = None
    rf:             Optional[str]   = None
    cell_id:        Optional[str]   = None
    mimo:           Optional[str]   = None
    bbu_name:       Optional[str]   = None
    cell_status:    Optional[str]   = None
    cell_max_power: Optional[str]   = None

    model_config = {"from_attributes": True}


# ── 3G ────────────────────────────────────────────────────────────────────────

class Cell3GBase(CellBase):
    chung_anten: Optional[str] = None
    arfcn:       Optional[str] = None
    uarfcn:      Optional[str] = None
    lac:         Optional[str] = None
    rac:         Optional[str] = None
    psc:         Optional[str] = None
    ura_id:      Optional[str] = None
    cpich_power: Optional[str] = None
    rnc_name:    Optional[str] = None


class Cell3GCreate(Cell3GBase, CellCreate):
    pass


class Cell3GUpdate(CellUpdate):
    chung_anten: Optional[str] = None
    arfcn:       Optional[str] = None
    uarfcn:      Optional[str] = None
    lac:         Optional[str] = None
    rac:         Optional[str] = None
    psc:         Optional[str] = None
    ura_id:      Optional[str] = None
    cpich_power: Optional[str] = None
    rnc_name:    Optional[str] = None


class Cell3GRead(Cell3GBase):
    id: int
    model_config = {"from_attributes": True}


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


class Cell4GCreate(Cell4GBase, CellCreate):
    pass


class Cell4GUpdate(CellUpdate):
    chung_anten:      Optional[str] = None
    enodeb_id:        Optional[str] = None
    earfcn:           Optional[str] = None
    tac:              Optional[str] = None
    pci:              Optional[str] = None
    root_sequence_id: Optional[str] = None
    bandwidth:        Optional[str] = None
    eci:              Optional[str] = None


class Cell4GRead(Cell4GBase):
    id: int
    model_config = {"from_attributes": True}


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


class Cell5GCreate(Cell5GBase, CellCreate):
    pass


class Cell5GUpdate(CellUpdate):
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


class Cell5GRead(Cell5GBase):
    id: int
    model_config = {"from_attributes": True}
PYEOF

# ─────────────────────────────────────────────────────────────────────────────
# 3. IMPORT EXCEL SERVICE
# ─────────────────────────────────────────────────────────────────────────────

echo "[3/10] Patching import_excel.py..."

cat > "${BACKEND}/services/import_excel.py" << 'PYEOF'
"""
import_excel.py – Excel → DB record conversion for Sites, Cell3G, Cell4G, Cell5G.

Key design decisions:
  1. Column PRESENT in Excel + blank value → intentional clear → set field to None/False
  2. Column ABSENT from Excel → do not touch that field
  3. Required fields are validated and errors collected (not raised).
  4. do_cao_dinh_cot_anten, do_cao_cot_anten (sites) and
     do_cao_anten, azimuth, m_tilt, e_tilt, total_tilt (cells)
     are now STRING fields – they accept any non-empty string value
     (numeric like "35.5" or special like "IBC").
"""
from __future__ import annotations

import io
import re
import unicodedata
from typing import Any, Dict, List, Optional, Set, Tuple

import pandas as pd

VN_LAT_MIN, VN_LAT_MAX = 8.33,   23.39
VN_LON_MIN, VN_LON_MAX = 102.14, 109.47

# Sentinel: column exists in Excel but is blank → intentional clear
_CLEAR = object()

# ── Required fields ────────────────────────────────────────────────────────────
SITE_REQUIRED_FIELDS = {
    "site_name":             "Site name",
    "lat":                   "Lat",
    "long":                  "Long",
    "dia_chi":               "Địa chỉ",
    "do_cao_dinh_cot_anten": "Độ cao đỉnh cột anten tới mặt đất",
}

CELL_REQUIRED_FIELDS = {
    "site_name":    "Site name",
    "cell_name":    "Cell name",
    "vendor":       "Vendor",
    "lat":          "Lat",
    "long":         "Long",
    "azimuth":      "Azimuth",
    "do_cao_anten": "Độ cao anten",
    "m_tilt":       "M-tilt",
    "e_tilt":       "E-Tilt",
}

# ── Allowed dropdown values ────────────────────────────────────────────────────
ALLOWED_VENDORS   = {"Ericsson", "Nokia", "Huawei", "ZTE", "Samsung"}
ALLOWED_MIEN      = {"MB", "MT", "MN"}
ALLOWED_VUNG      = {"Indoor", "Outdoor"}
ALLOWED_MIMO      = {"2x2", "4x4", "8x8"}
ALLOWED_MORAN     = {"VNPT HOST", "MBF HOST"}
ALLOWED_SITE_VIP  = {"VIP", "VVIP"}
ALLOWED_CELL_VIP  = {"VIP", "VVIP"}
ALLOWED_CHUNG_3G  = {"3G", "3G/4G", "2G/3G/4G", "3G/4G/5G", "3G/5G"}
ALLOWED_CHUNG_4G  = {"4G", "2G/4G", "3G/4G", "2G/3G/4G", "4G/5G"}
ALLOWED_MU_MIMO   = {"Yes", "No"}


def _strip_accents(text: str) -> str:
    _CHAR_MAP = str.maketrans({"Đ": "D", "đ": "d"})
    text = text.translate(_CHAR_MAP)
    nfkd = unicodedata.normalize("NFKD", text)
    return "".join(c for c in nfkd if not unicodedata.combining(c))


_PREFIX_RE = re.compile(
    r"^(tp\.?|thanh\s+pho|thi\s+tran|thi\s+xa|phuong|huyen|tinh|quan|xa)\s+",
    re.IGNORECASE,
)


def _normalize(text: str) -> str:
    t = _strip_accents(text).lower().strip()
    t = _PREFIX_RE.sub("", t)
    t = re.sub(r"[\s\-_\.]+", "", t)
    return t


class GeoCache:
    def __init__(self, db) -> None:
        from app.models.dropdown import DropdownTinhXaPhuong
        rows = db.query(DropdownTinhXaPhuong).all()
        self.tinh_map:  Dict[str, str] = {}
        self.xa_map:    Dict[Tuple[str, str], str] = {}
        self.tinh_mien: Dict[str, str] = {}
        for r in rows:
            if r.ten_tinh:
                k = _normalize(r.ten_tinh)
                self.tinh_map[k]           = r.ten_tinh
                self.tinh_mien[r.ten_tinh] = r.mien or ""
            if r.ten_tinh and r.ten_phuong_xa:
                self.xa_map[
                    (_normalize(r.ten_tinh), _normalize(r.ten_phuong_xa))
                ] = r.ten_phuong_xa

    def resolve_tinh(self, raw: Optional[str]) -> Optional[str]:
        if not raw:
            return None
        return self.tinh_map.get(_normalize(raw))

    def resolve_xa(self, tinh_official: str, raw_xa: Optional[str]) -> Optional[str]:
        if not raw_xa or not tinh_official:
            return None
        return self.xa_map.get((_normalize(tinh_official), _normalize(raw_xa)))

    def mien_for(self, tinh_official: str) -> str:
        return self.tinh_mien.get(tinh_official, "")


def _read_excel(file_bytes: bytes) -> pd.DataFrame:
    df = pd.read_excel(io.BytesIO(file_bytes), dtype=str)
    df = df.where(pd.notna(df), None)
    df.columns = [str(c).strip() for c in df.columns]
    return df


def _v(row: Dict, *keys) -> Optional[str]:
    for key in keys:
        val = row.get(key)
        if val is not None and str(val).strip() not in ("", "nan", "None"):
            return str(val).strip()
    return None


def _v_aware(row: Dict, excel_cols: Set[str], *keys) -> Any:
    col_found = False
    for key in keys:
        if key in excel_cols:
            col_found = True
            val = row.get(key)
            if val is not None and str(val).strip() not in ("", "nan", "None"):
                return str(val).strip()
            return None
    if not col_found:
        return _CLEAR


def _float_aware(row: Dict, excel_cols: Set[str], *keys) -> Any:
    col_found = False
    for key in keys:
        if key in excel_cols:
            col_found = True
            val = row.get(key)
            if val is not None and str(val).strip() not in ("", "nan", "None"):
                try:
                    return float(str(val).strip())
                except (ValueError, TypeError):
                    return None
            return None
    if not col_found:
        return _CLEAR


def _str_aware(row: Dict, excel_cols: Set[str], *keys) -> Any:
    """
    Like _v_aware but for fields that were previously float (now string).
    Returns the raw string value if present, None if blank, _CLEAR if column absent.
    """
    col_found = False
    for key in keys:
        if key in excel_cols:
            col_found = True
            val = row.get(key)
            if val is not None and str(val).strip() not in ("", "nan", "None"):
                # Normalise: if it looks like an integer float (e.g. "35.0"), strip ".0"
                s = str(val).strip()
                try:
                    f = float(s)
                    if f == int(f):
                        s = str(int(f))
                except (ValueError, TypeError):
                    pass
                return s
            return None
    if not col_found:
        return _CLEAR


def _bool_aware(row: Dict, excel_cols: Set[str], *keys) -> Any:
    col_found = False
    for key in keys:
        if key in excel_cols:
            col_found = True
            val = row.get(key)
            if val is not None and str(val).strip() not in ("", "nan", "None"):
                return bool(str(val).strip().lower() in ("x", "true", "yes", "1", "co", "có"))
            return False
    if not col_found:
        return _CLEAR


def _float(row: Dict, *keys) -> Optional[float]:
    v = _v(row, *keys)
    if v is None:
        return None
    try:
        return float(v)
    except (ValueError, TypeError):
        return None


def _bool(row: Dict, *keys) -> bool:
    v = _v(row, *keys)
    if v is None:
        return False
    return str(v).strip().lower() in ("x", "true", "yes", "1", "co", "có")


# ── Validation helpers ─────────────────────────────────────────────────────────

def _check_required(value: Any, field_label: str, row_num: int,
                    record_label: str, errors: List[str]) -> bool:
    is_missing = (
        value is None
        or value is _CLEAR
        or (isinstance(value, str) and value.strip() == "")
    )
    if is_missing:
        errors.append(
            f"Row {row_num} ({record_label}): Trường bắt buộc '{field_label}' bị để trống."
        )
        return False
    return True


def _check_dropdown(value: Any, field_label: str, allowed: Set[str],
                    row_num: int, record_label: str, errors: List[str],
                    required: bool = False) -> bool:
    if value is None or value is _CLEAR or (isinstance(value, str) and value.strip() == ""):
        if required:
            errors.append(
                f"Row {row_num} ({record_label}): Trường bắt buộc '{field_label}' bị để trống."
            )
            return False
        return True
    if str(value) not in allowed:
        errors.append(
            f"Row {row_num} ({record_label}): Giá trị '{value}' không hợp lệ cho trường "
            f"'{field_label}'. Các giá trị cho phép: {sorted(allowed)}. "
            f"Nếu cần thêm giá trị mới, vui lòng liên hệ quản trị viên."
        )
        return False
    return True


def _check_db_dropdown(value: Any, field_label: str, allowed_set: Set[str],
                       row_num: int, record_label: str, errors: List[str],
                       required: bool = False) -> bool:
    if value is None or value is _CLEAR or (isinstance(value, str) and value.strip() == ""):
        if required:
            errors.append(
                f"Row {row_num} ({record_label}): Trường bắt buộc '{field_label}' bị để trống."
            )
            return False
        return True
    if str(value) not in allowed_set:
        errors.append(
            f"Row {row_num} ({record_label}): Giá trị '{value}' không tồn tại trong hệ thống "
            f"cho trường '{field_label}'. Vui lòng liên hệ quản trị viên để thêm giá trị này."
        )
        return False
    return True


def _validate_lat(lat: Any, row_num: int, label: str, errors: List[str],
                  required: bool = False) -> Optional[float]:
    if lat is None:
        if required:
            errors.append(f"Row {row_num} ({label}): Trường bắt buộc 'Lat' bị để trống.")
        return None
    try:
        lat_f = float(lat)
    except (ValueError, TypeError):
        errors.append(f"Row {row_num} ({label}): Giá trị Lat '{lat}' không phải số hợp lệ.")
        return None
    if not (VN_LAT_MIN <= lat_f <= VN_LAT_MAX):
        errors.append(
            f"Row {row_num} ({label}): Latitude {lat_f} nằm ngoài phạm vi Việt Nam "
            f"({VN_LAT_MIN}–{VN_LAT_MAX}). Vui lòng kiểm tra lại toạ độ."
        )
        return None
    return lat_f


def _validate_lon(lon: Any, row_num: int, label: str, errors: List[str],
                  required: bool = False) -> Optional[float]:
    if lon is None:
        if required:
            errors.append(f"Row {row_num} ({label}): Trường bắt buộc 'Long' bị để trống.")
        return None
    try:
        lon_f = float(lon)
    except (ValueError, TypeError):
        errors.append(f"Row {row_num} ({label}): Giá trị Long '{lon}' không phải số hợp lệ.")
        return None
    if not (VN_LON_MIN <= lon_f <= VN_LON_MAX):
        errors.append(
            f"Row {row_num} ({label}): Longitude {lon_f} nằm ngoài phạm vi Việt Nam "
            f"({VN_LON_MIN}–{VN_LON_MAX}). Vui lòng kiểm tra lại toạ độ."
        )
        return None
    return lon_f


def _norm_compare(v: Any, is_bool: bool = False) -> Any:
    if is_bool:
        if v is None:
            return False
        if isinstance(v, bool):
            return v
        if isinstance(v, int):
            return v != 0
        if isinstance(v, str):
            return v.strip().lower() not in ("false", "0", "no", "off", "")
        return bool(v)
    if v is None or (isinstance(v, str) and v.strip() == ""):
        return None
    if isinstance(v, float):
        return v
    return str(v).strip() if isinstance(v, str) else v


# ── Site import ────────────────────────────────────────────────────────────────

_SITE_BOOL_FIELDS = {
    'tram_2g', 'tram_3g', 'tram_4g', 'tram_5g',
    'repeater', 'booster', 'node_truyen_dan_only', 'tram_phu_song_tsca',
}


def _get_phan_loai_opts(db) -> Set[str]:
    if db is None:
        return set()
    try:
        from app.models.dropdown import DropdownGeneral
        rows = db.query(DropdownGeneral).filter(
            DropdownGeneral.category == "phan_loai_tram"
        ).all()
        return {r.value for r in rows}
    except Exception:
        return set()


def _get_antenna_names(db) -> Set[str]:
    if db is None:
        return set()
    try:
        from app.models.antenna import Antenna
        rows = db.query(Antenna.name).all()
        return {r[0] for r in rows if r[0]}
    except Exception:
        return set()


def _get_rnc_names(db) -> Set[str]:
    if db is None:
        return set()
    try:
        from app.models.rnc import RncName
        rows = db.query(RncName.name).all()
        return {r[0] for r in rows if r[0]}
    except Exception:
        return set()


def parse_site_excel(file_bytes: bytes, db=None, dry_run: bool = False) -> Dict[str, Any]:
    df  = _read_excel(file_bytes)
    geo = GeoCache(db) if db else None
    excel_cols: Set[str] = set(df.columns)
    phan_loai_opts = _get_phan_loai_opts(db)

    to_create: List[Dict] = []
    to_update: List[Dict] = []
    errors:    List[str]  = []
    fatal_rows: Set[int]  = set()

    from app.models.site import Site

    for i, row in df.iterrows():
        row_num   = int(str(i)) + 2
        row_errors: List[str] = []

        site_name = _v(row, "Site name", "Site Name", "site_name", "SITE NAME")
        if not site_name:
            errors.append(f"Row {row_num}: Trường bắt buộc 'Site name' bị để trống – bỏ qua dòng này.")
            fatal_rows.add(row_num)
            continue

        label = f"site '{site_name}'"

        raw_tinh   = _v(row, "Tỉnh", "Tinh", "TINH", "tinh", "Province")
        raw_phuong = _v(row, "Phường xã", "Phuong xa", "Phường Xã", "phuong_xa", "Ward")
        raw_mien   = _v(row, "Miền", "Mien", "MIEN", "mien")

        if geo and raw_tinh:
            tinh_official = geo.resolve_tinh(raw_tinh)
            if not tinh_official:
                row_errors.append(
                    f"Row {row_num} ({label}): Tỉnh/TP '{raw_tinh}' không tìm thấy trong hệ thống."
                )
                fatal_rows.add(row_num)
                errors.extend(row_errors)
                continue
            mien = geo.mien_for(tinh_official) or raw_mien or ""
            phuong_xa_official: Optional[str] = None
            if raw_phuong:
                phuong_xa_official = geo.resolve_xa(tinh_official, raw_phuong)
                if not phuong_xa_official:
                    row_errors.append(
                        f"Row {row_num} ({label}): Phường/Xã '{raw_phuong}' không tìm thấy "
                        f"trong '{tinh_official}'."
                    )
        else:
            tinh_official      = raw_tinh or ""
            mien               = raw_mien or ""
            phuong_xa_official = raw_phuong

        if not tinh_official:
            row_errors.append(f"Row {row_num} ({label}): Trường 'Tỉnh' bị để trống.")

        # ── Lat / Long (required, must be numeric) ───────────────────────────
        raw_lat  = _float(row, "Lat", "LAT", "lat", "Latitude")
        raw_long = _float(row, "Long", "LONG", "long", "Longitude")
        lat  = _validate_lat(raw_lat,  row_num, label, row_errors, required=True)
        long = _validate_lon(raw_long, row_num, label, row_errors, required=True)

        # ── Địa chỉ (required) ────────────────────────────────────────────────
        dia_chi_val = _v_aware(row, excel_cols, "Địa chỉ", "Dia chi", "dia_chi")
        if dia_chi_val is None or dia_chi_val is _CLEAR:
            row_errors.append(
                f"Row {row_num} ({label}): Trường bắt buộc 'Địa chỉ' bị để trống."
            )

        # ── Độ cao đỉnh cột anten (required, now STRING) ──────────────────────
        raw_dcant = _str_aware(row, excel_cols,
            "Độ cao đỉnh cột anten (m) đến mặt đất",
            "Do cao dinh cot anten", "do_cao_dinh_cot_anten")
        if raw_dcant is None or raw_dcant is _CLEAR:
            row_errors.append(
                f"Row {row_num} ({label}): Trường bắt buộc "
                f"'Độ cao đỉnh cột anten tới mặt đất' bị để trống."
            )
        # No numeric range validation – accepts any non-empty string

        # ── Optional dropdown validations ─────────────────────────────────────
        site_vip_val = _v_aware(row, excel_cols, "Site VIP", "site_vip")
        if site_vip_val and site_vip_val is not _CLEAR:
            _check_dropdown(site_vip_val, "Site VIP", ALLOWED_SITE_VIP,
                            row_num, label, row_errors)

        mien_val = mien if mien else None
        if mien_val:
            _check_dropdown(mien_val, "Miền", ALLOWED_MIEN,
                            row_num, label, row_errors)

        phan_loai_val = _v_aware(row, excel_cols,
            "IBC/ Macro outdoor / IBC + Outdoor / miniDAS / Smallcell",
            "Phan loai tram", "phan_loai_tram")
        if (phan_loai_val and phan_loai_val is not _CLEAR and phan_loai_opts):
            _check_db_dropdown(phan_loai_val, "Phân loại trạm", phan_loai_opts,
                               row_num, label, row_errors)

        moran_fields = [
            (_v_aware(row, excel_cols,
                "TRẠM MORAN 3G (VNPT HOST, MBF HOST)", "MORAN 3G", "moran_3g"),
             "MORAN 3G"),
            (_v_aware(row, excel_cols,
                "TRẠM MORAN 4G (VNPT HOST, MBF HOST)", "MORAN 4G", "moran_4g"),
             "MORAN 4G"),
            (_v_aware(row, excel_cols,
                "TRẠM MORAN 5G (VNPT HOST, MBF HOST)", "MORAN 5G", "moran_5g"),
             "MORAN 5G"),
        ]
        for moran_val, moran_label in moran_fields:
            if moran_val and moran_val is not _CLEAR:
                _check_dropdown(moran_val, moran_label, ALLOWED_MORAN,
                                row_num, label, row_errors)

        if row_errors:
            errors.extend(row_errors)
            fatal_rows.add(row_num)
            continue

        file_site_name_old = _v(row, "Site name (cũ)", "Site name (cu)",
                                 "Site Name (cũ)", "Site Name Old", "site_name_old")

        rec: Dict[str, Any] = {
            "mien": mien, "tinh": tinh_official, "phuong_xa": phuong_xa_official,
            "site_name_cu": file_site_name_old, "site_name": site_name,
            "site_vip":    _v_aware(row, excel_cols, "Site VIP", "site_vip"),
            "lat": lat, "long": long,
            "tram_2g":    _bool_aware(row, excel_cols, "Trạm 2G", "Tram 2G", "tram_2g"),
            "tram_3g":    _bool_aware(row, excel_cols, "Trạm 3G", "Tram 3G", "tram_3g"),
            "tram_4g":    _bool_aware(row, excel_cols, "Trạm 4G", "Tram 4G", "tram_4g"),
            "tram_5g":    _bool_aware(row, excel_cols, "Trạm 5G", "Tram 5G", "tram_5g"),
            "repeater":   _bool_aware(row, excel_cols, "Repeater", "repeater"),
            "booster":    _bool_aware(row, excel_cols, "Booster",  "booster"),
            "node_truyen_dan_only": _bool_aware(row, excel_cols,
                "Node truyền dẫn only", "Node truyen dan only", "node_truyen_dan_only"),
            "tram_phu_song_tsca": _bool_aware(row, excel_cols,
                "Trạm phủ sóng TSCA", "Tram phu song TSCA", "tram_phu_song_tsca"),
            "phan_loai_tram": phan_loai_val if (phan_loai_val and phan_loai_val is not _CLEAR)
                              else _v_aware(row, excel_cols,
                                  "IBC/ Macro outdoor / IBC + Outdoor / miniDAS / Smallcell",
                                  "Phan loai tram", "phan_loai_tram"),
            "moran_3g": _v_aware(row, excel_cols,
                "TRẠM MORAN 3G (VNPT HOST, MBF HOST)", "MORAN 3G", "moran_3g"),
            "moran_4g": _v_aware(row, excel_cols,
                "TRẠM MORAN 4G (VNPT HOST, MBF HOST)", "MORAN 4G", "moran_4g"),
            "moran_5g": _v_aware(row, excel_cols,
                "TRẠM MORAN 5G (VNPT HOST, MBF HOST)", "MORAN 5G", "moran_5g"),
            "ma_ptm": _v_aware(row, excel_cols, "Mã PTM", "Ma PTM", "ma_ptm", "MaPTM", "PTM"),
            # Now string fields:
            "do_cao_dinh_cot_anten": raw_dcant if (raw_dcant and raw_dcant is not _CLEAR) else raw_dcant,
            "do_cao_cot_anten": _str_aware(row, excel_cols,
                "Độ cao cột anten", "Do cao cot anten", "do_cao_cot_anten",
                "Độ cao cột anten (đỉnh cột anten đến chân cột anten, không tính độ cao công trình)"),
            "dia_chi": dia_chi_val,
            "ghi_chu":  _v_aware(row, excel_cols, "Ghi chú", "Ghi chu", "ghi_chu"),
        }

        if db:
            existing = db.query(Site).filter(Site.site_name == site_name).first()
            if not existing and file_site_name_old:
                existing_by_old = db.query(Site).filter(
                    Site.site_name == file_site_name_old).first()
                if existing_by_old:
                    rec["_site_name_old_ref"] = file_site_name_old
                    to_update.append({
                        "existing_id": existing_by_old.id,
                        "anchor": file_site_name_old,
                        "changes": rec, "is_rename": True,
                    })
                    continue
            if existing:
                to_update.append({
                    "existing_id": existing.id, "anchor": site_name,
                    "changes": rec, "is_rename": False,
                })
            else:
                to_create.append(_resolve_create_rec(rec))
        else:
            to_create.append(_resolve_create_rec(rec))

    return {
        "to_create": to_create, "to_update": to_update,
        "errors": errors, "dry_run": dry_run,
        "fatal_count": len(fatal_rows),
    }


def _resolve_create_rec(rec: Dict) -> Dict:
    result = {}
    for k, v in rec.items():
        if v is _CLEAR:
            if k in _SITE_BOOL_FIELDS:
                result[k] = False
            else:
                result[k] = None
        else:
            result[k] = v
    return result


# ── Cell common field extractor ────────────────────────────────────────────────

def _cell_common_aware(row: Dict, excel_cols: Set[str],
                        geo=None, errors_out=None, row_num=0,
                        antenna_names: Set[str] = None,
                        rnc_names: Set[str] = None) -> Dict[str, Any]:
    if errors_out is None:
        errors_out = []

    raw_tinh   = _v(row, "Tỉnh", "Tinh", "tinh")
    raw_phuong = _v(row, "Phường xã", "Phuong xa", "phuong_xa")
    raw_mien   = _v(row, "Miền", "Mien", "mien")

    if geo and raw_tinh:
        tinh_official = geo.resolve_tinh(raw_tinh)
        if not tinh_official:
            errors_out.append(
                f"Row {row_num}: Tỉnh/TP '{raw_tinh}' không tìm thấy trong hệ thống."
            )
            tinh_official = raw_tinh
        mien = geo.mien_for(tinh_official) or raw_mien or ""
        phuong_xa_official: Optional[str] = None
        if raw_phuong:
            phuong_xa_official = geo.resolve_xa(tinh_official, raw_phuong)
    else:
        tinh_official      = raw_tinh
        mien               = raw_mien
        phuong_xa_official = raw_phuong

    cell_name = _v(row, "Cell Name", "Cell name", "cell_name") or ""
    label     = cell_name or f"row {row_num}"

    # ── Required: Lat, Long (must be numeric) ────────────────────────────────
    raw_lat  = _float(row, "Lat", "LAT", "lat")
    raw_long = _float(row, "Long", "LONG", "long")
    lat  = _validate_lat(raw_lat,  row_num, label, errors_out, required=True)
    lon  = _validate_lon(raw_long, row_num, label, errors_out, required=True)

    # ── Required: Azimuth (now STRING – any non-empty value accepted) ─────────
    azimuth_val = _str_aware(row, excel_cols, "Azimuth", "azimuth")
    if azimuth_val is None or azimuth_val is _CLEAR:
        errors_out.append(
            f"Row {row_num} ({label}): Trường bắt buộc 'Azimuth' bị để trống."
        )
        azimuth_val = None
    # No numeric range check – accepts "IBC" or "120" equally

    # ── Required: Độ cao anten (now STRING) ───────────────────────────────────
    dca_val = _str_aware(row, excel_cols, "Độ cao anten", "Do cao anten", "do_cao_anten")
    if dca_val is None or dca_val is _CLEAR:
        errors_out.append(
            f"Row {row_num} ({label}): Trường bắt buộc 'Độ cao anten' bị để trống."
        )
        dca_val = None

    # ── Required: M-tilt (now STRING) ─────────────────────────────────────────
    mtilt_val = _str_aware(row, excel_cols, "M-tilt", "M-Tilt", "m_tilt")
    if mtilt_val is None or mtilt_val is _CLEAR:
        errors_out.append(
            f"Row {row_num} ({label}): Trường bắt buộc 'M-tilt' bị để trống."
        )
        mtilt_val = None

    # ── Required: E-Tilt (now STRING) ─────────────────────────────────────────
    etilt_val = _str_aware(row, excel_cols, "E-Tilt", "E-tilt", "e_tilt")
    if etilt_val is None or etilt_val is _CLEAR:
        errors_out.append(
            f"Row {row_num} ({label}): Trường bắt buộc 'E-Tilt' bị để trống."
        )
        etilt_val = None

    # ── Required: Vendor ─────────────────────────────────────────────────────
    vendor_val = _v_aware(row, excel_cols, "Vendor", "vendor")
    _check_dropdown(vendor_val, "Vendor", ALLOWED_VENDORS,
                    row_num, label, errors_out, required=True)

    # ── Optional dropdowns ────────────────────────────────────────────────────
    vung_val = _v_aware(row, excel_cols, "Vùng phủ sóng", "Vung phu song", "vung_phu_song")
    if vung_val and vung_val is not _CLEAR:
        _check_dropdown(vung_val, "Vùng phủ sóng", ALLOWED_VUNG,
                        row_num, label, errors_out)

    mimo_val = _v_aware(row, excel_cols, "MIMO", "mimo")
    if mimo_val and mimo_val is not _CLEAR:
        _check_dropdown(mimo_val, "MIMO", ALLOWED_MIMO,
                        row_num, label, errors_out)

    moran_val = _v_aware(row, excel_cols, "MORAN", "Moran", "moran")
    if moran_val and moran_val is not _CLEAR:
        _check_dropdown(moran_val, "MORAN", ALLOWED_MORAN,
                        row_num, label, errors_out)

    cell_vip_val = _v_aware(row, excel_cols, "Cell VIP", "cell_vip")
    if cell_vip_val and cell_vip_val is not _CLEAR:
        _check_dropdown(cell_vip_val, "Cell VIP", ALLOWED_CELL_VIP,
                        row_num, label, errors_out)

    loai_anten_val = _v_aware(row, excel_cols, "Loại Anten", "Loai Anten", "loai_anten")
    if (loai_anten_val and loai_anten_val is not _CLEAR and antenna_names):
        _check_db_dropdown(loai_anten_val, "Loại Anten", antenna_names,
                           row_num, label, errors_out)

    # ── Total Tilt (optional, now STRING) ─────────────────────────────────────
    total_tilt_val = _str_aware(row, excel_cols, "Total Tilt", "Total tilt", "total_tilt")

    return {
        "mien": mien, "tinh": tinh_official, "phuong_xa": phuong_xa_official,
        "site_name":     _v(row, "Site Name", "Site name", "site_name") or "",
        "site_name_old": _v_aware(row, excel_cols, "Site Name Old", "Site name old",
                                   "site_name_old", "Site Name (cũ)", "Site name (cu)"),
        "cell_name":     cell_name,
        "cell_name_old": _v_aware(row, excel_cols, "Cell Name Old", "Cell name old",
                                   "cell_name_old", "Cell Name (cũ)"),
        "cell_vip":      cell_vip_val,
        "moran":         moran_val,
        "lat": lat, "long": lon,
        "vung_phu_song": vung_val,
        "vendor":        vendor_val,
        "do_cao_anten":  dca_val,       # string now
        "azimuth":       azimuth_val,   # string now
        "m_tilt":        mtilt_val,     # string now
        "e_tilt":        etilt_val,     # string now
        "total_tilt":    total_tilt_val, # string now
        "loai_anten":    loai_anten_val,
        "baseband":      _v_aware(row, excel_cols, "Baseband", "baseband"),
        "rf":            _v_aware(row, excel_cols, "RF", "rf"),
        "cell_id":       _v_aware(row, excel_cols, "Cell ID", "cell_id"),
        "mimo":          mimo_val,
        "bbu_name":      _v_aware(row, excel_cols, "BBUname", "BBU Name", "bbu_name"),
        "cell_status":   _v_aware(row, excel_cols, "Cell status (at dump time)",
                                   "Cell status", "cell_status"),
        "cell_max_power": _v_aware(row, excel_cols, "Cell max power (dBm)",
                                    "Cell max power", "cell_max_power"),
    }


# ── Core cell Excel parser ─────────────────────────────────────────────────────

def _parse_cell_excel(
    file_bytes, Model, extra_fields_fn, db=None, dry_run=False
) -> Dict[str, Any]:
    df  = _read_excel(file_bytes)
    excel_cols: Set[str] = set(df.columns)
    geo = GeoCache(db) if db else None
    antenna_names = _get_antenna_names(db)
    rnc_names     = _get_rnc_names(db)

    to_create:         List[Dict] = []
    to_update:         List[Dict] = []
    sites_to_create:   List[Dict] = []
    errors:            List[str]  = []
    fatal_rows:        Set[int]   = set()
    pending_new_sites: Dict[str, Dict] = {}

    from app.models.site import Site

    for i, row in df.iterrows():
        row_num    = int(str(i)) + 2
        row_errors: List[str] = []

        cell_name_raw = _v(row, "Cell Name", "Cell name", "cell_name")
        site_name_raw = _v(row, "Site Name", "Site name", "site_name")

        if not cell_name_raw:
            errors.append(
                f"Row {row_num}: Trường bắt buộc 'Cell Name' bị để trống – bỏ qua dòng này."
            )
            fatal_rows.add(row_num)
            continue
        if not site_name_raw:
            errors.append(
                f"Row {row_num}: Trường bắt buộc 'Site Name' bị để trống – bỏ qua dòng này."
            )
            fatal_rows.add(row_num)
            continue

        common = _cell_common_aware(
            row, excel_cols, geo=geo,
            errors_out=row_errors, row_num=row_num,
            antenna_names=antenna_names,
            rnc_names=rnc_names,
        )

        if row_errors:
            errors.extend(row_errors)
            fatal_rows.add(row_num)
            continue

        cell_name     = common.get("cell_name", "")
        cell_name_old_val = common.get("cell_name_old", _CLEAR)
        cell_name_old = cell_name_old_val if cell_name_old_val is not _CLEAR else None
        site_name     = common.get("site_name", "")
        site_name_old_val = common.get("site_name_old", _CLEAR)
        site_name_old = site_name_old_val if site_name_old_val is not _CLEAR else None

        extra = extra_fields_fn(row, excel_cols, row_num, errors, rnc_names, antenna_names)
        if extra is None:
            fatal_rows.add(row_num)
            continue

        rec = {**common, **extra}

        site_obj = None
        if db:
            site_obj = db.query(Site).filter(Site.site_name == site_name).first()
            if not site_obj and site_name_old:
                site_obj = db.query(Site).filter(
                    Site.site_name == site_name_old).first()

        if site_obj:
            site_id = site_obj.id
        elif site_name in pending_new_sites:
            site_id = None
        else:
            new_site_rec = {
                "site_name": site_name,
                "mien":      common.get("mien") or "",
                "tinh":      common.get("tinh") or "",
                "phuong_xa": common.get("phuong_xa"),
                "lat":       common.get("lat"),
                "long":      common.get("long"),
            }
            pending_new_sites[site_name] = new_site_rec
            sites_to_create.append(new_site_rec)
            site_id = None

        rec["site_id"] = site_id

        existing_cell = None
        if db:
            if site_obj:
                existing_cell = db.query(Model).filter(
                    Model.site_id == site_obj.id,
                    Model.cell_name == cell_name,
                ).first()
                if not existing_cell and cell_name_old:
                    existing_by_old = db.query(Model).filter(
                        Model.site_id == site_obj.id,
                        Model.cell_name == cell_name_old,
                    ).first()
                    if existing_by_old:
                        to_update.append({
                            "existing_id": existing_by_old.id,
                            "anchor":      f"{site_name}/{cell_name_old}",
                            "changes":     rec,
                            "is_rename":   True,
                        })
                        continue
            else:
                existing_cell = db.query(Model).filter(
                    Model.cell_name == cell_name).first()
                if not existing_cell and cell_name_old:
                    existing_cell = db.query(Model).filter(
                        Model.cell_name == cell_name_old).first()
                if existing_cell:
                    rec["site_id"] = existing_cell.site_id

        if existing_cell:
            to_update.append({
                "existing_id": existing_cell.id,
                "anchor":      f"{site_name}/{cell_name}",
                "changes":     rec,
                "is_rename":   False,
            })
        else:
            to_create.append(_resolve_cell_create_rec(rec))

    return {
        "to_create":       to_create,
        "to_update":       to_update,
        "sites_to_create": sites_to_create,
        "errors":          errors,
        "dry_run":         dry_run,
        "fatal_count":     len(fatal_rows),
    }


def _resolve_cell_create_rec(rec: Dict) -> Dict:
    return {k: (None if v is _CLEAR else v) for k, v in rec.items()}


def parse_site_excel_simple(file_bytes: bytes) -> List[Dict[str, Any]]:
    result = parse_site_excel(file_bytes, db=None, dry_run=False)
    records: List[Dict] = []
    for rec in result["to_create"]:
        records.append(rec)
    for upd in result["to_update"]:
        records.append(_resolve_create_rec(upd["changes"]))
    return records


def parse_cell3g_excel(file_bytes, db=None, dry_run=False):
    from app.models.cell_3g import Cell3G
    rnc_names = _get_rnc_names(db)

    def extra(row, excel_cols, row_num=0, errors=None, rnc_names_inner=None, antenna_names=None):
        if errors is None:
            errors = []
        row_errors: List[str] = []
        label = _v(row, "Cell Name", "Cell name", "cell_name") or f"row {row_num}"

        rnc_val = _v_aware(row, excel_cols, "RNC Name", "RNC name", "RNCNAME", "rnc_name")
        effective_rnc = rnc_names_inner or rnc_names
        if rnc_val and rnc_val is not _CLEAR and effective_rnc:
            _check_db_dropdown(rnc_val, "RNC Name", effective_rnc,
                               row_num, label, row_errors)

        chung_val = _v_aware(row, excel_cols, "Chung anten", "chung_anten")
        if chung_val and chung_val is not _CLEAR:
            _check_dropdown(chung_val, "Chung anten", ALLOWED_CHUNG_3G,
                            row_num, label, row_errors)

        if row_errors:
            errors.extend(row_errors)
            return None

        return {
            "chung_anten": chung_val,
            "arfcn":       _v_aware(row, excel_cols, "ARFCN", "arfcn"),
            "uarfcn":      _v_aware(row, excel_cols, "UARFCN", "uarfcn"),
            "lac":         _v_aware(row, excel_cols, "LAC", "lac"),
            "rac":         _v_aware(row, excel_cols, "RAC", "rac"),
            "psc":         _v_aware(row, excel_cols, "PSC", "psc"),
            "ura_id":      _v_aware(row, excel_cols, "URAId", "URA ID", "ura_id"),
            "cpich_power": _v_aware(row, excel_cols, "CPICH power (dBm)",
                                     "CPICH power", "cpich_power"),
            "rnc_name":    rnc_val,
        }
    return _parse_cell_excel(file_bytes, Cell3G, extra, db=db, dry_run=dry_run)


def parse_cell4g_excel(file_bytes, db=None, dry_run=False):
    from app.models.cell_4g import Cell4G

    def extra(row, excel_cols, row_num=0, errors=None, rnc_names=None, antenna_names=None):
        if errors is None:
            errors = []
        row_errors: List[str] = []
        label = _v(row, "Cell Name", "Cell name", "cell_name") or f"row {row_num}"

        chung_val = _v_aware(row, excel_cols, "Chung anten", "chung_anten")
        if chung_val and chung_val is not _CLEAR:
            _check_dropdown(chung_val, "Chung anten", ALLOWED_CHUNG_4G,
                            row_num, label, row_errors)

        if row_errors:
            errors.extend(row_errors)
            return None

        return {
            "chung_anten":      chung_val,
            "enodeb_id":        _v_aware(row, excel_cols, "EnodeB ID", "enodeb_id"),
            "earfcn":           _v_aware(row, excel_cols, "EARFCN", "earfcn"),
            "tac":              _v_aware(row, excel_cols, "TAC", "tac"),
            "pci":              _v_aware(row, excel_cols, "PCI", "pci"),
            "root_sequence_id": _v_aware(row, excel_cols, "Root Sequence ID", "root_sequence_id"),
            "bandwidth":        _v_aware(row, excel_cols, "Bandwitdh", "Bandwidth", "bandwidth"),
            "eci":              _v_aware(row, excel_cols, "ECI", "eci"),
        }
    return _parse_cell_excel(file_bytes, Cell4G, extra, db=db, dry_run=dry_run)


def parse_cell5g_excel(file_bytes, db=None, dry_run=False):
    from app.models.cell_5g import Cell5G

    def extra(row, excel_cols, row_num=0, errors=None, rnc_names=None, antenna_names=None):
        if errors is None:
            errors = []
        row_errors: List[str] = []
        label = _v(row, "Cell Name", "Cell name", "cell_name") or f"row {row_num}"

        mu_mimo_val = _v_aware(row, excel_cols, "MU-MIMO", "mu_mimo")
        if mu_mimo_val and mu_mimo_val is not _CLEAR:
            _check_dropdown(mu_mimo_val, "MU-MIMO", ALLOWED_MU_MIMO,
                            row_num, label, row_errors)

        if row_errors:
            errors.extend(row_errors)
            return None

        return {
            "gnodeb_id":        _v_aware(row, excel_cols, "gNodeB ID", "gnodeb_id"),
            "tac":              _v_aware(row, excel_cols, "TAC", "tac"),
            "pci":              _v_aware(row, excel_cols, "PCI", "pci"),
            "root_sequence_id": _v_aware(row, excel_cols, "Root Sequence ID", "root_sequence_id"),
            "ssb_arfcn":        _v_aware(row, excel_cols, "SSB-ARFCN", "ssb_arfcn"),
            "center_arfcn":     _v_aware(row, excel_cols, "Center-ARFCN", "center_arfcn"),
            "gscn":             _v_aware(row, excel_cols, "GSCN", "gscn"),
            "bandwidth":        _v_aware(row, excel_cols, "Bandwidth (MHz)", "Bandwidth", "bandwidth"),
            "nci":              _v_aware(row, excel_cols, "NCI", "nci"),
            "mu_mimo":          mu_mimo_val,
        }
    return _parse_cell_excel(file_bytes, Cell5G, extra, db=db, dry_run=dry_run)
PYEOF

# ─────────────────────────────────────────────────────────────────────────────
# 4. EXCEL TEMPLATE GENERATOR
# ─────────────────────────────────────────────────────────────────────────────

echo "[4/10] Patching create_excel_templates.py (validation sections)..."

# We use Python to do a targeted patch of the validation sections
python3 << 'PATCHEOF'
import re

path = "backend/create_excel_templates.py"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

# ── Remove numeric validation for site height fields ─────────────────────────
# Replace _dv_decimal validations for do_cao_dinh_cot_anten and do_cao_cot_anten
# with no validation (they are now free-text strings in the template too).

old_site_dv = '''    _apply_dv(ws, _dv_decimal(0, 999,
                               "Độ cao không hợp lệ", "Phải là số dương (m)"),
              cm["Do cao dinh cot anten"])
    _apply_dv(ws, _dv_decimal(0, 999,
                               "Độ cao không hợp lệ", "Phải là số dương (m)"),
              cm["Do cao cot anten"])'''

new_site_dv = '''    # do_cao_dinh_cot_anten / do_cao_cot_anten are now free-text strings
    # (accept numeric values like "35" or special values like "IBC")
    # No data validation applied – any non-empty string is valid.'''

src = src.replace(old_site_dv, new_site_dv)

# ── Remove numeric validation for cell height/tilt/azimuth fields ─────────────
# In _apply_common_cell_validations, replace the do_cao_anten, azimuth,
# m_tilt, e_tilt, total_tilt validations.

old_cell_dv = '''    _apply_dv(ws, _dv_decimal(0, 999, "Độ cao không hợp lệ", "Phải là số dương (m)"),
              cm["Do cao anten"])
    _apply_dv(ws, _dv_whole(AZI_MIN, AZI_MAX,
                             "Azimuth không hợp lệ",
                             f"Azimuth phải trong khoảng {AZI_MIN}–{AZI_MAX}"),
              cm["Azimuth"])

    for col_name in ["M-tilt", "E-Tilt", "Total Tilt"]:
        _apply_dv(ws, _dv_decimal(-30, 30,
                                   f"{col_name} không hợp lệ",
                                   f"{col_name} thường trong khoảng -30 đến 30"),
                  cm[col_name])'''

new_cell_dv = '''    # do_cao_anten, azimuth, m_tilt, e_tilt, total_tilt are now free-text strings
    # (accept numeric values like "35" or special values like "IBC")
    # No numeric data validation applied for these columns.'''

src = src.replace(old_cell_dv, new_cell_dv)

# ── Update column type notes in site columns list ─────────────────────────────
src = src.replace(
    '("Do cao dinh cot anten", "Độ cao đỉnh cột anten tới mặt đất (m) – bắt buộc",        22,  True)',
    '("Do cao dinh cot anten", "Độ cao đỉnh cột anten tới mặt đất – bắt buộc (số hoặc chuỗi, vd: 35 hoặc IBC)", 22, True)',
)
src = src.replace(
    '("Do cao cot anten",      "Độ cao cột anten – đỉnh đến chân cột (m)",                 20,  False)',
    '("Do cao cot anten",      "Độ cao cột anten – đỉnh đến chân cột (số hoặc chuỗi, vd: 30 hoặc IBC)", 20, False)',
)

# ── Update column type notes in cell columns list ─────────────────────────────
src = src.replace(
    '("Do cao anten",   "Độ cao anten (m) – bắt buộc, số dương",                       16,  True)',
    '("Do cao anten",   "Độ cao anten – bắt buộc (số hoặc chuỗi, vd: 28 hoặc IBC)",    16,  True)',
)
src = src.replace(
    '("Azimuth",        f"Góc phương vị – bắt buộc, trong {AZI_MIN}–{AZI_MAX}",        12,  True)',
    '("Azimuth",        "Góc phương vị – bắt buộc (số hoặc chuỗi, vd: 120 hoặc IBC)", 12,  True)',
)
src = src.replace(
    '("M-tilt",         "Mechanical tilt – bắt buộc",                                   10,  True)',
    '("M-tilt",         "Mechanical tilt – bắt buộc (số hoặc chuỗi, vd: 2 hoặc IBC)", 10,  True)',
)
src = src.replace(
    '("E-Tilt",         "Electrical tilt – bắt buộc",                                   10,  True)',
    '("E-Tilt",         "Electrical tilt – bắt buộc (số hoặc chuỗi, vd: 4 hoặc IBC)", 10,  True)',
)
src = src.replace(
    '("Total Tilt",     "Tổng tilt = M-tilt + E-Tilt (tự tính hoặc để trống)",         12,  False)',
    '("Total Tilt",     "Tổng tilt (số hoặc chuỗi, tự tính hoặc để trống)",            12,  False)',
)

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

print("  create_excel_templates.py patched OK")
PATCHEOF

# ─────────────────────────────────────────────────────────────────────────────
# 5. FRONTEND TYPES
# ─────────────────────────────────────────────────────────────────────────────

echo "[5/10] Patching frontend types/index.ts..."

cat > "${FRONTEND}/types/index.ts" << 'TSEOF'
export interface User {
  id: number
  email: string
  username: string
  full_name?: string
  role: 'admin' | 'user'
  is_active: boolean
  auth_provider: 'local' | 'sso'
}

export interface Site {
  id: number
  mien?: string
  tinh?: string
  phuong_xa?: string
  site_name_cu?: string
  site_name: string
  site_vip?: string
  lat: number
  long: number
  tram_2g: boolean
  tram_3g: boolean
  tram_4g: boolean
  tram_5g: boolean
  repeater: boolean
  booster: boolean
  node_truyen_dan_only: boolean
  tram_phu_song_tsca: boolean
  phan_loai_tram?: string
  moran_3g?: string
  moran_4g?: string
  moran_5g?: string
  ma_ptm?: string
  do_cao_dinh_cot_anten?: string   // changed: number → string
  do_cao_cot_anten?: string        // changed: number → string
  dia_chi: string
  ghi_chu?: string
}

export interface CellBase {
  id: number
  site_id: number
  mien?: string
  tinh?: string
  phuong_xa?: string
  site_name: string
  site_name_old?: string
  cell_name: string
  cell_name_old?: string
  cell_vip?: string
  moran?: string
  lat: number
  long: number
  vung_phu_song?: string
  vendor: string
  do_cao_anten?: string    // changed: number → string
  azimuth?: string         // changed: number → string
  m_tilt?: string          // changed: number → string
  e_tilt?: string          // changed: number → string
  total_tilt?: string      // changed: number → string
  loai_anten?: string
  baseband?: string
  rf?: string
  cell_id?: string
  mimo?: string
  bbu_name?: string
  cell_status?: string
  cell_max_power?: string
}

export interface Cell3G extends CellBase {
  chung_anten?: string
  arfcn?: string
  uarfcn?: string
  lac?: string
  rac?: string
  psc?: string
  ura_id?: string
  cpich_power?: string
  rnc_name?: string
}

export interface Cell4G extends CellBase {
  chung_anten?: string
  enodeb_id?: string
  earfcn?: string
  tac?: string
  pci?: string
  root_sequence_id?: string
  bandwidth?: string
  eci?: string
}

export interface Cell5G extends CellBase {
  gnodeb_id?: string
  tac?: string
  pci?: string
  root_sequence_id?: string
  ssb_arfcn?: string
  center_arfcn?: string
  gscn?: string
  bandwidth?: string
  nci?: string
  mu_mimo?: string
}

export interface ReportRow {
  mien?: string
  tinh?: string
  site_count: number
  site_2g: number
  site_3g: number
  site_4g: number
  site_5g: number
  cell_3g: number
  cell_4g: number
  cell_5g: number
}

export interface AuditLog {
  id: number
  username: string
  full_name: string
  email: string
  action: string
  table_name: string
  record_id: number
  old_value?: string
  new_value?: string
  timestamp: string
}

export interface TinhItem {
  ten_tinh: string
  mien: string
}

export interface PhuongXaItem {
  id: number
  mien: string
  ten_tinh: string
  ten_phuong_xa: string
  ma_tinh: string
  ma_phuong_xa: string
  ky_tu_1_6: string
}

export interface AntennaItem {
  id: number
  name: string
  band?: string
  no_of_ports?: number
  no_of_beam?: number
  horizontal_bw?: string
  vertical_bw?: string
  gain?: string
  etilt?: string
  h?: string
  w?: string
  d?: string
  weight?: string
  connector_type?: string
  ghi_chu?: string
  is_5g_aau?: boolean
}

export interface ProvinceChartItem {
  tinh: string
  site_count: number
}

export interface CellProvinceChartItem {
  tinh: string
  cell_count: number
}

export interface SiteDryRunResult {
  to_create: number
  to_update: number
  errors: number
  error_details: string[]
  preview_create: string[]
  preview_update: string[]
  dry_run: true
  has_fatal_errors?: boolean
}

export interface CellDryRunResult {
  to_create: number
  to_update: number
  sites_to_create: number
  errors: number
  error_details: string[]
  preview_create: string[]
  preview_update: string[]
  preview_new_sites: string[]
  dry_run: true
  has_fatal_errors?: boolean
}

export interface ImportResult {
  created: number
  updated: number
  sites_auto_created?: number
  errors: string[]
}

export interface AntennaFull {
  id: number
  name: string
  no_of_ports?: number
  band?: string
  no_of_beam?: number
  horizontal_bw?: string
  vertical_bw?: string
  gain?: string
  etilt?: string
  h?: string
  w?: string
  d?: string
  weight?: string
  connector_type?: string
  ghi_chu?: string
  is_5g_aau: boolean
  spec_file_name?: string
  spec_file_path?: string
}
TSEOF

# ─────────────────────────────────────────────────────────────────────────────
# 6. FRONTEND VALIDATORS
# ─────────────────────────────────────────────────────────────────────────────

echo "[6/10] Patching frontend validators.ts..."

cat > "${FRONTEND}/utils/validators.ts" << 'TSEOF'
/**
 * validators.ts
 * Shared Ant Design form validators for SiteLink.
 *
 * NOTE: do_cao_anten, azimuth, m_tilt, e_tilt, total_tilt (cells) and
 *       do_cao_dinh_cot_anten, do_cao_cot_anten (sites) are now STRING fields.
 * They accept any non-empty string (e.g. "35", "IBC", "N/A").
 * Only lat/long remain purely numeric with range validation.
 */

// Vietnam bounding box (lat/long remain float with range validation)
export const VN_LAT_MIN = 8.33
export const VN_LAT_MAX = 23.39
export const VN_LON_MIN = 102.14
export const VN_LON_MAX = 109.47

export const latValidator = (_: unknown, value: number) => {
  if (value === undefined || value === null) return Promise.resolve()
  const v = Number(value)
  if (isNaN(v)) return Promise.reject(new Error('Latitude phải là số'))
  if (v < VN_LAT_MIN || v > VN_LAT_MAX)
    return Promise.reject(
      new Error(`Latitude phải trong khoảng ${VN_LAT_MIN} – ${VN_LAT_MAX} (lãnh thổ Việt Nam)`)
    )
  return Promise.resolve()
}

export const lonValidator = (_: unknown, value: number) => {
  if (value === undefined || value === null) return Promise.resolve()
  const v = Number(value)
  if (isNaN(v)) return Promise.reject(new Error('Longitude phải là số'))
  if (v < VN_LON_MIN || v > VN_LON_MAX)
    return Promise.reject(
      new Error(`Longitude phải trong khoảng ${VN_LON_MIN} – ${VN_LON_MAX} (lãnh thổ Việt Nam)`)
    )
  return Promise.resolve()
}

/**
 * azimuthValidator – now accepts any non-empty string.
 * Numeric values are still checked for 0–359 range as a soft warning,
 * but non-numeric strings (e.g. "IBC") pass without error.
 */
export const azimuthValidator = (_: unknown, value: string | number | undefined | null) => {
  if (value === undefined || value === null || value === '') return Promise.resolve()
  const v = Number(value)
  if (!isNaN(v) && (v < 0 || v > 359))
    return Promise.reject(new Error('Azimuth số phải trong khoảng 0 – 359'))
  return Promise.resolve()
}

/**
 * positiveNumberValidator – now accepts any non-empty string.
 * Numeric values are still checked for >= 0 as a soft warning,
 * but non-numeric strings (e.g. "IBC") pass without error.
 */
export const positiveNumberValidator = (_: unknown, value: string | number | undefined | null) => {
  if (value === undefined || value === null || value === '') return Promise.resolve()
  const v = Number(value)
  if (!isNaN(v) && v < 0)
    return Promise.reject(new Error('Giá trị số phải >= 0'))
  return Promise.resolve()
}

/**
 * tiltValidator – accepts any non-empty string.
 * Numeric values checked for -90 to 90 range as soft warning.
 */
export const tiltValidator = (_: unknown, value: string | number | undefined | null) => {
  if (value === undefined || value === null || value === '') return Promise.resolve()
  const v = Number(value)
  if (!isNaN(v) && (v < -90 || v > 90))
    return Promise.reject(new Error('Tilt số thường trong khoảng -90 đến 90'))
  return Promise.resolve()
}
TSEOF

# ─────────────────────────────────────────────────────────────────────────────
# 7. SITE FORM PAGE
# ─────────────────────────────────────────────────────────────────────────────

echo "[7/10] Patching SiteFormPage.tsx..."

cat > "${FRONTEND}/pages/sites/SiteFormPage.tsx" << 'TSEOF'
import React, { useEffect, useState, useCallback } from 'react'
import {
  Typography, Form, Input, Select, Switch, Button,
  Row, Col, Card, Space, message,
} from 'antd'
import { SaveOutlined, ArrowLeftOutlined } from '@ant-design/icons'
import { useNavigate, useParams } from 'react-router-dom'
import { getSite, createSite, updateSite } from '@/api/sites'
import { getDropdown, getTinhList, getTinhXaPhuong } from '@/api/report'
import type { TinhItem, PhuongXaItem } from '@/types'

export default function SiteFormPage() {
  const [form]   = Form.useForm()
  const navigate = useNavigate()
  const { id }   = useParams<{ id: string }>()
  const isEdit   = Boolean(id)

  const [loading,         setLoading]         = useState(false)
  const [phanLoaiOpts,    setPhanLoaiOpts]    = useState<string[]>([])
  const [tinhList,        setTinhList]        = useState<TinhItem[]>([])
  const [phuongXaList,    setPhuongXaList]    = useState<PhuongXaItem[]>([])
  const [selectedTinh,    setSelectedTinh]    = useState<string | undefined>()
  const [loadingPhuongXa, setLoadingPhuongXa] = useState(false)

  useEffect(() => {
    getDropdown('phan_loai_tram').then((rows: any[]) =>
      setPhanLoaiOpts(rows.map((r) => r.value)))
    getTinhList().then((rows: TinhItem[]) => setTinhList(rows))

    if (isEdit && id) {
      getSite(Number(id)).then((site) => {
        form.setFieldsValue(site)
        if (site.tinh) setSelectedTinh(site.tinh)
      })
    }
  }, [id])

  useEffect(() => {
    if (!selectedTinh) { setPhuongXaList([]); return }
    setLoadingPhuongXa(true)
    getTinhXaPhuong(selectedTinh)
      .then((rows: PhuongXaItem[]) => setPhuongXaList(rows))
      .finally(() => setLoadingPhuongXa(false))
  }, [selectedTinh])

  const handleTinhChange = useCallback((value: string) => {
    setSelectedTinh(value)
    form.setFieldValue('phuong_xa', undefined)
    const found = tinhList.find((t) => t.ten_tinh === value)
    if (found) form.setFieldValue('mien', found.mien)
  }, [tinhList, form])

  const onFinish = async (values: any) => {
    setLoading(true)
    try {
      if (isEdit) {
        await updateSite(Number(id), values)
        message.success('Cập nhật site thành công')
      } else {
        await createSite(values)
        message.success('Tạo site mới thành công')
      }
      navigate('/sites')
    } catch (e: any) {
      const detail = e.response?.data?.detail || 'Có lỗi xảy ra'
      if (typeof detail === 'string' && detail.includes('already exists')) {
        message.warning(`Site đã tồn tại: ${values.site_name}`)
      } else {
        message.error(typeof detail === 'string' ? detail : 'Có lỗi xảy ra')
      }
    } finally {
      setLoading(false)
    }
  }

  return (
    <div>
      <Space style={{ marginBottom: 16 }}>
        <Button icon={<ArrowLeftOutlined />} onClick={() => navigate('/sites')}>
          Quay lại
        </Button>
        <Typography.Title level={3} style={{ margin: 0 }}>
          {isEdit ? 'Chỉnh sửa Site' : 'Thêm Site mới'}
        </Typography.Title>
      </Space>

      <Form form={form} layout="vertical" onFinish={onFinish}>
        <Card title="Thông tin chung" style={{ marginBottom: 16 }}>
          <Row gutter={16}>
            <Col span={4}>
              <Form.Item name="mien" label="Miền">
                <Select placeholder="Chọn miền" allowClear>
                  {['MB', 'MT', 'MN'].map((m) => (
                    <Select.Option key={m} value={m}>{m}</Select.Option>
                  ))}
                </Select>
              </Form.Item>
            </Col>
            <Col span={10}>
              <Form.Item name="tinh" label="Tỉnh / Thành phố"
                         rules={[{ required: true, message: 'Vui lòng chọn tỉnh' }]}>
                <Select
                  showSearch allowClear
                  placeholder="Chọn tỉnh / thành phố..."
                  optionFilterProp="children"
                  onChange={handleTinhChange}
                  filterOption={(input, option) =>
                    String(option?.children ?? '').toLowerCase()
                      .includes(input.toLowerCase())
                  }
                >
                  {tinhList.map((t) => (
                    <Select.Option key={t.ten_tinh} value={t.ten_tinh}>
                      {t.ten_tinh}
                    </Select.Option>
                  ))}
                </Select>
              </Form.Item>
            </Col>
            <Col span={10}>
              <Form.Item name="phuong_xa" label="Phường / Xã">
                <Select
                  showSearch allowClear
                  placeholder={selectedTinh ? 'Chọn phường / xã...' : 'Chọn tỉnh trước'}
                  disabled={!selectedTinh}
                  loading={loadingPhuongXa}
                  optionFilterProp="children"
                  filterOption={(input, option) =>
                    String(option?.children ?? '').toLowerCase()
                      .includes(input.toLowerCase())
                  }
                >
                  {phuongXaList.map((p) => (
                    <Select.Option key={p.id} value={p.ten_phuong_xa}>
                      {p.ten_phuong_xa}
                    </Select.Option>
                  ))}
                </Select>
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="site_name_cu" label="Site name (cũ)">
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="site_name" label="Site name *"
                         rules={[{ required: true, message: 'Vui lòng nhập site name' }]}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={4}>
              <Form.Item name="site_vip" label="Site VIP">
                <Select allowClear>
                  <Select.Option value="VIP">VIP</Select.Option>
                  <Select.Option value="VVIP">VVIP</Select.Option>
                </Select>
              </Form.Item>
            </Col>
            <Col span={4}>
              <Form.Item name="ma_ptm" label="Mã PTM">
                <Input />
              </Form.Item>
            </Col>
          </Row>
        </Card>

        <Card title="Toạ độ và Cột anten" style={{ marginBottom: 16 }}>
          <Row gutter={16}>
            <Col span={6}>
              <Form.Item
                name="lat"
                label="Latitude *"
                rules={[
                  { required: true, message: 'Vui lòng nhập Latitude' },
                  {
                    validator: (_: unknown, value: number) => {
                      if (value === undefined || value === null) return Promise.resolve()
                      const v = Number(value)
                      if (isNaN(v)) return Promise.reject('Latitude phải là số')
                      if (v < 8.33 || v > 23.39)
                        return Promise.reject('Latitude phải trong khoảng 8.33 – 23.39 (Việt Nam)')
                      return Promise.resolve()
                    }
                  }
                ]}
              >
                <Input placeholder="8.33 – 23.39" />
              </Form.Item>
            </Col>
            <Col span={6}>
              <Form.Item
                name="long"
                label="Longitude *"
                rules={[
                  { required: true, message: 'Vui lòng nhập Longitude' },
                  {
                    validator: (_: unknown, value: number) => {
                      if (value === undefined || value === null) return Promise.resolve()
                      const v = Number(value)
                      if (isNaN(v)) return Promise.reject('Longitude phải là số')
                      if (v < 102.14 || v > 109.47)
                        return Promise.reject('Longitude phải trong khoảng 102.14 – 109.47 (Việt Nam)')
                      return Promise.resolve()
                    }
                  }
                ]}
              >
                <Input placeholder="102.14 – 109.47" />
              </Form.Item>
            </Col>
            <Col span={6}>
              {/* Now a free-text string field */}
              <Form.Item
                name="do_cao_dinh_cot_anten"
                label="Độ cao đỉnh cột anten tới mặt đất *"
                rules={[{ required: true, message: 'Vui lòng nhập độ cao đỉnh cột anten' }]}
              >
                <Input placeholder="vd: 35 hoặc IBC" />
              </Form.Item>
            </Col>
            <Col span={6}>
              {/* Now a free-text string field */}
              <Form.Item
                name="do_cao_cot_anten"
                label="Độ cao cột anten"
              >
                <Input placeholder="vd: 30 hoặc IBC" />
              </Form.Item>
            </Col>
          </Row>
        </Card>

        <Card title="Địa chỉ" style={{ marginBottom: 16 }}>
          <Row gutter={16}>
            <Col span={24}>
              <Form.Item
                name="dia_chi"
                label="Địa chỉ *"
                rules={[{ required: true, message: 'Vui lòng nhập địa chỉ' }]}
              >
                <Input.TextArea rows={2} placeholder="Nhập địa chỉ đầy đủ của trạm..." />
              </Form.Item>
            </Col>
          </Row>
        </Card>

        <Card title="Loại trạm và Công nghệ" style={{ marginBottom: 16 }}>
          <Row gutter={16}>
            <Col span={8}>
              <Form.Item name="phan_loai_tram" label="Phân loại trạm">
                <Select allowClear>
                  {phanLoaiOpts.map((o) => (
                    <Select.Option key={o} value={o}>{o}</Select.Option>
                  ))}
                </Select>
              </Form.Item>
            </Col>
            {([
              ['tram_2g',            'Trạm 2G'],
              ['tram_3g',            'Trạm 3G'],
              ['tram_4g',            'Trạm 4G'],
              ['tram_5g',            'Trạm 5G'],
              ['repeater',           'Repeater'],
              ['booster',            'Booster'],
              ['node_truyen_dan_only','Node truyền dẫn only'],
              ['tram_phu_song_tsca', 'Trạm phủ sóng TSCA'],
            ] as [string, string][]).map(([name, label]) => (
              <Col span={4} key={name}>
                <Form.Item name={name} label={label} valuePropName="checked">
                  <Switch />
                </Form.Item>
              </Col>
            ))}
          </Row>
          <Row gutter={16}>
            {([
              ['moran_3g', 'MORAN 3G'],
              ['moran_4g', 'MORAN 4G'],
              ['moran_5g', 'MORAN 5G'],
            ] as [string, string][]).map(([name, label]) => (
              <Col span={6} key={name}>
                <Form.Item name={name} label={label}>
                  <Select allowClear>
                    <Select.Option value="VNPT HOST">VNPT HOST</Select.Option>
                    <Select.Option value="MBF HOST">MBF HOST</Select.Option>
                  </Select>
                </Form.Item>
              </Col>
            ))}
          </Row>
        </Card>

        <Card title="Thông tin khác" style={{ marginBottom: 16 }}>
          <Row gutter={16}>
            <Col span={12}>
              <Form.Item name="ghi_chu" label="Ghi chú">
                <Input.TextArea rows={2} />
              </Form.Item>
            </Col>
          </Row>
        </Card>

        <Space>
          <Button type="primary" htmlType="submit" icon={<SaveOutlined />} loading={loading}>
            {isEdit ? 'Cập nhật' : 'Tạo mới'}
          </Button>
          <Button onClick={() => navigate('/sites')}>Hủy</Button>
        </Space>
      </Form>
    </div>
  )
}
TSEOF

# ─────────────────────────────────────────────────────────────────────────────
# 8. CELL PAGES  (3G / 4G / 5G) – patch form fields
# ─────────────────────────────────────────────────────────────────────────────

echo "[8/10] Patching Cell page form fields (InputNumber → Input for string fields)..."

# We use Python for surgical replacement to avoid re-writing 3 large files
python3 << 'PATCHEOF'
import re, os

# ── Helper: replace InputNumber with Input for the 5 string fields ─────────────
def patch_cell_page(path: str, tech: str):
    with open(path, "r", encoding="utf-8") as f:
        src = f.read()

    # 1. do_cao_anten: was InputNumber with min/required validator, now Input
    src = re.sub(
        r'(<Form\.Item\s+name="do_cao_anten"[^>]*label="[^"]*"[^>]*>)\s*'
        r'<InputNumber[^/]*/>\s*'
        r'(</Form\.Item>)',
        lambda m: m.group(1) + '\n                <Input placeholder="vd: 28 hoặc IBC" />\n              ' + m.group(2),
        src
    )

    # 2. azimuth: was InputNumber with azimuthValidator, now Input
    # Replace the entire Form.Item for azimuth
    src = re.sub(
        r'<Form\.Item\s+name="azimuth"\s+label="Azimuth[^"]*"[^>]*rules=\{[^\}]*azimuthValidator[^\}]*\}[^>]*>\s*'
        r'<InputNumber[^/]*/>\s*'
        r'</Form\.Item>',
        '<Form.Item name="azimuth" label="Azimuth *"\n                rules={[{ required: true, message: \'Vui lòng nhập Azimuth\' }, { validator: azimuthValidator }]}>\n                <Input placeholder="vd: 120 hoặc IBC" />\n              </Form.Item>',
        src
    )
    # Also handle the simpler no-required variant in 4G/5G
    src = re.sub(
        r'<Form\.Item\s+name="azimuth"\s+label="Azimuth \(0[^"]*\)"[^>]*rules=\{[^\}]*azimuthValidator[^\}]*\}[^>]*>\s*'
        r'<InputNumber[^/]*/>\s*'
        r'</Form\.Item>',
        '<Form.Item name="azimuth" label="Azimuth" rules={[{ validator: azimuthValidator }]}>\n                <Input placeholder="vd: 120 hoặc IBC" />\n              </Form.Item>',
        src
    )

    # 3. m_tilt / e_tilt: now Input
    for field, label_frag in [('m_tilt', 'M-tilt'), ('e_tilt', 'E-Tilt')]:
        # required variant (4G/5G uses required=true)
        src = re.sub(
            rf'<Form\.Item\s+name="{field}"\s+label="{label_frag}[^"]*"[^>]*rules=\{{[^\}}]*required[^\}}]*\}}[^>]*>\s*'
            r'<InputNumber[^/]*/>\s*'
            r'</Form\.Item>',
            f'<Form.Item name="{field}" label="{label_frag} *"\n                rules={{[{{ required: true, message: \'Vui lòng nhập {label_frag}\' }}]}}>\n                <Input placeholder="vd: 2 hoặc IBC" />\n              </Form.Item>',
            src
        )
        # simple variant
        src = re.sub(
            rf'<Form\.Item\s+name="{field}"\s+label="{label_frag}"[^>]*>\s*'
            r'<InputNumber[^/]*/>\s*'
            r'</Form\.Item>',
            f'<Form.Item name="{field}" label="{label_frag}">\n                <Input placeholder="vd: 2 hoặc IBC" />\n              </Form.Item>',
            src
        )

    # 4. total_tilt: always optional, now Input
    src = re.sub(
        r'<Form\.Item\s+name="total_tilt"\s+label="Total Tilt"[^>]*>\s*'
        r'<InputNumber[^/]*/>\s*'
        r'</Form\.Item>',
        '<Form.Item name="total_tilt" label="Total Tilt">\n                <Input placeholder="vd: 6 hoặc IBC" />\n              </Form.Item>',
        src
    )

    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print(f"  {path} patched OK")


patch_cell_page("frontend/src/pages/cells/Cells3GPage.tsx", "3g")
patch_cell_page("frontend/src/pages/cells/Cells4GPage.tsx", "4g")
patch_cell_page("frontend/src/pages/cells/Cells5GPage.tsx", "5g")
PATCHEOF

# ─────────────────────────────────────────────────────────────────────────────
# 9. CELL BULK EDIT MODAL
# ─────────────────────────────────────────────────────────────────────────────

echo "[9/10] Patching CellBulkEditModal.tsx..."

cat > "${FRONTEND}/components/shared/CellBulkEditModal.tsx" << 'TSEOF'
/**
 * CellBulkEditModal
 * -----------------
 * Generic bulk-edit modal for Cell 3G / 4G / 5G.
 *
 * do_cao_anten, azimuth, m_tilt, e_tilt, total_tilt are now STRING fields.
 * They use <Input> instead of <InputNumber>.
 * Validators still warn if a numeric value is out of range, but accept
 * any non-numeric string (e.g. "IBC", "N/A").
 */
import React, { useState, useRef } from 'react'
import {
  Modal, Form, Input, Select, Row, Col,
  Alert, Space, Typography, Divider,
} from 'antd'
import { EditOutlined, ExclamationCircleOutlined } from '@ant-design/icons'
import { azimuthValidator, tiltValidator, positiveNumberValidator } from '@/utils/validators'

export type CellTech = '3g' | '4g' | '5g'

interface Props {
  open:        boolean
  onClose:     () => void
  count:       number
  tech:        CellTech
  antennaList: { id: number; name: string }[]
  onConfirm:   (changes: Record<string, unknown>) => Promise<void>
}

const VENDORS   = ['Ericsson', 'Nokia', 'Huawei', 'ZTE', 'Samsung']
const MIMOS     = ['2x2', '4x4', '8x8']
const MORANS    = ['VNPT HOST', 'MBF HOST']
const VUNGS     = ['Indoor', 'Outdoor']
const CELL_VIPS = ['VIP', 'VVIP']

const CHUNG_ANTEN: Record<CellTech, string[]> = {
  '3g': ['3G', '3G/4G', '2G/3G/4G', '3G/4G/5G', '3G/5G'],
  '4g': ['4G', '2G/4G', '3G/4G', '2G/3G/4G', '4G/5G'],
  '5g': [],
}

export default function CellBulkEditModal({
  open, onClose, count, tech, antennaList, onConfirm,
}: Props) {
  const [form]   = Form.useForm()
  const [busy,   setBusy]   = useState(false)
  const [errors, setErrors] = useState<string[]>([])
  const touchedFields = useRef<Set<string>>(new Set())

  const handleFieldsChange = (changedFields: any[]) => {
    changedFields.forEach(f => {
      if (f.name) {
        const name = Array.isArray(f.name) ? f.name[0] : f.name
        touchedFields.current.add(String(name))
      }
    })
  }

  const handleOk = async () => {
    try { await form.validateFields() } catch { return }
    const allValues = form.getFieldsValue()

    const changes: Record<string, unknown> = {}
    touchedFields.current.forEach(fieldName => {
      const v = allValues[fieldName]
      if (v !== undefined) {
        changes[fieldName] = v
      }
    })

    if (Object.keys(changes).length === 0) {
      setErrors(['Vui lòng thay đổi ít nhất một trường để cập nhật'])
      return
    }

    setBusy(true)
    setErrors([])
    try {
      await onConfirm(changes)
      handleClose()
    } catch (e: any) {
      setErrors([e?.response?.data?.detail || e?.message || 'Có lỗi xảy ra'])
    } finally {
      setBusy(false)
    }
  }

  const handleClose = () => {
    form.resetFields()
    touchedFields.current.clear()
    setErrors([])
    onClose()
  }

  const techLabel = tech.toUpperCase()

  return (
    <Modal
      title={
        <Space>
          <EditOutlined style={{ color: '#1890ff' }} />
          <span>Sửa hàng loạt – {count} Cell {techLabel} đã chọn</span>
        </Space>
      }
      open={open}
      onCancel={handleClose}
      onOk={handleOk}
      okText="Cập nhật tất cả"
      cancelText="Hủy"
      confirmLoading={busy}
      width={900}
      destroyOnClose
    >
      <Alert
        type="warning"
        showIcon
        icon={<ExclamationCircleOutlined />}
        style={{ marginBottom: 16 }}
        message={
          <span>
            Đang cập nhật <strong>{count}</strong> Cell {techLabel} được chọn.{' '}
            Chỉ các trường bạn <strong>thay đổi</strong> mới được cập nhật.
          </span>
        }
      />

      {errors.length > 0 && (
        <Alert
          type="error"
          showIcon
          style={{ marginBottom: 16 }}
          message="Lỗi"
          description={errors.map((e, i) => <div key={i}>{e}</div>)}
        />
      )}

      <Form form={form} layout="vertical" onFieldsChange={handleFieldsChange}>

        {/* ── Common fields ── */}
        <Typography.Text strong style={{ color: '#666', fontSize: 12 }}>
          THÔNG TIN CHUNG
        </Typography.Text>
        <Divider style={{ margin: '6px 0 12px' }} />
        <Row gutter={12}>
          <Col span={6}>
            <Form.Item name="cell_vip" label="Cell VIP">
              <Select allowClear placeholder="(giữ nguyên)">
                {CELL_VIPS.map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}
              </Select>
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item name="moran" label="MORAN">
              <Select allowClear placeholder="(giữ nguyên)">
                {MORANS.map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}
              </Select>
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item name="vung_phu_song" label="Vùng phủ sóng">
              <Select allowClear placeholder="(giữ nguyên)">
                {VUNGS.map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}
              </Select>
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item name="vendor" label="Vendor">
              <Select allowClear placeholder="(giữ nguyên)">
                {VENDORS.map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}
              </Select>
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item name="mimo" label="MIMO">
              <Select allowClear placeholder="(giữ nguyên)">
                {MIMOS.map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}
              </Select>
            </Form.Item>
          </Col>
          {tech !== '5g' && (
            <Col span={6}>
              <Form.Item name="chung_anten" label="Chung anten">
                <Select allowClear placeholder="(giữ nguyên)">
                  {CHUNG_ANTEN[tech].map(v => (
                    <Select.Option key={v} value={v}>{v}</Select.Option>
                  ))}
                </Select>
              </Form.Item>
            </Col>
          )}
          {tech === '5g' && (
            <Col span={6}>
              <Form.Item name="mu_mimo" label="MU-MIMO">
                <Select allowClear placeholder="(giữ nguyên)">
                  <Select.Option value="Yes">Yes</Select.Option>
                  <Select.Option value="No">No</Select.Option>
                </Select>
              </Form.Item>
            </Col>
          )}
          {/* String fields – use Input, soft numeric validation */}
          <Col span={6}>
            <Form.Item
              name="azimuth"
              label="Azimuth"
              rules={[{ validator: azimuthValidator }]}
            >
              <Input placeholder="vd: 120 hoặc IBC" />
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item name="m_tilt" label="M-tilt"
              rules={[{ validator: tiltValidator }]}>
              <Input placeholder="vd: 2 hoặc IBC" />
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item name="e_tilt" label="E-Tilt"
              rules={[{ validator: tiltValidator }]}>
              <Input placeholder="vd: 4 hoặc IBC" />
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item name="total_tilt" label="Total Tilt"
              rules={[{ validator: tiltValidator }]}>
              <Input placeholder="vd: 6 hoặc IBC" />
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item name="do_cao_anten" label="Độ cao anten"
              rules={[{ validator: positiveNumberValidator }]}>
              <Input placeholder="vd: 28 hoặc IBC" />
            </Form.Item>
          </Col>
        </Row>

        {/* ── Antenna / Equipment ── */}
        <Typography.Text strong style={{ color: '#666', fontSize: 12 }}>
          THIẾT BỊ
        </Typography.Text>
        <Divider style={{ margin: '6px 0 12px' }} />
        <Row gutter={12}>
          <Col span={24}>
            <Form.Item name="loai_anten" label="Loại Anten">
              <Select
                showSearch allowClear placeholder="(giữ nguyên)"
                filterOption={(i, o) =>
                  String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())
                }
              >
                {antennaList.map(a => (
                  <Select.Option key={a.id} value={a.name}>{a.name}</Select.Option>
                ))}
              </Select>
            </Form.Item>
          </Col>
          <Col span={8}>
            <Form.Item name="baseband" label="Baseband">
              <Input placeholder="(giữ nguyên)" />
            </Form.Item>
          </Col>
          <Col span={8}>
            <Form.Item name="rf" label="RF">
              <Input placeholder="(giữ nguyên)" />
            </Form.Item>
          </Col>
          <Col span={8}>
            <Form.Item name="bbu_name" label="BBUname">
              <Input placeholder="(giữ nguyên)" />
            </Form.Item>
          </Col>
          <Col span={16}>
            <Form.Item name="cell_status" label="Cell status (at dump time)">
              <Input placeholder="(giữ nguyên)" />
            </Form.Item>
          </Col>
        </Row>
      </Form>
    </Modal>
  )
}
TSEOF

# ─────────────────────────────────────────────────────────────────────────────
# 10. SITE BULK EDIT MODAL – patch height fields
# ─────────────────────────────────────────────────────────────────────────────

echo "[10/10] Patching SiteBulkEditModal.tsx height fields..."

python3 << 'PATCHEOF'
path = "frontend/src/components/shared/SiteBulkEditModal.tsx"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

# Replace InputNumber imports – keep the rest but drop InputNumber if only used for heights
# Actually SiteBulkEditModal still uses InputNumber for lat/long, so we keep the import.
# Just replace the two height fields from InputNumber to Input.

old_cao_dinh = '''          <Col span={6}>
            <Form.Item name="do_cao_dinh_cot_anten" label="Cao đỉnh cột anten (m)">
              <InputNumber style={{ width: '100%' }} min={0} placeholder="(giữ nguyên)" />
            </Form.Item>
          </Col>'''

new_cao_dinh = '''          <Col span={6}>
            <Form.Item name="do_cao_dinh_cot_anten" label="Cao đỉnh cột anten">
              <Input placeholder="vd: 35 hoặc IBC" />
            </Form.Item>
          </Col>'''

old_cao_cot = '''          <Col span={6}>
            <Form.Item name="do_cao_cot_anten" label="Cao cột anten (m)">
              <InputNumber style={{ width: '100%' }} min={0} placeholder="(giữ nguyên)" />
            </Form.Item>
          </Col>'''

new_cao_cot = '''          <Col span={6}>
            <Form.Item name="do_cao_cot_anten" label="Cao cột anten">
              <Input placeholder="vd: 30 hoặc IBC" />
            </Form.Item>
          </Col>'''

src = src.replace(old_cao_dinh, new_cao_dinh)
src = src.replace(old_cao_cot, new_cao_cot)

# Ensure Input is imported (it already is, so just verify)
if 'Input,' not in src and 'Input ' not in src:
    src = src.replace(
        "import {\n  Modal, Form, Input,",
        "import {\n  Modal, Form, Input,"
    )

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("  SiteBulkEditModal.tsx patched OK")
PATCHEOF

echo ""
echo "=== All code patches applied successfully ==="
echo ""
echo "Next steps:"
echo "  1. Run the SQL migration:  psql -U sitelink -d sitelink_db -f alter_float_to_string.sql"
echo "  2. Restart backend:        docker compose restart backend"
echo "  3. Rebuild frontend:       cd frontend && npm run build"
echo "  4. Templates will be auto-regenerated on backend startup."
echo ""
echo "Summary of changes:"
echo "  - backend/app/models/site.py              : do_cao_dinh_cot_anten, do_cao_cot_anten → String(50)"
echo "  - backend/app/models/cell_3g/4g/5g.py     : do_cao_anten, azimuth, m_tilt, e_tilt, total_tilt → String(50)"
echo "  - backend/app/models/site_revision.py      : same site fields"
echo "  - backend/app/models/cell_revision.py      : same cell fields"
echo "  - backend/app/schemas/site.py              : do_cao_* → Optional[str]"
echo "  - backend/app/schemas/cell.py              : do_cao_anten, azimuth, m_tilt, e_tilt, total_tilt → Optional[str]"
echo "  - backend/app/services/import_excel.py     : _str_aware() helper; no numeric range checks on those fields"
echo "  - backend/create_excel_templates.py        : removed numeric DV rules for those columns"
echo "  - frontend/src/types/index.ts              : affected fields → string"
echo "  - frontend/src/utils/validators.ts         : azimuth/tilt/positive = soft numeric checks, accept any string"
echo "  - frontend/src/pages/sites/SiteFormPage.tsx: height fields use <Input> not <InputNumber>"
echo "  - frontend/src/pages/cells/Cells*Page.tsx  : do_cao_anten,azimuth,m_tilt,e_tilt,total_tilt use <Input>"
echo "  - frontend/src/components/shared/CellBulkEditModal.tsx: same"
echo "  - frontend/src/components/shared/SiteBulkEditModal.tsx: height fields use <Input>"