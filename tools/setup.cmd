@echo off
rem One-time setup on a new PC: downloads and verifies Godot 4.4.1 into tools\godot\.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
if errorlevel 1 (
  echo Setup failed.
  exit /b 1
)
