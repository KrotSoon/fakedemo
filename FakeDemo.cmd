@echo off
rem FakeDemo launcher window
start "" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0launcher.ps1"
