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
