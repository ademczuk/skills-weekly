@echo off
REM OpenClaw Skills Weekly — Daily Snapshot + X Signal Capture
REM Runs at 9:00 AM via Windows Task Scheduler
REM 1. Records ClawHub metrics to SQLite (container-side, full catalog)
REM 2. Captures X/Twitter signals and appends to weekly_signals.json (host-side)

REM Set PROJECT to parent of cron\ directory (repo root)
set PROJECT=%~dp0..
set LOGDIR=%PROJECT%\cron\logs
if not exist "%LOGDIR%" mkdir "%LOGDIR%"

set LOGFILE=%LOGDIR%\snapshot_%date:~6,4%%date:~3,2%%date:~0,2%.log

echo ============================================ >> "%LOGFILE%" 2>&1
echo [%date% %time%] Starting daily pipeline... >> "%LOGFILE%" 2>&1
echo ============================================ >> "%LOGFILE%" 2>&1

REM --- Phase 1: ClawHub snapshot (container-side) ---
echo. >> "%LOGFILE%" 2>&1
echo [PHASE 1] ClawHub API Snapshot (container) >> "%LOGFILE%" 2>&1

docker ps --filter name=openclaw-gateway-secure --format "{{.Status}}" | findstr /C:"(healthy)" > nul 2>&1
if errorlevel 1 (
    echo [%date% %time%] Container not healthy. Attempting start... >> "%LOGFILE%" 2>&1
    docker start openclaw-gateway-secure >> "%LOGFILE%" 2>&1
    timeout /t 30 /nobreak > nul
)

docker exec -u node openclaw-gateway-secure python3 /home/node/.openclaw/workspace/skills/last30days-weekly/scripts/clawhub_snapshot.py snapshot >> "%LOGFILE%" 2>&1
echo [%date% %time%] ClawHub snapshot exit code: %errorlevel% >> "%LOGFILE%" 2>&1

REM --- Phase 2: X/Twitter signal capture (host-side) ---
echo. >> "%LOGFILE%" 2>&1
echo [PHASE 2] X/Twitter Signal Capture (host) >> "%LOGFILE%" 2>&1

cd /d "%PROJECT%"
python x_capture.py --append >> "%LOGFILE%" 2>&1
echo [%date% %time%] X capture exit code: %errorlevel% >> "%LOGFILE%" 2>&1

REM --- Phase 3: Sync signals to container ---
echo. >> "%LOGFILE%" 2>&1
echo [PHASE 3] Syncing signals to container >> "%LOGFILE%" 2>&1

if exist "%PROJECT%\data\weekly_signals.json" (
    docker cp "%PROJECT%\data\weekly_signals.json" openclaw-gateway-secure:/home/node/.openclaw/workspace/data/skills-weekly/weekly_signals.json >> "%LOGFILE%" 2>&1
    docker exec -u root openclaw-gateway-secure chown 1000:1000 /home/node/.openclaw/workspace/data/skills-weekly/weekly_signals.json >> "%LOGFILE%" 2>&1
    echo [%date% %time%] Signals synced to container >> "%LOGFILE%" 2>&1
) else (
    echo [%date% %time%] No signals file to sync >> "%LOGFILE%" 2>&1
)

echo. >> "%LOGFILE%" 2>&1
echo [%date% %time%] Daily pipeline complete >> "%LOGFILE%" 2>&1
