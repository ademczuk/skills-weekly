@echo off
REM OpenClaw Skills Weekly — Standalone Video Render
REM Renders the latest scraper JSON into a YouTube-ready MP4
REM Can be run manually or registered as a separate scheduled task
REM
REM Usage:
REM   video_render.bat              (auto-detect latest JSON + episode)
REM   video_render.bat --no-tts     (skip TTS, use fixed 8s timing)

set PROJECT=%~dp0..
set REMOTION_DIR=%PROJECT%\..\CursorfulClone\cursorful-ext\remotion
set LOGDIR=%PROJECT%\cron\logs
if not exist "%LOGDIR%" mkdir "%LOGDIR%"

set LOGFILE=%LOGDIR%\render_%date:~6,4%%date:~3,2%%date:~0,2%.log

echo [%date% %time%] Video render start >> "%LOGFILE%" 2>&1

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

if not defined LATEST_JSON (
    echo [%date% %time%] ERROR: No scraper JSON found at %PROJECT% >> "%LOGFILE%" 2>&1
    exit /b 1
)

if not exist "%REMOTION_DIR%\render-episode.ts" (
    echo [%date% %time%] ERROR: Remotion not found at %REMOTION_DIR% >> "%LOGFILE%" 2>&1
    exit /b 1
)

echo [%date% %time%] Rendering episode %EPISODE_NUM% >> "%LOGFILE%" 2>&1
echo   JSON: %LATEST_JSON% >> "%LOGFILE%" 2>&1

cd /d "%REMOTION_DIR%"
call npx tsx render-episode.ts --scraper-json "%LATEST_JSON%" --episode %EPISODE_NUM% --fps 30 --crf 18 %* >> "%LOGFILE%" 2>&1
set RENDER_EXIT=%errorlevel%

echo [%date% %time%] Video render complete (exit %RENDER_EXIT%) >> "%LOGFILE%" 2>&1
