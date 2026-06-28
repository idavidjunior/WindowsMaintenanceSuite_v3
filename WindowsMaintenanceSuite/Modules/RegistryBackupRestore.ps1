<#
.SYNOPSIS
    Módulo para backup e restauração do Registro do Windows.
.DESCRIPTION
    Este módulo fornece funções para criar backups completos do registro e restaurá-los,
    aumentando a segurança antes de operações críticas de manutenção.
#>

function Backup-Registry {
    param (
        [string]$BackupPath = "C:\WMS_RegistryBackups"
    )

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  BACKUP DO REGISTRO" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "`n[1/4] Criando diretorio de backup..." -ForegroundColor Yellow
    
    if (-not (Test-Path -Path $BackupPath)) {
        New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
        Write-Host "      [OK] Diretorio criado: $BackupPath" -ForegroundColor Green
    } else {
        Write-Host "      [OK] Diretorio ja existe: $BackupPath" -ForegroundColor Green
    }

    Write-Host "`n[2/4] Gerando nome do arquivo..." -ForegroundColor Yellow
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $BackupFile = Join-Path -Path $BackupPath -ChildPath "RegistryBackup_$Timestamp.reg"
    Write-Host "      [OK] Arquivo: $BackupFile" -ForegroundColor Green

    try {
        # Exporta HKLM e HKCU para backup completo. Requer privilegios de administrador.
        Write-Host "`n[3/4] Exportando HKLM (Local Machine)..." -ForegroundColor Yellow
        $BackupFileHKLM = $BackupFile -replace '\.reg$', '_HKLM.reg'
        $hklmProcess = Start-Process -FilePath "reg.exe" -ArgumentList "export HKLM `"$BackupFileHKLM`" /y" -Wait -PassThru -NoNewWindow
        if ($hklmProcess.ExitCode -eq 0) {
            Write-Host "      [OK] HKLM exportado com sucesso." -ForegroundColor Green
        } else {
            Write-Host "      [ERRO] Falha ao exportar HKLM." -ForegroundColor Red
            return $false
        }
        
        Write-Host "`n[3/4] Exportando HKCU (Current User)..." -ForegroundColor Yellow
        $BackupFileHKCU = $BackupFile -replace '\.reg$', '_HKCU.reg'
        $hkcuProcess = Start-Process -FilePath "reg.exe" -ArgumentList "export HKCU `"$BackupFileHKCU`" /y" -Wait -PassThru -NoNewWindow
        if ($hkcuProcess.ExitCode -eq 0) {
            Write-Host "      [OK] HKCU exportado com sucesso." -ForegroundColor Green
        } else {
            Write-Host "      [ERRO] Falha ao exportar HKCU." -ForegroundColor Red
            return $false
        }
        
        # Criar arquivo combinado
        Write-Host "`n[4/4] Combinando arquivos de backup..." -ForegroundColor Yellow
        $CombinedContent = @()
        $CombinedContent += Get-Content $BackupFileHKLM
        $CombinedContent += Get-Content $BackupFileHKCU
        $CombinedContent | Out-File -FilePath $BackupFile -Encoding UTF8
        
        # Remover arquivos temporarios
        Remove-Item $BackupFileHKLM -Force -ErrorAction SilentlyContinue
        Remove-Item $BackupFileHKCU -Force -ErrorAction SilentlyContinue
        
        $backupSize = [Math]::Round((Get-Item $BackupFile).Length / 1MB, 2)
        Write-Host "      [OK] Backup combinado criado ($backupSize MB)." -ForegroundColor Green
        
        Write-Host "`n========================================" -ForegroundColor Green
        Write-Host "  BACKUP CONCLUIDO COM SUCESSO!" -ForegroundColor Green
        Write-Host "  Arquivo: $BackupFile" -ForegroundColor Green
        Write-Host "  Tamanho: $backupSize MB" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        
        Write-Log "Backup do Registro concluido: $BackupFile ($backupSize MB)" "SUCCESS"
        return $true
    }
    catch {
        Write-Host "`n========================================" -ForegroundColor Red
        Write-Host "  ERRO AO CRIAR BACKUP" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "Erro ao criar backup do Registro: $_" -ForegroundColor Red
        Write-Log "Erro ao criar backup do Registro: $_" "ERROR"
        return $false
    }
}

function Restore-Registry {
    param (
        [string]$BackupFile
    )

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  RESTAURACAO DO REGISTRO" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    if (-not (Test-Path -Path $BackupFile)) {
        Write-Host "`n[ERRO] Arquivo de backup nao encontrado: $BackupFile" -ForegroundColor Red
        Write-Log "Arquivo de backup nao encontrado: $BackupFile" "ERROR"
        return $false
    }
    
    Write-Host "`n[INFO] Arquivo encontrado: $BackupFile" -ForegroundColor Cyan
    $backupSize = [Math]::Round((Get-Item $BackupFile).Length / 1MB, 2)
    Write-Host "[INFO] Tamanho: $backupSize MB" -ForegroundColor Cyan

    Write-Host "`n[AVISO] Esta operacao pode afetar a estabilidade do sistema." -ForegroundColor Red
    Write-Host "[AVISO] Recomenda-se criar um backup antes de continuar." -ForegroundColor Red
    
    $Confirm = Read-Host "Tem certeza que deseja continuar? (S/N)"
    if ($Confirm -ne 'S') {
        Write-Host "`n[INFO] Restauracao cancelada pelo usuario." -ForegroundColor Yellow
        Write-Log "Restauracao cancelada pelo usuario." "INFO"
        return $false
    }

    try {
        Write-Host "`n[1/1] Importando arquivo de registro..." -ForegroundColor Yellow
        # Importa o arquivo de registro. Requer privilegios de administrador.
        $importProcess = Start-Process -FilePath "reg.exe" -ArgumentList "import `"$BackupFile`"" -Wait -PassThru -NoNewWindow
        
        if ($importProcess.ExitCode -eq 0) {
            Write-Host "      [OK] Restauracao concluida com sucesso." -ForegroundColor Green
            Write-Host "`n========================================" -ForegroundColor Green
            Write-Host "  RESTAURACAO CONCLUIDA!" -ForegroundColor Green
            Write-Host "  REINICIE O COMPUTADOR" -ForegroundColor Green
            Write-Host "========================================" -ForegroundColor Green
            Write-Log "Restauracao do Registro concluida: $BackupFile" "SUCCESS"
            return $true
        } else {
            Write-Host "      [ERRO] Falha ao importar arquivo de registro." -ForegroundColor Red
            Write-Log "Falha ao importar arquivo de registro: $BackupFile" "ERROR"
            return $false
        }
    }
    catch {
        Write-Host "`n========================================" -ForegroundColor Red
        Write-Host "  ERRO AO RESTAURAR" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "Erro ao restaurar o Registro: $_" -ForegroundColor Red
        Write-Log "Erro ao restaurar o Registro: $_" "ERROR"
        return $false
    }
}

