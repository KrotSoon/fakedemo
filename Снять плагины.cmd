@echo off
rem Emergency: take FakeDemo plugins out of CS2 (close CS2 first)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0fakedemo.ps1" off
pause
