@echo off
rem Co-op tests: each starts a host and a client of the game on this PC and checks they
rem work together. Exit code is 0 only if every host and client reports NET TEST PASS.
setlocal
set GODOT="%~dp0godot\Godot_v4.4.1-stable_win64_console.exe"
set PROJECT="%~dp0.."
set LOGDIR=%TEMP%\arpg_net_test
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
del /q "%LOGDIR%\*.log" 2>nul

call :run_pair net_test 24600
if errorlevel 1 exit /b 1
call :run_pair net_hub_test 24601
if errorlevel 1 exit /b 1
call :run_pair net_boss_test 24602
if errorlevel 1 exit /b 1
exit /b 0

rem Runs res://tests/<name>.tscn as host (background) and client, on the given port.
:run_pair
set NAME=%1
set PORT=%2
echo --- %NAME% ---
start "net-test-host" /b cmd /c "%GODOT% --headless --path %PROJECT% res://tests/%NAME%.tscn -- --role=host --port=%PORT% > "%LOGDIR%\%NAME%_host.log" 2>&1"
%GODOT% --headless --path %PROJECT% res://tests/%NAME%.tscn -- --role=client --port=%PORT% > "%LOGDIR%\%NAME%_client.log" 2>&1

rem Give the host up to 20 seconds to finish after the client.
set /a WAITED=0
:wait_for_host
findstr /c:"NET TEST" "%LOGDIR%\%NAME%_host.log" >nul 2>&1 && goto check
if %WAITED% geq 20 goto check
ping -n 2 127.0.0.1 >nul
set /a WAITED+=1
goto wait_for_host

:check
echo host:
findstr /c:"ok " /c:"FAIL" /c:"NET TEST" "%LOGDIR%\%NAME%_host.log"
echo client:
findstr /c:"ok " /c:"FAIL" /c:"NET TEST" "%LOGDIR%\%NAME%_client.log"
findstr /c:"NET TEST PASS" "%LOGDIR%\%NAME%_host.log" >nul || exit /b 1
findstr /c:"NET TEST PASS" "%LOGDIR%\%NAME%_client.log" >nul || exit /b 1
exit /b 0
