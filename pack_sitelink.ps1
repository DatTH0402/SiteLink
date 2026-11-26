<#
.SYNOPSIS
  Builds an offline bundle of SiteLink (images + DB + uploads + config) for Ubuntu.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\pack_sitelink.ps1
  .\pack_sitelink.ps1 -NoData          # code-only update (no DB / uploads)
  .\pack_sitelink.ps1 -Quiesce         # stop backend briefly for a fully consistent snapshot
#>
[CmdletBinding()]
param(
  [string]$ProjectDir,
  [string]$OutDir,
  [switch]$NoData,
  [switch]$Quiesce
)
$ErrorActionPreference = 'Stop'

# Resolve the script folder robustly (works on any PowerShell version / host)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot }
             elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path }
             else { (Get-Location).Path }
if (-not $ProjectDir) { $ProjectDir = $ScriptDir }
if (-not $OutDir)     { $OutDir     = Join-Path $ScriptDir 'dist-offline' }

function Say($m) { Write-Host "[pack] $m" -ForegroundColor Cyan }
function Native {
  param([string]$Exe, [string[]]$Arguments)
  & $Exe @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): $Exe $($Arguments -join ' ')" }
}
function Read-DotEnv($path) {
  $h = @{}
  foreach ($line in Get-Content $path) {
    if ($line -match '^\s*#' -or $line -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') { continue }
    $h[$Matches[1]] = $Matches[2].Trim('"', "'")
  }
  return $h
}
function Write-Lf($path, $text) {
  New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
  [IO.File]::WriteAllText($path, ($text -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding $false))
}
function Copy-Lf($src, $dst) { Write-Lf $dst ([IO.File]::ReadAllText($src)) }
function Pack-Dir($dir, $archive) {
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  Native tar @('-czf', $archive, '-C', $dir, '.')
}

# ---------------------------------------------------------------- checks
$ProjectDir = (Resolve-Path $ProjectDir).Path
Native docker @('version', '--format', '{{.Server.Os}}/{{.Server.Arch}}')
if (-not (Get-Command tar -ErrorAction SilentlyContinue)) { throw "tar.exe not found (needs Windows Server 2019+)." }
foreach ($f in 'docker-compose.yml', '.env', 'nginx\nginx.conf') {
  if (-not (Test-Path (Join-Path $ProjectDir $f))) { throw "Missing $f in $ProjectDir" }
}

$ver   = Get-Date -Format 'yyyyMMdd-HHmm'
$name  = "sitelink-bundle-$ver"
$stage = Join-Path $OutDir $name
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
foreach ($d in 'images', 'data', 'nginx', 'ops', 'postgres\init') {
  New-Item -ItemType Directory -Force -Path (Join-Path $stage $d) | Out-Null
}
$envv = Read-DotEnv (Join-Path $ProjectDir '.env')

# ---------------------------------------------------------------- compose override (image tags)
$override = @"
services:
  backend:
    image: sitelink-backend:$ver
  frontend:
    image: sitelink-frontend:$ver
"@
Write-Lf "$stage\docker-compose.images.yml" $override

# ---------------------------------------------------------------- build
Say "Building images (tag $ver) ..."
$dc = @('compose', '--project-directory', $ProjectDir, '-p', 'sitelink',
        '-f', "$ProjectDir\docker-compose.yml", '-f', "$stage\docker-compose.images.yml")
Native docker ($dc + @('build'))

foreach ($b in 'postgres:15-alpine', 'nginx:alpine') {
  Say "Pulling $b"
  try { Native docker @('pull', $b) }
  catch {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    docker image inspect $b 2>&1 | Out-Null
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($rc -ne 0) { throw "Cannot pull $b and it is not available locally." }
    Write-Warning "Pull failed, using local copy of $b"
  }
}

# ---------------------------------------------------------------- data
if (-not $NoData) {
  $pg = docker ps --filter 'name=^sitelink_postgres$' --format '{{.Names}}'
  if (-not $pg) { throw "Container sitelink_postgres is not running - cannot dump DB." }

  $stopped = $false
  try {
    if ($Quiesce) { Say "Stopping backend for consistent snapshot"; Native docker @('stop', 'sitelink_backend'); $stopped = $true }

    Say "Dumping database ..."
    Native docker @('exec', 'sitelink_postgres', 'pg_dump', '-U', $envv.POSTGRES_USER, '-d', $envv.POSTGRES_DB,
                    '-Fc', '--no-owner', '--no-privileges', '-f', '/tmp/sitelink.dump')
    Native docker @('cp', 'sitelink_postgres:/tmp/sitelink.dump', "$stage\data\sitelink.dump")
    docker exec sitelink_postgres rm -f /tmp/sitelink.dump | Out-Null
    if ((Get-Item "$stage\data\sitelink.dump").Length -lt 1024) { throw "DB dump looks empty." }

    Say "Archiving uploads and templates ..."
    Pack-Dir "$ProjectDir\backend\uploads"   "$stage\data\uploads.tar.gz"
    Pack-Dir "$ProjectDir\backend\templates" "$stage\data\templates.tar.gz"
  }
  finally {
    if ($stopped) { docker start sitelink_backend | Out-Null }
  }
}

# ---------------------------------------------------------------- images
Say "Saving images (this can take a while) ..."
Native docker @('save', '-o', "$stage\images\sitelink-images.tar",
                "sitelink-backend:$ver", "sitelink-frontend:$ver", 'postgres:15-alpine', 'nginx:alpine')

# ---------------------------------------------------------------- config
Copy-Lf "$ProjectDir\docker-compose.yml" "$stage\docker-compose.yml"
Copy-Lf "$ProjectDir\.env"               "$stage\.env"
Copy-Lf "$ProjectDir\nginx\nginx.conf"   "$stage\nginx\nginx.conf"
if (Test-Path "$ProjectDir\postgres\init") {
  Get-ChildItem "$ProjectDir\postgres\init" -File | ForEach-Object { Copy-Lf $_.FullName "$stage\postgres\init\$($_.Name)" }
}
if (Test-Path "$ProjectDir\ops") {
  Get-ChildItem "$ProjectDir\ops" -Filter *.sh -File | ForEach-Object { Copy-Lf $_.FullName "$stage\ops\$($_.Name)" }
}

# ---------------------------------------------------------------- Ubuntu installer
$installSh = @'
#!/usr/bin/env bash
# SiteLink offline installer / updater.   Usage: sudo bash install.sh [--dir=/opt/sitelink] [--force-db]
set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR=/opt/sitelink
PROJECT=sitelink
FORCE_DB=0
for a in "$@"; do
  case "$a" in
    --dir=*)    INSTALL_DIR="${a#--dir=}" ;;
    --force-db) FORCE_DB=1 ;;
    -h|--help)  echo "Usage: sudo bash install.sh [--dir=/opt/sitelink] [--force-db]"; exit 0 ;;
    *) echo "Unknown option: $a"; exit 1 ;;
  esac
