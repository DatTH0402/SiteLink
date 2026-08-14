#!/bin/bash
set -e

REVISION_PAGE="frontend/src/pages/revision/RevisionPage.tsx"

# Verify file exists
if [ ! -f "$REVISION_PAGE" ]; then
  echo "ERROR: $REVISION_PAGE not found. Run this script from the project root (SiteLink/)."
  exit 1
fi

# Add rnc_name column to makeCell3GColumns() specific columns array.
# We insert it after the 'Chung anten' entry in the specific[] array inside makeCell3GColumns().
# The anchor line is the CPICH power entry (last item in 3G specific columns).
# Strategy: find the line with 'CPICH power (dBm)' inside makeCell3GColumns and insert rnc_name before it.

python3 - <<'PYEOF'
import re, sys

path = "frontend/src/pages/revision/RevisionPage.tsx"

with open(path, "r", encoding="utf-8") as f:
    content = f.read()

# The rnc_name column definition to insert
rnc_col = """    { title: 'RNC Name', key: 'rnc_name', width: 130,
      render: (_: unknown, r: CellRevisionBase) => r['rnc_name'] ? <Tag color="cyan">{String(r['rnc_name'])}</Tag> : <span>-</span> },
"""

# Anchor: the CPICH power line inside makeCell3GColumns specific array
anchor = "    { title: 'CPICH power (dBm)', key: 'cpich_power', width: 155,"

if "rnc_name" in content:
    print("INFO: rnc_name already exists in RevisionPage.tsx – no change needed.")
    sys.exit(0)

if anchor not in content:
    print("ERROR: anchor line not found in file. Please check the file content.")
    sys.exit(1)

# Insert rnc_name BEFORE the CPICH power line
new_content = content.replace(anchor, rnc_col + anchor, 1)

with open(path, "w", encoding="utf-8") as f:
    f.write(new_content)

print("SUCCESS: rnc_name column added to makeCell3GColumns() in RevisionPage.tsx")
PYEOF

echo ""
echo "Done. Summary of change:"
echo "  File   : $REVISION_PAGE"
echo "  Added  : 'RNC Name' column (key: rnc_name, width: 130) in makeCell3GColumns()"
echo "  Position: before 'CPICH power (dBm)' column in the 3G-specific columns array"
echo ""
echo "To apply: rebuild/restart the frontend dev server."