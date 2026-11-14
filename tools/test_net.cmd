@echo off
rem Co-op test: starts a host and a client of the game on this PC and checks they work
rem together. Exit code is 0 only if both report NET TEST PASS.
setlocal
set GODOT="%~dp0godot\Godot_v4.4.1-stable_win64_console.exe"
set PROJECT="%~dp0.."
set LOGDIR=%TEMP%\arpg_net_test
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
del /q "%LOGDIR%\*.log" 2>nul

start "net-test-host" /b cmd /c "%GODOT% --headless --path %PROJECT% res://tests/net_test.tscn -- --role=host --port=24600 > "%LOGDIR%\host.log" 2>&1"
%GODOT% --headless --path %PROJECT% res://tests/net_test.tscn -- --role=client --port=24600 > "%LOGDIR%\client.log" 2>&1

rem Give the host up to 20 seconds to finish after the client.
set /a WAITED=0
:wait_for_host
findstr /c:"NET TEST" "%LOGDIR%\host.log" >nul 2>&1 && goto check
if %WAITED% geq 20 goto check
ping -n 2 127.0.0.1 >nul
set /a WAITED+=1
goto wait_for_host

:check
echo --- host ---
findstr /c:"ok " /c:"FAIL" /c:"NET TEST" "%LOGDIR%\host.log"
echo --- client ---
findstr /c:"ok " /c:"FAIL" /c:"NET TEST" "%LOGDIR%\client.log"
findstr /c:"NET TEST PASS" "%LOGDIR%\host.log" >nul || exit /b 1
findstr /c:"NET TEST PASS" "%LOGDIR%\client.log" >nul || exit /b 1
exit /b 0
