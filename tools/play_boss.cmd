@echo off
rem Playtest shortcut: starts solo straight in "The Three Pillars" boss fight as Venza,
rem using a separate "dev" save file so your real progress is not touched.
"%~dp0godot\Godot_v4.4.1-stable_win64.exe" --path "%~dp0.." -- --solo --profile=dev --dev-unlock-venza --mission=res://missions/data/three_pillars.tres
