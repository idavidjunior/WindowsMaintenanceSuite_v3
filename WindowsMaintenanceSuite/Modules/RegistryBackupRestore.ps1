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

    Write-Host "Iniciando backup do Registro..." -ForegroundColor Cyan
    
    if (-not (Test-Path -Path $BackupPath)) {
        New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
    }

    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $BackupFile = Join-Path -Path $BackupPath -ChildPath "RegistryBackup_$Timestamp.reg"

    try {
        # Exporta HKLM e HKCU para backup completo. Requer privilégios de administrador.
        $BackupFileHKLM = $BackupFile -replace '\.reg$', '_HKLM.reg'
        $BackupFileHKCU = $BackupFile -replace '\.reg$', '_HKCU.reg'
        
        Start-Process -FilePath "reg.exe" -ArgumentList "export HKLM `"$BackupFileHKLM`" /y" -Wait -NoNewWindow
        Start-Process -FilePath "reg.exe" -ArgumentList "export HKCU `"$BackupFileHKCU`" /y" -Wait -NoNewWindow
        
        # Criar arquivo combinado
        $CombinedContent = @()
        $CombinedContent += Get-Content $BackupFileHKLM
        $CombinedContent += Get-Content $BackupFileHKCU
        $CombinedContent | Out-File -FilePath $BackupFile -Encoding UTF8
        
        # Remover arquivos temporários
        Remove-Item $BackupFileHKLM -Force -ErrorAction SilentlyContinue
        Remove-Item $BackupFileHKCU -Force -ErrorAction SilentlyContinue
        Write-Host "Backup do Registro (HKLM + HKCU) concluído com sucesso em: $BackupFile" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Erro ao criar backup do Registro: $_" -ForegroundColor Red
        return $false
    }
}

function Restore-Registry {
    param (
        [string]$BackupFile
    )

    if (-not (Test-Path -Path $BackupFile)) {
        Write-Host "Arquivo de backup não encontrado: $BackupFile" -ForegroundColor Red
        return $false
    }

    Write-Host "Iniciando restauração do Registro a partir de: $BackupFile" -ForegroundColor Yellow
    Write-Host "AVISO: Esta operação pode afetar a estabilidade do sistema." -ForegroundColor Red
    
    $Confirm = Read-Host "Tem certeza que deseja continuar? (S/N)"
    if ($Confirm -ne 'S') {
        Write-Host "Restauração cancelada pelo usuário." -ForegroundColor Yellow
        return $false
    }

    try {
        # Importa o arquivo de registro. Requer privilégios de administrador.
        Start-Process -FilePath "reg.exe" -ArgumentList "import `"$BackupFile`"" -Wait -NoNewWindow
        Write-Host "Restauração do Registro concluída com sucesso. Reinicie o computador." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Erro ao restaurar o Registro: $_" -ForegroundColor Red
        return $false
    }
}

