from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime, Text, ForeignKey
from app.db.base import Base


class SiteRevision(Base):
    __tablename__ = "site_revisions"

    id              = Column(Integer, primary_key=True, index=True)
    site_id         = Column(Integer, nullable=False, index=True)
    site_name       = Column(String(100), nullable=False, index=True)
    revision_no     = Column(Integer, nullable=False, default=1)
    changed_by      = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    changed_by_name = Column(String(100), nullable=True)
    change_source   = Column(String(20), default="form")   # 'form' | 'excel'
    change_note     = Column(Text, nullable=True)

    # All site fields snapshot
    mien                    = Column(String(10))
    tinh                    = Column(String(100))
    phuong_xa               = Column(String(150))
    site_name_cu            = Column(String(100))
    site_name_old_ref       = Column(String(100))          # previous name before rename
    site_vip                = Column(String(10))
    lat                     = Column(Float)
    long                    = Column(Float)
    tram_2g                 = Column(Boolean, default=False)
    tram_3g                 = Column(Boolean, default=False)
    tram_4g                 = Column(Boolean, default=False)
    tram_5g                 = Column(Boolean, default=False)
    repeater                = Column(Boolean, default=False)
    booster                 = Column(Boolean, default=False)
    node_truyen_dan_only    = Column(Boolean, default=False)
    tram_phu_song_tsca      = Column(Boolean, default=False)
    phan_loai_tram          = Column(String(100))
    moran_3g                = Column(String(50))
    moran_4g                = Column(String(50))
    moran_5g                = Column(String(50))
    ma_ptm                  = Column(String(100))
    do_cao_dinh_cot_anten   = Column(Float)
    do_cao_cot_anten        = Column(Float)
    dia_chi                 = Column(Text)
    ghi_chu                 = Column(Text)

    changed_fields  = Column(Text)   # JSON {field: [old_val, new_val]}
    created_at      = Column(DateTime(timezone=True),
                             default=lambda: datetime.now(timezone.utc))
