@echo off
:: Force UTF-8 encoding for Windows CMD and Python stdout/stderr
chcp 65001 >nul
set PYTHONIOENCODING=utf-8

:: 1. Switch to the D: drive and target folder
cd /d "D:\workspace\source\SiteLink"

:: 2. Create the logs folder if it doesn't exist
if not exist "D:\workspace\source\SiteLink\logs" (
    mkdir "D:\workspace\source\SiteLink\logs"
)

:: 3. Get today's date in YYYY-MM-DD format
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set "TODAY=%%i"
set "LOGFILE=D:\workspace\source\SiteLink\logs\reconcile_%TODAY%.log"

echo ================================================== >> "%LOGFILE%"
echo [%DATE% %TIME%] Starting script... >> "%LOGFILE%"

:: 4. Run Python
"C:\Users\Admin\AppData\Local\Programs\Python\Python313\python.exe" -u update_cells_with_revision.py --reconcile >> "%LOGFILE%" 2>&1
set "EXIT_CODE=%ERRORLEVEL%"

echo [%DATE% %TIME%] Finished with exit code %EXIT_CODE% >> "%LOGFILE%"

:: 5. Pass the Python exit code back to Windows Task Scheduler
exit /b %EXIT_CODE%