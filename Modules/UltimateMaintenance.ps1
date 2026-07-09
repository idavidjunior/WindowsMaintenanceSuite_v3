<#
.SYNOPSIS
    MÃ³dulo de manutenÃ§Ã£o completa do sistema.
.DESCRIPTION
    Este mÃ³dulo executa tarefas avanÃ§adas de manutenÃ§Ã£o do sistema Windows.
#>

# Importar SecurityHelper
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\SecurityHelper.ps1"

# NOTA: A verificaÃ§Ã£o de administrador Ã© feita UMA ÃšNICA vez em MainMenu.ps1.

function Invoke-UltimateMaintenance {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  MANUTENCAO COMPLETA (ULTIMATE)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Log "Iniciando Manutencao Completa (Ultimate)..." "INFO"

    $freeBefore = Get-DiskFreeGB
    
    # Criar Ponto de restauração (Seguranca)
    Write-Host "`n[0/4] Criando Ponto de restauração do Sistema..." -ForegroundColor Yellow
    Write-Log "Criando Ponto de restauração do Sistema..." "INFO"
    try {
        Checkpoint-Computer -Description "WMS_Ultimate_Maintenance" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Host "      [OK] Ponto de restauração criado com sucesso." -ForegroundColor Green
        Write-Log "Ponto de restauração criado com sucesso." "SUCCESS"
    } catch {
        Write-Host "      [AVISO] Falha ao criar ponto de restauração O servico pode estar desativado." -ForegroundColor Yellow
        Write-Log "Falha ao criar ponto de restauração. O servico pode estar desativado." "WARNING"
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
    
    # 3. Limpeza de Logs de Eventos (OPT-IN, com backup dos logs crÃ­ticos)
    Write-Host "`n[4/4] Limpeza de Logs de Eventos do Windows..." -ForegroundColor Yellow
    Write-Log "Oferecendo limpeza de Logs de Eventos do Windows..." "INFO"
    $cleanEvents = Read-Host "`nLimpar TODOS os logs de eventos do Windows? Isso apaga historico de erros/eventos (S/N)"
    if ($cleanEvents -eq 'S' -or $cleanEvents -eq 's') {
        # Backup dos 3 logs mais importantes antes de limpar
        Write-Host "      [INFO] Fazendo backup dos logs criticos (System/Application/Security)..." -ForegroundColor Cyan
        $evtBackupDir = Get-SafeBackupPath
        foreach ($logName in @('System', 'Application', 'Security')) {
            try {
                $evtFile = Join-Path $evtBackupDir "EventLog_${logName}_$(Get-Date -Format 'yyyyMMdd_HHmmss').evtx"
                wevtutil epl $logName $evtFile 2>$null
                if (Test-Path $evtFile) {
                    Write-Host "      [OK] Backup do log '$logName' salvo." -ForegroundColor Green
                }
            } catch {
                Write-Host "      [AVISO] Nao foi possivel fazer backup do log '$logName'." -ForegroundColor Yellow
            }
        }
        $Logs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue
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
    } else {
        Write-Host "      [INFO] Limpeza de logs de eventos cancelada pelo usuario." -ForegroundColor Cyan
        Write-Log "Limpeza de logs de eventos cancelada pelo usuario." "INFO"
    }
    
    # Atualiza Historico
    Update-WMSHistory -Key "LastUltimate" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")

    $freeAfter = Get-DiskFreeGB
    $freed = [Math]::Round($freeAfter - $freeBefore, 2)

    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  MANUTENCAO COMPLETA CONCLUIDA!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  Espaco livre: $freeBefore GB  ->  $freeAfter GB  (~$freed GB liberados)" -ForegroundColor Cyan
    Write-Log "Manutencao Completa concluida com sucesso! (~$freed GB liberados)" "SUCCESS"
}



