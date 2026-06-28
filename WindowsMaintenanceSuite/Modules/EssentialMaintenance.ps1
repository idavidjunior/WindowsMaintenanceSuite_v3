function Start-EssentialMaintenance {
    Write-Log "Iniciando Manutenção Essencial..." "INFO"
    
    # Criar Ponto de Restauração (Segurança)
    Write-Log "Criando Ponto de Restauração do Sistema..." "INFO"
    try {
        Checkpoint-Computer -Description "WMS_Essential_Maintenance" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Log "Ponto de restauração criado com sucesso." "SUCCESS"
    } catch {
        Write-Log "Falha ao criar ponto de restauração. O serviço pode estar desativado." "WARNING"
    }
    
    # 1. Limpeza de Arquivos Temporários
    Write-Log "Limpando arquivos temporários..." "INFO"
    $TempPaths = @("$env:TEMP\*", "C:\Windows\Temp\*")
    foreach ($path in $TempPaths) {
        try {
            Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
        } catch {
            # Silencia erros de arquivos em uso, pois é normal no Windows
        }
    }
    
    # 2. Flush DNS
    Write-Log "Limpando cache de DNS..." "INFO"
    ipconfig /flushdns | Out-Null
    
    # 3. Limpeza do Cache do Windows Update
    Write-Log "Limpando cache do Windows Update..." "INFO"
    Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "bits" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue
    
    # 4. Verificação de Integridade (SFC)
    Write-Log "Executando SFC /scannow (Isso pode demorar)..." "INFO"
    $sfcResult = sfc /scannow
    if ($LASTEXITCODE -ne 0) {
        Write-Log "SFC encontrou erros que não puderam ser corrigidos." "WARNING"
    } else {
        Write-Log "SFC concluído com sucesso." "SUCCESS"
    }
    
    # 5. DISM RestoreHealth
    Write-Log "Executando DISM RestoreHealth..." "INFO"
    $dismResult = DISM /Online /Cleanup-Image /RestoreHealth
    if ($LASTEXITCODE -ne 0) {
        Write-Log "DISM falhou ao restaurar a imagem." "ERROR"
    } else {
        Write-Log "DISM concluído com sucesso." "SUCCESS"
    }
    
    # 6. CHKDSK Scan
    Write-Log "Executando CHKDSK /scan..." "INFO"
    chkdsk /scan
    
    # 7. Otimização de Disco
    Write-Log "Otimizando discos (Defrag/Trim)..." "INFO"
    defrag /O
    
    # Atualiza Histórico
    Update-WMSHistory -Key "LastEssential" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    Write-Log "Manutenção Essencial concluída com sucesso!" "SUCCESS"
}

Export-ModuleMember -Function Start-EssentialMaintenance
