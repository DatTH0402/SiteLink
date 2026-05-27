from typing import Optional
from pydantic import BaseModel


class CellBase(BaseModel):
    site_id: int
    mien: Optional[str] = None
    tinh: Optional[str] = None
    phuong_xa: Optional[str] = None
    site_name: str
    cell_name: str
    cell_vip: Optional[str] = None
    moran: Optional[str] = None
    lat: Optional[float] = None
    long: Optional[float] = None
    vung_phu_song: Optional[str] = None
    vendor: Optional[str] = None
    do_cao_anten: Optional[float] = None
    azimuth: Optional[float] = None
    m_tilt: Optional[float] = None
    e_tilt: Optional[float] = None
    total_tilt: Optional[float] = None
    loai_anten: Optional[str] = None
    baseband: Optional[str] = None
    rf: Optional[str] = None
    cell_id: Optional[str] = None
    mimo: Optional[str] = None


# ---------- 3G ----------
class Cell3GBase(CellBase):
    chung_anten: Optional[str] = None
    arfcn: Optional[str] = None
    psc: Optional[str] = None


class Cell3GCreate(Cell3GBase):
    pass


class Cell3GUpdate(BaseModel):
    cell_vip: Optional[str] = None
    moran: Optional[str] = None
    lat: Optional[float] = None
    long: Optional[float] = None
    vung_phu_song: Optional[str] = None
    vendor: Optional[str] = None
    do_cao_anten: Optional[float] = None
    azimuth: Optional[float] = None
    m_tilt: Optional[float] = None
    e_tilt: Optional[float] = None
    total_tilt: Optional[float] = None
    loai_anten: Optional[str] = None
    chung_anten: Optional[str] = None
    baseband: Optional[str] = None
    rf: Optional[str] = None
    cell_id: Optional[str] = None
    arfcn: Optional[str] = None
    psc: Optional[str] = None
    mimo: Optional[str] = None


class Cell3GRead(Cell3GBase):
    id: int

    class Config:
        from_attributes = True


# ---------- 4G ----------
class Cell4GBase(CellBase):
    chung_anten: Optional[str] = None
    earfcn: Optional[str] = None
    pci: Optional[str] = None
    root_sequence_id: Optional[str] = None


class Cell4GCreate(Cell4GBase):
    pass


class Cell4GUpdate(BaseModel):
    cell_vip: Optional[str] = None
    moran: Optional[str] = None
    lat: Optional[float] = None
    long: Optional[float] = None
    vung_phu_song: Optional[str] = None
    vendor: Optional[str] = None
    do_cao_anten: Optional[float] = None
    azimuth: Optional[float] = None
    m_tilt: Optional[float] = None
    e_tilt: Optional[float] = None
    total_tilt: Optional[float] = None
    loai_anten: Optional[str] = None
    chung_anten: Optional[str] = None
    baseband: Optional[str] = None
    rf: Optional[str] = None
    cell_id: Optional[str] = None
    earfcn: Optional[str] = None
    pci: Optional[str] = None
    root_sequence_id: Optional[str] = None
    mimo: Optional[str] = None


class Cell4GRead(Cell4GBase):
    id: int

    class Config:
        from_attributes = True


# ---------- 5G ----------
class Cell5GBase(CellBase):
    nr_arfcn: Optional[str] = None
    pci: Optional[str] = None
    root_sequence_id: Optional[str] = None


class Cell5GCreate(Cell5GBase):
    pass


class Cell5GUpdate(BaseModel):
    cell_vip: Optional[str] = None
    moran: Optional[str] = None
    lat: Optional[float] = None
    long: Optional[float] = None
    vung_phu_song: Optional[str] = None
    vendor: Optional[str] = None
    do_cao_anten: Optional[float] = None
    azimuth: Optional[float] = None
    m_tilt: Optional[float] = None
    e_tilt: Optional[float] = None
    total_tilt: Optional[float] = None
    loai_anten: Optional[str] = None
    baseband: Optional[str] = None
    rf: Optional[str] = None
    cell_id: Optional[str] = None
    nr_arfcn: Optional[str] = None
    pci: Optional[str] = None
    root_sequence_id: Optional[str] = None
    mimo: Optional[str] = None


class Cell5GRead(Cell5GBase):
    id: int

    class Config:
        from_attributes = True
