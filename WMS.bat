@echo off
:: Windows Maintenance Suite Launcher
:: Versão 1.0

set "WMS_DIR=%~dp0"
set "CORE_DIR=%WMS_DIR%Core"

title Windows Maintenance Suite

:: Verifica privilégios de Administrador
net session >nul 2>&1
if %errorLevel% == 0 (
    goto :run
) else (
    echo.
    echo ######################################################
    echo # ERRO: ESTE SCRIPT REQUER PRIVILEGIOS DE ADMIN.     #
    echo # POR FAVOR, CLIQUE COM O BOTAO DIREITO E SELECIONE  #
    echo # 'EXECUTAR COMO ADMINISTRADOR'.                     #
    echo ######################################################
    echo.
    pause
    exit /b
)

:run
:: Executa o Menu Principal em PowerShell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CORE_DIR%\MainMenu.ps1"

pause
