#!/usr/bin/env bash
# =============================================================================
# SiteLink – Add new cell columns (3G / 4G / 5G)
# Run from project root:  bash update_cells.sh
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND="$ROOT/backend"
FRONTEND="$ROOT/frontend/src"

echo "=== SiteLink cell column update ==="

# ─────────────────────────────────────────────────────────────────────────────
# 1. SQL MIGRATION
# ─────────────────────────────────────────────────────────────────────────────
cat > "$ROOT/migrate_new_cell_columns.sql" << 'SQLEOF'
-- ============================================================
-- SiteLink DB Migration: new cell columns (3G / 4G / 5G)
-- Run with:
--   docker exec -i sitelink_postgres psql -U sitelink -d sitelink_db \
--     < migrate_new_cell_columns.sql
-- ============================================================

-- ── Cell 3G ──────────────────────────────────────────────────────────────────
ALTER TABLE cells_3g
  ADD COLUMN IF NOT EXISTS uarfcn            VARCHAR(50),
  ADD COLUMN IF NOT EXISTS lac               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS rac               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS ura_id            VARCHAR(50),
  ADD COLUMN IF NOT EXISTS cell_max_power    VARCHAR(50),
  ADD COLUMN IF NOT EXISTS cpich_power       VARCHAR(50),
  ADD COLUMN IF NOT EXISTS bbu_name          VARCHAR(100),
  ADD COLUMN IF NOT EXISTS cell_status       VARCHAR(100);

-- ── Cell 4G ──────────────────────────────────────────────────────────────────
ALTER TABLE cells_4g
  ADD COLUMN IF NOT EXISTS enodeb_id         VARCHAR(50),
  ADD COLUMN IF NOT EXISTS tac               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS bandwidth         VARCHAR(50),
  ADD COLUMN IF NOT EXISTS cell_max_power    VARCHAR(50),
  ADD COLUMN IF NOT EXISTS eci               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS bbu_name          VARCHAR(100),
  ADD COLUMN IF NOT EXISTS cell_status       VARCHAR(100);

-- ── Cell 5G ──────────────────────────────────────────────────────────────────
ALTER TABLE cells_5g
  ADD COLUMN IF NOT EXISTS gnodeb_id         VARCHAR(50),
  ADD COLUMN IF NOT EXISTS tac               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS ssb_arfcn         VARCHAR(50),
  ADD COLUMN IF NOT EXISTS center_arfcn      VARCHAR(50),
  ADD COLUMN IF NOT EXISTS gscn              VARCHAR(50),
  ADD COLUMN IF NOT EXISTS bandwidth         VARCHAR(50),
  ADD COLUMN IF NOT EXISTS cell_max_power    VARCHAR(50),
  ADD COLUMN IF NOT EXISTS nci               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS bbu_name          VARCHAR(100),
  ADD COLUMN IF NOT EXISTS mu_mimo           VARCHAR(20),
  ADD COLUMN IF NOT EXISTS cell_status       VARCHAR(100);

-- ── Cell 3G revisions ─────────────────────────────────────────────────────────
ALTER TABLE cell_3g_revisions
  ADD COLUMN IF NOT EXISTS uarfcn            VARCHAR(50),
  ADD COLUMN IF NOT EXISTS lac               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS rac               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS ura_id            VARCHAR(50),
  ADD COLUMN IF NOT EXISTS cell_max_power    VARCHAR(50),
  ADD COLUMN IF NOT EXISTS cpich_power       VARCHAR(50),
  ADD COLUMN IF NOT EXISTS bbu_name          VARCHAR(100),
  ADD COLUMN IF NOT EXISTS cell_status       VARCHAR(100);

-- ── Cell 4G revisions ─────────────────────────────────────────────────────────
ALTER TABLE cell_4g_revisions
  ADD COLUMN IF NOT EXISTS enodeb_id         VARCHAR(50),
  ADD COLUMN IF NOT EXISTS tac               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS bandwidth         VARCHAR(50),
  ADD COLUMN IF NOT EXISTS cell_max_power    VARCHAR(50),
  ADD COLUMN IF NOT EXISTS eci               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS bbu_name          VARCHAR(100),
  ADD COLUMN IF NOT EXISTS cell_status       VARCHAR(100);

-- ── Cell 5G revisions ─────────────────────────────────────────────────────────
ALTER TABLE cell_5g_revisions
  ADD COLUMN IF NOT EXISTS gnodeb_id         VARCHAR(50),
  ADD COLUMN IF NOT EXISTS tac               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS ssb_arfcn         VARCHAR(50),
  ADD COLUMN IF NOT EXISTS center_arfcn      VARCHAR(50),
  ADD COLUMN IF NOT EXISTS gscn              VARCHAR(50),
  ADD COLUMN IF NOT EXISTS bandwidth         VARCHAR(50),
  ADD COLUMN IF NOT EXISTS cell_max_power    VARCHAR(50),
  ADD COLUMN IF NOT EXISTS nci               VARCHAR(50),
  ADD COLUMN IF NOT EXISTS bbu_name          VARCHAR(100),
  ADD COLUMN IF NOT EXISTS mu_mimo           VARCHAR(20),
  ADD COLUMN IF NOT EXISTS cell_status       VARCHAR(100);

SELECT 'New cell columns migration completed.' AS result;
SQLEOF
echo "[OK] migrate_new_cell_columns.sql"

# ─────────────────────────────────────────────────────────────────────────────
# 2. BACKEND – models/cell_3g.py
# ─────────────────────────────────────────────────────────────────────────────
cat > "$BACKEND/app/models/cell_3g.py" << 'PYEOF'
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
PYEOF
echo "[OK] models/cell_3g.py"

# ─────────────────────────────────────────────────────────────────────────────
# 3. BACKEND – models/cell_4g.py
# ─────────────────────────────────────────────────────────────────────────────
cat > "$BACKEND/app/models/cell_4g.py" << 'PYEOF'
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
PYEOF
echo "[OK] models/cell_4g.py"

# ─────────────────────────────────────────────────────────────────────────────
# 4. BACKEND – models/cell_5g.py
# ─────────────────────────────────────────────────────────────────────────────
cat > "$BACKEND/app/models/cell_5g.py" << 'PYEOF'
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
    do_cao_anten     = Column(Float)
    azimuth          = Column(Float)
    m_tilt           = Column(Float)
    e_tilt           = Column(Float)
    total_tilt       = Column(Float)
    loai_anten       = Column(String(200))
    baseband         = Column(String(100))
    rf               = Column(String(100))
    gnodeb_id        = Column(String(50))   # gNodeB ID
    cell_id          = Column(String(50))
    tac              = Column(String(50))   # Tracking Area Code
    pci              = Column(String(50))
    root_sequence_id = Column(String(50))
    mimo             = Column(String(100))
    ssb_arfcn        = Column(String(50))   # SSB-ARFCN
    center_arfcn     = Column(String(50))   # Center-ARFCN
    gscn             = Column(String(50))   # GSCN
    bandwidth        = Column(String(50))   # Bandwidth (MHz)
    cell_max_power   = Column(String(50))   # Cell max power (dBm)
    nci              = Column(String(50))   # NR Cell Identity
    bbu_name         = Column(String(100))  # BBU name
    mu_mimo          = Column(String(20))   # MU-MIMO
    cell_status      = Column(String(100))  # Cell status at dump time
    created_at       = Column(DateTime(timezone=True),
                              default=lambda: datetime.now(timezone.utc))
    updated_at       = Column(DateTime(timezone=True),
                              default=lambda: datetime.now(timezone.utc),
                              onupdate=lambda: datetime.now(timezone.utc))
    created_by       = Column(Integer, ForeignKey("users.id"), nullable=True)

    site = relationship("Site", back_populates="cells_5g")
PYEOF
echo "[OK] models/cell_5g.py"

# ─────────────────────────────────────────────────────────────────────────────
# 5. BACKEND – models/cell_revision.py
# ─────────────────────────────────────────────────────────────────────────────
cat > "$BACKEND/app/models/cell_revision.py" << 'PYEOF'
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
echo "[OK] models/cell_revision.py"

# ─────────────────────────────────────────────────────────────────────────────
# 6. BACKEND – schemas/cell.py
# ─────────────────────────────────────────────────────────────────────────────
cat > "$BACKEND/app/schemas/cell.py" << 'PYEOF'
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
    arfcn:          Optional[str] = None   # legacy / backward compat
    uarfcn:         Optional[str] = None   # UARFCN
    lac:            Optional[str] = None   # Location Area Code
    rac:            Optional[str] = None   # Routing Area Code
    psc:            Optional[str] = None   # Primary Scrambling Code
    ura_id:         Optional[str] = None   # URA ID
    cpich_power:    Optional[str] = None   # CPICH power (dBm)


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
    enodeb_id:        Optional[str] = None   # eNodeB ID
    earfcn:           Optional[str] = None
    tac:              Optional[str] = None   # Tracking Area Code
    pci:              Optional[str] = None
    root_sequence_id: Optional[str] = None
    bandwidth:        Optional[str] = None   # Bandwidth (MHz)
    eci:              Optional[str] = None   # E-UTRAN Cell Identifier


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
    gnodeb_id:        Optional[str] = None   # gNodeB ID
    tac:              Optional[str] = None   # Tracking Area Code
    pci:              Optional[str] = None
    root_sequence_id: Optional[str] = None
    ssb_arfcn:        Optional[str] = None   # SSB-ARFCN
    center_arfcn:     Optional[str] = None   # Center-ARFCN
    gscn:             Optional[str] = None   # GSCN
    bandwidth:        Optional[str] = None   # Bandwidth (MHz)
    nci:              Optional[str] = None   # NR Cell Identity
    mu_mimo:          Optional[str] = None   # MU-MIMO


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
echo "[OK] schemas/cell.py"

# ─────────────────────────────────────────────────────────────────────────────
# 7. BACKEND – services/revision.py  (updated snapshots)
# ─────────────────────────────────────────────────────────────────────────────
cat > "$BACKEND/app/services/revision.py" << 'PYEOF'
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


def _diff(old: Dict, new: Dict) -> Dict:
    result = {}
    all_keys = set(old) | set(new)
    for k in all_keys:
        ov = old.get(k)
        nv = new.get(k)
        if ov != nv:
            result[k] = [ov, nv]
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


def _site_snapshot(site: Site) -> Dict[str, Any]:
    return {
        "mien": site.mien, "tinh": site.tinh, "phuong_xa": site.phuong_xa,
        "site_name_cu": site.site_name_cu, "site_vip": site.site_vip,
        "lat": site.lat, "long": site.long,
        "tram_2g": site.tram_2g, "tram_3g": site.tram_3g,
        "tram_4g": site.tram_4g, "tram_5g": site.tram_5g,
        "repeater": site.repeater, "booster": site.booster,
        "node_truyen_dan_only": site.node_truyen_dan_only,
        "tram_phu_song_tsca": site.tram_phu_song_tsca,
        "phan_loai_tram": site.phan_loai_tram,
        "moran_3g": site.moran_3g, "moran_4g": site.moran_4g, "moran_5g": site.moran_5g,
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
        "do_cao_anten": cell.do_cao_anten, "azimuth": cell.azimuth,
        "m_tilt": cell.m_tilt, "e_tilt": cell.e_tilt, "total_tilt": cell.total_tilt,
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
        "m_tilt": cell.m_tilt, "e_tilt": cell.e_tilt, "total_tilt": cell.total_tilt,
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
        "site_name": cell.site_name, "site_name_old": cell.site_name_old,
        "cell_name": cell.cell_name, "cell_name_old": cell.cell_name_old,
        "mien": cell.mien, "tinh": cell.tinh, "phuong_xa": cell.phuong_xa,
        "cell_vip": cell.cell_vip, "moran": cell.moran,
        "lat": cell.lat, "long": cell.long,
        "vung_phu_song": cell.vung_phu_song, "vendor": cell.vendor,
        "do_cao_anten": cell.do_cao_anten, "azimuth": cell.azimuth,
        "m_tilt": cell.m_tilt, "e_tilt": cell.e_tilt, "total_tilt": cell.total_tilt,
        "loai_anten": cell.loai_anten,
        "baseband": cell.baseband, "rf": cell.rf,
        "gnodeb_id": cell.gnodeb_id, "cell_id": cell.cell_id,
        "tac": cell.tac, "pci": cell.pci,
        "root_sequence_id": cell.root_sequence_id, "mimo": cell.mimo,
        "ssb_arfcn": cell.ssb_arfcn, "center_arfcn": cell.center_arfcn,
        "gscn": cell.gscn, "bandwidth": cell.bandwidth,
        "cell_max_power": cell.cell_max_power, "nci": cell.nci,
        "bbu_name": cell.bbu_name, "mu_mimo": cell.mu_mimo,
        "cell_status": cell.cell_status,
    }


