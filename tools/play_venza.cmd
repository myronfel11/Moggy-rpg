@echo off
rem Playtest shortcut: starts solo as Venza with her pistols, using a separate "dev" save
rem file so your real progress is not touched.
"%~dp0godot\Godot_v4.4.1-stable_win64.exe" --path "%~dp0.." -- --solo --profile=dev --dev-unlock-venza
