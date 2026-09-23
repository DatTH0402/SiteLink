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