def record_site_revision(
    db: Session, site: Site, old_snapshot: Optional[Dict],
    changed_by_id: Optional[int], changed_by_name: Optional[str],
    change_source: str = "form", change_note: Optional[str] = None,
    site_name_old_ref: Optional[str] = None,
) -> SiteRevision:
    new_snap = _site_snapshot(site)
    diff = _diff(old_snapshot, new_snap) if old_snapshot else {}
    rev = SiteRevision(
        site_id=site.id, site_name=site.site_name,
        revision_no=_next_rev_no_site(db, site.id),
        changed_by=changed_by_id, changed_by_name=changed_by_name,
        change_source=change_source, change_note=change_note,
        site_name_old_ref=site_name_old_ref,
        mien=site.mien, tinh=site.tinh, phuong_xa=site.phuong_xa,
        site_name_cu=site.site_name_cu, site_vip=site.site_vip,
        lat=site.lat, long=site.long,
        tram_2g=site.tram_2g, tram_3g=site.tram_3g,
        tram_4g=site.tram_4g, tram_5g=site.tram_5g,
        repeater=site.repeater, booster=site.booster,
        node_truyen_dan_only=site.node_truyen_dan_only,
        tram_phu_song_tsca=site.tram_phu_song_tsca,
        phan_loai_tram=site.phan_loai_tram,
        moran_3g=site.moran_3g, moran_4g=site.moran_4g, moran_5g=site.moran_5g,
        ma_ptm=site.ma_ptm,
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
) -> Cell3GRevision:
    new_snap = _cell3g_snapshot(cell)
    diff = _diff(old_snapshot, new_snap) if old_snapshot else {}
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
) -> Cell4GRevision:
    new_snap = _cell4g_snapshot(cell)
    diff = _diff(old_snapshot, new_snap) if old_snapshot else {}
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
) -> Cell5GRevision:
    new_snap = _cell5g_snapshot(cell)
    diff = _diff(old_snapshot, new_snap) if old_snapshot else {}
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
echo "[OK] services/revision.py"

# ─────────────────────────────────────────────────────────────────────────────
# 8. BACKEND – services/import_excel.py  (new columns)
# ─────────────────────────────────────────────────────────────────────────────
cat > "$BACKEND/app/services/import_excel.py" << 'PYEOF'
"""
import_excel.py – Excel → DB record conversion for Sites, Cell3G, Cell4G, Cell5G.
"""
from __future__ import annotations

import io
import re
import unicodedata
from typing import Any, Dict, List, Optional, Tuple

import pandas as pd

VN_LAT_MIN, VN_LAT_MAX = 8.33,   23.39
VN_LON_MIN, VN_LON_MAX = 102.14, 109.47
AZI_MIN,    AZI_MAX    = 0,       359


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
                self.xa_map[(_normalize(r.ten_tinh), _normalize(r.ten_phuong_xa))] = r.ten_phuong_xa

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


def _v(row, *keys) -> Optional[str]:
    for key in keys:
        val = row.get(key)
        if val is not None and str(val).strip() not in ("", "nan", "None"):
            return str(val).strip()
    return None


def _bool(row, *keys) -> bool:
    v = _v(row, *keys)
    if v is None:
        return False
    return str(v).strip().lower() in ("x", "true", "yes", "1", "co", "có")


def _float(row, *keys) -> Optional[float]:
    v = _v(row, *keys)
    if v is None:
        return None
    try:
        return float(v)
    except (ValueError, TypeError):
        return None


def _validate_lat(lat, row_num, label, errors):
    if lat is None:
        return None
    if not (VN_LAT_MIN <= lat <= VN_LAT_MAX):
        errors.append(
            f"Row {row_num} ({label}): Latitude {lat} ngoai pham vi Viet Nam "
            f"({VN_LAT_MIN}–{VN_LAT_MAX}) – giu nguyen gia tri nhung canh bao"
        )
    return lat


def _validate_lon(lon, row_num, label, errors):
    if lon is None:
        return None
    if not (VN_LON_MIN <= lon <= VN_LON_MAX):
        errors.append(
            f"Row {row_num} ({label}): Longitude {lon} ngoai pham vi Viet Nam "
            f"({VN_LON_MIN}–{VN_LON_MAX}) – giu nguyen gia tri nhung canh bao"
        )
    return lon


def _validate_azimuth(azi, row_num, label, errors):
    if azi is None:
        return None
    if not (AZI_MIN <= azi <= AZI_MAX):
        errors.append(
            f"Row {row_num} ({label}): Azimuth {azi} phai trong khoang "
            f"{AZI_MIN}–{AZI_MAX} – dong bi bo qua"
        )
        return None
    return azi


# ── Site import ───────────────────────────────────────────────────────────────
def parse_site_excel(file_bytes: bytes, db=None, dry_run: bool = False) -> Dict[str, Any]:
    df  = _read_excel(file_bytes)
    geo = GeoCache(db) if db else None
    to_create: List[Dict] = []
    to_update: List[Dict] = []
    errors:    List[str]  = []

    from app.models.site import Site

    for i, row in df.iterrows():
        row_num   = int(str(i)) + 2
        site_name = _v(row, "Site name", "Site Name", "site_name", "SITE NAME")
        if not site_name:
            errors.append(f"Row {row_num}: 'Site name' column is empty – skipped")
            continue

        raw_tinh   = _v(row, "Tỉnh", "Tinh", "TINH", "tinh", "Province")
        raw_phuong = _v(row, "Phường xã", "Phuong xa", "Phường Xã", "phuong_xa", "Ward")
        raw_mien   = _v(row, "Miền", "Mien", "MIEN", "mien")

        if geo and raw_tinh:
            tinh_official = geo.resolve_tinh(raw_tinh)
            if not tinh_official:
                errors.append(
                    f"Row {row_num} (site '{site_name}'): "
                    f"Province '{raw_tinh}' not found in DB – skipped"
                )
                continue
            mien = geo.mien_for(tinh_official) or raw_mien or ""
            phuong_xa_official: Optional[str] = None
            if raw_phuong:
                phuong_xa_official = geo.resolve_xa(tinh_official, raw_phuong)
                if not phuong_xa_official:
                    errors.append(
                        f"Row {row_num} (site '{site_name}'): "
                        f"Ward '{raw_phuong}' not found under '{tinh_official}' – field left blank"
                    )
        else:
            tinh_official      = raw_tinh or ""
            mien               = raw_mien or ""
            phuong_xa_official = raw_phuong

        if not tinh_official:
            errors.append(f"Row {row_num} (site '{site_name}'): 'Tinh' is empty – skipped")
            continue

        raw_lat  = _float(row, "Lat", "LAT", "lat", "Latitude")
        raw_long = _float(row, "Long", "LONG", "long", "Longitude")
        lat  = _validate_lat(raw_lat,  row_num, site_name, errors)
        long = _validate_lon(raw_long, row_num, site_name, errors)

        file_site_name_old = _v(row, "Site name (cũ)", "Site name (cu)", "Site Name (cũ)",
                                 "Site Name Old", "site_name_old")

        rec: Dict[str, Any] = {
            "mien": mien, "tinh": tinh_official, "phuong_xa": phuong_xa_official,
            "site_name_cu": file_site_name_old, "site_name": site_name,
            "site_vip": _v(row, "Site VIP", "site_vip"),
            "lat": lat, "long": long,
            "tram_2g": _bool(row, "Trạm 2G", "Tram 2G", "tram_2g"),
            "tram_3g": _bool(row, "Trạm 3G", "Tram 3G", "tram_3g"),
            "tram_4g": _bool(row, "Trạm 4G", "Tram 4G", "tram_4g"),
            "tram_5g": _bool(row, "Trạm 5G", "Tram 5G", "tram_5g"),
            "repeater": _bool(row, "Repeater", "repeater"),
            "booster":  _bool(row, "Booster",  "booster"),
            "node_truyen_dan_only": _bool(row, "Node truyền dẫn only",
                                          "Node truyen dan only", "node_truyen_dan_only"),
            "tram_phu_song_tsca": _bool(row, "Trạm phủ sóng TSCA",
                                        "Tram phu song TSCA", "tram_phu_song_tsca"),
            "phan_loai_tram": _v(row, "IBC/ Macro outdoor / IBC + Outdoor / miniDAS / Smallcell",
                                  "Phan loai tram", "phan_loai_tram"),
            "moran_3g": _v(row, "TRẠM MORAN 3G (VNPT HOST, MBF HOST)", "MORAN 3G", "moran_3g"),
            "moran_4g": _v(row, "TRẠM MORAN 4G (VNPT HOST, MBF HOST)", "MORAN 4G", "moran_4g"),
            "moran_5g": _v(row, "TRẠM MORAN 5G (VNPT HOST, MBF HOST)", "MORAN 5G", "moran_5g"),
            "ma_ptm": _v(row, "Mã PTM", "Ma PTM", "ma_ptm", "MaPTM", "PTM") or "",
            "do_cao_dinh_cot_anten": _float(row, "Độ cao đỉnh cột anten (m) đến mặt đất",
                                            "Do cao dinh cot anten", "do_cao_dinh_cot_anten"),
            "do_cao_cot_anten": _float(row, "Độ cao cột anten", "Do cao cot anten",
                                       "do_cao_cot_anten"),
            "dia_chi": _v(row, "Địa chỉ", "Dia chi", "dia_chi"),
            "ghi_chu": _v(row, "Ghi chú", "Ghi chu", "ghi_chu"),
        }

        if db:
            existing = db.query(Site).filter(Site.site_name == site_name).first()
            if not existing and file_site_name_old:
                existing_by_old = db.query(Site).filter(
                    Site.site_name == file_site_name_old).first()
                if existing_by_old:
                    rec["_site_name_old_ref"] = file_site_name_old
                    to_update.append({
                        "existing_id": existing_by_old.id, "anchor": file_site_name_old,
                        "changes": rec, "is_rename": True,
                    })
                    continue
            if existing:
                to_update.append({
                    "existing_id": existing.id, "anchor": site_name,
                    "changes": rec, "is_rename": False,
                })
            else:
                to_create.append(rec)
        else:
            to_create.append(rec)

    return {"to_create": to_create, "to_update": to_update, "errors": errors, "dry_run": dry_run}


# ── Cell common ───────────────────────────────────────────────────────────────
def _cell_common(row, geo=None, errors_out=None, row_num=0) -> Dict[str, Any]:
    raw_tinh   = _v(row, "Tỉnh", "Tinh", "tinh")
    raw_phuong = _v(row, "Phường xã", "Phuong xa", "phuong_xa")
    raw_mien   = _v(row, "Miền", "Mien", "mien")

    if geo and raw_tinh:
        tinh_official = geo.resolve_tinh(raw_tinh)
        if not tinh_official:
            if errors_out is not None:
                errors_out.append(f"Row {row_num}: Province '{raw_tinh}' not found in DB – stored as-is")
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

    raw_lat  = _float(row, "Lat", "LAT", "lat")
    raw_long = _float(row, "Long", "LONG", "long")
    raw_azi  = _float(row, "Azimuth", "azimuth")

    lat = _validate_lat(raw_lat,  row_num, label, errors_out or [])
    lon = _validate_lon(raw_long, row_num, label, errors_out or [])
    azi = _validate_azimuth(raw_azi, row_num, label, errors_out or [])

    return {
        "mien": mien, "tinh": tinh_official, "phuong_xa": phuong_xa_official,
        "site_name":     _v(row, "Site Name", "Site name", "site_name") or "",
        "site_name_old": _v(row, "Site Name Old", "Site name old", "site_name_old",
                             "Site Name (cũ)", "Site name (cu)"),
        "cell_name":     cell_name,
        "cell_name_old": _v(row, "Cell Name Old", "Cell name old", "cell_name_old",
                             "Cell Name (cũ)"),
        "cell_vip":      _v(row, "Cell VIP", "cell_vip"),
        "moran":         _v(row, "MORAN", "Moran", "moran"),
        "lat": lat, "long": lon,
        "vung_phu_song": _v(row, "Vùng phủ sóng", "Vung phu song", "vung_phu_song"),
        "vendor":        _v(row, "Vendor", "vendor"),
        "do_cao_anten":  _float(row, "Độ cao anten", "Do cao anten", "do_cao_anten"),
        "azimuth": azi,
        "m_tilt":   _float(row, "M-tilt", "M-Tilt", "m_tilt"),
        "e_tilt":   _float(row, "E-Tilt", "E-tilt", "e_tilt"),
        "total_tilt": _float(row, "Total Tilt", "Total tilt", "total_tilt"),
        "loai_anten": _v(row, "Loại Anten", "Loai Anten", "loai_anten"),
        "baseband":   _v(row, "Baseband", "baseband"),
        "rf":         _v(row, "RF", "rf"),
        "cell_id":    _v(row, "Cell ID", "cell_id"),
        "mimo":       _v(row, "MIMO", "mimo"),
        "bbu_name":   _v(row, "BBUname", "BBU Name", "bbu_name"),
        "cell_status": _v(row, "Cell status (at dump time)", "Cell status", "cell_status"),
        "cell_max_power": _v(row, "Cell max power (dBm)", "Cell max power", "cell_max_power"),
    }


