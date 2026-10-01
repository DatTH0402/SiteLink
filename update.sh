#!/usr/bin/env bash
# update_pagination_2.sh — apply useTablePagination to
#   AntennaPage, RevisionPage (2 tables), AuditPage, UsersPage
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Please run with bash:  bash update_pagination_2.sh [ROOT]"; exit 1
fi
set -uo pipefail

# ── Resolve project root ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
is_root() { [ -d "$1/backend/app" ] && [ -d "$1/frontend/src" ]; }

ROOT=""
if [ -n "${1:-}" ]; then
  ROOT="$(cd "$1" 2>/dev/null && pwd)" || { echo "ERROR: cannot cd to '$1'"; exit 1; }
elif is_root "$SCRIPT_DIR"; then
  ROOT="$SCRIPT_DIR"
elif TOP="$(git rev-parse --show-toplevel 2>/dev/null)" && is_root "$TOP"; then
  ROOT="$TOP"
fi
if [ -z "$ROOT" ] || ! is_root "$ROOT"; then
  echo "ERROR: could not find the SiteLink root (needs backend/app and frontend/src)."
  echo "Usage: bash update_pagination_2.sh /path/to/SiteLink"
  exit 1
fi
command -v python3 >/dev/null || { echo "ERROR: python3 required"; exit 1; }

IS_GIT=0
git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 && IS_GIT=1
echo "==> Project root : $ROOT"
echo "==> Git repo     : $([ $IS_GIT -eq 1 ] && git -C "$ROOT" rev-parse --show-toplevel || echo 'NO')"

STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$HOME/.sitelink_patch_backups/pagination2_$STAMP"

# ── 1) Shared hook: create only if missing (never overwrite) ─────────────────
HOOK="$ROOT/frontend/src/hooks/useTablePagination.tsx"
mkdir -p "$ROOT/frontend/src/hooks"
if [ -f "$HOOK" ]; then
  echo "    hook already exists: frontend/src/hooks/useTablePagination.tsx (kept as is)"
else
  cat > "$HOOK" <<'TSEOF'
/**
 * useTablePagination.tsx
 * Controlled pagination for Ant Design <Table> (client-side data).
 * Custom page-size selector: 10 / 20 / 50 / 100 / Tất cả.
 */
import React, { useState } from 'react'
import { Select, Space } from 'antd'
import type { TablePaginationConfig } from 'antd/es/table'

export const PAGE_SIZE_ALL = 0
const PAGE_SIZES = [10, 20, 50, 100]

export function useTablePagination(
  total: number,
  unit = 'bản ghi',
  defaultPageSize = 50,
) {
  const [pageSize, setPageSize] = useState<number>(defaultPageSize)
  const [current,  setCurrent]  = useState<number>(1)

  const isAll         = pageSize === PAGE_SIZE_ALL
  const effectiveSize = isAll ? Math.max(total, 1) : pageSize
  const maxPage       = Math.max(1, Math.ceil(total / effectiveSize))
  const safeCurrent   = Math.min(current, maxPage)

  const handleSizeChange = (size: number) => {
    setPageSize(size)
    setCurrent(1)
  }

  const pagination: TablePaginationConfig = {
    current: safeCurrent,
    pageSize: effectiveSize,
    showSizeChanger: false,
    onChange: (page) => setCurrent(page),
    showTotal: (t) => (
      <Space size={12}>
        <span>{t} {unit}</span>
        <Select
          size="small"
          value={pageSize}
          onChange={handleSizeChange}
          style={{ width: 130 }}
          options={[
            ...PAGE_SIZES.map((n) => ({ value: n, label: `${n} / trang` })),
            { value: PAGE_SIZE_ALL, label: 'Tất cả' },
          ]}
        />
      </Space>
    ),
  }

  return { pagination, pageSize, isAll }
}
TSEOF
  echo "    wrote frontend/src/hooks/useTablePagination.tsx"
fi

# ── 2) Patch the four pages ──────────────────────────────────────────────────
python3 - "$ROOT" "$BACKUP_DIR" <<'PYEOF'
import re, sys, shutil
from pathlib import Path

root = Path(sys.argv[1])
bak  = Path(sys.argv[2])
total_fail = 0


class Patch:
    def __init__(self, rel):
        self.rel, self.fail = rel, 0
        p = root / rel
        print(f"--- {rel}")
        if not p.is_file():
            print("  FAIL file not found")
            self.text = self.orig = None
            return
        self.text = self.orig = p.read_text(encoding="utf-8")

    @property
    def ok(self):
        return self.text is not None

    def sub(self, label, pattern, make, flags=0, skip=None, count=1):
        """skip = (substring, n): skip when substring already occurs >= n times."""
        if skip and self.text.count(skip[0]) >= skip[1]:
            print(f"  skip {label} (already applied)")
            return
        ms = list(re.finditer(pattern, self.text, flags))
        if len(ms) != count:
            self.fail += 1
            print(f"  FAIL {label}: expected {count} match(es), found {len(ms)}")
            return
        for m in reversed(ms):          # right-to-left keeps offsets valid
            self.text = self.text[:m.start()] + make(m) + self.text[m.end():]
        print(f"  ok   {label}" + (f" (x{count})" if count > 1 else ""))

    def save(self):
        global total_fail
        total_fail += self.fail
        if self.fail:
            print("  => NOT saved (a patch failed; file left untouched)")
            return
        if self.text != self.orig:
            dst = bak / self.rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(root / self.rel, dst)
            (root / self.rel).write_text(self.text, encoding="utf-8")
            print("  => SAVED (backup made)")
        else:
            print("  => no change")


