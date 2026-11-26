@echo off
setlocal
cd /d "%~dp0"
rem Let Windows PowerShell load its own modules when called from PowerShell 7.
set "PSModulePath="
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\setup-windows.ps1" %*
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" (
  echo.
  echo isme.gg setup failed. Review the messages above.
  pause
)
exit /b %RESULT%
