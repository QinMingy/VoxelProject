@echo off
chcp 65001 >nul
setlocal
set "GODOT_EXE=%LOCALAPPDATA%\Programs\Godot\4.7.2\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT_EXE%" (
  echo 找不到 Godot 4.7.2。请在编辑器打开 project.godot，运行后关闭基地界面，按 G 选择“冒险遗物试挖”。
  pause
  exit /b 1
)
start "" "%GODOT_EXE%" --path "%~dp0." -- --adventure-trial
