#!/usr/bin/env bash
# =============================================================================
# add_kmz_export.sh
# Adds KMZ export feature to SiteLink (backend + frontend)
# Run from the project root: bash add_kmz_export.sh
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "=== SiteLink KMZ Export Feature Installation ==="
echo "=== Project root: ${ROOT_DIR} ==="

# ─────────────────────────────────────────────────────────────────────────────
# 1. BACKEND – patch backend/app/api/routes/export.py
#    Append the KMZ endpoint to the existing export router
# ─────────────────────────────────────────────────────────────────────────────
EXPORT_PY="${ROOT_DIR}/backend/app/api/routes/export.py"

echo ""
echo "[1/3] Patching backend export route: ${EXPORT_PY}"

# Check the file exists
if [[ ! -f "${EXPORT_PY}" ]]; then
  echo "ERROR: ${EXPORT_PY} not found. Are you running from the project root?"
  exit 1
fi

# Check if already patched
if grep -q "export_sites_kmz" "${EXPORT_PY}"; then
  echo "  -> KMZ endpoint already present, skipping backend patch."
else
  cat >> "${EXPORT_PY}" << 'PYTHON_EOF'


# =============================================================================
# KMZ Export  (KML inside a ZIP — readable by Google Earth)
# =============================================================================
import zipfile as _zipfile
import xml.sax.saxutils as _saxutils


def _build_kml(sites: list) -> str:
    """
    Build a KML document string for the given list of Site ORM objects.
    Each site becomes a <Placemark> with:
      - name        : site_name
      - description : province / ward / site_name / site_name_old
      - coordinates : lon,lat (Google Earth order)
    """
    def esc(v) -> str:
        """XML-escape a value; return empty string for None."""
        if v is None:
            return ""
        return _saxutils.escape(str(v))

    placemarks = []
    for s in sites:
        # Skip sites with no valid coordinates
        if s.lat is None or s.long is None:
            continue

        description = (
            f"<b>Tỉnh/TP:</b> {esc(s.tinh)}<br/>"
            f"<b>Phường/Xã:</b> {esc(s.phuong_xa)}<br/>"
            f"<b>Site name:</b> {esc(s.site_name)}<br/>"
            f"<b>Site name (cũ):</b> {esc(s.site_name_cu)}<br/>"
        )

        placemarks.append(f"""  <Placemark>
    <name>{esc(s.site_name)}</name>
    <description><![CDATA[{description}]]></description>
    <Point>
      <coordinates>{s.long},{s.lat},0</coordinates>
    </Point>
  </Placemark>""")

    kml_body = "\n".join(placemarks)

    return f"""<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>SiteLink – Site Locations</name>
    <description>Exported from SiteLink</description>
    <Style id="siteIcon">
      <IconStyle>
        <color>ff0000ff</color>
        <scale>1.0</scale>
        <Icon>
          <href>http://maps.google.com/mapfiles/kml/paddle/red-circle.png</href>
        </Icon>
      </IconStyle>
    </Style>
{kml_body}
  </Document>
</kml>"""


