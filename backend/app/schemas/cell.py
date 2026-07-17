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
