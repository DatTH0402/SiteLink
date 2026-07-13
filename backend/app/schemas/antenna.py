from typing import Optional
from pydantic import BaseModel


class AntennaBase(BaseModel):
    name:           str
    no_of_ports:    Optional[int]   = None
    band:           Optional[str]   = None
    no_of_beam:     Optional[int]   = None
    horizontal_bw:  Optional[str]   = None
    vertical_bw:    Optional[str]   = None
    gain:           Optional[str]   = None
    etilt:          Optional[str]   = None
    h:              Optional[str]   = None
    w:              Optional[str]   = None
    d:              Optional[str]   = None
    weight:         Optional[str]   = None
    connector_type: Optional[str]   = None
    ghi_chu:        Optional[str]   = None
    is_5g_aau:      bool            = False


class AntennaCreate(AntennaBase):
    pass


class AntennaUpdate(BaseModel):
    name:           Optional[str]   = None
    no_of_ports:    Optional[int]   = None
    band:           Optional[str]   = None
    no_of_beam:     Optional[int]   = None
    horizontal_bw:  Optional[str]   = None
    vertical_bw:    Optional[str]   = None
    gain:           Optional[str]   = None
    etilt:          Optional[str]   = None
    h:              Optional[str]   = None
    w:              Optional[str]   = None
    d:              Optional[str]   = None
    weight:         Optional[str]   = None
    connector_type: Optional[str]   = None
    ghi_chu:        Optional[str]   = None
    is_5g_aau:      Optional[bool]  = None


class AntennaRead(AntennaBase):
    id:             int
    spec_file_name: Optional[str] = None
    spec_file_path: Optional[str] = None

    class Config:
        from_attributes = True
