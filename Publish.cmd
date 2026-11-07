@echo off
setlocal
chcp 65001 >nul
title Moon Excavation - Publish
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\publish_demo.ps1" %*
set "PUBLISH_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %PUBLISH_EXIT%
