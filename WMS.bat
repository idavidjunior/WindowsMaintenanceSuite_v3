@echo off
:: Windows Maintenance Suite Launcher
:: Versao 2.0 - GUI

set "WMS_DIR=%~dp0"
set "GUI_EXE=%WMS_DIR%WindowGUI\dist_build\win-unpacked\Windows Maintenance Suite.exe"

title Windows Maintenance Suite

:: Verifica privilegios de Administrador
net session >nul 2>&1
if %errorLevel% NEQ 0 (
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
:: Abre a interface grafica (Electron) e fecha esta janela
start "" "%GUI_EXE%"
exit /b
