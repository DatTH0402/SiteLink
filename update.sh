cat > /tmp/fix_cells.sh << 'SHELLSCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# Helper to extract a human-readable error message from axios error responses
# Fixes: FastAPI 422 returns detail as array-of-objects, not a string
# Passing an object/array to antd message.error() causes React error #31

FIX_3G="frontend/src/pages/cells/Cells3GPage.tsx"
FIX_4G="frontend/src/pages/cells/Cells4GPage.tsx"
FIX_5G="frontend/src/pages/cells/Cells5GPage.tsx"

# ── Utility: format FastAPI error detail ─────────────────────────────────────
# We'll add a shared helper. But since these are self-contained page files,
# we inline a one-liner helper inside each handleSave.

# The pattern to find in all three files:
OLD='} catch (e: any) { message.error(e.response?.data?.detail || '"'"'Có lỗi xảy ra'"'"') }'

# The replacement — safely stringify detail whether it's a string or array
NEW='} catch (e: any) {
      const detail = e?.response?.data?.detail
      const msg = Array.isArray(detail)
        ? detail.map((d: any) => `${d.loc?.slice(-1)?.[0] ?? '"'"'field'"'"'}: ${d.msg}`).join('"'"'; '"'"')
        : (typeof detail === '"'"'string'"'"' ? detail : (e?.message || '"'"'Có lỗi xảy ra'"'"'))
      message.error(msg)
    }'

for FILE in "$FIX_3G" "$FIX_4G" "$FIX_5G"; do
  if [[ ! -f "$FILE" ]]; then
    echo "ERROR: $FILE not found"
    exit 1
  fi
  echo "Patching $FILE ..."
  # Use python3 for reliable multi-line sed replacement
  python3 - "$FILE" << 'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    src = f.read()

old = r"} catch \(e: any\) \{ message\.error\(e\.response\?\.data\?\.detail \|\| 'Có lỗi xảy ra'\) \}"
new = """\
} catch (e: any) {
      const detail = e?.response?.data?.detail
      const msg = Array.isArray(detail)
        ? detail.map((d: any) => `${d.loc?.slice(-1)?.[0] ?? 'field'}: ${d.msg}`).join('; ')
        : (typeof detail === 'string' ? detail : (e?.message || 'Có lỗi xảy ra'))
      message.error(msg)
    }"""

new_src, count = re.subn(old, new, src)
if count == 0:
    print(f"  WARNING: pattern not found in {path}, trying alternate pattern...")
    # Try alternate spacing/formatting
    old2 = r"}\s*catch\s*\(e:\s*any\)\s*\{\s*message\.error\(e\.response\?\.data\?\.detail\s*\|\|\s*'Có lỗi xảy ra'\)\s*\}"
    new_src, count = re.subn(old2, new, src, flags=re.DOTALL)
    if count == 0:
        print(f"  ERROR: could not find error handler pattern in {path}")
        sys.exit(1)

with open(path, 'w', encoding='utf-8') as f:
    f.write(new_src)
print(f"  OK: replaced {count} occurrence(s) in {path}")
PYEOF
done

echo ""
echo "All files patched. Summary of change:"
echo "  Before: message.error(e.response?.data?.detail || 'Có lỗi xảy ra')"
echo "  After:  Safely formats FastAPI 422 detail array into readable string"
echo ""
echo "Done."
SHELLSCRIPT

chmod +x /tmp/fix_cells.sh
bash /tmp/fix_cells.sh