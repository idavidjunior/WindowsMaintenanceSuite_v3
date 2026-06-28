function Start-UltimateMaintenance {
    Write-Log "Iniciando Manutenção Completa (Ultimate)..." "INFO"
    
    # Criar Ponto de Restauração (Segurança)
    Write-Log "Criando Ponto de Restauração do Sistema..." "INFO"
    try {
        Checkpoint-Computer -Description "WMS_Ultimate_Maintenance" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Log "Ponto de restauração criado com sucesso." "SUCCESS"
    } catch {
        Write-Log "Falha ao criar ponto de restauração. O serviço pode estar desativado." "WARNING"
    }
    
    # Executa a Essencial primeiro
    Start-EssentialMaintenance
    
    # 1. Defender Quick Scan
    Write-Log "Iniciando Verificação Rápida do Windows Defender..." "INFO"
    try {
        Start-MpScan -ScanType QuickScan -ErrorAction Stop
        Write-Log "Verificação Rápida do Windows Defender concluída." "SUCCESS"
    } catch {
        Write-Log "Falha ao executar Verificação Rápida do Windows Defender." "ERROR"
    }
    
    # 2. Limpeza da Loja de Componentes (DISM)
    Write-Log "Limpando Loja de Componentes (DISM StartComponentCleanup)..." "INFO"
    try {
        DISM /Online /Cleanup-Image /StartComponentCleanup -ErrorAction Stop
        Write-Log "Limpeza da Loja de Componentes concluída." "SUCCESS"
    } catch {
        Write-Log "Falha ao limpar a Loja de Componentes." "ERROR"
    }
    
    # 3. Limpeza de Logs de Eventos (Opcional - mas solicitado na spec)
    Write-Log "Limpando Logs de Eventos do Windows..." "INFO"
    $Logs = Get-WinEvent -ListLog *
    foreach ($log in $Logs) {
        try {
            [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($log.LogName)
            Write-Log "Log $($log.LogName) limpo." "INFO"
        } catch {
            Write-Log "Falha ao limpar o log $($log.LogName)." "WARNING"
        }
    }
    
    # Atualiza Histórico
    Update-WMSHistory -Key "LastUltimate" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    Write-Log "Manutenção Completa concluída com sucesso!" "SUCCESS"
}

Export-ModuleMember -Function Start-UltimateMaintenance
