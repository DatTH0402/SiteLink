#!/usr/bin/env bash
# =============================================================================
# SiteLink – Fix 500 errors caused by over-strict Pydantic schemas
# Root cause: SiteBase / CellBase had required fields that broke GET serialization
# Fix: Required validation only on Create schemas; Base/Read/Update stay Optional
# =============================================================================
set -euo pipefail

BACKEND="backend/app"

echo "=== SiteLink Schema Fix ==="

# =============================================================================
# 1. FIX backend/app/schemas/site.py
#    - SiteBase: all fields Optional (used for Read/Update/serialization)
#    - SiteCreate: adds required-field validators via @model_validator
#    - SiteUpdate: all Optional (partial update)
# =============================================================================

cat > "${BACKEND}/schemas/site.py" << 'PYTHON_EOF'
"""
schemas/site.py

Design:
  SiteBase   – all fields Optional  → safe for DB reads/serialization (GET endpoints)
  SiteCreate – inherits SiteBase + model_validator enforces required fields on WRITE
  SiteUpdate – all fields Optional  → partial update (PATCH/PUT)
  SiteRead   – inherits SiteBase + id, used as response_model
"""
from __future__ import annotations
from typing import Optional
from pydantic import BaseModel, model_validator


class SiteBase(BaseModel):
    mien:                   Optional[str]   = None
    tinh:                   Optional[str]   = None
    phuong_xa:              Optional[str]   = None
    site_name_cu:           Optional[str]   = None
    site_name:              Optional[str]   = None
    site_vip:               Optional[str]   = None
    lat:                    Optional[float] = None
    long:                   Optional[float] = None
    tram_2g:                Optional[bool]  = False
    tram_3g:                Optional[bool]  = False
    tram_4g:                Optional[bool]  = False
    tram_5g:                Optional[bool]  = False
    repeater:               Optional[bool]  = False
    booster:                Optional[bool]  = False
    node_truyen_dan_only:   Optional[bool]  = False
    tram_phu_song_tsca:     Optional[bool]  = False
    phan_loai_tram:         Optional[str]   = None
    moran_3g:               Optional[str]   = None
    moran_4g:               Optional[str]   = None
    moran_5g:               Optional[str]   = None
    ma_ptm:                 Optional[str]   = None
    do_cao_dinh_cot_anten:  Optional[float] = None
    do_cao_cot_anten:       Optional[float] = None
    dia_chi:                Optional[str]   = None
    ghi_chu:                Optional[str]   = None

    model_config = {"from_attributes": True}


class SiteCreate(SiteBase):
    """
    Required fields for creating a new site.
    Validation is done here (write path) so GET serialization is never affected.
    """
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

        if self.do_cao_dinh_cot_anten is None:
            errors.append("'do_cao_dinh_cot_anten' (Độ cao đỉnh cột anten) là trường bắt buộc.")
        elif self.do_cao_dinh_cot_anten < 0:
            errors.append(
                f"'do_cao_dinh_cot_anten' phải >= 0 (giá trị: {self.do_cao_dinh_cot_anten})."
            )

        if errors:
            raise ValueError("; ".join(errors))
        return self


class SiteUpdate(BaseModel):
    """All fields optional – supports partial updates."""
    mien:                   Optional[str]   = None
    tinh:                   Optional[str]   = None
    phuong_xa:              Optional[str]   = None
    site_name_cu:           Optional[str]   = None
    site_name:              Optional[str]   = None
    site_vip:               Optional[str]   = None
    lat:                    Optional[float] = None
    long:                   Optional[float] = None
    tram_2g:                Optional[bool]  = None
    tram_3g:                Optional[bool]  = None
    tram_4g:                Optional[bool]  = None
    tram_5g:                Optional[bool]  = None
    repeater:               Optional[bool]  = None
    booster:                Optional[bool]  = None
    node_truyen_dan_only:   Optional[bool]  = None
    tram_phu_song_tsca:     Optional[bool]  = None
    phan_loai_tram:         Optional[str]   = None
    moran_3g:               Optional[str]   = None
    moran_4g:               Optional[str]   = None
    moran_5g:               Optional[str]   = None
    ma_ptm:                 Optional[str]   = None
    do_cao_dinh_cot_anten:  Optional[float] = None
    do_cao_cot_anten:       Optional[float] = None
    dia_chi:                Optional[str]   = None
    ghi_chu:                Optional[str]   = None

    model_config = {"from_attributes": True}


