"""
services/site_info.py
Cells denormalise a few columns from their parent Site. The cell forms do not
collect them, so they are copied from the Site on the server side.
"""
from typing import Any, Dict

from app.models.site import Site

SITE_INHERITED_FIELDS = ("site_name", "mien", "tinh", "phuong_xa")


def apply_site_info(data: Dict[str, Any], site: Site) -> Dict[str, Any]:
    out = dict(data)
    out["site_id"] = site.id
    for field in SITE_INHERITED_FIELDS:
        value = getattr(site, field, None)
        if value is not None and str(value).strip() != "":
            out[field] = value
    return out
