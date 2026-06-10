from typing import Optional
from pydantic import BaseModel


class SiteBase(BaseModel):
    mien:                   Optional[str]   = None
    tinh:                   Optional[str]   = None
    phuong_xa:              Optional[str]   = None
    site_name_cu:           Optional[str]   = None
    site_name:              str                       # ONLY required field
    site_vip:               Optional[str]   = None
    lat:                    Optional[float] = None
    long:                   Optional[float] = None
    tram_2g:                bool            = False
    tram_3g:                bool            = False
    tram_4g:                bool            = False
    tram_5g:                bool            = False
    repeater:               bool            = False
    booster:                bool            = False
    node_truyen_dan_only:   bool            = False
    phan_loai_tram:         Optional[str]   = None
    tram_phu_song_tsca:     Optional[str]   = None
    moran_3g:               Optional[str]   = None
    moran_4g:               Optional[str]   = None
    moran_5g:               Optional[str]   = None
    ma_ptm:                 Optional[str]   = None    # now optional
    do_cao_dinh_cot_anten:  Optional[float] = None
    do_cao_cot_anten:       Optional[float] = None
    dia_chi:                Optional[str]   = None
    ghi_chu:                Optional[str]   = None


class SiteCreate(SiteBase):
    pass


class SiteUpdate(BaseModel):
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
    phan_loai_tram:         Optional[str]   = None
    tram_phu_song_tsca:     Optional[str]   = None
    moran_3g:               Optional[str]   = None
    moran_4g:               Optional[str]   = None
    moran_5g:               Optional[str]   = None
    ma_ptm:                 Optional[str]   = None
    do_cao_dinh_cot_anten:  Optional[float] = None
    do_cao_cot_anten:       Optional[float] = None
    dia_chi:                Optional[str]   = None
    ghi_chu:                Optional[str]   = None


class SiteRead(SiteBase):
    id: int

    class Config:
        from_attributes = True