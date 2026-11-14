@echo off
rem Starts the game as a co-op host (skips the menu).
start "" "%~dp0godot\Godot_v4.4.1-stable_win64.exe" --path "%~dp0.." -- --host
