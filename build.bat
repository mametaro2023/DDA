@echo off
rem Build the Danmaku beta (game only, no songs) and zip it.
rem Requires the Godot 4.7.2 stable export templates (Godot editor: Editor > Manage Export Templates).
rem See docs/distribution.md ("Haifu") for details.
cd /d "%~dp0"
set "G=%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%G%" set "G=godot"
rem Register rcedit in the Godot editor settings so the exe gets the icon (tools\set_rcedit.ps1)
powershell -NoProfile -ExecutionPolicy Bypass -File tools\set_rcedit.ps1
set "OUT=build\Danmaku_beta"
if exist build rmdir /s /q build
mkdir "%OUT%\songs"
"%G%" --headless --path . --export-release "Windows Desktop" "%OUT%\Danmaku.exe"
if errorlevel 1 (
  echo Export failed. Check that the export templates are installed.
  exit /b 1
)
copy /y dist_files\README.txt "%OUT%\README.txt" >nul
copy /y dist_files\LICENSE-Godot.txt "%OUT%\LICENSE-Godot.txt" >nul
copy /y dist_files\songs_README.txt "%OUT%\songs\README.txt" >nul
powershell -NoProfile -Command "Compress-Archive -Path 'build\Danmaku_beta' -DestinationPath 'build\Danmaku_beta_v0.15.0.zip' -Force"
echo Done: build\Danmaku_beta_v0.15.0.zip
