"""
Tables written by backend/reconcile_cells.py (daily batch) and read by /api/v1/reconcile.
Keep in sync with the DDL in backend/cell_reconcile_core.py.
"""
from sqlalchemy import Column, DateTime, Index, Integer, String, Text

from app.db.base import Base


class CellReconcileRun(Base):
    """One row per (batch execution, technology). status: ok | error."""
    __tablename__ = "cell_reconcile_runs"

    id          = Column(Integer, primary_key=True)
    batch_id    = Column(String(40))
    tech        = Column(String(5), nullable=False)
    run_date    = Column(String(10))
    started_at  = Column(DateTime(timezone=True))
    finished_at = Column(DateTime(timezone=True))
    status      = Column(String(20), nullable=False, default="ok")
    error       = Column(Text)
    prev_run_id = Column(Integer)

    dump_total                = Column(Integer, default=0)
    dump_active               = Column(Integer, default=0)
    dump_inactive             = Column(Integer, default=0)
    web_total                 = Column(Integer, default=0)
    matched                   = Column(Integer, default=0)
    missing_in_web            = Column(Integer, default=0)
    missing_in_dump           = Column(Integer, default=0)
    missing_in_dump_uncovered = Column(Integer, default=0)
    dump_inactive_not_in_web  = Column(Integer, default=0)
    new_missing_in_web        = Column(Integer, default=0)
    new_missing_in_dump       = Column(Integer, default=0)
    resolved_missing_in_web   = Column(Integer, default=0)
    resolved_missing_in_dump  = Column(Integer, default=0)

    vendor_status = Column(Text)    # JSON
    status_stats  = Column(Text)    # JSON

    __table_args__ = (Index("ix_cell_reconcile_runs_tech_id", "tech", "id"),)


class CellReconcileItem(Base):
    """One row per difference. direction: missing_in_web | missing_in_dump."""
    __tablename__ = "cell_reconcile_items"

    id             = Column(Integer, primary_key=True)
    run_id         = Column(Integer, nullable=False)
    tech           = Column(String(5), nullable=False)
    direction      = Column(String(20), nullable=False)
    cell_name      = Column(String(200))
    subcell_id     = Column(String(50))
    web_id         = Column(Integer)
    site_name      = Column(String(200))
    vendor         = Column(String(50))
    mien           = Column(String(10))
    tinh           = Column(String(100))
    phuong_xa      = Column(String(150))
    cell_status    = Column(String(100))
    bbu_name       = Column(String(200))
    rf             = Column(String(200))
    oss            = Column(String(50))
    dump_date      = Column(String(50))
    cell_id        = Column(String(50))
    node_id        = Column(String(50))
    freq           = Column(String(50))
    pci            = Column(String(50))
    tac            = Column(String(50))
    bandwidth      = Column(String(50))
    mimo           = Column(String(100))
    web_updated_at = Column(String(30))
    first_seen     = Column(String(10))
    dump_covered   = Column(String(1))

    __table_args__ = (Index("ix_cell_reconcile_items_run_dir", "run_id", "direction"),)
