@echo off
rem Runs every automated test without opening a window.
rem Exit code is 0 only if all tests pass.
setlocal
set GODOT="%~dp0godot\Godot_v4.4.1-stable_win64_console.exe"
set PROJECT="%~dp0.."

echo === Refreshing Godot's script and asset cache ===
%GODOT% --headless --path %PROJECT% --import >nul 2>&1

echo === Unit tests ===
%GODOT% --headless --path %PROJECT% res://tests/unit_tests.tscn
if errorlevel 1 exit /b 1

echo === Smoke test (plays the real arena with scripted input) ===
%GODOT% --headless --fixed-fps 60 --path %PROJECT% res://tests/smoke_test.tscn
if errorlevel 1 exit /b 1

echo === All tests passed ===