done
log(){ echo -e "\033[1;36m[install]\033[0m $*"; }
die(){ echo -e "\033[1;31m[error]\033[0m $*" >&2; exit 1; }

command -v docker >/dev/null            || die "Docker is not installed."
docker compose version >/dev/null 2>&1  || die "Docker compose plugin is missing."
docker info >/dev/null 2>&1             || die "Cannot reach the Docker daemon (use sudo?)."

log "Verifying checksums ..."
( cd "$HERE" && sha256sum --quiet -c SHA256SUMS ) || die "Checksum verification failed - bundle corrupted."

log "Loading images ..."
docker load -i "$HERE/images/sitelink-images.tar"

log "Installing files into $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{nginx,postgres/init,ops,backend/uploads,backend/templates,frontend}
cp -f "$HERE/docker-compose.yml" "$HERE/docker-compose.images.yml" "$INSTALL_DIR/"
cp -f "$HERE/nginx/nginx.conf" "$INSTALL_DIR/nginx/"
cp -f "$HERE"/postgres/init/* "$INSTALL_DIR/postgres/init/" 2>/dev/null || true
cp -f "$HERE"/ops/* "$INSTALL_DIR/ops/" 2>/dev/null && chmod +x "$INSTALL_DIR"/ops/*.sh || true
if [ -f "$INSTALL_DIR/.env" ]; then
  cp -f "$HERE/.env" "$INSTALL_DIR/.env.bundle"
  log "Existing .env kept (new one saved as .env.bundle)"
else
  cp "$HERE/.env" "$INSTALL_DIR/.env"; chmod 600 "$INSTALL_DIR/.env"
fi

cd "$INSTALL_DIR"
set -a; . ./.env; set +a
dc(){ docker compose -p "$PROJECT" -f docker-compose.yml -f docker-compose.images.yml "$@"; }

EXISTING=0
docker volume inspect "${PROJECT}_postgres_data" >/dev/null 2>&1 && EXISTING=1
RESTORE=0
if [ -f "$HERE/data/sitelink.dump" ]; then
  if [ "$EXISTING" = 0 ]; then RESTORE=1
  elif [ "$FORCE_DB" = 1 ]; then RESTORE=1; log "WARNING: --force-db will overwrite the existing database"
  else log "Existing database found -> UPDATE mode (DB and uploads untouched; use --force-db to overwrite)"
  fi
fi

if [ "$RESTORE" = 1 ]; then
  dc stop backend frontend nginx >/dev/null 2>&1 || true
  log "Starting PostgreSQL ..."
  dc up -d --no-build postgres
  for i in $(seq 1 60); do
    docker exec sitelink_postgres pg_isready -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1 && break
    sleep 2
  done
  docker exec sitelink_postgres pg_isready -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1 || die "PostgreSQL did not become ready."
  sleep 2

  log "Restoring database ..."
  docker cp "$HERE/data/sitelink.dump" sitelink_postgres:/tmp/sitelink.dump
  docker exec sitelink_postgres pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
      --clean --if-exists --no-owner --no-privileges /tmp/sitelink.dump \
      || log "pg_restore reported warnings (usually harmless) - verifying ..."
  docker exec sitelink_postgres rm -f /tmp/sitelink.dump
  N=$(docker exec sitelink_postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc \
      "select count(*) from information_schema.tables where table_schema='public'")
  log "Tables in public schema after restore: $N"
  [ "${N:-0}" -gt 0 ] || die "Restore produced no tables."

  [ -f "$HERE/data/uploads.tar.gz" ]   && tar -xzf "$HERE/data/uploads.tar.gz"   -C backend/uploads
  [ -f "$HERE/data/templates.tar.gz" ] && tar -xzf "$HERE/data/templates.tar.gz" -C backend/templates
fi

log "Starting all services ..."
dc up -d --no-build

log "Waiting for backend health ..."
for i in $(seq 1 60); do
  s=$(docker inspect -f '{{.State.Health.Status}}' sitelink_backend 2>/dev/null || echo none)
  [ "$s" = healthy ] && break
  sleep 5
done
dc ps
[ "${s:-}" = healthy ] || { dc logs --tail=50 backend; die "Backend is not healthy."; }

systemctl enable docker >/dev/null 2>&1 || true
log "DONE. Open http://<this-server-ip>:8101/sitelink/"
log "Docs: http://<this-server-ip>:8101/docs"
'@
Write-Lf "$stage\install.sh" $installSh

# ---------------------------------------------------------------- checksums + final archive
Say "Computing checksums ..."
$lines = Get-ChildItem $stage -Recurse -File | ForEach-Object {
  $rel = $_.FullName.Substring($stage.Length + 1).Replace('\', '/')
  '{0}  {1}' -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $rel
}
Write-Lf "$stage\SHA256SUMS" (($lines -join "`n") + "`n")

$archive = Join-Path $OutDir "$name.tar.gz"
Say "Creating $archive ..."
Native tar @('-czf', $archive, '-C', $OutDir, $name)
Remove-Item -Recurse -Force $stage

$mb = [math]::Round((Get-Item $archive).Length / 1MB, 1)
Write-Host "`nBundle ready: $archive ($mb MB)" -ForegroundColor Green
Write-Host "On Ubuntu:  tar xzf $name.tar.gz && cd $name && sudo bash install.sh" -ForegroundColor Green