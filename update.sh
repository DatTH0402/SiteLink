#!/usr/bin/env bash
# =============================================================================
# make_dia_chi_optional.sh
# Make Site.dia_chi (Địa chỉ) an OPTIONAL field across SiteLink.
#
# Usage:
#   bash make_dia_chi_optional.sh [PROJECT_ROOT]
#   APPLY_DOCKER=1 bash make_dia_chi_optional.sh [PROJECT_ROOT]
#
# Env (optional):
#   APPLY_DOCKER=1       also: DROP NOT NULL in Postgres, regenerate Excel
#                        templates inside the backend container, restart it
#   PG_CONTAINER=name    postgres container (auto-detected if omitted)
#   BACKEND_CONTAINER=n  backend container  (auto-detected if omitted)
# =============================================================================
set -euo pipefail

PROJECT_ROOT="${1:-/home/mlmt/work/src/SiteLink}"
APPLY_DOCKER="${APPLY_DOCKER:-0}"

POSTGRES_USER="${POSTGRES_USER:-sitelink}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-sitelink_pass}"
POSTGRES_DB="${POSTGRES_DB:-sitelink_db}"

if [ ! -d "$PROJECT_ROOT/backend" ] || [ ! -d "$PROJECT_ROOT/frontend" ]; then
  echo "ERROR: '$PROJECT_ROOT' does not look like the SiteLink root (backend/ + frontend/ expected)." >&2
  exit 1
fi
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required." >&2; exit 1; }

echo "==> Project root: $PROJECT_ROOT"
echo "==> Patching source files ..."

python3 - "$PROJECT_ROOT" <<'PYEOF'
import os
import re
import shutil
import sys

root = sys.argv[1]
pending = []   # (path, original_text, new_text)


class PatchError(Exception):
    pass


def patch(relpath, steps):
    """steps: list of (name, regex, replacement, is_already_applied(text)->bool)"""
    path = os.path.join(root, relpath)
    if not os.path.isfile(path):
        raise PatchError(f"File not found: {path}")
    with open(path, encoding="utf-8", newline="") as f:
        original = f.read()
    text = original
    for name, pattern, repl, done in steps:
        new_text, n = re.subn(pattern, repl, text, count=1, flags=re.M)
        if n == 1:
            text = new_text
            print(f"   [patched] {relpath}: {name}")
        elif done(text):
            print(f"   [skip]    {relpath}: {name} (already applied)")
        else:
            raise PatchError(
                f"{relpath}: cannot apply '{name}' - the code differs from what was expected."
            )
    if text != original:
        pending.append((path, original, text))


try:
    # ------------------------------------------------------------------ #
    # 1. Excel template generator
    # ------------------------------------------------------------------ #
    patch("backend/create_excel_templates.py", [
        (
            "remove 'Dia chi' from SITE_REQUIRED",
            r'(\n    "Long",\n)    "Dia chi",\n(    "Do cao dinh cot anten",\n\})',
            r'\1\2',
            lambda t: not re.search(r'SITE_REQUIRED\s*=\s*\{[^}]*"Dia chi"', t),
        ),
        (
            "Site column 'Dia chi' -> optional",
            r'(\("Dia chi",\s+"Địa chỉ chi tiết của trạm )[^"]*(",\s+30,\s+)True\)',
            r'\1– không bắt buộc\2False)',
            lambda t: re.search(
                r'\("Dia chi",\s+"[^"]*không bắt buộc",\s+30,\s+False\)', t) is not None,
        ),
    ])

    # ------------------------------------------------------------------ #
    # 2. Pydantic schema (SiteCreate validator)
    # ------------------------------------------------------------------ #
    patch("backend/app/schemas/site.py", [
        (
            "remove dia_chi required check in SiteCreate",
            r'\n        if not self\.dia_chi or not str\(self\.dia_chi\)\.strip\(\):\n'
            r'            errors\.append\([^\n]*\)\n',
            "\n",
            lambda t: "self.dia_chi" not in t,
        ),
    ])

    # ------------------------------------------------------------------ #
    # 3. Excel import parser
    # ------------------------------------------------------------------ #
    patch("backend/app/services/import_excel.py", [
        (
            "remove dia_chi from SITE_REQUIRED_FIELDS",
            r'^    "dia_chi":\s+"Địa chỉ",\n',
            "",
            lambda t: re.search(r'^    "dia_chi":\s+"Địa chỉ",\n', t, re.M) is None,
        ),
        (
            "remove 'Địa chỉ is empty' row error in parse_site_excel",
            r'        # [^\n]*Địa chỉ \(required\)[^\n]*\n'
            r'(        dia_chi_val = _v_aware\([^\n]*\)\n)'
            r'        if dia_chi_val is None or dia_chi_val is _CLEAR:\n'
            r'            row_errors\.append\(\n'
            r'[^\n]*\n'
            r'            \)\n',
            "        # -- Địa chỉ (optional - không bắt buộc) --\n\\1",
            lambda t: re.search(r"Trường bắt buộc 'Địa chỉ' bị để trống", t) is None,
        ),
    ])

    # ------------------------------------------------------------------ #
    # 4. Frontend: site form
    # ------------------------------------------------------------------ #
    patch("frontend/src/pages/sites/SiteFormPage.tsx", [
        (
            "dia_chi: remove '*' and required rule",
            r'(name="dia_chi"\s+)label="Địa chỉ \*"\s+'
            r"rules=\{\[\{ required: true, message: 'Vui lòng nhập địa chỉ' \}\]\}",
            r'\1label="Địa chỉ"',
            lambda t: re.search(r'name="dia_chi"\s+label="Địa chỉ \*"', t) is None,
        ),
    ])

    # ------------------------------------------------------------------ #
    # 5. Frontend: TypeScript type
    # ------------------------------------------------------------------ #
    patch("frontend/src/types/index.ts", [
        (
            "Site.dia_chi -> optional",
            r'^  dia_chi: string$',
            "  dia_chi?: string",
            lambda t: re.search(r'^  dia_chi\?: string', t, re.M) is not None,
        ),
    ])

