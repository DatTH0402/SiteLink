#!/usr/bin/env bash
# Usage:
#   ./change_port.sh              # apply: 8101 -> 8101, then rebuild/restart
#   DRY_RUN=1 ./change_port.sh    # only show what would change
#   NO_RESTART=1 ./change_port.sh # change files, don't touch docker
#   OLD_PORT=8101 NEW_PORT=8101 ./change_port.sh
set -euo pipefail

OLD_PORT="${OLD_PORT:-8101}"
NEW_PORT="${NEW_PORT:-8101}"
DRY_RUN="${DRY_RUN:-0}"
NO_RESTART="${NO_RESTART:-0}"

cd "$(dirname "$(readlink -f "$0")")"
[ -f docker-compose.yml ] || { echo "ERROR: run this from the SiteLink project root"; exit 1; }

# --- sanity: new port must be free (skip check if our own stack is using it) ---
if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${NEW_PORT}\$"; then
  if ! docker ps --format '{{.Ports}}' 2>/dev/null | grep -q ":${NEW_PORT}->"; then
    echo "ERROR: port ${NEW_PORT} is already in use by another process"; exit 1
  fi
fi

# --- find every text file mentioning the old port (exact token, not e.g. 18081 / 80811) ---
mapfile -t FILES < <(
  grep -rIlE "(^|[^0-9A-Za-z])${OLD_PORT}([^0-9A-Za-z]|\$)" . \
    --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=dist \
    --exclude-dir=build --exclude-dir=__pycache__ --exclude-dir=uploads \
    --exclude-dir=backups --exclude-dir=templates \
    --exclude='*.bak*' --exclude='*.log' --exclude='change_port.sh' || true
)

if [ ${#FILES[@]} -eq 0 ]; then
  echo "No files reference port ${OLD_PORT}. Nothing to do."; exit 0
fi

echo "=== Occurrences of ${OLD_PORT} ==="
for f in "${FILES[@]}"; do
  grep -nE "(^|[^0-9A-Za-z])${OLD_PORT}([^0-9A-Za-z]|\$)" "$f" | sed "s|^|${f}:|"
done
echo

if [ "$DRY_RUN" = "1" ]; then
  echo "DRY_RUN=1 -> no changes made."; exit 0
fi

# --- backup + replace ---
BK="backups/port_change_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BK"
for f in "${FILES[@]}"; do
  mkdir -p "$BK/$(dirname "$f")"
  cp -p "$f" "$BK/$f"
  perl -pi -e "s/(?<![0-9A-Za-z])${OLD_PORT}(?![0-9A-Za-z])/${NEW_PORT}/g" "$f"
done
echo "Backup of originals: $BK"
echo "Updated files:"; printf '  %s\n' "${FILES[@]}"
echo

# --- verify compose ---
echo "=== docker-compose port mapping now ==="
grep -nE "\"${NEW_PORT}:80\"" docker-compose.yml || echo "WARNING: ${NEW_PORT}:80 not found in docker-compose.yml"
echo

# --- rebuild / restart ---
if [ "$NO_RESTART" = "1" ]; then
  echo "NO_RESTART=1 -> skipping docker. Run:  docker compose up -d --build"
else
  # backend: re-reads .env (SSO_REDIRECT_URI) | frontend: rebuilt in case URLs are baked in
  # nginx: recreated so the new host port mapping takes effect
  docker compose up -d --build
  echo
  docker compose ps
  echo
  sleep 5
  echo "=== health check on new port ==="
  curl -s -o /dev/null -w "http://localhost:${NEW_PORT}/health    -> HTTP %{http_code}\n" "http://localhost:${NEW_PORT}/health" || true
  curl -s -o /dev/null -w "http://localhost:${NEW_PORT}/sitelink/ -> HTTP %{http_code}\n" "http://localhost:${NEW_PORT}/sitelink/" || true
fi

cat <<EOF

=================== MANUAL STEPS STILL REQUIRED ===================
1) DOMAIN NGINX (the server serving https://mlmt.mobifone.vn):
     change   proxy_pass http://10.24.15.169:${OLD_PORT};
     to       proxy_pass http://10.24.15.169:${NEW_PORT};
   then:  nginx -t && systemctl reload nginx

2) KEYCLOAK client CLIENT-MLMT -> Valid Redirect URIs, add:
     http://localhost:${NEW_PORT}/sitelink/sso/callback
     http://10.24.15.169:${NEW_PORT}/sitelink/sso/callback
     (https://mlmt.mobifone.vn/sitelink/sso/callback is unchanged)
   Remove the old ${OLD_PORT} entries afterwards.

3) FIREWALL (if enabled), e.g.:
     sudo ufw allow ${NEW_PORT}/tcp && sudo ufw delete allow ${OLD_PORT}/tcp
   or: sudo firewall-cmd --permanent --add-port=${NEW_PORT}/tcp && sudo firewall-cmd --reload

4) Update anything outside this repo that calls :${OLD_PORT}
   (monitoring, Windows scheduled tasks, bookmarks, other servers).
   If you set CORS_ORIGINS in .env, make sure it uses :${NEW_PORT}.
===================================================================
EOF