@echo off
REM OpenClaw Skills Weekly — Full Weekly Report
REM Runs Mondays at 9:30 AM via Windows Task Scheduler
REM 0. Backup host DB, then copy container DB (has daily snapshot history)
REM 1. Full host-side pipeline: X capture + discover + snapshot + rank + harvest + scripts
REM 2. Container snapshot for its own DB accumulation
REM 3. Sync signals to container so TUI reports include community buzz
REM 4. Render YouTube video via Remotion (screenshots + TTS + encode)

REM Set PROJECT to parent of cron\ directory (repo root)
set PROJECT=%~dp0..
set LOGDIR=%PROJECT%\cron\logs
if not exist "%LOGDIR%" mkdir "%LOGDIR%"

set LOGFILE=%LOGDIR%\report_%date:~6,4%%date:~3,2%%date:~0,2%.log

echo ============================================ >> "%LOGFILE%" 2>&1
echo [%date% %time%] Starting weekly report pipeline... >> "%LOGFILE%" 2>&1
echo ============================================ >> "%LOGFILE%" 2>&1

REM --- Phase 0: Backup host DB, then bridge container DB ---
echo. >> "%LOGFILE%" 2>&1
echo [PHASE 0] Backing up host DB, then copying container DB >> "%LOGFILE%" 2>&1

REM Backup existing host DB before overwriting
if exist "%PROJECT%\data\metrics.db" (
    copy /Y "%PROJECT%\data\metrics.db" "%PROJECT%\data\metrics.db.bak" >> "%LOGFILE%" 2>&1
    echo [%date% %time%] Host DB backed up to metrics.db.bak >> "%LOGFILE%" 2>&1
)

docker ps --filter name=openclaw-gateway-secure --format "{{.Status}}" | findstr /C:"(healthy)" > nul 2>&1
if errorlevel 1 (
    echo [%date% %time%] Container not healthy. Attempting start... >> "%LOGFILE%" 2>&1
    docker start openclaw-gateway-secure >> "%LOGFILE%" 2>&1
    timeout /t 30 /nobreak > nul
)

docker cp openclaw-gateway-secure:/home/node/.openclaw/workspace/data/skills-weekly/metrics.db "%PROJECT%\data\metrics.db" >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo [%date% %time%] WARNING: docker cp failed, restoring backup >> "%LOGFILE%" 2>&1
    if exist "%PROJECT%\data\metrics.db.bak" (
        copy /Y "%PROJECT%\data\metrics.db.bak" "%PROJECT%\data\metrics.db" >> "%LOGFILE%" 2>&1
    )
) else (
    echo [%date% %time%] Container DB copied to host >> "%LOGFILE%" 2>&1
)

REM --- Phase 1: Full host-side pipeline (run_weekly.py) ---
REM This handles: X capture -> ClawHub discovery -> storage -> ranking -> harvesting -> scripts -> markdown
echo. >> "%LOGFILE%" 2>&1
echo [PHASE 1] Full Pipeline via run_weekly.py (host) >> "%LOGFILE%" 2>&1

cd /d "%PROJECT%"
python run_weekly.py --top 10 --episode 0 >> "%LOGFILE%" 2>&1
echo [%date% %time%] Host pipeline exit code: %errorlevel% >> "%LOGFILE%" 2>&1

REM --- Phase 2: Container snapshot (keeps container DB up-to-date) ---
echo. >> "%LOGFILE%" 2>&1
echo [PHASE 2] Container ClawHub Snapshot >> "%LOGFILE%" 2>&1

docker ps --filter name=openclaw-gateway-secure --format "{{.Status}}" | findstr /C:"(healthy)" > nul 2>&1
if errorlevel 1 (
    echo [%date% %time%] Container not healthy. Attempting start... >> "%LOGFILE%" 2>&1
    docker start openclaw-gateway-secure >> "%LOGFILE%" 2>&1
    timeout /t 30 /nobreak > nul
)

docker exec -u node openclaw-gateway-secure python3 /home/node/.openclaw/workspace/skills/last30days-weekly/scripts/clawhub_snapshot.py snapshot >> "%LOGFILE%" 2>&1
echo [%date% %time%] Container snapshot exit code: %errorlevel% >> "%LOGFILE%" 2>&1

REM --- Phase 3: Sync signals to container ---
echo. >> "%LOGFILE%" 2>&1
echo [PHASE 3] Syncing signals to container >> "%LOGFILE%" 2>&1

if exist "%PROJECT%\data\weekly_signals.json" (
    docker cp "%PROJECT%\data\weekly_signals.json" openclaw-gateway-secure:/home/node/.openclaw/workspace/data/skills-weekly/weekly_signals.json >> "%LOGFILE%" 2>&1
    docker exec -u root openclaw-gateway-secure chown 1000:1000 /home/node/.openclaw/workspace/data/skills-weekly/weekly_signals.json >> "%LOGFILE%" 2>&1
    echo [%date% %time%] Signals synced to container >> "%LOGFILE%" 2>&1
)

REM --- Phase 4: Render YouTube video via Remotion ---
echo. >> "%LOGFILE%" 2>&1
echo [PHASE 4] Rendering YouTube video >> "%LOGFILE%" 2>&1

set REMOTION_DIR=%PROJECT%\..\CursorfulClone\cursorful-ext\remotion

REM Find the latest scraper JSON
set LATEST_JSON=
for /f "delims=" %%F in ('dir /b /o-d "%PROJECT%\openclaw_weekly_*.json" 2^>nul') do (
    if not defined LATEST_JSON set LATEST_JSON=%PROJECT%\%%F
)

REM Read episode number from counter
set EPISODE_NUM=1
for /f "tokens=2 delims=:," %%a in ('type "%PROJECT%\data\episode_counter.json" 2^>nul ^| findstr "episode"') do (
    for /f "tokens=* delims= " %%b in ("%%a") do set EPISODE_NUM=%%b
)

if defined LATEST_JSON (
    if exist "%REMOTION_DIR%\render-episode.ts" (
        echo [%date% %time%] Rendering episode %EPISODE_NUM% from %LATEST_JSON% >> "%LOGFILE%" 2>&1
        cd /d "%REMOTION_DIR%"
        call npx tsx render-episode.ts --scraper-json "%LATEST_JSON%" --episode %EPISODE_NUM% --fps 30 --crf 18 >> "%LOGFILE%" 2>&1
        echo [%date% %time%] Video render exit code: %errorlevel% >> "%LOGFILE%" 2>&1
        cd /d "%PROJECT%"
    ) else (
        echo [%date% %time%] SKIP: Remotion not found at %REMOTION_DIR% >> "%LOGFILE%" 2>&1
    )
) else (
    echo [%date% %time%] SKIP: No scraper JSON found >> "%LOGFILE%" 2>&1
)

echo. >> "%LOGFILE%" 2>&1
echo [%date% %time%] Weekly report pipeline complete >> "%LOGFILE%" 2>&1
echo Check for output at: %PROJECT%\openclaw_weekly_*.md >> "%LOGFILE%" 2>&1
