@echo off
rem Launch DDA. Uses the winget install of Godot if present, else godot from PATH.
cd /d "%~dp0"
set "G=%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe"
if exist "%G%" (
  start "" "%G%" --path "%~dp0."
) else (
  start "" godot --path "%~dp0."
)
