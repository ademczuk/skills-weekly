@echo off
REM OpenClaw Skills Weekly — Hourly Top-500 Heartbeat
REM Runs every hour at :30 via Windows Task Scheduler
REM Captures top 500 skills + OpenClaw GitHub project metadata

set PROJECT=%~dp0..
set LOGDIR=%PROJECT%\cron\logs
if not exist "%LOGDIR%" mkdir "%LOGDIR%"

REM Build log filename with date and hour
for /f "tokens=1-4 delims=:. " %%a in ("%time%") do set HOUR=%%a
set HOUR=%HOUR: =0%
set LOGFILE=%LOGDIR%\heartbeat_%date:~6,4%%date:~3,2%%date:~0,2%_%HOUR%.log

echo [%date% %time%] Hourly heartbeat start >> "%LOGFILE%" 2>&1
cd /d "%PROJECT%"
python hourly_heartbeat.py >> "%LOGFILE%" 2>&1
echo [%date% %time%] Heartbeat complete (exit %errorlevel%) >> "%LOGFILE%" 2>&1