class SiteRead(SiteBase):
    id: int

    model_config = {"from_attributes": True}
PYTHON_EOF

echo "  ✓ backend/app/schemas/site.py – fixed (SiteBase all-Optional, required only in SiteCreate)"

# =============================================================================
# 2. FIX backend/app/schemas/cell.py
#    Same pattern: CellBase all-Optional, CellCreate validates required fields
# =============================================================================

cat > "${BACKEND}/schemas/cell.py" << 'PYTHON_EOF'
"""
schemas/cell.py

Design:
  CellBase      – all fields Optional  → safe for DB reads/serialization
  CellCreate    – inherits CellBase + model_validator for required fields
  CellUpdate    – all Optional
  Cell3GRead    – response model for 3G cells
  Cell4GRead    – response model for 4G cells
  Cell5GRead    – response model for 5G cells
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

        if self.azimuth is None:
            errors.append("'azimuth' là trường bắt buộc.")
        elif not (0 <= self.azimuth <= 359):
            errors.append(
                f"'azimuth' = {self.azimuth} phải trong khoảng 0 – 359."
            )

        if self.do_cao_anten is None:
            errors.append("'do_cao_anten' (Độ cao anten) là trường bắt buộc.")
        elif self.do_cao_anten < 0:
            errors.append(
                f"'do_cao_anten' phải >= 0 (giá trị: {self.do_cao_anten})."
            )

        if self.m_tilt is None:
            errors.append("'m_tilt' (M-tilt) là trường bắt buộc.")

        if self.e_tilt is None:
            errors.append("'e_tilt' (E-Tilt) là trường bắt buộc.")

        if errors:
            raise ValueError("; ".join(errors))
        return self


class CellUpdate(BaseModel):
    """All fields optional – supports partial updates."""
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
PYTHON_EOF

echo "  ✓ backend/app/schemas/cell.py – fixed (CellBase all-Optional, required only in CellCreate)"

# =============================================================================
# 3. Update routes to use the correct schema classes
#    sites.py      → SiteCreate, SiteUpdate, SiteRead
#    cells_3g.py   → Cell3GCreate, Cell3GUpdate, Cell3GRead
#    cells_4g.py   → Cell4GCreate, Cell4GUpdate, Cell4GRead
#    cells_5g.py   → Cell5GCreate, Cell5GUpdate, Cell5GRead
# =============================================================================

python3 - << 'PYEOF'
import re, sys

# ── sites.py ──────────────────────────────────────────────────────────────────
path = "backend/app/api/routes/sites.py"
try:
    with open(path) as f:
        src = f.read()
except FileNotFoundError:
    print(f"  ✗ {path} not found – skipping")
    sys.exit(0)

# Fix import line – make sure SiteRead is imported
old_import = "from app.schemas.site import SiteCreate, SiteUpdate, SiteRead"
if old_import not in src:
    # Try to patch whatever import line exists
    src = re.sub(
        r"from app\.schemas\.site import[^\n]+",
        "from app.schemas.site import SiteCreate, SiteUpdate, SiteRead",
        src,
    )

with open(path, "w") as f:
    f.write(src)
print(f"  ✓ {path}: schema imports verified")
PYEOF

python3 - << 'PYEOF'
import re

for tech, suffix in [("3g", "3G"), ("4g", "4G"), ("5g", "5G")]:
    path = f"backend/app/api/routes/cells_{tech}.py"
    try:
        with open(path) as f:
            src = f.read()
    except FileNotFoundError:
        print(f"  ✗ {path} not found – skipping")
        continue

    # Fix schema import to use tech-specific classes
    src = re.sub(
        r"from app\.schemas\.cell import[^\n]+",
        (
            f"from app.schemas.cell import "
            f"Cell{suffix}Create, Cell{suffix}Update, Cell{suffix}Read, "
            f"CellCreate, CellUpdate"
        ),
        src,
    )

    # Fix response_model annotations in function signatures
    # Read list endpoint
    src = re.sub(
        r"response_model=List\[CellBase\]",
        f"response_model=List[Cell{suffix}Read]",
        src,
    )
    src = re.sub(
        r"response_model=CellBase\b",
        f"response_model=Cell{suffix}Read",
        src,
    )
    # Also fix any bare CellRead if present
    src = re.sub(
        r"response_model=CellRead\b",
        f"response_model=Cell{suffix}Read",
        src,
    )

    with open(path, "w") as f:
        f.write(src)
    print(f"  ✓ backend/app/api/routes/cells_{tech}.py: schema classes updated")
PYEOF

# =============================================================================
# 4. Ensure sites.py response_model uses SiteRead (not SiteBase)
# =============================================================================

python3 - << 'PYEOF'
import re

path = "backend/app/api/routes/sites.py"
with open(path) as f:
    src = f.read()

# Replace any List[SiteBase] or SiteBase response_model with SiteRead
src = re.sub(r"response_model=List\[SiteBase\]", "response_model=List[SiteRead]", src)
src = re.sub(r"response_model=SiteBase\b",        "response_model=SiteRead",       src)

with open(path, "w") as f:
    f.write(src)
print("  ✓ backend/app/api/routes/sites.py: response_model → SiteRead")
PYEOF

# =============================================================================
# 5. Verify
# =============================================================================

echo ""
echo "=== Verification ==="
for f in \
  "backend/app/schemas/site.py" \
  "backend/app/schemas/cell.py" \
  "backend/app/api/routes/sites.py" \
  "backend/app/api/routes/cells_3g.py" \
  "backend/app/api/routes/cells_4g.py" \
  "backend/app/api/routes/cells_5g.py"; do
  if [ -f "$f" ]; then
    echo "  ✓ $f"
  else
    echo "  ✗ MISSING: $f"
  fi
done

# Quick sanity check: SiteBase must not have bare required fields
python3 - << 'PYEOF'
with open("backend/app/schemas/site.py") as f:
    src = f.read()

problems = []
for required_field in ["lat: float", "long: float", "dia_chi: str",
                        "do_cao_dinh_cot_anten: float"]:
    if required_field in src:
        problems.append(required_field)

if problems:
    print(f"  ✗ STILL HAS bare required fields in SiteBase: {problems}")
    print("    This will break GET serialization!")
else:
    print("  ✓ SiteBase: no bare required fields (all Optional) – GET safe")

with open("backend/app/schemas/cell.py") as f:
    src = f.read()

problems = []
for required_field in ["lat: float", "long: float", "vendor: str",
                        "do_cao_anten: float", "azimuth: float",
                        "m_tilt: float", "e_tilt: float"]:
    if required_field in src:
        problems.append(required_field)

if problems:
    print(f"  ✗ STILL HAS bare required fields in CellBase: {problems}")
    print("    This will break GET serialization!")
else:
    print("  ✓ CellBase: no bare required fields (all Optional) – GET safe")
PYEOF

echo ""
echo "=== Root Cause Summary ==="
echo ""
echo "PROBLEM:"
echo "  The previous script changed SiteBase.lat/long/dia_chi/do_cao_dinh_cot_anten"
echo "  and CellBase.lat/long/vendor/do_cao_anten/azimuth/m_tilt/e_tilt"
echo "  from Optional to REQUIRED (no default value)."
echo ""
echo "  FastAPI uses the SAME schema for both:"
echo "    - INPUT  (POST body validation)    ← required fields make sense here"
echo "    - OUTPUT (GET response serialization) ← existing DB rows may have NULL"
echo "                                            → Pydantic raises ValidationError"
echo "                                            → FastAPI returns HTTP 500"
echo ""
echo "SOLUTION:"
echo "  SiteBase / CellBase → all Optional (safe for reads)"
echo "  SiteCreate / CellCreate → model_validator enforces required on WRITE only"
echo "  SiteUpdate / CellUpdate → all Optional (partial update)"
echo "  SiteRead / Cell*Read → used as response_model (inherits Optional base)"
echo ""
echo "=== Done! ==="
echo ""
echo "NEXT STEPS:"
echo "  1. docker compose restart backend"
echo "     OR: cd backend && uvicorn app.main:app --reload"
echo "  2. Test GET /api/v1/sites/ → should return 200 with data"
echo "  3. Test GET /api/v1/cells-3g/ → should return 200 with data"
echo "  4. Test POST (create site without lat) → should return 422 with clear message"