@echo off
setlocal
chcp 65001 >nul
set "GODOT_EXE=%LOCALAPPDATA%\Programs\Godot\4.7.2\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT_EXE%" (
  echo 未找到 Godot 4.7.2，请在编辑器中打开本目录的 project.godot 后按 F5。
  pause
  exit /b 1
)
start "" "%GODOT_EXE%" --path "%~dp0."
