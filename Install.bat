@echo off
REM Double-click this file to set up Odoo in Claude.
REM Wraps install.ps1 so Windows won't block it or open it in Notepad.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
if errorlevel 1 exit /b 1
