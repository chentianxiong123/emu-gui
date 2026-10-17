@echo off
where pwsh >nul 2>&1
if %errorlevel%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%USERPROFILE%\tools\emu-gui.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%USERPROFILE%\tools\emu-gui.ps1" %*
)