@echo off
rem Joins a co-op game. With no argument it joins this PC (127.0.0.1).
rem Usage: join.cmd [address]
set ADDRESS=%1
if "%ADDRESS%"=="" set ADDRESS=127.0.0.1
start "" "%~dp0godot\Godot_v4.4.1-stable_win64.exe" --path "%~dp0.." -- --join=%ADDRESS% --profile=p2
