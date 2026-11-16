#!/usr/bin/env bash
# patch_reconcile_ignore.sh
# Adds ignore rules to backend/cell_reconcile_core.py:
#   - web cells not in dump : ignore names starting/ending with "MBF"
#   - dump cells not on web : ignore names starting/ending with "VNP"
set -euo pipefail

TARGET="${1:-backend/cell_reconcile_core.py}"

if [ ! -f "$TARGET" ]; then
  echo "❌ File not found: $TARGET"
  echo "   Usage: $0 [path/to/cell_reconcile_core.py]"
  exit 1
fi

if grep -q "IGNORE_WEB_NOT_IN_DUMP" "$TARGET"; then
  echo "ℹ️  Already patched, nothing to do."
  exit 0
fi

BACKUP="${TARGET}.bak.$(date +%Y%m%d_%H%M%S)"
cp "$TARGET" "$BACKUP"
echo "📦 Backup: $BACKUP"

if ! python3 - "$TARGET" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    src = f.read()


def rep(old, new):
    global src
    n = src.count(old)
    if n != 1:
        sys.exit("❌ Anchor expected exactly once but found %d times:\n%s" % (n, old))
    src = src.replace(old, new)


# 1) docstring ---------------------------------------------------------------
rep(
    "Safety nets (a bad download must never produce a flood of false alarms):",
    "Ignore rules (cells that are deliberately not reconciled):\n"
    "  * web cells whose name starts OR ends with MBF are never reported as missing_in_dump\n"
    "  * dump cells whose name starts OR ends with VNP are never reported as missing_in_web\n"
    "  (env RECONCILE_IGNORE_WEB_NOT_IN_DUMP / RECONCILE_IGNORE_DUMP_NOT_IN_WEB, comma separated)\n"
    "\n"
    "Safety nets (a bad download must never produce a flood of false alarms):",
)

# 2) config + helper ---------------------------------------------------------
rep(
    "INSERT_BATCH = 2000\n",
    "INSERT_BATCH = 2000\n"
    "\n"
    "\n"
    "# -- ignore rules (prefix OR postfix, case-insensitive) ----------------------\n"
    "def _parse_affixes(env_name: str, default: str) -> Tuple[str, ...]:\n"
    "    raw = os.environ.get(env_name, default)\n"
    "    return tuple(x.strip().upper() for x in raw.split(\",\") if x.strip())\n"
    "\n"
    "\n"
    "IGNORE_WEB_NOT_IN_DUMP = _parse_affixes(\"RECONCILE_IGNORE_WEB_NOT_IN_DUMP\", \"MBF\")\n"
    "IGNORE_DUMP_NOT_IN_WEB = _parse_affixes(\"RECONCILE_IGNORE_DUMP_NOT_IN_WEB\", \"VNP\")\n"
    "\n"
    "\n"
    "def has_affix(name: Any, affixes: Tuple[str, ...]) -> bool:\n"
    "    # True when the cell name starts or ends with one of the affixes\n"
    "    n = str(name or \"\").strip().upper()\n"
    "    return bool(n) and bool(affixes) and (n.startswith(affixes) or n.endswith(affixes))\n",
)

# 3) counters ----------------------------------------------------------------
rep(
    "    matched = inactive_not_in_web = 0\n",
    "    matched = inactive_not_in_web = 0\n"
    "    ignored_dump = ignored_web = 0\n",
)

# 4) dump -> web direction (VNP) ---------------------------------------------
rep(
    "        items.append(_dump_item(tech, rec, geo))\n",
    "        if has_affix(rec[\"cell_name\"], IGNORE_DUMP_NOT_IN_WEB):\n"
    "            ignored_dump += 1\n"
    "            continue\n"
    "        items.append(_dump_item(tech, rec, geo))\n",
)

# 5) web -> dump direction (MBF) + notes --------------------------------------
rep(
    "        items.append(_web_item(tech, r, name))\n",
    "        if has_affix(name, IGNORE_WEB_NOT_IN_DUMP):\n"
    "            ignored_web += 1\n"
    "            continue\n"
    "        items.append(_web_item(tech, r, name))\n"
    "    if ignored_dump:\n"
    "        notes.append(\"Bỏ qua %d cell active trong dump có tiền tố/hậu tố %s (không đối soát).\"\n"
    "                     % (ignored_dump, \"/\".join(IGNORE_DUMP_NOT_IN_WEB)))\n"
    "    if ignored_web:\n"
    "        notes.append(\"Bỏ qua %d cell trên web có tiền tố/hậu tố %s (không đối soát).\"\n"
    "                     % (ignored_web, \"/\".join(IGNORE_WEB_NOT_IN_DUMP)))\n",
)

# 6) 'resolved' counters must not count ignored cells from older runs ----------
rep(
    "    res_web = sum(1 for k in prev if k[0] == \"missing_in_web\" and k not in cur_keys)\n",
    "    res_web = sum(1 for k in prev if k[0] == \"missing_in_web\" and k not in cur_keys\n"
    "                  and not has_affix(k[1], IGNORE_DUMP_NOT_IN_WEB))\n",
)
rep(
    "    res_dump = sum(1 for k, v in prev.items() if k[0] == \"missing_in_dump\" and v[1] != \"N\" and k not in cur_keys)\n",
    "    res_dump = sum(1 for k, v in prev.items() if k[0] == \"missing_in_dump\" and v[1] != \"N\"\n"
    "                   and k not in cur_keys and not has_affix(k[1], IGNORE_WEB_NOT_IN_DUMP))\n",
)

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("✅ Patched:", path)
PY
then
  echo "❌ Patch failed - restoring backup."
  cp "$BACKUP" "$TARGET"
  exit 1
fi

if ! python3 -m py_compile "$TARGET"; then
  echo "❌ Syntax check failed - restoring backup."
  cp "$BACKUP" "$TARGET"
  exit 1
fi

echo "✅ Syntax OK."
echo
echo "Next steps:"
echo "  1) Test:  python backend/reconcile_cells.py --dry-run"
echo "  2) Real run (refreshes the stored results shown on the 'Đối soát Cell' page):"
echo "       python backend/reconcile_cells.py"
echo "  Optional env overrides (comma separated):"
echo "       RECONCILE_IGNORE_WEB_NOT_IN_DUMP=MBF"
echo "       RECONCILE_IGNORE_DUMP_NOT_IN_WEB=VNP"