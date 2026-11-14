@echo off
rem Opens the project in the Godot editor. Press F5 there to play.
start "" "%~dp0godot\Godot_v4.4.1-stable_win64.exe" --editor --path "%~dp0.."
