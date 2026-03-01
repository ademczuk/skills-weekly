@echo off
echo Registering OpenClaw Skills Weekly scheduled tasks...

REM Derive paths from this script's location
set CRONDIR=%~dp0

REM Daily snapshot at 9:00 AM
schtasks /Create /TN "OpenClawDailySnapshot" /TR "%CRONDIR%daily_snapshot.bat" /SC DAILY /ST 09:00 /F
if %errorlevel%==0 (echo   [OK] Daily snapshot task registered) else (echo   [FAIL] Daily snapshot task)

REM Weekly report on Mondays at 9:30 AM
schtasks /Create /TN "OpenClawWeeklyReport" /TR "%CRONDIR%weekly_report.bat" /SC WEEKLY /D MON /ST 09:30 /F
if %errorlevel%==0 (echo   [OK] Weekly report task registered) else (echo   [FAIL] Weekly report task)

echo.
echo Verifying:
schtasks /Query /TN "OpenClawDailySnapshot" /FO LIST | findstr "TaskName Status Next"
schtasks /Query /TN "OpenClawWeeklyReport" /FO LIST | findstr "TaskName Status Next"

echo.
echo Done. To test manually:
echo   schtasks /Run /TN "OpenClawDailySnapshot"
echo   schtasks /Run /TN "OpenClawWeeklyReport"
