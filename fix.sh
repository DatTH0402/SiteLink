#!/usr/bin/env bash
# =============================================================================
# fix_kmz_button.sh
# Force-inserts the KMZ button into SitesPage.tsx by rewriting the file
# Run from the project root: bash fix_kmz_button.sh
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITES_PAGE="${ROOT_DIR}/frontend/src/pages/sites/SitesPage.tsx"

echo "=== KMZ Button Fix ==="
echo "=== Target: ${SITES_PAGE} ==="

if [[ ! -f "${SITES_PAGE}" ]]; then
  echo "ERROR: ${SITES_PAGE} not found."
  exit 1
fi

# Show current state of the file around the toolbar area for diagnosis
echo ""
echo "--- Current toolbar area in SitesPage.tsx ---"
grep -n "KMZ\|Xuất Excel\|Xuất KMZ\|exportingKmz\|handleKmzExport\|exportSitesKmz\|DownloadOutlined\|Tooltip" "${SITES_PAGE}" || echo "(no matches found)"
echo "---------------------------------------------"
echo ""

# Use Python to do a reliable rewrite of the file
python3 - "${SITES_PAGE}" << 'PYEOF'
import sys
import re

path = sys.argv[1]

with open(path, 'r', encoding='utf-8') as f:
    original = f.read()

content = original

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Ensure exportSitesKmz is in the import from '@/api/export'
# ─────────────────────────────────────────────────────────────────────────────
# Match any variant of the export import line
export_import_pattern = re.compile(
    r"import\s*\{([^}]*)\}\s*from\s*'@/api/export'"
)
match = export_import_pattern.search(content)
if match:
    imports_str = match.group(1)
    imports_list = [x.strip() for x in imports_str.split(',') if x.strip()]
    if 'exportSitesKmz' not in imports_list:
        imports_list.append('exportSitesKmz')
        new_imports = ', '.join(imports_list)
        new_line = f"import {{ {new_imports} }} from '@/api/export'"
        content = export_import_pattern.sub(new_line, content, count=1)
        print(f"  [fix] Updated export import: {new_line}")
    else:
        print("  [ok] exportSitesKmz already in import.")
else:
    print("  [WARN] Could not find import from '@/api/export' - adding it")
    # Add after the last import line
    last_import = list(re.finditer(r'^import .+$', content, re.MULTILINE))
    if last_import:
        pos = last_import[-1].end()
        content = content[:pos] + "\nimport { exportSitesKmz } from '@/api/export'" + content[pos:]

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: Ensure exportingKmz state exists
# ─────────────────────────────────────────────────────────────────────────────
if 'exportingKmz' not in content:
    # Insert after the exporting state line
    content = re.sub(
        r'(const \[exporting\s*,\s*setExporting\]\s*=\s*useState\(false\))',
        r'\1\n  const [exportingKmz,    setExportingKmz]    = useState(false)',
        content,
        count=1
    )
    print("  [fix] Added exportingKmz state.")
else:
    print("  [ok] exportingKmz state already present.")

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: Ensure handleKmzExport handler exists
# ─────────────────────────────────────────────────────────────────────────────
if 'handleKmzExport' not in content:
    new_handler = """  const handleKmzExport = async () => {
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

  const clearFilters"""

    content = content.replace(
        '  const clearFilters',
        new_handler,
        1
    )
    print("  [fix] Added handleKmzExport handler.")
else:
    print("  [ok] handleKmzExport already present.")

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: Insert the KMZ button in the toolbar
# Strategy: find the Space block that contains the toolbar buttons and
# inject the KMZ button before the Excel Tooltip block.
# We use multiple fallback strategies.
# ─────────────────────────────────────────────────────────────────────────────

