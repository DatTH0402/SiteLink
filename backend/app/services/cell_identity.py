"""
services/cell_identity.py
-------------------------
Identity rules for 3G / 4G / 5G cells.

A cell is identified by  (site_id, cell_name, subcell_id).
  * subcell_id is OPTIONAL; blank == NULL.
  * When subcell_id is empty, cell_name alone identifies the cell.
  * Several cells may share the same cell_name when their subcell_id differ.
  * Syncing from the vendor CSV files only uses cell_name (see cell_sync_core.py):
    cells sharing a name receive the same synced values.
"""
from __future__ import annotations

from typing import Optional

from fastapi import HTTPException
from sqlalchemy import func, or_


def norm_subcell(v) -> Optional[str]:
    """'' / whitespace / None -> None, otherwise the stripped string."""
    if v is None:
        return None
    s = str(v).strip()
    return s or None


def subcell_clause(model, sub: Optional[str]):
    """SQL condition: model.subcell_id equals `sub` (None == blank / NULL)."""
    col = model.subcell_id
    if sub is None:
        return or_(col.is_(None), func.trim(col) == "")
    return func.trim(col) == sub


def find_cell(db, model, cell_name: str, subcell_id: Optional[str],
              site_id: Optional[int] = None, exclude_id: Optional[int] = None):
    """Exact identity lookup: (site_id, cell_name, subcell_id)."""
    q = db.query(model).filter(model.cell_name == cell_name)
    if site_id is not None:
        q = q.filter(model.site_id == site_id)
    q = q.filter(subcell_clause(model, norm_subcell(subcell_id)))
    if exclude_id is not None:
        q = q.filter(model.id != exclude_id)
    return q.order_by(model.id).first()


def assert_no_duplicate(db, model, site_id: Optional[int], cell_name: str,
                        subcell_id: Optional[str], exclude_id: Optional[int] = None) -> None:
    """HTTP 409 when another cell already has the same (site, cell_name, subcell_id)."""
    if not cell_name:
        return
    sub = norm_subcell(subcell_id)
    if find_cell(db, model, cell_name, sub, site_id, exclude_id) is None:
        return
    if sub:
        detail = ("Cell '%s' với Subcell-ID '%s' đã tồn tại trong site này. "
                  "Hãy nhập Subcell-ID khác để phân biệt." % (cell_name, sub))
    else:
        detail = ("Cell '%s' (chưa có Subcell-ID) đã tồn tại trong site này. "
                  "Nếu nhiều cell trùng tên, hãy nhập Subcell-ID để phân biệt." % cell_name)
    raise HTTPException(status_code=409, detail=detail)