def _parse_cell_excel(file_bytes, Model, extra_fields_fn, db=None, dry_run=False) -> Dict[str, Any]:
    df  = _read_excel(file_bytes)
    geo = GeoCache(db) if db else None

    to_create:        List[Dict] = []
    to_update:        List[Dict] = []
    sites_to_create:  List[Dict] = []
    errors:           List[str]  = []
    pending_new_sites: Dict[str, Dict] = {}

    from app.models.site import Site

    for i, row in df.iterrows():
        row_num    = int(str(i)) + 2
        row_errors: List[str] = []

        common    = _cell_common(row, geo=geo, errors_out=row_errors, row_num=row_num)
        errors.extend(row_errors)

        cell_name     = common.get("cell_name", "")
        cell_name_old = common.get("cell_name_old", "")
        site_name     = common.get("site_name", "")
        site_name_old = common.get("site_name_old", "")

        if not cell_name:
            errors.append(f"Row {row_num}: 'Cell Name' is empty – skipped")
            continue
        if not site_name:
            errors.append(f"Row {row_num}: 'Site Name' is empty – skipped")
            continue

        extra = extra_fields_fn(row)
        rec   = {**common, **extra}

        site_obj = None
        if db:
            site_obj = db.query(Site).filter(Site.site_name == site_name).first()
            if not site_obj and site_name_old:
                site_obj = db.query(Site).filter(Site.site_name == site_name_old).first()

        if site_obj:
            site_id = site_obj.id
        elif site_name in pending_new_sites:
            site_id = None
        else:
            new_site_rec = {
                "site_name": site_name, "mien": common.get("mien") or "",
                "tinh": common.get("tinh") or "", "phuong_xa": common.get("phuong_xa"),
                "lat": common.get("lat"), "long": common.get("long"),
            }
            pending_new_sites[site_name] = new_site_rec
            sites_to_create.append(new_site_rec)
            site_id = None

        rec["site_id"] = site_id

        existing_cell = None
        if db and site_obj:
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
                        "changes":     rec, "is_rename": True,
                    })
                    continue

        if existing_cell:
            to_update.append({
                "existing_id": existing_cell.id,
                "anchor":      f"{site_name}/{cell_name}",
                "changes":     rec, "is_rename": False,
            })
        else:
            to_create.append(rec)

    return {
        "to_create": to_create, "to_update": to_update,
        "sites_to_create": sites_to_create,
        "errors": errors, "dry_run": dry_run,
    }


def parse_site_excel_simple(file_bytes: bytes) -> List[Dict[str, Any]]:
    result = parse_site_excel(file_bytes, db=None, dry_run=False)
    records: List[Dict] = []
    for rec in result["to_create"]:
        records.append(rec)
    for upd in result["to_update"]:
        records.append(upd["changes"])
    return records


def parse_cell3g_excel(file_bytes, db=None, dry_run=False):
    from app.models.cell_3g import Cell3G
    def extra(row):
        return {
            "chung_anten": _v(row, "Chung anten", "chung_anten"),
            "arfcn":       _v(row, "ARFCN", "arfcn"),
            "uarfcn":      _v(row, "UARFCN", "uarfcn"),
            "lac":         _v(row, "LAC", "lac"),
            "rac":         _v(row, "RAC", "rac"),
            "psc":         _v(row, "PSC", "psc"),
            "ura_id":      _v(row, "URAId", "URA ID", "ura_id"),
            "cpich_power": _v(row, "CPICH power (dBm)", "CPICH power", "cpich_power"),
        }
    return _parse_cell_excel(file_bytes, Cell3G, extra, db=db, dry_run=dry_run)


def parse_cell4g_excel(file_bytes, db=None, dry_run=False):
    from app.models.cell_4g import Cell4G
    def extra(row):
        return {
            "chung_anten":      _v(row, "Chung anten",     "chung_anten"),
            "enodeb_id":        _v(row, "EnodeB ID",       "enodeb_id"),
            "earfcn":           _v(row, "EARFCN",           "earfcn"),
            "tac":              _v(row, "TAC",              "tac"),
            "pci":              _v(row, "PCI",              "pci"),
            "root_sequence_id": _v(row, "Root Sequence ID", "root_sequence_id"),
            "bandwidth":        _v(row, "Bandwitdh", "Bandwidth", "bandwidth"),
            "eci":              _v(row, "ECI",              "eci"),
        }
    return _parse_cell_excel(file_bytes, Cell4G, extra, db=db, dry_run=dry_run)


def parse_cell5g_excel(file_bytes, db=None, dry_run=False):
    from app.models.cell_5g import Cell5G
    def extra(row):
        return {
            "gnodeb_id":        _v(row, "gNodeB ID",       "gnodeb_id"),
            "tac":              _v(row, "TAC",              "tac"),
            "pci":              _v(row, "PCI",              "pci"),
            "root_sequence_id": _v(row, "Root Sequence ID", "root_sequence_id"),
            "ssb_arfcn":        _v(row, "SSB-ARFCN",        "ssb_arfcn"),
            "center_arfcn":     _v(row, "Center-ARFCN",     "center_arfcn"),
            "gscn":             _v(row, "GSCN",             "gscn"),
            "bandwidth":        _v(row, "Bandwidth (MHz)", "Bandwidth", "bandwidth"),
            "nci":              _v(row, "NCI",              "nci"),
            "mu_mimo":          _v(row, "MU-MIMO",          "mu_mimo"),
        }
    return _parse_cell_excel(file_bytes, Cell5G, extra, db=db, dry_run=dry_run)
PYEOF
echo "[OK] services/import_excel.py"

# ─────────────────────────────────────────────────────────────────────────────
# 9. BACKEND – api/routes/export.py  (new columns)
# ─────────────────────────────────────────────────────────────────────────────
cat > "$BACKEND/app/api/routes/export.py" << 'PYEOF'
"""
export.py – Excel export endpoints (Sites, Cells 3G/4G/5G, Antennas)
Token can be passed as Bearer header OR ?token= query param.
"""
from __future__ import annotations

import io
from typing import Optional

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
        cell.fill      = HEADER_FILL
        cell.font      = HEADER_FONT
        cell.alignment = CENTER
        cell.border    = BORDER
        ws.column_dimensions[get_column_letter(col_idx)].width = width
    return wb, ws


def _style_row(ws, row_idx, num_cols, alternate):
    fill = ALT_FILL if alternate else None
    for col_idx in range(1, num_cols + 1):
        cell = ws.cell(row=row_idx, column=col_idx)
        cell.alignment = LEFT
        cell.border    = BORDER
        if fill:
            cell.fill = fill


def _stream(wb, filename):
    buf = io.BytesIO()
    wb.save(buf)
    buf.seek(0)
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
    search:  Optional[str]  = Query(None),
    mien:    Optional[str]  = Query(None),
    tinh:    Optional[str]  = Query(None),
    tram_3g: Optional[bool] = Query(None),
    tram_4g: Optional[bool] = Query(None),
    tram_5g: Optional[bool] = Query(None),
    db:      Session        = Depends(get_db),
    _:       User           = Depends(get_optional_user),
):
    q = db.query(Site)
    if search:  q = q.filter(Site.site_name.ilike(f"%{search}%"))
    if mien:    q = q.filter(Site.mien == mien)
    if tinh:    q = q.filter(Site.tinh == tinh)
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

    def b(val): return "x" if val else ""

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
    search:        Optional[str] = Query(None),
    mien:          Optional[str] = Query(None),
    tinh:          Optional[str] = Query(None),
    vendor:        Optional[str] = Query(None),
    mimo:          Optional[str] = Query(None),
    vung_phu_song: Optional[str] = Query(None),
    db:    Session = Depends(get_db),
    _:     User    = Depends(get_optional_user),
):
    q = db.query(Cell3G)
    if search:        q = q.filter(Cell3G.cell_name.ilike(f"%{search}%") | Cell3G.site_name.ilike(f"%{search}%"))
    if mien:          q = q.filter(Cell3G.mien == mien)
    if tinh:          q = q.filter(Cell3G.tinh == tinh)
    if vendor:        q = q.filter(Cell3G.vendor == vendor)
    if mimo:          q = q.filter(Cell3G.mimo == mimo)
    if vung_phu_song: q = q.filter(Cell3G.vung_phu_song == vung_phu_song)
    cells = q.order_by(Cell3G.mien, Cell3G.tinh, Cell3G.site_name, Cell3G.cell_name).all()

    headers = [
        ("STT", 6), ("Mien", 8), ("Tinh", 22), ("Phuong xa", 22),
        ("Site Name", 25), ("Site Name Old", 22), ("Cell Name", 25), ("Cell Name Old", 22),
        ("Cell VIP", 10), ("MORAN", 15), ("Lat", 14), ("Long", 14),
        ("Vung phu song", 15), ("Vendor", 14), ("Do cao anten", 15),
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
            c.vung_phu_song, c.vendor, c.do_cao_anten,
            c.azimuth, c.m_tilt, c.e_tilt, c.total_tilt,
            c.loai_anten, c.chung_anten, c.baseband, c.rf,
            c.cell_id, c.uarfcn, c.lac, c.rac,
            c.psc, c.mimo, c.ura_id,
            c.cell_max_power, c.cpich_power,
            c.bbu_name, c.cell_status,
        ]
        for col_idx, val in enumerate(values, start=1):
            ws.cell(row=row, column=col_idx, value=val)
        _style_row(ws, row, len(headers), idx % 2 == 0)

    ws.auto_filter.ref = f"A1:{get_column_letter(len(headers))}1"
    return _stream(wb, "Cells_3G_Export.xlsx")


@router.get("/cells-4g")
def export_cells_4g(
    search:        Optional[str] = Query(None),
    mien:          Optional[str] = Query(None),
    tinh:          Optional[str] = Query(None),
    vendor:        Optional[str] = Query(None),
    mimo:          Optional[str] = Query(None),
    vung_phu_song: Optional[str] = Query(None),
    db:    Session = Depends(get_db),
    _:     User    = Depends(get_optional_user),
):
    q = db.query(Cell4G)
    if search:        q = q.filter(Cell4G.cell_name.ilike(f"%{search}%") | Cell4G.site_name.ilike(f"%{search}%"))
    if mien:          q = q.filter(Cell4G.mien == mien)
    if tinh:          q = q.filter(Cell4G.tinh == tinh)
    if vendor:        q = q.filter(Cell4G.vendor == vendor)
    if mimo:          q = q.filter(Cell4G.mimo == mimo)
    if vung_phu_song: q = q.filter(Cell4G.vung_phu_song == vung_phu_song)
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
            c.cell_max_power, c.eci,
            c.bbu_name, c.cell_status,
        ]
        for col_idx, val in enumerate(values, start=1):
            ws.cell(row=row, column=col_idx, value=val)
        _style_row(ws, row, len(headers), idx % 2 == 0)

    ws.auto_filter.ref = f"A1:{get_column_letter(len(headers))}1"
    return _stream(wb, "Cells_4G_Export.xlsx")


@router.get("/cells-5g")
def export_cells_5g(
    search:        Optional[str] = Query(None),
    mien:          Optional[str] = Query(None),
    tinh:          Optional[str] = Query(None),
    vendor:        Optional[str] = Query(None),
    mimo:          Optional[str] = Query(None),
    vung_phu_song: Optional[str] = Query(None),
    db:    Session = Depends(get_db),
    _:     User    = Depends(get_optional_user),
):
    q = db.query(Cell5G)
    if search:        q = q.filter(Cell5G.cell_name.ilike(f"%{search}%") | Cell5G.site_name.ilike(f"%{search}%"))
    if mien:          q = q.filter(Cell5G.mien == mien)
    if tinh:          q = q.filter(Cell5G.tinh == tinh)
    if vendor:        q = q.filter(Cell5G.vendor == vendor)
    if mimo:          q = q.filter(Cell5G.mimo == mimo)
    if vung_phu_song: q = q.filter(Cell5G.vung_phu_song == vung_phu_song)
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
echo "[OK] api/routes/export.py"

# ─────────────────────────────────────────────────────────────────────────────
# 10. BACKEND – create_templates.py  (regenerate all 3 cell templates)
# ─────────────────────────────────────────────────────────────────────────────
cat > "$BACKEND/create_templates.py" << 'PYEOF'
"""
create_templates.py
-------------------
Generates Excel template files for import.
Run once: python create_templates.py
"""
import os
import openpyxl
from openpyxl.styles import PatternFill, Font, Alignment, Border, Side
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation

TEMPLATE_DIR = os.path.join(os.path.dirname(__file__), "templates")
os.makedirs(TEMPLATE_DIR, exist_ok=True)

HEADER_FILL   = PatternFill("solid", fgColor="1F4E79")
HEADER_FONT   = Font(color="FFFFFF", bold=True, size=11)
REQUIRED_FILL = PatternFill("solid", fgColor="FFE699")
REQUIRED_FONT = Font(color="7B3F00", bold=True, size=11)
CENTER        = Alignment(horizontal="center", vertical="center", wrap_text=True)
LEFT          = Alignment(horizontal="left",   vertical="center", wrap_text=True)
THIN          = Side(style="thin", color="BFBFBF")
BORDER        = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)

