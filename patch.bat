@echo off
chcp 65001 >nul
title Island 1.2.10 - patch
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch.ps1"
echo.
pause
