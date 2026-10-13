#!/usr/bin/env bash
# Nightly PostgreSQL backup.  Cron example (every day 02:30):
#   30 2 * * *  /home/mlmt/work/src/SiteLink/ops/backup_db.sh >> /var/log/sitelink_backup.log 2>&1
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p backups
out="backups/sitelink_$(date +%F_%H%M).dump"
docker exec sitelink_postgres sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$out"
find backups -name 'sitelink_*.dump' -mtime +14 -delete
echo "backup written: $out"