VN_LAT_MIN, VN_LAT_MAX = 8.33,   23.39
VN_LON_MIN, VN_LON_MAX = 102.14, 109.47
AZI_MIN,    AZI_MAX    = 0,       359

MIEN_LIST     = ["MB", "MT", "MN"]
CELL_VIP_LIST = ["VIP", "VVIP"]
MORAN_LIST    = ["VNPT HOST", "MBF HOST"]
VENDOR_LIST   = ["Ericsson", "Nokia", "Huawei", "ZTE", "Samsung"]
VUNG_PHU_SONG = ["Indoor", "Outdoor"]
MIMO_LIST     = ["2x2", "4x4", "8x8"]
SITE_VIP_LIST = ["VIP", "VVIP"]
PHAN_LOAI_LIST = ["IBC", "Macro outdoor", "IBC + Outdoor", "Smallcell", "miniDAS"]
CHUNG_ANTEN_3G = ["3G", "3G/4G", "2G/3G/4G", "3G/4G/5G", "3G/5G"]
CHUNG_ANTEN_4G = ["4G", "2G/4G", "3G/4G", "2G/3G/4G", "4G/5G"]
BOOL_LIST      = ["x", ""]
MU_MIMO_LIST   = ["Yes", "No"]


def _dv_list(ws, col_letter, values, start_row=2, end_row=1000, error_msg="Vui lòng chọn từ danh sách"):
    joined = ",".join(values)
    dv = DataValidation(
        type="list", formula1=f'"{joined}"',
        allow_blank=True, showDropDown=False,
        showErrorMessage=True,
        errorTitle="Giá trị không hợp lệ", error=error_msg,
    )
    dv.sqref = f"{col_letter}{start_row}:{col_letter}{end_row}"
    ws.add_data_validation(dv)


def _dv_decimal(ws, col_letter, min_val, max_val, start_row=2, end_row=1000, error_msg="Giá trị ngoài phạm vi"):
    dv = DataValidation(
        type="decimal", operator="between",
        formula1=str(min_val), formula2=str(max_val),
        allow_blank=True, showErrorMessage=True,
        errorStyle="warning", errorTitle="Giá trị ngoài phạm vi", error=error_msg,
    )
    dv.sqref = f"{col_letter}{start_row}:{col_letter}{end_row}"
    ws.add_data_validation(dv)


def _dv_whole(ws, col_letter, min_val, max_val, start_row=2, end_row=1000, error_msg="Giá trị ngoài phạm vi"):
    dv = DataValidation(
        type="whole", operator="between",
        formula1=str(min_val), formula2=str(max_val),
        allow_blank=True, showErrorMessage=True,
        errorStyle="warning", errorTitle="Giá trị ngoài phạm vi", error=error_msg,
    )
    dv.sqref = f"{col_letter}{start_row}:{col_letter}{end_row}"
    ws.add_data_validation(dv)


def style_header(ws, col_idx, value, required=False, width=20):
    cell = ws.cell(row=1, column=col_idx, value=value)
    cell.fill      = REQUIRED_FILL if required else HEADER_FILL
    cell.font      = REQUIRED_FONT if required else HEADER_FONT
    cell.alignment = CENTER
    cell.border    = BORDER
    ws.column_dimensions[get_column_letter(col_idx)].width = width


def add_example_row(ws, row_idx, values):
    for col_idx, val in enumerate(values, start=1):
        cell = ws.cell(row=row_idx, column=col_idx, value=val)
        cell.alignment = LEFT
        cell.border    = BORDER


def finalize(ws, num_cols):
    ws.row_dimensions[1].height = 36
    ws.freeze_panes = "A2"
    ws.auto_filter.ref = f"A1:{get_column_letter(num_cols)}1"


# ── SITE template ─────────────────────────────────────────────────────────────
def create_site_template():
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Sites"

    columns = [
        ("Mien",                         False, 10),
        ("Tinh",                         True,  22),
        ("Phuong xa",                    False, 22),
        ("Site name (cu)",               False, 22),
        ("Site name",                    True,  25),
        ("Site VIP",                     False, 12),
        ("Lat",                          False, 14),
        ("Long",                         False, 14),
        ("Tram 2G",                      False, 10),
        ("Tram 3G",                      False, 10),
        ("Tram 4G",                      False, 10),
        ("Tram 5G",                      False, 10),
        ("Repeater",                     False, 10),
        ("Booster",                      False, 10),
        ("Node truyen dan only",         False, 20),
        ("Tram phu song TSCA",           False, 18),
        ("Phan loai tram",               False, 22),
        ("MORAN 3G",                     False, 15),
        ("MORAN 4G",                     False, 15),
        ("MORAN 5G",                     False, 15),
        ("Ma PTM",                       False, 14),
        ("Do cao dinh cot anten",        False, 22),
        ("Do cao cot anten",             False, 20),
        ("Dia chi",                      False, 30),
        ("Ghi chu",                      False, 30),
    ]

    for i, (hdr, req, w) in enumerate(columns, start=1):
        style_header(ws, i, hdr, required=req, width=w)

    num_cols = len(columns)
    _dv_list(ws, "A", MIEN_LIST)
    _dv_list(ws, "F", SITE_VIP_LIST)
    _dv_decimal(ws, "G", VN_LAT_MIN, VN_LAT_MAX)
    _dv_decimal(ws, "H", VN_LON_MIN, VN_LON_MAX)
    for col_letter in ["I","J","K","L","M","N","O","P"]:
        _dv_list(ws, col_letter, BOOL_LIST)
    _dv_list(ws, "Q", PHAN_LOAI_LIST)
    for col_letter in ["R","S","T"]:
        _dv_list(ws, col_letter, MORAN_LIST)

    example = [
        "MB", "Ha Noi", "Phuong Trung Hoa", "HN-001-OLD",
        "HN-001", "VIP", 21.0285, 105.8542,
        "x", "x", "x", "x", "", "", "", "",
        "Macro outdoor", "MBF HOST", "MBF HOST", "",
        "PTM-001", 35.5, 30.0, "So 1, Duong ABC, Ha Noi", ""
    ]
    add_example_row(ws, 2, example)
    finalize(ws, num_cols)

    path = os.path.join(TEMPLATE_DIR, "template_site.xlsx")
    wb.save(path)
    print(f"  Created: {path}")


# ── CELL 3G template ──────────────────────────────────────────────────────────
# Required columns per spec:
# Baseband | RF | Cell ID | UARFCN | LAC | RAC | PSC | MIMO |
# URAId | Cell max power (dBm) | CPICH power (dBm) | BBUname | Cell status (at dump time)
def create_cell3g_template():
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Cells_3G"

    columns = [
        ("Mien",                       False, 10),   #  1  A
        ("Tinh",                       False, 22),   #  2  B
        ("Phuong xa",                  False, 22),   #  3  C
        ("Site Name Old",              False, 25),   #  4  D
        ("Cell Name Old",              False, 25),   #  5  E
        ("Site Name",                  True,  25),   #  6  F
        ("Cell Name",                  True,  25),   #  7  G
        ("Cell VIP",                   False, 12),   #  8  H
        ("MORAN",                      False, 15),   #  9  I
        ("Lat",                        False, 14),   # 10  J
        ("Long",                       False, 14),   # 11  K
        ("Vung phu song",              False, 15),   # 12  L
        ("Vendor",                     False, 14),   # 13  M
        ("Do cao anten",               False, 15),   # 14  N
        ("Azimuth",                    False, 12),   # 15  O
        ("M-tilt",                     False, 10),   # 16  P
        ("E-Tilt",                     False, 10),   # 17  Q
        ("Total Tilt",                 False, 12),   # 18  R
        ("Loai Anten",                 False, 30),   # 19  S
        ("Chung anten",                False, 18),   # 20  T
        ("Baseband",                   False, 18),   # 21  U
        ("RF",                         False, 14),   # 22  V
        ("Cell ID",                    False, 14),   # 23  W
        ("UARFCN",                     False, 12),   # 24  X
        ("LAC",                        False, 10),   # 25  Y
        ("RAC",                        False, 10),   # 26  Z
        ("PSC",                        False, 10),   # 27  AA
        ("MIMO",                       False, 10),   # 28  AB
        ("URAId",                      False, 10),   # 29  AC
        ("Cell max power (dBm)",       False, 20),   # 30  AD
        ("CPICH power (dBm)",          False, 18),   # 31  AE
        ("BBUname",                    False, 16),   # 32  AF
        ("Cell status (at dump time)", False, 24),   # 33  AG
    ]

    for i, (hdr, req, w) in enumerate(columns, start=1):
        style_header(ws, i, hdr, required=req, width=w)

    num_cols = len(columns)

    _dv_list(ws, "A", MIEN_LIST)
    _dv_list(ws, "H", CELL_VIP_LIST)
    _dv_list(ws, "I", MORAN_LIST)
    _dv_decimal(ws, "J", VN_LAT_MIN, VN_LAT_MAX)
    _dv_decimal(ws, "K", VN_LON_MIN, VN_LON_MAX)
    _dv_list(ws, "L", VUNG_PHU_SONG)
    _dv_list(ws, "M", VENDOR_LIST)
    _dv_whole(ws, "O", AZI_MIN, AZI_MAX)
    _dv_list(ws, "T", CHUNG_ANTEN_3G)
    _dv_list(ws, "AB", MIMO_LIST)

    example = [
        "MB", "Ha Noi", "Phuong Trung Hoa",
        "HN-001-OLD", "HN-001-3G-1-OLD",
        "HN-001", "HN-001-3G-1",
        "", "MBF HOST",
        21.0285, 105.8542, "Outdoor", "Huawei",
        30.0, 45, 2.0, 0.0, 2.0,
        "Huawei ATR4518R10v06", "3G", "BBU3910", "RRU3908",
        "12345",      # Cell ID
        "10562",      # UARFCN
        "1234",       # LAC
        "10",         # RAC
        "100",        # PSC
        "2x2",        # MIMO
        "1",          # URAId
        "43",         # Cell max power (dBm)
        "33",         # CPICH power (dBm)
        "BBU-HN-001", # BBUname
        "Active",     # Cell status
    ]
    add_example_row(ws, 2, example)
    finalize(ws, num_cols)

    path = os.path.join(TEMPLATE_DIR, "template_cell_3g.xlsx")
    wb.save(path)
    print(f"  Created: {path}")


# ── CELL 4G template ──────────────────────────────────────────────────────────
# Required columns per spec:
# Baseband | RF | EnodeB ID | Cell ID | EARFCN | TAC | PCI | Root Sequence ID |
# MIMO | Bandwidth | Cell max power (dBm) | ECI | BBUname | Cell status (at dump time)
def create_cell4g_template():
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Cells_4G"

    columns = [
        ("Mien",                       False, 10),   #  1  A
        ("Tinh",                       False, 22),   #  2  B
        ("Phuong xa",                  False, 22),   #  3  C
        ("Site Name Old",              False, 25),   #  4  D
        ("Cell Name Old",              False, 25),   #  5  E
        ("Site Name",                  True,  25),   #  6  F
        ("Cell Name",                  True,  25),   #  7  G
        ("Cell VIP",                   False, 12),   #  8  H
        ("MORAN",                      False, 15),   #  9  I
        ("Lat",                        False, 14),   # 10  J
        ("Long",                       False, 14),   # 11  K
        ("Vung phu song",              False, 15),   # 12  L
        ("Vendor",                     False, 14),   # 13  M
        ("Do cao anten",               False, 15),   # 14  N
        ("Azimuth",                    False, 12),   # 15  O
        ("M-tilt",                     False, 10),   # 16  P
        ("E-Tilt",                     False, 10),   # 17  Q
        ("Total Tilt",                 False, 12),   # 18  R
        ("Loai Anten",                 False, 30),   # 19  S
        ("Chung anten",                False, 18),   # 20  T
        ("Baseband",                   False, 18),   # 21  U
        ("RF",                         False, 14),   # 22  V
        ("EnodeB ID",                  False, 14),   # 23  W
        ("Cell ID",                    False, 14),   # 24  X
        ("EARFCN",                     False, 12),   # 25  Y
        ("TAC",                        False, 10),   # 26  Z
        ("PCI",                        False, 10),   # 27  AA
        ("Root Sequence ID",           False, 18),   # 28  AB
        ("MIMO",                       False, 10),   # 29  AC
        ("Bandwitdh",                  False, 12),   # 30  AD  (matches spec spelling)
        ("Cell max power (dBm)",       False, 20),   # 31  AE
        ("ECI",                        False, 12),   # 32  AF
        ("BBUname",                    False, 16),   # 33  AG
        ("Cell status (at dump time)", False, 24),   # 34  AH
    ]

    for i, (hdr, req, w) in enumerate(columns, start=1):
        style_header(ws, i, hdr, required=req, width=w)

    num_cols = len(columns)

    _dv_list(ws, "A", MIEN_LIST)
    _dv_list(ws, "H", CELL_VIP_LIST)
    _dv_list(ws, "I", MORAN_LIST)
    _dv_decimal(ws, "J", VN_LAT_MIN, VN_LAT_MAX)
    _dv_decimal(ws, "K", VN_LON_MIN, VN_LON_MAX)
    _dv_list(ws, "L", VUNG_PHU_SONG)
    _dv_list(ws, "M", VENDOR_LIST)
    _dv_whole(ws, "O", AZI_MIN, AZI_MAX)
    _dv_list(ws, "T", CHUNG_ANTEN_4G)
    _dv_list(ws, "AC", MIMO_LIST)

    example = [
        "MB", "Ha Noi", "Phuong Trung Hoa",
        "HN-001-OLD", "HN-001-4G-1-OLD",
        "HN-001", "HN-001-4G-1",
        "", "MBF HOST",
        21.0285, 105.8542, "Outdoor", "Huawei",
        30.0, 45, 2.0, 0.0, 2.0,
        "Huawei ATR4518R10v06", "4G", "BBU5900", "RRU5258",
        "12345",      # EnodeB ID
        "67890",      # Cell ID
        "1825",       # EARFCN
        "1234",       # TAC
        "100",        # PCI
        "0",          # Root Sequence ID
        "4x4",        # MIMO
        "20",         # Bandwidth
        "46",         # Cell max power (dBm)
        "1234567890", # ECI
        "BBU-HN-001", # BBUname
        "Active",     # Cell status
    ]
    add_example_row(ws, 2, example)
    finalize(ws, num_cols)

    path = os.path.join(TEMPLATE_DIR, "template_cell_4g.xlsx")
    wb.save(path)
    print(f"  Created: {path}")


