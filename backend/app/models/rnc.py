from sqlalchemy import Column, Integer, String
from app.db.base import Base


class RncName(Base):
    __tablename__ = "rnc_names"

    id     = Column(Integer, primary_key=True, index=True)
    vendor = Column(String(50), nullable=False, index=True)
    name   = Column(String(100), nullable=False)