def _build_kmz(kml_content: str) -> bytes:
    """Wrap a KML string inside a KMZ (zip) archive, return raw bytes."""
    buf = io.BytesIO()
    with _zipfile.ZipFile(buf, mode="w", compression=_zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("doc.kml", kml_content.encode("utf-8"))
    buf.seek(0)
    return buf.read()


@router.get("/sites-kmz")
def export_sites_kmz(
    search:       Optional[str]        = Query(None),
    site_name_cu: Optional[str]        = Query(None),
    mien:         Optional[List[str]]  = Query(None),
    tinh:         Optional[List[str]]  = Query(None),
    phuong_xa:    Optional[List[str]]  = Query(None),
    tram_3g:      Optional[bool]       = Query(None),
    tram_4g:      Optional[bool]       = Query(None),
    tram_5g:      Optional[bool]       = Query(None),
    db:           Session              = Depends(get_db),
    _:            User                 = Depends(get_optional_user),
):
    """
    Export filtered sites as a KMZ file (Google Earth compatible).
    Accepts the same filter parameters as the Sites list and Excel export.
    Token may be passed as Bearer header OR ?token= query param.
    """
    q = db.query(Site)
    if search:       q = q.filter(Site.site_name.ilike(f"%{search}%"))
    if site_name_cu: q = q.filter(Site.site_name_cu.ilike(f"%{site_name_cu}%"))
    if mien:         q = q.filter(Site.mien.in_(mien))
    if tinh:         q = q.filter(Site.tinh.in_(tinh))
    if phuong_xa:    q = q.filter(Site.phuong_xa.in_(phuong_xa))
    if tram_3g is not None: q = q.filter(Site.tram_3g == tram_3g)
    if tram_4g is not None: q = q.filter(Site.tram_4g == tram_4g)
    if tram_5g is not None: q = q.filter(Site.tram_5g == tram_5g)

    sites = q.order_by(Site.mien, Site.tinh, Site.site_name).all()

    valid_count = sum(1 for s in sites if s.lat is not None and s.long is not None)

    kml_content = _build_kml(sites)
    kmz_bytes   = _build_kmz(kml_content)

    return StreamingResponse(
        iter([kmz_bytes]),
        media_type="application/vnd.google-earth.kmz",
        headers={
            "Content-Disposition": 'attachment; filename="Sites_Export.kmz"',
            "X-Site-Count": str(len(sites)),
            "X-Valid-Coords": str(valid_count),
        },
    )
PYTHON_EOF

  echo "  -> Backend KMZ endpoint appended successfully."
fi


# ─────────────────────────────────────────────────────────────────────────────
# 2. FRONTEND – patch frontend/src/api/export.ts
#    Add exportSitesKmz() function
# ─────────────────────────────────────────────────────────────────────────────
EXPORT_TS="${ROOT_DIR}/frontend/src/api/export.ts"

echo ""
echo "[2/3] Patching frontend API: ${EXPORT_TS}"

if [[ ! -f "${EXPORT_TS}" ]]; then
  echo "ERROR: ${EXPORT_TS} not found."
  exit 1
fi

if grep -q "exportSitesKmz" "${EXPORT_TS}"; then
  echo "  -> exportSitesKmz already present, skipping frontend API patch."
else
  cat >> "${EXPORT_TS}" << 'TS_EOF'

export function exportSitesKmz(filters: {
  search?:       string
  site_name_cu?: string
  mien?:         string[]
  tinh?:         string[]
  phuong_xa?:    string[]
}) {
  const qs = buildQS(filters)
  return downloadBlob(`/api/v1/export/sites-kmz${qs}`, 'Sites_Export.kmz')
}
TS_EOF

  echo "  -> exportSitesKmz() appended to export.ts successfully."
fi


# ─────────────────────────────────────────────────────────────────────────────
# 3. FRONTEND – patch frontend/src/pages/sites/SitesPage.tsx
#    a) Add exportSitesKmz to the import line
#    b) Add exportingKmz state variable
#    c) Add handleKmzExport handler
#    d) Add KMZ button in the toolbar
# ─────────────────────────────────────────────────────────────────────────────
SITES_PAGE="${ROOT_DIR}/frontend/src/pages/sites/SitesPage.tsx"

echo ""
echo "[3/3] Patching SitesPage: ${SITES_PAGE}"

if [[ ! -f "${SITES_PAGE}" ]]; then
  echo "ERROR: ${SITES_PAGE} not found."
  exit 1
fi

# ── 3a. Add exportSitesKmz to the import from '@/api/export' ──────────────
if grep -q "exportSitesKmz" "${SITES_PAGE}"; then
  echo "  -> KMZ import already present, skipping import patch."
else
  # Replace: "import { exportSites } from '@/api/export'"
  # With:    "import { exportSites, exportSitesKmz } from '@/api/export'"
  sed -i "s|import { exportSites } from '@/api/export'|import { exportSites, exportSitesKmz } from '@/api/export'|g" "${SITES_PAGE}"
  echo "  -> Added exportSitesKmz to import statement."
fi

# ── 3b. Add exportingKmz state after the exportingState declaration ─────────
if grep -q "exportingKmz" "${SITES_PAGE}"; then
  echo "  -> exportingKmz state already present, skipping state patch."
else
  # Insert "const [exportingKmz, setExportingKmz] = useState(false)"
  # after the line that declares "const [exporting, setExporting]"
  sed -i "/const \[exporting,\s*setExporting\]\s*=\s*useState(false)/a\\  const [exportingKmz,    setExportingKmz]    = useState(false)" "${SITES_PAGE}"
  echo "  -> Added exportingKmz state variable."
fi

# ── 3c. Add handleKmzExport handler after the handleExport function ──────────
if grep -q "handleKmzExport" "${SITES_PAGE}"; then
  echo "  -> handleKmzExport already present, skipping handler patch."
else
  # We insert the new handler after the closing brace of handleExport.
  # The handleExport function ends with:   }
  # followed by an empty line then "  const clearFilters"
  # We use a Python helper for multi-line sed (more reliable cross-platform)
  python3 - "${SITES_PAGE}" << 'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

new_handler = """
  const handleKmzExport = async () => {
    setExportingKmz(true)
    try {
      await exportSitesKmz({
        search:       search || undefined,
        site_name_cu: siteNameCu || undefined,
        mien:         mien.length ? mien : undefined,
        tinh:         tinh.length ? tinh : undefined,
        phuong_xa:    phuongXa.length ? phuongXa : undefined,
      })
      message.success(`Xuất KMZ thành công (${sites.length} sites)`)
    } catch (e: any) {
      message.error(e?.message || 'Xuất KMZ thất bại')
    } finally {
      setExportingKmz(false)
    }
  }

"""

# Insert before "  const clearFilters"
if 'handleKmzExport' not in content:
    content = content.replace(
        '  const clearFilters = () => {',
        new_handler + '  const clearFilters = () => {',
        1
    )
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('  -> handleKmzExport handler inserted.')
else:
    print('  -> handleKmzExport already exists, skipping.')
PYEOF
fi

# ── 3d. Add KMZ button in the toolbar ───────────────────────────────────────
if grep -q "Xuất KMZ" "${SITES_PAGE}"; then
  echo "  -> KMZ button already present, skipping button patch."
else
  python3 - "${SITES_PAGE}" << 'PYEOF'
import sys

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# The KMZ button is inserted immediately before the existing Excel export button.
# We look for the Tooltip that wraps the Excel button.
excel_button_block = '          <Tooltip title="Xuất dữ liệu hiện tại ra Excel">'

kmz_button = """          <Tooltip title="Xuất dữ liệu hiện tại ra KMZ (Google Earth)">
            <Button
              icon={<DownloadOutlined />}
              loading={exportingKmz}
              onClick={handleKmzExport}
              style={{ borderColor: '#722ed1', color: '#722ed1' }}
            >
              Xuất KMZ ({sites.length})
            </Button>
          </Tooltip>
"""

if 'Xuất KMZ' not in content:
    content = content.replace(
        excel_button_block,
        kmz_button + excel_button_block,
        1
    )
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('  -> KMZ button inserted into toolbar.')
else:
    print('  -> KMZ button already exists, skipping.')
PYEOF
fi

# ─────────────────────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo " KMZ Export feature installation COMPLETE"
echo "============================================================"
echo ""
echo " Changes made:"
echo "   backend/app/api/routes/export.py  -> GET /api/v1/export/sites-kmz"
echo "   frontend/src/api/export.ts        -> exportSitesKmz()"
echo "   frontend/src/pages/sites/SitesPage.tsx -> KMZ button + handler"
echo ""
echo " Next steps:"
echo "   Docker:    docker compose restart backend frontend"
echo "   Local dev: restart uvicorn + vite dev server"
echo ""
echo " Test the endpoint directly:"
echo '   curl -H "Authorization: Bearer <token>" \'
echo '        "http://localhost:8000/api/v1/export/sites-kmz" -o test.kmz'
echo '   file test.kmz   # should report: Zip archive data'
echo ""