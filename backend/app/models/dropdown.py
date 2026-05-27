from sqlalchemy import Column, Integer, String
from app.db.base import Base


class DropdownTinhXaPhuong(Base):
    __tablename__ = "dropdown_tinh_xa_phuong"
    id            = Column(Integer, primary_key=True)
    stt           = Column(Integer)
    mien          = Column(String(10))
    ten_tinh      = Column(String(100))
    ten_phuong_xa = Column(String(150))
    ma_tinh       = Column(String(20))
    ma_phuong_xa  = Column(String(20))
    ky_tu_1_6     = Column(String(10))


class DropdownAntenna(Base):
    __tablename__ = "dropdown_antenna"
    id             = Column(Integer, primary_key=True)
    name           = Column(String(300), unique=True)
    no_of_ports    = Column(Integer)
    band           = Column(String(100))
    no_of_beam     = Column(Integer)
    horizontal_bw  = Column(String(50))
    vertical_bw    = Column(String(50))
    gain           = Column(String(50))
    etilt          = Column(String(50))
    h              = Column(String(50))
    w              = Column(String(50))
    d              = Column(String(50))
    weight         = Column(String(50))
    connector_type = Column(String(100))


class DropdownVendor(Base):
    __tablename__ = "dropdown_vendor"
    id        = Column(Integer, primary_key=True)
    vendor_2g = Column(String(50))
    vendor_3g = Column(String(50))
    vendor_4g = Column(String(50))
    vendor_5g = Column(String(50))


class DropdownGeneral(Base):
    __tablename__ = "dropdown_general"
    id       = Column(Integer, primary_key=True)
    category = Column(String(100), nullable=False, index=True)
    value    = Column(String(200), nullable=False)
    label    = Column(String(200))
