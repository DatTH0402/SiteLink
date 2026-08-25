"""
templates.py
------------
Serves Excel template files for download.
Templates are stored in backend/templates/

Cache policy: no-store / no-cache on all responses so browsers and
proxies always fetch the latest regenerated file.
"""
import hashlib
import os
import time
from fastapi import APIRouter, HTTPException, Depends
from fastapi.responses import FileResponse, JSONResponse

from app.utils.deps import get_current_user

router = APIRouter()

TEMPLATE_DIR = os.path.abspath(
    os.path.join(
        os.path.dirname(__file__),   # .../app/api/routes/
        "..", "..", "..",             # .../backend/
        "templates",
    )
)

# ── registry ──────────────────────────────────────────────────────────────────
TEMPLATES = {
    "site":    "template_site.xlsx",
    "cell-3g": "template_cell_3g.xlsx",
    "cell-4g": "template_cell_4g.xlsx",
    "cell-5g": "template_cell_5g.xlsx",
    "antenna": "template_antenna.xlsx",
}

DISPLAY_NAMES = {
    "site":    "Template_Site.xlsx",
    "cell-3g": "Template_Cell_3G.xlsx",
    "cell-4g": "Template_Cell_4G.xlsx",
    "cell-5g": "Template_Cell_5G.xlsx",
    "antenna": "Template_Antenna.xlsx",
}

# No-cache headers applied to every template response
_NO_CACHE_HEADERS = {
    "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
    "Pragma":        "no-cache",
    "Expires":       "0",
}


def _file_etag(path: str) -> str:
    """Generate ETag from file mtime + size so it changes whenever file changes."""
    stat = os.stat(path)
    raw  = f"{stat.st_mtime_ns}-{stat.st_size}"
    return hashlib.md5(raw.encode()).hexdigest()


def _get_file_path(template_name: str) -> str:
    """Resolve and validate template file path. Raises HTTPException if invalid."""
    if template_name not in TEMPLATES:
        raise HTTPException(
            status_code=404,
            detail=(
                f"Template '{template_name}' not found. "
                f"Available: {list(TEMPLATES.keys())}"
            ),
        )
    file_path = os.path.join(TEMPLATE_DIR, TEMPLATES[template_name])
    if not os.path.exists(file_path):
        raise HTTPException(
            status_code=503,
            detail=(
                "Template file not found on server – it may still be "
                "generating. Please wait a few seconds and try again."
            ),
        )
    return file_path


# ── Download endpoint ─────────────────────────────────────────────────────────

@router.get("/{template_name}/download")
@router.get("/{template_name}")          # keep backward-compatible path
def download_template(
    template_name: str,
    _=Depends(get_current_user),
):
    """
    Download an Excel import template.
    template_name: site | cell-3g | cell-4g | cell-5g | antenna

    Response always includes Cache-Control: no-store so browsers and
    proxies never serve a stale cached copy.
    """
    file_path = _get_file_path(template_name)
    etag      = _file_etag(file_path)

    return FileResponse(
        path=file_path,
        filename=DISPLAY_NAMES[template_name],
        media_type=(
            "application/vnd.openxmlformats-officedocument"
            ".spreadsheetml.sheet"
        ),
        headers={
            **_NO_CACHE_HEADERS,
            "ETag":              f'"{etag}"',
            "X-Template-ETag":   etag,
            "X-Template-Name":   template_name,
        },
    )


# ── Info endpoint (used by frontend to detect updates) ───────────────────────

@router.get("/info/{template_name}")
def template_info(
    template_name: str,
    _=Depends(get_current_user),
):
    """
    Return metadata about a template file without downloading it.
    Frontend can poll this to detect when a regenerated template is ready.

    Response:
    {
        "name":         "cell-3g",
        "filename":     "template_cell_3g.xlsx",
        "size_bytes":   102400,
        "last_modified": 1234567890.123,
        "etag":         "abc123def456",
        "exists":       true
    }
    """
    if template_name not in TEMPLATES:
        raise HTTPException(
            status_code=404,
            detail=f"Template '{template_name}' not found.",
        )

    file_path = os.path.join(TEMPLATE_DIR, TEMPLATES[template_name])

    if not os.path.exists(file_path):
        return JSONResponse(
            content={
                "name":          template_name,
                "filename":      TEMPLATES[template_name],
                "exists":        False,
                "size_bytes":    0,
                "last_modified": 0,
                "etag":          "",
            },
            headers=_NO_CACHE_HEADERS,
        )

    stat = os.stat(file_path)
    return JSONResponse(
        content={
            "name":          template_name,
            "filename":      DISPLAY_NAMES[template_name],
            "exists":        True,
            "size_bytes":    stat.st_size,
            "last_modified": stat.st_mtime,
            "etag":          _file_etag(file_path),
        },
        headers=_NO_CACHE_HEADERS,
    )


# ── List all templates info ───────────────────────────────────────────────────

@router.get("/")
def list_templates(_=Depends(get_current_user)):
    """Return info for all available templates."""
    result = []
    for key, filename in TEMPLATES.items():
        file_path = os.path.join(TEMPLATE_DIR, filename)
        exists    = os.path.exists(file_path)
        entry = {
            "name":          key,
            "filename":      DISPLAY_NAMES[key],
            "exists":        exists,
            "size_bytes":    0,
            "last_modified": 0,
            "etag":          "",
        }
        if exists:
            stat           = os.stat(file_path)
            entry["size_bytes"]    = stat.st_size
            entry["last_modified"] = stat.st_mtime
            entry["etag"]          = _file_etag(file_path)
        result.append(entry)

    return JSONResponse(content=result, headers=_NO_CACHE_HEADERS)
