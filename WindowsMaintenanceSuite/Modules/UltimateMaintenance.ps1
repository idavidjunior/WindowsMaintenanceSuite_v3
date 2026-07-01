<#
.SYNOPSIS
    Módulo de manutenção completa do sistema.
.DESCRIPTION
    Este módulo executa tarefas avançadas de manutenção do sistema Windows.
#>

# Importar SecurityHelper
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\SecurityHelper.ps1"

# Validar privilégios de administrador
Require-Administrator

function Invoke-UltimateMaintenance {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  MANUTENCAO COMPLETA (ULTIMATE)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Log "Iniciando Manutencao Completa (Ultimate)..." "INFO"
    
    # Criar Ponto de Restauracao (Seguranca)
    Write-Host "`n[0/4] Criando Ponto de Restauracao do Sistema..." -ForegroundColor Yellow
    Write-Log "Criando Ponto de Restauracao do Sistema..." "INFO"
    try {
        Checkpoint-Computer -Description "WMS_Ultimate_Maintenance" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Host "      [OK] Ponto de restauracao criado com sucesso." -ForegroundColor Green
        Write-Log "Ponto de restauracao criado com sucesso." "SUCCESS"
    } catch {
        Write-Host "      [AVISO] Falha ao criar ponto de restauracao O servico pode estar desativado." -ForegroundColor Yellow
        Write-Log "Falha ao criar ponto de restauracao. O servico pode estar desativado." "WARNING"
    }
    
    # Executa a Essencial primeiro
    Write-Host "`n[1/4] Executando Manutencao Essencial..." -ForegroundColor Yellow
    Invoke-EssentialMaintenance
    
    # 1. Defender Quick Scan
    Write-Host "`n[2/4] Iniciando Verificacao Rapida do Windows Defender..." -ForegroundColor Yellow
    Write-Log "Iniciando Verificacao Rapida do Windows Defender..." "INFO"
    try {
        Start-MpScan -ScanType QuickScan -ErrorAction Stop
        Write-Host "      [OK] Verificacao Rapida do Windows Defender concluida." -ForegroundColor Green
        Write-Log "Verificacao Rapida do Windows Defender concluida." "SUCCESS"
    } catch {
        Write-Host "      [ERRO] Falha ao executar Verificacao Rapida do Windows Defender." -ForegroundColor Red
        Write-Log "Falha ao executar Verificacao Rapida do Windows Defender." "ERROR"
    }
    
    # 2. Limpeza da Loja de Componentes (DISM)
    Write-Host "`n[3/4] Limpando Loja de Componentes (DISM StartComponentCleanup)..." -ForegroundColor Yellow
    Write-Log "Limpando Loja de Componentes (DISM StartComponentCleanup)..." "INFO"
    try {
        $dismProcess = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup" -Wait -PassThru -NoNewWindow
        if ($dismProcess.ExitCode -eq 0) {
            Write-Host "      [OK] Limpeza da Loja de Componentes concluida." -ForegroundColor Green
            Write-Log "Limpeza da Loja de Componentes concluida." "SUCCESS"
        } else {
            Write-Host "      [ERRO] Falha ao limpar a Loja de Componentes." -ForegroundColor Red
            Write-Log "Falha ao limpar a Loja de Componentes." "ERROR"
        }
    } catch {
        Write-Host "      [ERRO] Falha ao limpar a Loja de Componentes." -ForegroundColor Red
        Write-Log "Falha ao limpar a Loja de Componentes." "ERROR"
    }
    
    # 3. Limpeza de Logs de Eventos
    Write-Host "`n[4/4] Limpando Logs de Eventos do Windows..." -ForegroundColor Yellow
    Write-Log "Limpando Logs de Eventos do Windows..." "INFO"
    $Logs = Get-WinEvent -ListLog *
    $cleanedLogs = 0
    foreach ($log in $Logs) {
        try {
            [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($log.LogName)
            $cleanedLogs++
        } catch {
            # Logs em uso ou protegidos podem falhar, e normal
        }
    }
    Write-Host "      [OK] $cleanedLogs logs de eventos limpos." -ForegroundColor Green
    Write-Log "$cleanedLogs logs de eventos limpos." "SUCCESS"
    
    # Atualiza Historico
    Update-WMSHistory -Key "LastUltimate" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  MANUTENCAO COMPLETA CONCLUIDA!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Log "Manutencao Completa concluida com sucesso!" "SUCCESS"
}