# hooks: list of (anchor_regex, 'after'|'before', hook_call_args)
SPECS = [
    dict(
        rel="frontend/src/pages/antenna/AntennaPage.tsx",
        hooks=[(r"^([ \t]*)const \[form\] = Form\.useForm\(\)[ \t]*$",
                "after", "data.length, 'antennas'")],
        pag=1,
    ),
    dict(
        rel="frontend/src/pages/revision/RevisionPage.tsx",
        hooks=[
            (r"^([ \t]*)const \[data,\s*setData\]\s*=\s*useState<SiteRevision\[\]>\(\[\]\)[ \t]*$",
             "after", "data.length, 'phiên bản'"),
            (r"^([ \t]*)const \[data,\s*setData\]\s*=\s*useState<CellRevisionBase\[\]>\(\[\]\)[ \t]*$",
             "after", "data.length, 'phiên bản'"),
        ],
        pag=2,   # Site tab + Cell tab
    ),
    dict(
        rel="frontend/src/pages/admin/AuditPage.tsx",
        hooks=[(r"^([ \t]*)const load = \(\) => \{",
                "before", "logs.length, 'records'")],
        pag=1,
    ),
    dict(
        rel="frontend/src/pages/admin/UsersPage.tsx",
        hooks=[(r"^([ \t]*)const load = \(\) => \{",
                "before", "users.length, 'users', 20")],
        pag=1,
    ),
]

# pageSize: N  [, ... showSizeChanger: true [,] ]   (also plain `pageSize: 20`)
PAG_RE = r"pagination=\{\{\s*pageSize:\s*\d+\s*(?:,.*?showSizeChanger:\s*true\s*,?\s*)?\}\}"

for spec in SPECS:
    p = Patch(spec["rel"])
    if not p.ok:
        total_fail += 1
        continue

    p.sub("import useTablePagination",
          r"^import React[^\n]*from 'react'[ \t]*$",
          lambda m: m.group(0) + "\nimport { useTablePagination } from '@/hooks/useTablePagination'",
          re.M,
          skip=("from '@/hooks/useTablePagination'", 1))

    for i, (anchor, mode, args) in enumerate(spec["hooks"], start=1):
        def make(m, mode=mode, args=args):
            indent = m.group(1)
            call = f"{indent}const {{ pagination }} = useTablePagination({args})"
            if mode == "after":
                return m.group(0) + "\n" + call
            return call + "\n\n" + m.group(0)
        p.sub(f"hook call #{i}", anchor, make, re.M,
              skip=("useTablePagination(", i))

    p.sub("Table pagination prop", PAG_RE,
          lambda m: "pagination={pagination}", re.S,
          skip=("pagination={pagination}", spec["pag"]),
          count=spec["pag"])

    p.save()

print()
print(f"Summary: {total_fail} failed edit(s)." if total_fail else "Summary: all edits OK.")
sys.exit(1 if total_fail else 0)
PYEOF
PY_RC=$?

# ── 3) Verification ──────────────────────────────────────────────────────────
echo "==> Verification"
for f in frontend/src/pages/antenna/AntennaPage.tsx frontend/src/pages/revision/RevisionPage.tsx \
         frontend/src/pages/admin/AuditPage.tsx frontend/src/pages/admin/UsersPage.tsx; do
  n_call=$(grep -c "useTablePagination(" "$ROOT/$f")
  n_prop=$(grep -c "pagination={pagination}" "$ROOT/$f")
  n_old=$(grep -c "pageSize:" "$ROOT/$f")
  printf "    %-48s hook-calls=%s  pagination-props=%s  leftover 'pageSize:'=%s\n" \
         "$f" "$n_call" "$n_prop" "$n_old"
done
echo "    (expected: Revision = 2 / 2 / 0, the other three = 1 / 1 / 0)"

echo "==> Other files that still define their own pagination (not modified):"
grep -rlE --include=*.tsx "pageSize|showSizeChanger" "$ROOT/frontend/src" 2>/dev/null \
  | grep -v "hooks/useTablePagination" \
  | while read -r f; do
      grep -q "useTablePagination" "$f" || echo "    ${f#$ROOT/}"
    done
echo "    (send me those files if you want them fixed too)"

if [ "${CHECK_TS:-0}" = "1" ] && [ -d "$ROOT/frontend/node_modules" ]; then
  echo "==> TypeScript check"
  (cd "$ROOT/frontend" && npx --no-install tsc --noEmit) || echo "    tsc reported issues (see above)"
fi

echo "==> git status of $ROOT"
if [ $IS_GIT -eq 1 ]; then
  git -C "$ROOT" status --short
  git -C "$ROOT" diff --stat
fi
echo "    backups (if any): $BACKUP_DIR"

if [ "$PY_RC" -ne 0 ]; then
  echo; echo "!! Some edits FAILED (see FAIL lines). Send me those lines."
  exit 1
fi

cat <<EOF

==> Done. Rebuild the frontend and hard-refresh (Ctrl+F5):
      docker compose up -d --build
    Optional type check first:
      CHECK_TS=1 bash update_pagination_2.sh
EOF