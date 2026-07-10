@echo off
:: Windows Maintenance Suite Launcher v3.0
set "WMS_DIR=%~dp0"
set "GUI_EXE=%WMS_DIR%WindowGUI\dist_latest\win-unpacked\Windows Maintenance Suite.exe"
title Windows Maintenance Suite

:: Auto-elevate to Administrator
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Solicitando privilegios de Administrador...
    powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs" 2>nul
    exit /b
)

start "" "%GUI_EXE%"
exit /b
