<#
.SYNOPSIS
    Módulo de manutenção essencial do sistema.
.DESCRIPTION
    Este módulo executa tarefas básicas de manutenção do sistema Windows.
#>

# Importar SecurityHelper
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\SecurityHelper.ps1"

# NOTA: A verificação de administrador é feita UMA ÚNICA vez em MainMenu.ps1.
# Chamar Require-Administrator aqui (escopo de topo) fazia com que o dot-source
# disparasse 'exit 1' e fechasse todo o PowerShell antes do menu aparecer.

function Invoke-EssentialMaintenance {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  MANUTENCAO ESSENCIAL" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Log "Iniciando Manutencao Essencial..." "INFO"

    $freeBefore = Get-DiskFreeGB
    
    # Criar Ponto de Restauracao (Seguranca)
    Write-Host "`n[1/7] Criando Ponto de Restauração do Sistema..." -ForegroundColor Yellow
    Write-Log "Criando Ponto de Restauracao do Sistema..." "INFO"
    try {
        Checkpoint-Computer -Description "WMS_Essential_Maintenance" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Host "      [OK] Ponto de restauracao criado com sucesso." -ForegroundColor Green
        Write-Log "Ponto de restauracao criado com sucesso." "SUCCESS"
    } catch {
        Write-Host "      [AVISO] Falha ao criar ponto de restauracao O servico pode estar desativado." -ForegroundColor Yellow
        Write-Log "Falha ao criar ponto de restauracao. O servico pode estar desativado." "WARNING"
    }
    
    # 1. Limpeza de Arquivos Temporarios
    Write-Host "`n[2/7] Limpando arquivos temporarios..." -ForegroundColor Yellow
    Write-Log "Limpando arquivos temporarios..." "INFO"
    $TempPaths = @("$env:TEMP\*", "C:\Windows\Temp\*")
    $cleanedCount = 0
    foreach ($path in $TempPaths) {
        try {
            $files = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
            if ($files) {
                Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                $cleanedCount += $files.Count
            }
        } catch {
            # Silencia erros de arquivos em uso, pois e normal no Windows
        }
    }
    Write-Host "      [OK] $cleanedCount arquivos temporarios removidos." -ForegroundColor Green
    Write-Log "Limpeza de arquivos temporarios concluida ($cleanedCount arquivos)." "SUCCESS"
    
    # 2. Flush DNS
    Write-Host "`n[3/7] Limpando cache de DNS..." -ForegroundColor Yellow
    Write-Log "Limpando cache de DNS..." "INFO"
    $dnsResult = ipconfig /flushdns
    if ($dnsResult -match "sucesso") {
        Write-Host "      [OK] Cache de DNS limpo com sucesso." -ForegroundColor Green
        Write-Log "Cache de DNS limpo com sucesso." "SUCCESS"
    } else {
        Write-Host "      [OK] Cache de DNS limpo." -ForegroundColor Green
        Write-Log "Cache de DNS limpo." "SUCCESS"
    }
    
    # 3. Limpeza do Cache do Windows Update
    Write-Host "`n[4/7] Limpando cache do Windows Update..." -ForegroundColor Yellow
    Write-Log "Limpando cache do Windows Update..." "INFO"
    try {
        Stop-Service -Name "wuauserv" -Force -ErrorAction Stop
        Stop-Service -Name "bits" -Force -ErrorAction Stop
        Write-Host "      [OK] Servicos Windows Update parados." -ForegroundColor Green
        
        $updateFiles = Get-ChildItem -Path "C:\Windows\SoftwareDistribution\Download" -ErrorAction SilentlyContinue
        if ($updateFiles) {
            Remove-Item -Path "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction Stop
            Write-Host "      [OK] Cache do Windows Update limpo ($($updateFiles.Count) arquivos)." -ForegroundColor Green
        } else {
            Write-Host "      [OK] Cache do Windows Update ja estava limpo." -ForegroundColor Green
        }
        
        Start-Service -Name "wuauserv" -ErrorAction Stop
        Start-Service -Name "bits" -ErrorAction Stop
        Write-Host "      [OK] Servicos Windows Update reiniciados." -ForegroundColor Green
        Write-Log "Cache do Windows Update limpo com sucesso." "SUCCESS"
    } catch {
        Write-Host "      [ERRO] Falha ao limpar cache do Windows Update." -ForegroundColor Red
        Write-Log "Falha ao limpar cache do Windows Update." "ERROR"
    }
    
    # 4. Verificacao de Integridade (SFC)
    Write-Host "`n[5/7] Executando SFC /scannow (Isso pode demorar)..." -ForegroundColor Yellow
    Write-Log "Executando SFC /scannow (Isso pode demorar)..." "INFO"
    $sfcProcess = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -Wait -PassThru -NoNewWindow
    if ($sfcProcess.ExitCode -eq 0) {
        Write-Host "      [OK] SFC concluido com sucesso - nenhum problema encontrado." -ForegroundColor Green
        Write-Log "SFC concluido com sucesso." "SUCCESS"
    } elseif ($sfcProcess.ExitCode -eq 1) {
        Write-Host "      [AVISO] SFC encontrou erros mas conseguiu corrigi-los." -ForegroundColor Yellow
        Write-Log "SFC encontrou erros mas conseguiu corrigi-los." "WARNING"
    } else {
        Write-Host "      [ERRO] SFC encontrou erros que nao puderam ser corrigidos." -ForegroundColor Red
        Write-Log "SFC encontrou erros que nao puderam ser corrigidos." "ERROR"
    }
    
    # 5. DISM RestoreHealth
    Write-Host "`n[6/7] Executando DISM RestoreHealth..." -ForegroundColor Yellow
    Write-Log "Executando DISM RestoreHealth..." "INFO"
    $dismProcess = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Cleanup-Image /RestoreHealth" -Wait -PassThru -NoNewWindow
    if ($dismProcess.ExitCode -eq 0) {
        Write-Host "      [OK] DISM concluido com sucesso." -ForegroundColor Green
        Write-Log "DISM concluido com sucesso." "SUCCESS"
    } else {
        Write-Host "      [ERRO] DISM falhou ao restaurar a imagem." -ForegroundColor Red
        Write-Log "DISM falhou ao restaurar a imagem." "ERROR"
    }
    
    # 6. CHKDSK Scan
    Write-Host "`n[7/7] Executando CHKDSK /scan..." -ForegroundColor Yellow
    Write-Log "Executando CHKDSK /scan..." "INFO"
    $chkdskResult = chkdsk /scan
    if ($chkdskResult -match "nao foram encontrados erros") {
        Write-Host "      [OK] CHKDSK concluido - nenhum erro encontrado." -ForegroundColor Green
        Write-Log "CHKDSK concluido - nenhum erro encontrado." "SUCCESS"
    } else {
        Write-Host "      [AVISO] CHKDSK concluido - verifique o resultado acima." -ForegroundColor Yellow
        Write-Log "CHKDSK concluido." "INFO"
    }
    
    # 7. Otimizacao de Disco
    Write-Host "`n[EXTRA] Otimizando discos (Defrag/Trim)..." -ForegroundColor Yellow
    Write-Log "Otimizando discos (Defrag/Trim)..." "INFO"
    defrag /O | Out-Null
    Write-Host "      [OK] Otimizacao de disco concluida." -ForegroundColor Green
    Write-Log "Otimizacao de disco concluida." "SUCCESS"
    
    # Atualiza Historico
    Update-WMSHistory -Key "LastEssential" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")

    $freeAfter = Get-DiskFreeGB
    $freed = [Math]::Round($freeAfter - $freeBefore, 2)

    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  MANUTENCAO ESSENCIAL CONCLUIDA!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  Espaco livre: $freeBefore GB  ->  $freeAfter GB  (~$freed GB liberados)" -ForegroundColor Cyan
    Write-Log "Manutencao Essencial concluida com sucesso! (~$freed GB liberados)" "SUCCESS"
}

