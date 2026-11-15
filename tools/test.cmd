@echo off
rem Runs every automated test without opening a window.
rem Exit code is 0 only if all tests pass.
setlocal
set GODOT="%~dp0godot\Godot_v4.4.1-stable_win64_console.exe"
set PROJECT="%~dp0.."

echo === Refreshing Godot's script and asset cache ===
%GODOT% --headless --path %PROJECT% --import >nul 2>&1

echo === Checking test scripts for syntax errors ===
rem A test whose script fails to load never quits, so catch that before running anything.
for %%T in (unit_tests smoke_test hub_test venza_test net_test net_hub_test) do (
  %GODOT% --headless --path %PROJECT% --check-only --script res://tests/%%T.gd
  if errorlevel 1 (
    echo Syntax error in tests/%%T.gd or a script it uses. See the messages above.
    exit /b 1
  )
)

echo === Unit tests ===
%GODOT% --headless --path %PROJECT% res://tests/unit_tests.tscn
if errorlevel 1 exit /b 1

echo === Smoke test (plays the real arena with scripted input) ===
%GODOT% --headless --fixed-fps 60 --path %PROJECT% res://tests/smoke_test.tscn
if errorlevel 1 exit /b 1

echo === Hub test (hub, crafting, armory, missions, saving) ===
%GODOT% --headless --fixed-fps 60 --path %PROJECT% res://tests/hub_test.tscn
if errorlevel 1 exit /b 1

echo === Venza test (pistols, skating, wall riding, trails) ===
%GODOT% --headless --fixed-fps 60 --path %PROJECT% res://tests/venza_test.tscn
if errorlevel 1 exit /b 1

echo === Co-op test (a host and a client on this PC) ===
call "%~dp0test_net.cmd"
if errorlevel 1 exit /b 1

echo === All tests passed ===