except PatchError as e:
    print(f"\nERROR: {e}\nNo file was modified.", file=sys.stderr)
    sys.exit(2)

# All patches matched -> write everything
for path, original, new in pending:
    bak = path + ".bak_dia_chi"
    if not os.path.exists(bak):
        shutil.copy2(path, bak)
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(new)

print(f"\n   {len(pending)} file(s) modified (backups: *.bak_dia_chi).")
PYEOF

# ---------------------------------------------------------------------------
# Syntax check of patched Python files (no .pyc written)
# ---------------------------------------------------------------------------
echo "==> Syntax-checking Python files ..."
for f in \
  "backend/create_excel_templates.py" \
  "backend/app/schemas/site.py" \
  "backend/app/services/import_excel.py"
do
  python3 -c "import ast,sys; ast.parse(open(sys.argv[1], encoding='utf-8').read())" \
    "$PROJECT_ROOT/$f" && echo "   OK  $f"
done

# ---------------------------------------------------------------------------
# Review: any other place that still marks dia_chi / Địa chỉ as required
# ---------------------------------------------------------------------------
echo "==> Scanning for leftover 'required' markers on dia_chi / Địa chỉ ..."
if grep -rnE --include='*.py' --include='*.ts' --include='*.tsx' \
     --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist \
     -i "(dia_chi|dia chi|địa chỉ).*(required|bắt buộc|bat buoc|\*)|(required|bắt buộc).*(dia_chi|địa chỉ)" \
     "$PROJECT_ROOT/backend" "$PROJECT_ROOT/frontend/src" 2>/dev/null \
   | grep -v "không bắt buộc" | grep -v "\.bak_dia_chi"; then
  echo "   ^^^ Please review the lines above (files not included in your description may need a manual tweak)."
else
  echo "   Nothing found."
fi

# ---------------------------------------------------------------------------
# Docker steps (DB column, template regeneration, backend restart)
# ---------------------------------------------------------------------------
PG_SQL="ALTER TABLE sites ALTER COLUMN dia_chi DROP NOT NULL;"

if [ "$APPLY_DOCKER" = "1" ]; then
  echo "==> Docker steps ..."
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    echo "   docker is not available/accessible - skipping."
  else
    # --- detect postgres container
    PG_CONTAINER="${PG_CONTAINER:-}"
    if [ -z "$PG_CONTAINER" ]; then
      mapfile -t _pg < <(docker ps --format '{{.Names}} {{.Image}}' | awk 'tolower($0) ~ /postgres/ {print $1}')
      if [ "${#_pg[@]}" -eq 1 ]; then PG_CONTAINER="${_pg[0]}"; fi
    fi
    # --- detect backend container
    BACKEND_CONTAINER="${BACKEND_CONTAINER:-}"
    if [ -z "$BACKEND_CONTAINER" ]; then
      for c in $(docker ps --format '{{.Names}}'); do
        if docker exec "$c" test -f /app/app/utils/template_regen.py >/dev/null 2>&1; then
          BACKEND_CONTAINER="$c"; break
        fi
      done
    fi

    # 1) DB: make sure the column is nullable (idempotent, harmless if already nullable)
    if [ -n "$PG_CONTAINER" ]; then
      echo "   [db] $PG_CONTAINER: $PG_SQL"
      docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$PG_CONTAINER" \
        psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "$PG_SQL" \
        || echo "   [db] WARNING: could not alter column (run the SQL manually)."
    else
      echo "   [db] postgres container not found. Set PG_CONTAINER=<name> or run manually:"
      echo "        $PG_SQL"
    fi

    # 2) Regenerate Excel templates + 3) restart backend so new Python code is loaded
    if [ -n "$BACKEND_CONTAINER" ]; then
      echo "   [templates] regenerating inside $BACKEND_CONTAINER ..."
      docker exec "$BACKEND_CONTAINER" python -c \
        "from app.utils.template_regen import _do_regen; _do_regen()" \
        || echo "   [templates] WARNING: regeneration failed (check logs)."
      echo "   [backend] restarting $BACKEND_CONTAINER ..."
      docker restart "$BACKEND_CONTAINER" >/dev/null && echo "   [backend] restarted."
    else
      echo "   [backend] container not found. Set BACKEND_CONTAINER=<name>."
    fi
  fi
else
  cat <<EOF

==> Code patched. Remaining (manual) steps:

  1) DB (only needed if the column was ever created NOT NULL; harmless otherwise):
       docker exec -e PGPASSWORD=$POSTGRES_PASSWORD <postgres_container> \\
         psql -U $POSTGRES_USER -d $POSTGRES_DB -c "$PG_SQL"

  2) Reload the backend so the new Python code is used, and regenerate the
     Excel templates (template_regen runs automatically on startup/data change;
     or force it):
       docker exec <backend_container> python -c \\
         "from app.utils.template_regen import _do_regen; _do_regen()"
       docker restart <backend_container>
     (If the backend code is baked into the image rather than bind-mounted:
       docker compose up -d --build backend)

  3) Frontend: restart 'npm run dev', or rebuild with 'npm run build'.

  Or let this script do 1) and 2) for you:
       APPLY_DOCKER=1 bash $0 "$PROJECT_ROOT"

  Rollback: for f in \$(find "$PROJECT_ROOT" -name '*.bak_dia_chi' -not -path '*/node_modules/*'); do mv "\$f" "\${f%.bak_dia_chi}"; done
EOF
fi

echo "==> Done."