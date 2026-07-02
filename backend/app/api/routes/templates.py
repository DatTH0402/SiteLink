"""
templates.py
------------
Serves Excel template files for download.
Templates are stored in backend/templates/
"""
import os
from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

from app.utils.deps import get_current_user
from fastapi import Depends

router = APIRouter()

TEMPLATE_DIR = os.path.join(
    os.path.dirname(__file__),   # .../app/api/routes/
    "..", "..", "..",             # .../backend/
    "templates"
)
TEMPLATE_DIR = os.path.abspath(TEMPLATE_DIR)

TEMPLATES = {
    "site":    "template_site.xlsx",
    "cell-3g": "template_cell_3g.xlsx",
    "cell-4g": "template_cell_4g.xlsx",
    "cell-5g": "template_cell_5g.xlsx",
}

DISPLAY_NAMES = {
    "site":    "Template_Site.xlsx",
    "cell-3g": "Template_Cell_3G.xlsx",
    "cell-4g": "Template_Cell_4G.xlsx",
    "cell-5g": "Template_Cell_5G.xlsx",
}


@router.get("/{template_name}")
def download_template(
    template_name: str,
    _=Depends(get_current_user),
):
    """
    Download an Excel import template.
    template_name: site | cell-3g | cell-4g | cell-5g
    """
    if template_name not in TEMPLATES:
        raise HTTPException(
            status_code=404,
            detail=f"Template '{template_name}' not found. "
                   f"Available: {list(TEMPLATES.keys())}"
        )

    file_path = os.path.join(TEMPLATE_DIR, TEMPLATES[template_name])

    if not os.path.exists(file_path):
        raise HTTPException(
            status_code=404,
            detail=f"Template file not found on server. "
                   f"Please contact administrator."
        )

    return FileResponse(
        path=file_path,
        filename=DISPLAY_NAMES[template_name],
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    )