kmz_button_jsx = """          <Tooltip title="Xuất dữ liệu hiện tại ra KMZ (Google Earth)">
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

def button_is_present(c):
    return (
        'exportingKmz' in c and
        'handleKmzExport' in c and
        ('Xuất KMZ' in c or 'sites-kmz' in c)
    )

# Check if the button JSX is actually rendered (not just the handler/state)
# We need to find it inside the return() JSX, so we check for the Button JSX
kmz_rendered = re.search(r'loading=\{exportingKmz\}', content) is not None

if kmz_rendered:
    print("  [ok] KMZ button JSX already rendered in toolbar.")
else:
    print("  [fix] KMZ button NOT found in JSX. Attempting to insert...")

    inserted = False

    # Strategy A: Insert before the Excel Tooltip block
    # Look for: <Tooltip title="Xuất dữ liệu hiện tại ra Excel">
    excel_tooltip = '<Tooltip title="Xuất dữ liệu hiện tại ra Excel">'
    if excel_tooltip in content:
        content = content.replace(
            excel_tooltip,
            kmz_button_jsx + '          ' + excel_tooltip,
            1
        )
        inserted = True
        print("  [fix] Strategy A: Inserted KMZ button before Excel Tooltip.")

    # Strategy B: Insert before the Excel Button (if Tooltip not found)
    if not inserted:
        # Look for the export button with green color
        excel_btn_pattern = re.compile(
            r'(<Button[^>]*loading=\{exporting\}[^/])',
            re.DOTALL
        )
        match_b = excel_btn_pattern.search(content)
        if match_b:
            # Find the Tooltip that wraps it — go back ~200 chars
            start = max(0, match_b.start() - 300)
            snippet = content[start:match_b.start()]
            tooltip_start_in_snippet = snippet.rfind('<Tooltip')
            if tooltip_start_in_snippet >= 0:
                abs_tooltip_start = start + tooltip_start_in_snippet
                content = (
                    content[:abs_tooltip_start]
                    + kmz_button_jsx + '          '
                    + content[abs_tooltip_start:]
                )
                inserted = True
                print("  [fix] Strategy B: Inserted KMZ button before Excel button's Tooltip.")

    # Strategy C: Insert before the Import Excel button
    if not inserted:
        import_btn = '<Button icon={<UploadOutlined />} onClick={() => setDryRunOpen(true)}>'
        if import_btn in content:
            content = content.replace(
                import_btn,
                kmz_button_jsx + '          ' + import_btn,
                1
            )
            inserted = True
            print("  [fix] Strategy C: Inserted KMZ button before Import Excel button.")

    # Strategy D: Insert inside the <Space> block in the header row
    # Find the Space tag that contains the action buttons
    if not inserted:
        space_pattern = re.compile(
            r'(<Space>\s*\n)(\s*<Tooltip)',
            re.MULTILINE
        )
        match_d = space_pattern.search(content)
        if match_d:
            insert_pos = match_d.start(2)
            content = (
                content[:insert_pos]
                + kmz_button_jsx
                + content[insert_pos:]
            )
            inserted = True
            print("  [fix] Strategy D: Inserted KMZ button at start of Space block.")

    if not inserted:
        print("  [ERROR] Could not automatically insert KMZ button.")
        print("          Please add it manually — see instructions below.")
        print("")
        print("  Add this JSX block in SitesPage.tsx inside the <Space> toolbar,")
        print("  before the Excel export Tooltip/Button:")
        print("")
        print(kmz_button_jsx)
        sys.exit(1)

# ─────────────────────────────────────────────────────────────────────────────
# Write the file only if something changed
# ─────────────────────────────────────────────────────────────────────────────
if content != original:
    # Backup original
    backup_path = path + '.bak'
    with open(backup_path, 'w', encoding='utf-8') as f:
        f.write(original)
    print(f"  [info] Original backed up to {backup_path}")

    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"  [info] {path} written successfully.")
else:
    print("  [info] No changes needed.")

# ─────────────────────────────────────────────────────────────────────────────
# Final verification
# ─────────────────────────────────────────────────────────────────────────────
print("")
print("--- Verification ---")
with open(path, 'r', encoding='utf-8') as f:
    final = f.read()

checks = {
    'exportSitesKmz import':    'exportSitesKmz' in final,
    'exportingKmz state':        'exportingKmz' in final,
    'handleKmzExport handler':   'handleKmzExport' in final,
    'KMZ button rendered (loading={exportingKmz})': 'loading={exportingKmz}' in final,
    'KMZ button onClick':        'onClick={handleKmzExport}' in final,
}

all_ok = True
for check, result in checks.items():
    status = '[PASS]' if result else '[FAIL]'
    if not result:
        all_ok = False
    print(f"  {status} {check}")

if all_ok:
    print("")
    print("  All checks passed!")
else:
    print("")
    print("  Some checks FAILED. Manual intervention required.")
    print("  Check the file and add missing pieces manually.")
    sys.exit(2)

PYEOF

echo ""
echo "=== Showing final toolbar section of SitesPage.tsx ==="
echo ""
# Show lines around the Space/toolbar area
grep -n "Xuất KMZ\|Xuất Excel\|exportingKmz\|handleKmzExport\|UploadOutlined\|Thêm mới" "${SITES_PAGE}" | head -30
echo ""

echo "============================================================"
echo " Fix complete. Now rebuild the frontend container:"
echo ""
echo "   docker compose build frontend && docker compose up -d frontend"
echo ""
echo " Or if you want to rebuild everything:"
echo "   docker compose up --build -d"
echo "============================================================"