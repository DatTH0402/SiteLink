# D:\workspace\source\SiteLink\ops\backup_db.ps1
# Nightly PostgreSQL backup for Windows Task Scheduler
$ErrorActionPreference = "Stop"

# Navigate to project root (D:\workspace\source\SiteLink)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = (Resolve-Path "$ScriptDir\..").Path
Set-Location $RootDir

# Ensure backups directory exists
$BackupDir = Join-Path $RootDir "backups"
if (-not (Test-Path -Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir | Out-Null
}

# Timestamp matches format: YYYY-MM-DD_HHMM
$Timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
$OutFile = Join-Path $BackupDir "sitelink_$Timestamp.dump"

# Run pg_dump via Docker
# NOTE: cmd.exe /c is intentionally used here to redirect output. 
# Native PowerShell '>' operator treats output as text and corrupts binary (-Fc) dumps.
$DockerCmd = 'docker exec sitelink_postgres sh -c "pg_dump -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\" -Fc" > "' + $OutFile + '"'
cmd.exe /c $DockerCmd

if ($LASTEXITCODE -ne 0) {
    Write-Error "pg_dump failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

# Delete backups older than 14 days
$CutoffDate = (Get-Date).AddDays(-14)
Get-ChildItem -Path $BackupDir -Filter "sitelink_*.dump" | 
    Where-Object { $_.LastWriteTime -lt $CutoffDate } | 
    Remove-Item -Force

Write-Output "backup written: $OutFile"