# ── CELL 5G template ──────────────────────────────────────────────────────────
# Required columns per spec:
# Baseband | RF | gNodeB ID | Cell ID | TAC | PCI | Root Sequence ID | MIMO |
# SSB-ARFCN | Center-ARFCN | GSCN | Bandwidth (MHz) | Cell max power (dBm) |
# NCI | BBUname | MU-MIMO | Cell status (at dump time)
def create_cell5g_template():
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Cells_5G"

    columns = [
        ("Mien",                       False, 10),   #  1  A
        ("Tinh",                       False, 22),   #  2  B
        ("Phuong xa",                  False, 22),   #  3  C
        ("Site Name Old",              False, 25),   #  4  D
        ("Cell Name Old",              False, 25),   #  5  E
        ("Site Name",                  True,  25),   #  6  F
        ("Cell Name",                  True,  25),   #  7  G
        ("Cell VIP",                   False, 12),   #  8  H
        ("MORAN",                      False, 15),   #  9  I
        ("Lat",                        False, 14),   # 10  J
        ("Long",                       False, 14),   # 11  K
        ("Vung phu song",              False, 15),   # 12  L
        ("Vendor",                     False, 14),   # 13  M
        ("Do cao anten",               False, 15),   # 14  N
        ("Azimuth",                    False, 12),   # 15  O
        ("M-tilt",                     False, 10),   # 16  P
        ("E-Tilt",                     False, 10),   # 17  Q
        ("Total Tilt",                 False, 12),   # 18  R
        ("Loai Anten",                 False, 30),   # 19  S
        ("Baseband",                   False, 18),   # 20  T
        ("RF",                         False, 14),   # 21  U
        ("gNodeB ID",                  False, 14),   # 22  V
        ("Cell ID",                    False, 14),   # 23  W
        ("TAC",                        False, 10),   # 24  X
        ("PCI",                        False, 10),   # 25  Y
        ("Root Sequence ID",           False, 18),   # 26  Z
        ("MIMO",                       False, 10),   # 27  AA
        ("SSB-ARFCN",                  False, 12),   # 28  AB
        ("Center-ARFCN",               False, 14),   # 29  AC
        ("GSCN",                       False, 10),   # 30  AD
        ("Bandwidth (MHz)",            False, 14),   # 31  AE
        ("Cell max power (dBm)",       False, 20),   # 32  AF
        ("NCI",                        False, 12),   # 33  AG
        ("BBUname",                    False, 16),   # 34  AH
        ("MU-MIMO",                    False, 10),   # 35  AI
        ("Cell status (at dump time)", False, 24),   # 36  AJ
    ]

    for i, (hdr, req, w) in enumerate(columns, start=1):
        style_header(ws, i, hdr, required=req, width=w)

    num_cols = len(columns)

    _dv_list(ws, "A", MIEN_LIST)
    _dv_list(ws, "H", CELL_VIP_LIST)
    _dv_list(ws, "I", MORAN_LIST)
    _dv_decimal(ws, "J", VN_LAT_MIN, VN_LAT_MAX)
    _dv_decimal(ws, "K", VN_LON_MIN, VN_LON_MAX)
    _dv_list(ws, "L", VUNG_PHU_SONG)
    _dv_list(ws, "M", VENDOR_LIST)
    _dv_whole(ws, "O", AZI_MIN, AZI_MAX)
    _dv_list(ws, "AA", MIMO_LIST)
    _dv_list(ws, "AI", MU_MIMO_LIST)

    example = [
        "MB", "Ha Noi", "Phuong Trung Hoa",
        "HN-001-OLD", "HN-001-5G-1-OLD",
        "HN-001", "HN-001-5G-1",
        "", "MBF HOST",
        21.0285, 105.8542, "Outdoor", "Huawei",
        30.0, 45, 2.0, 0.0, 2.0,
        "Huawei AAU5614", "BBU5900", "AAU5614",
        "12345",       # gNodeB ID
        "11111",       # Cell ID
        "1234",        # TAC
        "100",         # PCI
        "0",           # Root Sequence ID
        "8x8",         # MIMO
        "627264",      # SSB-ARFCN
        "630048",      # Center-ARFCN
        "7999",        # GSCN
        "100",         # Bandwidth (MHz)
        "46",          # Cell max power (dBm)
        "123456789",   # NCI
        "BBU-HN-001",  # BBUname
        "Yes",         # MU-MIMO
        "Active",      # Cell status
    ]
    add_example_row(ws, 2, example)
    finalize(ws, num_cols)

    path = os.path.join(TEMPLATE_DIR, "template_cell_5g.xlsx")
    wb.save(path)
    print(f"  Created: {path}")


if __name__ == "__main__":
    create_site_template()
    create_cell3g_template()
    create_cell4g_template()
    create_cell5g_template()
    print("All templates created successfully.")
PYEOF
echo "[OK] create_templates.py"

# ─────────────────────────────────────────────────────────────────────────────
# 11. FRONTEND – src/types/index.ts  (new fields)
# ─────────────────────────────────────────────────────────────────────────────
cat > "$FRONTEND/types/index.ts" << 'TSEOF'
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
  mien: string
  tinh: string
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
  ma_ptm: string
  do_cao_dinh_cot_anten?: number
  do_cao_cot_anten?: number
  dia_chi?: string
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
  lat?: number
  long?: number
  vung_phu_song?: string
  vendor?: string
  do_cao_anten?: number
  azimuth?: number
  m_tilt?: number
  e_tilt?: number
  total_tilt?: number
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
echo "[OK] types/index.ts"

# ─────────────────────────────────────────────────────────────────────────────
# 12. FRONTEND – pages/cells/Cells3GPage.tsx
# ─────────────────────────────────────────────────────────────────────────────
cat > "$FRONTEND/pages/cells/Cells3GPage.tsx" << 'TSXEOF'
import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, message, Row, Col,
  Modal, Form, InputNumber, Tooltip,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, SearchOutlined, UploadOutlined,
  EditOutlined, DeleteOutlined, DownloadOutlined,
} from '@ant-design/icons'
import { cells3gApi } from '@/api/cells'
import { exportCells3G } from '@/api/export'
import type { Cell3G, Site, AntennaItem } from '@/types'
import { getSites } from '@/api/sites'
import { getAntennaList } from '@/api/report'
import DryRunModal from '@/components/shared/DryRunModal'
import { latValidator, lonValidator, azimuthValidator } from '@/utils/validators'

const CHUNG_ANTEN_3G = ['3G', '3G/4G', '2G/3G/4G', '3G/4G/5G', '3G/5G']

export default function Cells3GPage() {
  const [data,        setData]        = useState<Cell3G[]>([])
  const [loading,     setLoading]     = useState(false)
  const [exporting,   setExporting]   = useState(false)
  const [search,      setSearch]      = useState('')
  const [mien,        setMien]        = useState<string | undefined>()
  const [tinh,        setTinh]        = useState<string | undefined>()
  const [vendor,      setVendor]      = useState<string | undefined>()
  const [sites,       setSites]       = useState<Site[]>([])
  const [antennaList, setAntennaList] = useState<AntennaItem[]>([])
  const [modalOpen,   setModalOpen]   = useState(false)
  const [editing,     setEditing]     = useState<Cell3G | null>(null)
  const [dryRunOpen,  setDryRunOpen]  = useState(false)
  const [form] = Form.useForm()

  const tinhOptions   = [...new Set(data.map((c) => c.tinh).filter(Boolean))].sort() as string[]
  const vendorOptions = [...new Set(data.map((c) => c.vendor).filter(Boolean))].sort() as string[]

  const load = async () => {
    setLoading(true)
    try {
      setData(await cells3gApi.list({
        search: search || undefined, mien: mien || undefined,
        tinh: tinh || undefined, vendor: vendor || undefined, limit: 1000,
      }))
    } finally { setLoading(false) }
  }

  useEffect(() => {
    load()
    getSites({ limit: 2000 }).then(setSites)
    getAntennaList().then((list: AntennaItem[]) => {
      const sorted = [...list].sort((a, b) => {
        const aU = a.name.toUpperCase().includes('CHƯA XÁC ĐỊNH') || a.name.toUpperCase().includes('CHUA XAC DINH')
        const bU = b.name.toUpperCase().includes('CHƯA XÁC ĐỊNH') || b.name.toUpperCase().includes('CHUA XAC DINH')
        if (aU) return -1; if (bU) return 1; return 0
      })
      setAntennaList(sorted)
    })
  }, [search, mien, tinh, vendor])

  const handleExport = async () => {
    setExporting(true)
    try {
      await exportCells3G({ search: search || undefined, mien: mien || undefined,
        tinh: tinh || undefined, vendor: vendor || undefined })
      message.success(`Xuất Excel thành công (${data.length} cells)`)
    } catch (e: any) { message.error(e?.message || 'Xuất thất bại')
    } finally { setExporting(false) }
  }

  const handleSiteSelect = (siteId: number) => {
    const site = sites.find((s) => s.id === siteId)
    if (site) form.setFieldValue('site_name', site.site_name)
  }

  const openCreate = () => { setEditing(null); form.resetFields(); setModalOpen(true) }
  const openEdit   = (r: Cell3G) => { setEditing(r); form.setFieldsValue(r); setModalOpen(true) }

  const handleSave = async () => {
    const values = await form.validateFields()
    try {
      if (editing) { await cells3gApi.update(editing.id, values); message.success('Cập nhật thành công') }
      else         { await cells3gApi.create(values);             message.success('Tạo cell thành công') }
      setModalOpen(false); load()
    } catch (e: any) { message.error(e.response?.data?.detail || 'Có lỗi xảy ra') }
  }

  const handleDelete = async (id: number) => {
    await cells3gApi.remove(id); message.success('Đã xóa'); load()
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
    { title: 'Miền',          dataIndex: 'mien',          fixed: 'left', width: 70  },
    { title: 'Tỉnh',          dataIndex: 'tinh',          fixed: 'left', width: 160 },
    { title: 'Phường/Xã',     dataIndex: 'phuong_xa',                    width: 160 },
    { title: 'Site Name Old', dataIndex: 'site_name_old', width: 200, ellipsis: { showTitle: true } },
    { title: 'Cell Name Old', dataIndex: 'cell_name_old', width: 200, ellipsis: { showTitle: true } },
    { title: 'Site Name', dataIndex: 'site_name', fixed: 'left', width: 220,
      ellipsis: { showTitle: true }, render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell Name', dataIndex: 'cell_name', fixed: 'left', width: 220,
      ellipsis: { showTitle: true }, render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell VIP', dataIndex: 'cell_vip', width: 90,
      render: (v: string) => v ? <Tag color="gold">{v}</Tag> : '-' },
    { title: 'MORAN',         dataIndex: 'moran',         width: 120 },
    { title: 'Lat',           dataIndex: 'lat',           width: 110 },
    { title: 'Long',          dataIndex: 'long',          width: 110 },
    { title: 'Vùng phủ sóng', dataIndex: 'vung_phu_song', width: 120 },
    { title: 'Vendor',        dataIndex: 'vendor',        width: 100 },
    { title: 'Độ cao anten',  dataIndex: 'do_cao_anten',  width: 120 },
    { title: 'Azimuth',       dataIndex: 'azimuth',       width: 90  },
    { title: 'M-tilt',        dataIndex: 'm_tilt',        width: 80  },
    { title: 'E-Tilt',        dataIndex: 'e_tilt',        width: 80  },
    { title: 'Total Tilt',    dataIndex: 'total_tilt',    width: 100 },
    { title: 'Loại Anten',    dataIndex: 'loai_anten',    width: 250, ellipsis: { showTitle: true } },
    { title: 'Chung anten',   dataIndex: 'chung_anten',   width: 120 },
    { title: 'Baseband',      dataIndex: 'baseband',      width: 120 },
    { title: 'RF',            dataIndex: 'rf',            width: 100 },
    { title: 'Cell ID',       dataIndex: 'cell_id',       width: 100 },
    { title: 'UARFCN',        dataIndex: 'uarfcn',        width: 100 },
    { title: 'LAC',           dataIndex: 'lac',           width: 80  },
    { title: 'RAC',           dataIndex: 'rac',           width: 80  },
    { title: 'PSC',           dataIndex: 'psc',           width: 80  },
    { title: 'MIMO', dataIndex: 'mimo', width: 80,
      render: (v: string) => v ? <Tag color="blue">{v}</Tag> : '-' },
    { title: 'URAId',              dataIndex: 'ura_id',        width: 80  },
    { title: 'Cell max power (dBm)', dataIndex: 'cell_max_power', width: 160 },
    { title: 'CPICH power (dBm)',  dataIndex: 'cpich_power',   width: 150 },
    { title: 'BBUname',            dataIndex: 'bbu_name',      width: 130 },
    { title: 'Cell status',        dataIndex: 'cell_status',   width: 140 },
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

      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="260px">
          <Input prefix={<SearchOutlined />} placeholder="Tìm cell / site name..."
                 value={search} onChange={(e) => setSearch(e.target.value)} allowClear />
        </Col>
        <Col>
          <Select placeholder="Miền" allowClear style={{ width: 90 }} value={mien} onChange={setMien}>
            {['MB','MT','MN'].map(m => <Select.Option key={m} value={m}>{m}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="180px">
          <Select placeholder="Tỉnh" allowClear showSearch style={{ width: '100%' }}
                  value={tinh} onChange={setTinh}
                  filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
            {tinhOptions.map(t => <Select.Option key={t} value={t}>{t}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="160px">
          <Select placeholder="Vendor" allowClear style={{ width: '100%' }}
                  value={vendor} onChange={setVendor}>
            {vendorOptions.map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}
          </Select>
        </Col>
        <Col>
          <Button onClick={() => { setSearch(''); setMien(undefined); setTinh(undefined); setVendor(undefined) }}>
            Xóa lọc
          </Button>
        </Col>
      </Row>

      <Table columns={columns} dataSource={data} rowKey="id" loading={loading}
             size="small" scroll={{ x: scrollX, y: 600 }} bordered
             pagination={{ pageSize: 50, showTotal: t => `${t} cells`, showSizeChanger: true }} />

      <Modal title={editing ? 'Chỉnh sửa Cell 3G' : 'Thêm Cell 3G mới'}
             open={modalOpen} onOk={handleSave} onCancel={() => setModalOpen(false)}
             width={900} okText="Lưu" destroyOnClose>
        <Form form={form} layout="vertical">
          <Row gutter={12}>
            <Col span={12}>
              <Form.Item name="site_id" label="Site" rules={[{ required: !editing }]}>
                <Select showSearch optionFilterProp="children" allowClear
                        placeholder="Chọn site..." onChange={handleSiteSelect}
                        disabled={Boolean(editing)}
                        filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                  {sites.map(s => <Select.Option key={s.id} value={s.id}>{s.site_name}</Select.Option>)}
                </Select>
              </Form.Item>
            </Col>
            <Col span={12}><Form.Item name="site_name_old" label="Site Name Old"><Input /></Form.Item></Col>
            <Col span={12}><Form.Item name="site_name" label="Site Name">
              <Input readOnly={!editing} style={!editing ? { background: '#f5f5f5' } : {}} />
            </Form.Item></Col>
            <Col span={12}><Form.Item name="cell_name_old" label="Cell Name Old"><Input /></Form.Item></Col>
            <Col span={12}><Form.Item name="cell_name" label="Cell Name" rules={[{ required: true }]}><Input /></Form.Item></Col>
            <Col span={6}><Form.Item name="cell_vip" label="Cell VIP">
              <Select allowClear><Select.Option value="VIP">VIP</Select.Option><Select.Option value="VVIP">VVIP</Select.Option></Select>
            </Form.Item></Col>
            <Col span={6}><Form.Item name="moran" label="MORAN">
              <Select allowClear><Select.Option value="VNPT HOST">VNPT HOST</Select.Option><Select.Option value="MBF HOST">MBF HOST</Select.Option></Select>
            </Form.Item></Col>
            <Col span={8}><Form.Item name="lat" label="Lat" rules={[{ validator: latValidator }]}>
              <InputNumber style={{ width: '100%' }} precision={5} />
            </Form.Item></Col>
            <Col span={8}><Form.Item name="long" label="Long" rules={[{ validator: lonValidator }]}>
              <InputNumber style={{ width: '100%' }} precision={5} />
            </Form.Item></Col>
            <Col span={8}><Form.Item name="vung_phu_song" label="Vùng phủ sóng">
              <Select allowClear><Select.Option value="Indoor">Indoor</Select.Option><Select.Option value="Outdoor">Outdoor</Select.Option></Select>
            </Form.Item></Col>
            <Col span={8}><Form.Item name="vendor" label="Vendor">
              <Select allowClear>{['Ericsson','Nokia','Huawei','ZTE','Samsung'].map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}</Select>
            </Form.Item></Col>
            <Col span={8}><Form.Item name="do_cao_anten" label="Độ cao anten (m)"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={8}><Form.Item name="azimuth" label="Azimuth (0–359)" rules={[{ validator: azimuthValidator }]}>
              <InputNumber style={{ width: '100%' }} min={0} max={359} />
            </Form.Item></Col>
            <Col span={8}><Form.Item name="m_tilt" label="M-tilt"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={8}><Form.Item name="e_tilt" label="E-Tilt"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={8}><Form.Item name="total_tilt" label="Total Tilt"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={24}><Form.Item name="loai_anten" label="Loại Anten">
              <Select showSearch allowClear filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                {antennaList.map(a => <Select.Option key={a.id} value={a.name}>{a.name}</Select.Option>)}
              </Select>
            </Form.Item></Col>
            <Col span={12}><Form.Item name="chung_anten" label="Chung anten">
              <Select allowClear>{CHUNG_ANTEN_3G.map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}</Select>
            </Form.Item></Col>
            <Col span={8}><Form.Item name="baseband" label="Baseband"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="rf" label="RF"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="cell_id" label="Cell ID"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="uarfcn" label="UARFCN"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="lac" label="LAC"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="rac" label="RAC"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="psc" label="PSC"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="mimo" label="MIMO">
              <Select allowClear>{['2x2','4x4','8x8'].map(m => <Select.Option key={m} value={m}>{m}</Select.Option>)}</Select>
            </Form.Item></Col>
            <Col span={8}><Form.Item name="ura_id" label="URAId"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="cell_max_power" label="Cell max power (dBm)"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="cpich_power" label="CPICH power (dBm)"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="bbu_name" label="BBUname"><Input /></Form.Item></Col>
            <Col span={16}><Form.Item name="cell_status" label="Cell status (at dump time)"><Input /></Form.Item></Col>
          </Row>
        </Form>
      </Modal>

      <DryRunModal open={dryRunOpen} onClose={() => setDryRunOpen(false)}
        title="Import Cell 3G từ Excel" templateKey="cell-3g"
        dryRunFn={cells3gApi.dryRunExcel} importFn={cells3gApi.importExcel} onSuccess={load} />
    </div>
  )
}
TSXEOF
echo "[OK] pages/cells/Cells3GPage.tsx"

# ─────────────────────────────────────────────────────────────────────────────
# 13. FRONTEND – pages/cells/Cells4GPage.tsx
# ─────────────────────────────────────────────────────────────────────────────
cat > "$FRONTEND/pages/cells/Cells4GPage.tsx" << 'TSXEOF'
import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, message, Row, Col,
  Modal, Form, InputNumber, Tooltip,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, SearchOutlined, UploadOutlined,
  EditOutlined, DeleteOutlined, DownloadOutlined,
} from '@ant-design/icons'
import { cells4gApi } from '@/api/cells'
import { exportCells4G } from '@/api/export'
import type { Cell4G, Site, AntennaItem } from '@/types'
import { getSites } from '@/api/sites'
import { getAntennaList } from '@/api/report'
import DryRunModal from '@/components/shared/DryRunModal'
import { latValidator, lonValidator, azimuthValidator } from '@/utils/validators'

const CHUNG_ANTEN_4G = ['4G', '2G/4G', '3G/4G', '2G/3G/4G', '4G/5G']

export default function Cells4GPage() {
  const [data,        setData]        = useState<Cell4G[]>([])
  const [loading,     setLoading]     = useState(false)
  const [exporting,   setExporting]   = useState(false)
  const [search,      setSearch]      = useState('')
  const [mien,        setMien]        = useState<string | undefined>()
  const [tinh,        setTinh]        = useState<string | undefined>()
  const [vendor,      setVendor]      = useState<string | undefined>()
  const [sites,       setSites]       = useState<Site[]>([])
  const [antennaList, setAntennaList] = useState<AntennaItem[]>([])
  const [modalOpen,   setModalOpen]   = useState(false)
  const [editing,     setEditing]     = useState<Cell4G | null>(null)
  const [dryRunOpen,  setDryRunOpen]  = useState(false)
  const [form] = Form.useForm()

  const tinhOptions   = [...new Set(data.map(c => c.tinh).filter(Boolean))].sort() as string[]
  const vendorOptions = [...new Set(data.map(c => c.vendor).filter(Boolean))].sort() as string[]

  const load = async () => {
    setLoading(true)
    try {
      setData(await cells4gApi.list({
        search: search || undefined, mien: mien || undefined,
        tinh: tinh || undefined, vendor: vendor || undefined, limit: 1000,
      }))
    } finally { setLoading(false) }
  }

  useEffect(() => {
    load()
    getSites({ limit: 2000 }).then(setSites)
    getAntennaList().then((list: AntennaItem[]) => {
      const sorted = [...list].sort((a, b) => {
        const aU = a.name.toUpperCase().includes('CHƯA XÁC ĐỊNH') || a.name.toUpperCase().includes('CHUA XAC DINH')
        const bU = b.name.toUpperCase().includes('CHƯA XÁC ĐỊNH') || b.name.toUpperCase().includes('CHUA XAC DINH')
        if (aU) return -1; if (bU) return 1; return 0
      })
      setAntennaList(sorted)
    })
  }, [search, mien, tinh, vendor])

  const handleExport = async () => {
    setExporting(true)
    try {
      await exportCells4G({ search: search || undefined, mien: mien || undefined,
        tinh: tinh || undefined, vendor: vendor || undefined })
      message.success(`Xuất Excel thành công (${data.length} cells)`)
    } catch (e: any) { message.error(e?.message || 'Xuất thất bại')
    } finally { setExporting(false) }
  }

  const handleSiteSelect = (siteId: number) => {
    const site = sites.find(s => s.id === siteId)
    if (site) form.setFieldValue('site_name', site.site_name)
  }

  const openCreate = () => { setEditing(null); form.resetFields(); setModalOpen(true) }
  const openEdit   = (r: Cell4G) => { setEditing(r); form.setFieldsValue(r); setModalOpen(true) }

  const handleSave = async () => {
    const values = await form.validateFields()
    try {
      if (editing) { await cells4gApi.update(editing.id, values); message.success('Cập nhật thành công') }
      else         { await cells4gApi.create(values);             message.success('Tạo cell thành công') }
      setModalOpen(false); load()
    } catch (e: any) { message.error(e.response?.data?.detail || 'Có lỗi xảy ra') }
  }

  const handleDelete = async (id: number) => {
    await cells4gApi.remove(id); message.success('Đã xóa'); load()
  }

  const columns: ColumnsType<Cell4G> = [
    { title: 'Hành động', key: 'action', fixed: 'left', width: 90,
      render: (_: unknown, r: Cell4G) => (
        <Space size={4}>
          <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(r)} />
          <Popconfirm title="Xóa cell này?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      )},
    { title: 'Miền',          dataIndex: 'mien',          fixed: 'left', width: 70  },
    { title: 'Tỉnh',          dataIndex: 'tinh',          fixed: 'left', width: 160 },
    { title: 'Phường/Xã',     dataIndex: 'phuong_xa',                    width: 160 },
    { title: 'Site Name Old', dataIndex: 'site_name_old', width: 200, ellipsis: { showTitle: true } },
    { title: 'Cell Name Old', dataIndex: 'cell_name_old', width: 200, ellipsis: { showTitle: true } },
    { title: 'Site Name', dataIndex: 'site_name', fixed: 'left', width: 220,
      ellipsis: { showTitle: true }, render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell Name', dataIndex: 'cell_name', fixed: 'left', width: 220,
      ellipsis: { showTitle: true }, render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell VIP', dataIndex: 'cell_vip', width: 90,
      render: (v: string) => v ? <Tag color="gold">{v}</Tag> : '-' },
    { title: 'MORAN',            dataIndex: 'moran',            width: 120 },
    { title: 'Lat',              dataIndex: 'lat',              width: 110 },
    { title: 'Long',             dataIndex: 'long',             width: 110 },
    { title: 'Vùng phủ sóng',    dataIndex: 'vung_phu_song',    width: 120 },
    { title: 'Vendor',           dataIndex: 'vendor',           width: 100 },
    { title: 'Độ cao anten',     dataIndex: 'do_cao_anten',     width: 120 },
    { title: 'Azimuth',          dataIndex: 'azimuth',          width: 90  },
    { title: 'M-tilt',           dataIndex: 'm_tilt',           width: 80  },
    { title: 'E-Tilt',           dataIndex: 'e_tilt',           width: 80  },
    { title: 'Total Tilt',       dataIndex: 'total_tilt',       width: 100 },
    { title: 'Loại Anten',       dataIndex: 'loai_anten',       width: 200, ellipsis: { showTitle: true } },
    { title: 'Chung anten',      dataIndex: 'chung_anten',      width: 120 },
    { title: 'Baseband',         dataIndex: 'baseband',         width: 120 },
    { title: 'RF',               dataIndex: 'rf',               width: 100 },
    { title: 'EnodeB ID',        dataIndex: 'enodeb_id',        width: 110 },
    { title: 'Cell ID',          dataIndex: 'cell_id',          width: 100 },
    { title: 'EARFCN',           dataIndex: 'earfcn',           width: 90  },
    { title: 'TAC',              dataIndex: 'tac',              width: 80  },
    { title: 'PCI',              dataIndex: 'pci',              width: 80  },
    { title: 'Root Sequence ID', dataIndex: 'root_sequence_id', width: 150 },
    { title: 'MIMO', dataIndex: 'mimo', width: 80,
      render: (v: string) => v ? <Tag color="blue">{v}</Tag> : '-' },
    { title: 'Bandwidth',           dataIndex: 'bandwidth',      width: 110 },
    { title: 'Cell max power (dBm)', dataIndex: 'cell_max_power', width: 165 },
    { title: 'ECI',              dataIndex: 'eci',              width: 120 },
    { title: 'BBUname',          dataIndex: 'bbu_name',         width: 130 },
    { title: 'Cell status',      dataIndex: 'cell_status',      width: 140 },
  ]
  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Cell 4G</Typography.Title>
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
      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="260px">
          <Input prefix={<SearchOutlined />} placeholder="Tìm cell / site name..."
                 value={search} onChange={e => setSearch(e.target.value)} allowClear />
        </Col>
        <Col>
          <Select placeholder="Miền" allowClear style={{ width: 90 }} value={mien} onChange={setMien}>
            {['MB','MT','MN'].map(m => <Select.Option key={m} value={m}>{m}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="180px">
          <Select placeholder="Tỉnh" allowClear showSearch style={{ width: '100%' }}
                  value={tinh} onChange={setTinh}
                  filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
            {tinhOptions.map(t => <Select.Option key={t} value={t}>{t}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="160px">
          <Select placeholder="Vendor" allowClear style={{ width: '100%' }}
                  value={vendor} onChange={setVendor}>
            {vendorOptions.map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}
          </Select>
        </Col>
        <Col>
          <Button onClick={() => { setSearch(''); setMien(undefined); setTinh(undefined); setVendor(undefined) }}>
            Xóa lọc
          </Button>
        </Col>
      </Row>
      <Table columns={columns} dataSource={data} rowKey="id" loading={loading}
             size="small" scroll={{ x: scrollX, y: 600 }} bordered
             pagination={{ pageSize: 50, showTotal: t => `${t} cells`, showSizeChanger: true }} />

      <Modal title={editing ? 'Chỉnh sửa Cell 4G' : 'Thêm Cell 4G mới'}
             open={modalOpen} onOk={handleSave} onCancel={() => setModalOpen(false)}
             width={900} okText="Lưu" destroyOnClose>
        <Form form={form} layout="vertical">
          <Row gutter={12}>
            <Col span={12}><Form.Item name="site_id" label="Site" rules={[{ required: !editing }]}>
              <Select showSearch optionFilterProp="children" allowClear placeholder="Chọn site..."
                      onChange={handleSiteSelect} disabled={Boolean(editing)}
                      filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                {sites.map(s => <Select.Option key={s.id} value={s.id}>{s.site_name}</Select.Option>)}
              </Select>
            </Form.Item></Col>
            <Col span={12}><Form.Item name="site_name_old" label="Site Name Old"><Input /></Form.Item></Col>
            <Col span={12}><Form.Item name="site_name" label="Site Name">
              <Input readOnly={!editing} style={!editing ? { background: '#f5f5f5' } : {}} />
            </Form.Item></Col>
            <Col span={12}><Form.Item name="cell_name_old" label="Cell Name Old"><Input /></Form.Item></Col>
            <Col span={12}><Form.Item name="cell_name" label="Cell Name" rules={[{ required: true }]}><Input /></Form.Item></Col>
            <Col span={6}><Form.Item name="cell_vip" label="Cell VIP">
              <Select allowClear><Select.Option value="VIP">VIP</Select.Option><Select.Option value="VVIP">VVIP</Select.Option></Select>
            </Form.Item></Col>
            <Col span={6}><Form.Item name="moran" label="MORAN">
              <Select allowClear><Select.Option value="VNPT HOST">VNPT HOST</Select.Option><Select.Option value="MBF HOST">MBF HOST</Select.Option></Select>
            </Form.Item></Col>
            <Col span={8}><Form.Item name="lat" label="Lat" rules={[{ validator: latValidator }]}><InputNumber style={{ width: '100%' }} precision={5} /></Form.Item></Col>
            <Col span={8}><Form.Item name="long" label="Long" rules={[{ validator: lonValidator }]}><InputNumber style={{ width: '100%' }} precision={5} /></Form.Item></Col>
            <Col span={8}><Form.Item name="vung_phu_song" label="Vùng phủ sóng">
              <Select allowClear><Select.Option value="Indoor">Indoor</Select.Option><Select.Option value="Outdoor">Outdoor</Select.Option></Select>
            </Form.Item></Col>
            <Col span={8}><Form.Item name="vendor" label="Vendor">
              <Select allowClear>{['Ericsson','Nokia','Huawei','ZTE','Samsung'].map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}</Select>
            </Form.Item></Col>
            <Col span={8}><Form.Item name="do_cao_anten" label="Độ cao anten (m)"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={8}><Form.Item name="azimuth" label="Azimuth (0–359)" rules={[{ validator: azimuthValidator }]}><InputNumber style={{ width: '100%' }} min={0} max={359} /></Form.Item></Col>
            <Col span={8}><Form.Item name="m_tilt" label="M-tilt"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={8}><Form.Item name="e_tilt" label="E-Tilt"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={8}><Form.Item name="total_tilt" label="Total Tilt"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={24}><Form.Item name="loai_anten" label="Loại Anten">
              <Select showSearch allowClear filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                {antennaList.map(a => <Select.Option key={a.id} value={a.name}>{a.name}</Select.Option>)}
              </Select>
            </Form.Item></Col>
            <Col span={12}><Form.Item name="chung_anten" label="Chung anten">
              <Select allowClear>{CHUNG_ANTEN_4G.map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}</Select>
            </Form.Item></Col>
            <Col span={8}><Form.Item name="baseband" label="Baseband"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="rf" label="RF"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="enodeb_id" label="EnodeB ID"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="cell_id" label="Cell ID"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="earfcn" label="EARFCN"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="tac" label="TAC"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="pci" label="PCI"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="root_sequence_id" label="Root Sequence ID"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="mimo" label="MIMO">
              <Select allowClear>{['2x2','4x4','8x8'].map(m => <Select.Option key={m} value={m}>{m}</Select.Option>)}</Select>
            </Form.Item></Col>
            <Col span={8}><Form.Item name="bandwidth" label="Bandwidth (MHz)"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="cell_max_power" label="Cell max power (dBm)"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="eci" label="ECI"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="bbu_name" label="BBUname"><Input /></Form.Item></Col>
            <Col span={16}><Form.Item name="cell_status" label="Cell status (at dump time)"><Input /></Form.Item></Col>
          </Row>
        </Form>
      </Modal>

      <DryRunModal open={dryRunOpen} onClose={() => setDryRunOpen(false)}
        title="Import Cell 4G từ Excel" templateKey="cell-4g"
        dryRunFn={cells4gApi.dryRunExcel} importFn={cells4gApi.importExcel} onSuccess={load} />
    </div>
  )
}
TSXEOF
echo "[OK] pages/cells/Cells4GPage.tsx"

# ─────────────────────────────────────────────────────────────────────────────
# 14. FRONTEND – pages/cells/Cells5GPage.tsx
# ─────────────────────────────────────────────────────────────────────────────
cat > "$FRONTEND/pages/cells/Cells5GPage.tsx" << 'TSXEOF'
import React, { useEffect, useState } from 'react'
import {
  Typography, Button, Space, Table, Input, Select,
  Popconfirm, Tag, message, Row, Col,
  Modal, Form, InputNumber, Tooltip,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, SearchOutlined, UploadOutlined,
  EditOutlined, DeleteOutlined, DownloadOutlined,
} from '@ant-design/icons'
import { cells5gApi } from '@/api/cells'
import { exportCells5G } from '@/api/export'
import type { Cell5G, Site, AntennaItem } from '@/types'
import { getSites } from '@/api/sites'
import { getAntennaList } from '@/api/report'
import DryRunModal from '@/components/shared/DryRunModal'
import { latValidator, lonValidator, azimuthValidator } from '@/utils/validators'

export default function Cells5GPage() {
  const [data,        setData]        = useState<Cell5G[]>([])
  const [loading,     setLoading]     = useState(false)
  const [exporting,   setExporting]   = useState(false)
  const [search,      setSearch]      = useState('')
  const [mien,        setMien]        = useState<string | undefined>()
  const [tinh,        setTinh]        = useState<string | undefined>()
  const [vendor,      setVendor]      = useState<string | undefined>()
  const [sites,       setSites]       = useState<Site[]>([])
  const [antennaList, setAntennaList] = useState<AntennaItem[]>([])
  const [modalOpen,   setModalOpen]   = useState(false)
  const [editing,     setEditing]     = useState<Cell5G | null>(null)
  const [dryRunOpen,  setDryRunOpen]  = useState(false)
  const [form] = Form.useForm()

  const tinhOptions   = [...new Set(data.map(c => c.tinh).filter(Boolean))].sort() as string[]
  const vendorOptions = [...new Set(data.map(c => c.vendor).filter(Boolean))].sort() as string[]

  const load = async () => {
    setLoading(true)
    try {
      setData(await cells5gApi.list({
        search: search || undefined, mien: mien || undefined,
        tinh: tinh || undefined, vendor: vendor || undefined, limit: 1000,
      }))
    } finally { setLoading(false) }
  }

  useEffect(() => {
    load()
    getSites({ limit: 2000 }).then(setSites)
    getAntennaList().then(setAntennaList)
  }, [search, mien, tinh, vendor])

  const handleExport = async () => {
    setExporting(true)
    try {
      await exportCells5G({ search: search || undefined, mien: mien || undefined,
        tinh: tinh || undefined, vendor: vendor || undefined })
      message.success(`Xuất Excel thành công (${data.length} cells)`)
    } catch (e: any) { message.error(e?.message || 'Xuất thất bại')
    } finally { setExporting(false) }
  }

  const handleSiteSelect = (siteId: number) => {
    const site = sites.find(s => s.id === siteId)
    if (site) form.setFieldValue('site_name', site.site_name)
  }

  const openCreate = () => { setEditing(null); form.resetFields(); setModalOpen(true) }
  const openEdit   = (r: Cell5G) => { setEditing(r); form.setFieldsValue(r); setModalOpen(true) }

  const handleSave = async () => {
    const values = await form.validateFields()
    try {
      if (editing) { await cells5gApi.update(editing.id, values); message.success('Cập nhật thành công') }
      else         { await cells5gApi.create(values);             message.success('Tạo cell thành công') }
      setModalOpen(false); load()
    } catch (e: any) { message.error(e.response?.data?.detail || 'Có lỗi xảy ra') }
  }

  const handleDelete = async (id: number) => {
    await cells5gApi.remove(id); message.success('Đã xóa'); load()
  }

  const columns: ColumnsType<Cell5G> = [
    { title: 'Hành động', key: 'action', fixed: 'left', width: 90,
      render: (_: unknown, r: Cell5G) => (
        <Space size={4}>
          <Button size="small" icon={<EditOutlined />} onClick={() => openEdit(r)} />
          <Popconfirm title="Xóa cell này?" onConfirm={() => handleDelete(r.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      )},
    { title: 'Miền',          dataIndex: 'mien',          fixed: 'left', width: 70  },
    { title: 'Tỉnh',          dataIndex: 'tinh',          fixed: 'left', width: 160 },
    { title: 'Phường xã',     dataIndex: 'phuong_xa',                    width: 160 },
    { title: 'Site Name Old', dataIndex: 'site_name_old', width: 200, ellipsis: { showTitle: true } },
    { title: 'Cell Name Old', dataIndex: 'cell_name_old', width: 200, ellipsis: { showTitle: true } },
    { title: 'Site Name', dataIndex: 'site_name', fixed: 'left', width: 220,
      ellipsis: { showTitle: true }, render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell Name', dataIndex: 'cell_name', fixed: 'left', width: 220,
      ellipsis: { showTitle: true }, render: (v: string) => <strong>{v}</strong> },
    { title: 'Cell VIP', dataIndex: 'cell_vip', width: 90,
      render: (v: string) => v ? <Tag color="gold">{v}</Tag> : '-' },
    { title: 'MORAN',            dataIndex: 'moran',            width: 120 },
    { title: 'Lat',              dataIndex: 'lat',              width: 110 },
    { title: 'Long',             dataIndex: 'long',             width: 110 },
    { title: 'Vùng phủ sóng',    dataIndex: 'vung_phu_song',    width: 120 },
    { title: 'Vendor',           dataIndex: 'vendor',           width: 100 },
    { title: 'Độ cao anten',     dataIndex: 'do_cao_anten',     width: 120 },
    { title: 'Azimuth',          dataIndex: 'azimuth',          width: 90  },
    { title: 'M-tilt',           dataIndex: 'm_tilt',           width: 80  },
    { title: 'E-Tilt',           dataIndex: 'e_tilt',           width: 80  },
    { title: 'Total Tilt',       dataIndex: 'total_tilt',       width: 100 },
    { title: 'Loại Anten',       dataIndex: 'loai_anten',       width: 250, ellipsis: { showTitle: true } },
    { title: 'Baseband',         dataIndex: 'baseband',         width: 120 },
    { title: 'RF',               dataIndex: 'rf',               width: 100 },
    { title: 'gNodeB ID',        dataIndex: 'gnodeb_id',        width: 110 },
    { title: 'Cell ID',          dataIndex: 'cell_id',          width: 100 },
    { title: 'TAC',              dataIndex: 'tac',              width: 80  },
    { title: 'PCI',              dataIndex: 'pci',              width: 80  },
    { title: 'Root Sequence ID', dataIndex: 'root_sequence_id', width: 150 },
    { title: 'MIMO', dataIndex: 'mimo', width: 80,
      render: (v: string) => v ? <Tag color="blue">{v}</Tag> : '-' },
    { title: 'SSB-ARFCN',        dataIndex: 'ssb_arfcn',        width: 110 },
    { title: 'Center-ARFCN',     dataIndex: 'center_arfcn',     width: 120 },
    { title: 'GSCN',             dataIndex: 'gscn',             width: 90  },
    { title: 'Bandwidth (MHz)',   dataIndex: 'bandwidth',        width: 130 },
    { title: 'Cell max power (dBm)', dataIndex: 'cell_max_power', width: 165 },
    { title: 'NCI',              dataIndex: 'nci',              width: 120 },
    { title: 'BBUname',          dataIndex: 'bbu_name',         width: 130 },
    { title: 'MU-MIMO',          dataIndex: 'mu_mimo',          width: 100 },
    { title: 'Cell status',      dataIndex: 'cell_status',      width: 140 },
  ]
  const scrollX = columns.reduce((s, c) => s + ((c.width as number) || 100), 0)

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>Cell 5G</Typography.Title>
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
      <Row gutter={8} style={{ marginBottom: 12 }}>
        <Col flex="260px">
          <Input prefix={<SearchOutlined />} placeholder="Tìm cell / site name..."
                 value={search} onChange={e => setSearch(e.target.value)} allowClear />
        </Col>
        <Col>
          <Select placeholder="Miền" allowClear style={{ width: 90 }} value={mien} onChange={setMien}>
            {['MB','MT','MN'].map(m => <Select.Option key={m} value={m}>{m}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="180px">
          <Select placeholder="Tỉnh" allowClear showSearch style={{ width: '100%' }}
                  value={tinh} onChange={setTinh}
                  filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
            {tinhOptions.map(t => <Select.Option key={t} value={t}>{t}</Select.Option>)}
          </Select>
        </Col>
        <Col flex="160px">
          <Select placeholder="Vendor" allowClear style={{ width: '100%' }}
                  value={vendor} onChange={setVendor}>
            {vendorOptions.map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}
          </Select>
        </Col>
        <Col>
          <Button onClick={() => { setSearch(''); setMien(undefined); setTinh(undefined); setVendor(undefined) }}>
            Xóa lọc
          </Button>
        </Col>
      </Row>
      <Table columns={columns} dataSource={data} rowKey="id" loading={loading}
             size="small" scroll={{ x: scrollX, y: 600 }} bordered
             pagination={{ pageSize: 50, showTotal: t => `${t} cells`, showSizeChanger: true }} />

      <Modal title={editing ? 'Chỉnh sửa Cell 5G' : 'Thêm Cell 5G mới'}
             open={modalOpen} onOk={handleSave} onCancel={() => setModalOpen(false)}
             width={900} okText="Lưu" destroyOnClose>
        <Form form={form} layout="vertical">
          <Row gutter={12}>
            <Col span={12}><Form.Item name="site_id" label="Site" rules={[{ required: !editing }]}>
              <Select showSearch optionFilterProp="children" allowClear placeholder="Chọn site..."
                      onChange={handleSiteSelect} disabled={Boolean(editing)}
                      filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                {sites.map(s => <Select.Option key={s.id} value={s.id}>{s.site_name}</Select.Option>)}
              </Select>
            </Form.Item></Col>
            <Col span={12}><Form.Item name="site_name_old" label="Site Name Old"><Input /></Form.Item></Col>
            <Col span={12}><Form.Item name="site_name" label="Site Name">
              <Input readOnly={!editing} style={!editing ? { background: '#f5f5f5' } : {}} />
            </Form.Item></Col>
            <Col span={12}><Form.Item name="cell_name_old" label="Cell Name Old"><Input /></Form.Item></Col>
            <Col span={12}><Form.Item name="cell_name" label="Cell Name" rules={[{ required: true }]}><Input /></Form.Item></Col>
            <Col span={6}><Form.Item name="cell_vip" label="Cell VIP">
              <Select allowClear><Select.Option value="VIP">VIP</Select.Option><Select.Option value="VVIP">VVIP</Select.Option></Select>
            </Form.Item></Col>
            <Col span={6}><Form.Item name="moran" label="MORAN">
              <Select allowClear><Select.Option value="VNPT HOST">VNPT HOST</Select.Option><Select.Option value="MBF HOST">MBF HOST</Select.Option></Select>
            </Form.Item></Col>
            <Col span={8}><Form.Item name="lat" label="Lat" rules={[{ validator: latValidator }]}><InputNumber style={{ width: '100%' }} precision={5} /></Form.Item></Col>
            <Col span={8}><Form.Item name="long" label="Long" rules={[{ validator: lonValidator }]}><InputNumber style={{ width: '100%' }} precision={5} /></Form.Item></Col>
            <Col span={8}><Form.Item name="vung_phu_song" label="Vùng phủ sóng">
              <Select allowClear><Select.Option value="Indoor">Indoor</Select.Option><Select.Option value="Outdoor">Outdoor</Select.Option></Select>
            </Form.Item></Col>
            <Col span={8}><Form.Item name="vendor" label="Vendor">
              <Select allowClear>{['Ericsson','Nokia','Huawei','ZTE','Samsung'].map(v => <Select.Option key={v} value={v}>{v}</Select.Option>)}</Select>
            </Form.Item></Col>
            <Col span={8}><Form.Item name="do_cao_anten" label="Độ cao anten (m)"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={8}><Form.Item name="azimuth" label="Azimuth (0–359)" rules={[{ validator: azimuthValidator }]}><InputNumber style={{ width: '100%' }} min={0} max={359} /></Form.Item></Col>
            <Col span={8}><Form.Item name="m_tilt" label="M-tilt"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={8}><Form.Item name="e_tilt" label="E-Tilt"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={8}><Form.Item name="total_tilt" label="Total Tilt"><InputNumber style={{ width: '100%' }} /></Form.Item></Col>
            <Col span={24}><Form.Item name="loai_anten" label="Loại Anten">
              <Select showSearch allowClear filterOption={(i, o) => String(o?.children ?? '').toLowerCase().includes(i.toLowerCase())}>
                {antennaList.map(a => <Select.Option key={a.id} value={a.name}>{a.name}</Select.Option>)}
              </Select>
            </Form.Item></Col>
            <Col span={8}><Form.Item name="baseband" label="Baseband"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="rf" label="RF"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="gnodeb_id" label="gNodeB ID"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="cell_id" label="Cell ID"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="tac" label="TAC"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="pci" label="PCI"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="root_sequence_id" label="Root Sequence ID"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="mimo" label="MIMO">
              <Select allowClear>{['2x2','4x4','8x8'].map(m => <Select.Option key={m} value={m}>{m}</Select.Option>)}</Select>
            </Form.Item></Col>
            <Col span={8}><Form.Item name="ssb_arfcn" label="SSB-ARFCN"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="center_arfcn" label="Center-ARFCN"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="gscn" label="GSCN"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="bandwidth" label="Bandwidth (MHz)"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="cell_max_power" label="Cell max power (dBm)"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="nci" label="NCI"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="bbu_name" label="BBUname"><Input /></Form.Item></Col>
            <Col span={8}><Form.Item name="mu_mimo" label="MU-MIMO">
              <Select allowClear><Select.Option value="Yes">Yes</Select.Option><Select.Option value="No">No</Select.Option></Select>
            </Form.Item></Col>
            <Col span={16}><Form.Item name="cell_status" label="Cell status (at dump time)"><Input /></Form.Item></Col>
          </Row>
        </Form>
      </Modal>

      <DryRunModal open={dryRunOpen} onClose={() => setDryRunOpen(false)}
        title="Import Cell 5G từ Excel" templateKey="cell-5g"
        dryRunFn={cells5gApi.dryRunExcel} importFn={cells5gApi.importExcel} onSuccess={load} />
    </div>
  )
}
TSXEOF
echo "[OK] pages/cells/Cells5GPage.tsx"

# ─────────────────────────────────────────────────────────────────────────────
# 15. Delete old template files so they get regenerated on startup
# ─────────────────────────────────────────────────────────────────────────────
for f in \
  "$BACKEND/templates/template_cell_3g.xlsx" \
  "$BACKEND/templates/template_cell_4g.xlsx" \
  "$BACKEND/templates/template_cell_5g.xlsx"
do
  [ -f "$f" ] && rm -f "$f" && echo "[OK] Removed old template: $(basename $f)"
done

# ─────────────────────────────────────────────────────────────────────────────
# 16. Run DB migration (if postgres container is running)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Running DB migration ==="
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "sitelink_postgres"; then
  docker exec -i sitelink_postgres psql -U sitelink -d sitelink_db \
    < "$ROOT/migrate_new_cell_columns.sql" \
    && echo "[OK] DB migration applied" \
    || echo "[WARN] DB migration failed – run manually"
else
  echo "[INFO] Postgres container not running."
  echo "       Run manually after starting containers:"
  echo "       docker exec -i sitelink_postgres psql -U sitelink -d sitelink_db < migrate_new_cell_columns.sql"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 17. Regenerate Excel templates inside backend container (or locally)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Regenerating Excel templates ==="
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "sitelink_backend"; then
  docker exec sitelink_backend python /app/create_templates.py \
    && echo "[OK] Templates regenerated in container" \
    || echo "[WARN] Template generation failed in container"
else
  echo "[INFO] Backend container not running."
  echo "       Templates will be auto-generated on next backend startup."
  echo "       Or run manually: cd backend && python create_templates.py"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 18. Rebuild & restart containers
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Rebuilding containers ==="
if command -v docker-compose &>/dev/null || docker compose version &>/dev/null 2>&1; then
  DC="docker compose"
  command -v docker-compose &>/dev/null && DC="docker-compose"

  cd "$ROOT"
  $DC build backend frontend \
    && echo "[OK] Build complete" \
    || echo "[WARN] Build failed – check errors above"

  $DC up -d \
    && echo "[OK] Containers restarted" \
    || echo "[WARN] Restart failed"
else
  echo "[INFO] docker-compose not found. Start manually:"
  echo "       docker-compose build backend frontend && docker-compose up -d"
fi

echo ""
echo "============================================================"
echo " SiteLink cell column update COMPLETE"
echo "============================================================"
echo ""
echo " Summary of changes:"
echo "  3G  added: uarfcn, lac, rac, ura_id, cell_max_power, cpich_power, bbu_name, cell_status"
echo "  4G  added: enodeb_id, tac, bandwidth, cell_max_power, eci, bbu_name, cell_status"
echo "  5G  added: gnodeb_id, tac, ssb_arfcn, center_arfcn, gscn, bandwidth,"
echo "             cell_max_power, nci, bbu_name, mu_mimo, cell_status"
echo "  Templates: template_cell_3g/4g/5g.xlsx regenerated with all new columns"
echo "  Migration: migrate_new_cell_columns.sql"
echo "============================================================"
