<#
.SYNOPSIS
    MÃ³dulo para backup e restauraÃ§Ã£o do Registro do Windows.
.DESCRIPTION
    Este mÃ³dulo fornece funÃ§Ãµes para criar backups completos do registro e restaurÃ¡-los,
    aumentando a seguranÃ§a antes de operaÃ§Ãµes crÃ­ticas de manutenÃ§Ã£o.
#>

# Importar SecurityHelper
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\SecurityHelper.ps1"

# NOTA: A verificaÃ§Ã£o de administrador Ã© feita UMA ÃšNICA vez em MainMenu.ps1.

function Backup-Registry {
    param (
        [string]$BackupPath = ""
    )

    # Usar caminho seguro se nÃ£o especificado
    if ([string]::IsNullOrEmpty($BackupPath)) {
        $BackupPath = Get-SafeBackupPath
    }

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  BACKUP DO REGISTRO" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "`n[1/4] Criando diretório de backup..." -ForegroundColor Yellow

    if (-not (Test-Path -Path $BackupPath)) {
        New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
        Write-Host "      [OK] diretório criado: $BackupPath" -ForegroundColor Green
    } else {
        Write-Host "      [OK] diretório ja existe: $BackupPath" -ForegroundColor Green
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
        
        # Criar arquivo combinado sem cabeÃ§alhos duplicados
        Write-Host "`n[4/4] Combinando arquivos de backup..." -ForegroundColor Yellow
        $hklmContent = Get-Content $BackupFileHKLM
        $hkcuContent = Get-Content $BackupFileHKCU

        # Se ambos os arquivos tiverem cabeÃ§alho, mantenha apenas o primeiro
        if ($hkcuContent.Count -gt 0 -and $hkcuContent[0] -match '^Windows Registry Editor Version') {
            $hkcuContent = $hkcuContent | Select-Object -Skip 1
        }
        if ($hkcuContent.Count -gt 0 -and $hkcuContent[0] -eq '') {
            $hkcuContent = $hkcuContent | Select-Object -Skip 1
        }

        $CombinedContent = @()
        $CombinedContent += $hklmContent
        $CombinedContent += $hkcuContent
        $CombinedContent | Out-File -FilePath $BackupFile -Encoding Unicode

        # Remover arquivos temporarios
        Remove-Item $BackupFileHKLM -Force -ErrorAction SilentlyContinue
        Remove-Item $BackupFileHKCU -Force -ErrorAction SilentlyContinue
        
        $backupSize = [Math]::Round((Get-Item $BackupFile).Length / 1MB, 2)
        Write-Host "      [OK] Backup combinado criado ($backupSize MB)." -ForegroundColor Green
        
        Write-Host "`n========================================" -ForegroundColor Green
        Write-Host "  BACKUP concluído COM SUCESSO!" -ForegroundColor Green
        Write-Host "  Arquivo: $BackupFile" -ForegroundColor Green
        Write-Host "  Tamanho: $backupSize MB" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        
        Write-Log "Backup do Registro concluído: $BackupFile ($backupSize MB)" "SUCCESS"
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
    Write-Host "  restauração DO REGISTRO" -ForegroundColor Cyan
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
        Write-Host "`n[INFO] restauração cancelada pelo usuario." -ForegroundColor Yellow
        Write-Log "restauração cancelada pelo usuario." "INFO"
        return $false
    }

    try {
        Write-Host "`n[1/1] Importando arquivo de registro..." -ForegroundColor Yellow
        # Importa o arquivo de registro. Requer privilegios de administrador.
        $importProcess = Start-Process -FilePath "reg.exe" -ArgumentList "import `"$BackupFile`"" -Wait -PassThru -NoNewWindow

        if ($importProcess.ExitCode -eq 0) {
            Write-Host "      [OK] restauração concluida com sucesso." -ForegroundColor Green
            Write-Host "`n========================================" -ForegroundColor Green
            Write-Host "  restauração CONCLUIDA!" -ForegroundColor Green
            Write-Host "  REINICIE O COMPUTADOR" -ForegroundColor Green
            Write-Host "========================================" -ForegroundColor Green
            Write-Log "restauração do Registro concluida: $BackupFile" "SUCCESS"
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

function Backup-TweaksConfig {
    <#
    .SYNOPSIS
        Exporta todas as chaves de registro usadas pelos tweaks do WMS para um
        unico arquivo de backup, permitindo reverter todos os tweaks de uma vez.
    #>
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  BACKUP DA CONFIG DE TWEAKS" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $BackupPath = Get-SafeBackupPath
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $tweaksBackupDir = Join-Path $BackupPath "TweaksConfig_$Timestamp"
    New-Item -ItemType Directory -Path $tweaksBackupDir -Force | Out-Null

    # Chaves usadas pelos tweaks (formato reg.exe: HKEY_...)
    $keys = @(
        "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DataCollection",
        "HKEY_CURRENT_USER\Control Panel\Desktop",
        "HKEY_CURRENT_USER\System\GameConfigStore",
        "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
        "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\PriorityControl",
        "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Windows Search",
        "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo",
        "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced",
        "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Search",
        "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects",
        "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager",
        "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\System",
        "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location",
        "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location",
        "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
    )

    $exported = 0
    $i = 0
    foreach ($key in $keys) {
        $i++
        $safeName = Convert-PathToSafeFileName -Path $key
        $outFile = Join-Path $tweaksBackupDir "$safeName.reg"
        $result = & reg.exe export $key $outFile /y 2>$null
        if (Test-Path $outFile) {
            $exported++
        }
    }

    Write-Host "`n[OK] $exported de $($keys.Count) chaves exportadas." -ForegroundColor Green
    Write-Host "     Pasta: $tweaksBackupDir" -ForegroundColor Green
    Write-Host "     Para reverter: Restaure cada .reg ou use a Opção de Restaurar." -ForegroundColor Cyan
    Write-Log "Backup da config de tweaks concluído: $exported/$($keys.Count) chaves em $tweaksBackupDir" "SUCCESS"

    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  BACKUP DE TWEAKS concluído!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    return $tweaksBackupDir
}

function Restore-TweaksConfig {
    <#
    .SYNOPSIS
        Restaura todas as chaves de registro a partir de um backup de tweaks.
    #>
    param ([string]$BackupFolder)

    if (-not $BackupFolder -or -not (Test-Path $BackupFolder)) {
        # Listar backups disponiveis
        $base = Get-SafeBackupPath
        $tweaksBackups = Get-ChildItem -Path $base -Filter "TweaksConfig_*" -Directory -ErrorAction SilentlyContinue
        if (-not $tweaksBackups -or $tweaksBackups.Count -eq 0) {
            Write-Host "[ERRO] Nenhum backup de tweaks encontrado em $base" -ForegroundColor Red
            return $false
        }
        Write-Host "`nBackups de tweaks disponiveis:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $tweaksBackups.Count; $i++) {
            Write-Host "  $($i+1). $($tweaksBackups[$i].Name)  ($($tweaksBackups[$i].LastWriteTime))"
        }
        $sel = Read-Host "Selecione o numero do backup para restaurar"
        if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $tweaksBackups.Count) {
            $BackupFolder = $tweaksBackups[[int]$sel - 1].FullName
        } else {
            Write-Host "Escolha inválida." -ForegroundColor Red
            return $false
        }
    }

    $confirm = Read-Host "`n[AVISO] Isto vai sobrescrever as chaves de registro atuais. Continuar? (S/N)"
    if ($confirm -ne 'S' -and $confirm -ne 's') {
        Write-Host "restauração cancelada." -ForegroundColor Yellow
        return $false
    }

    $regFiles = Get-ChildItem -Path $BackupFolder -Filter "*.reg" -ErrorAction SilentlyContinue
    $restored = 0
    foreach ($reg in $regFiles) {
        $proc = Start-Process -FilePath "reg.exe" -ArgumentList "import `"$($reg.FullName)`"" -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -eq 0) { $restored++ }
    }

    Write-Host "`n[OK] $restored de $($regFiles.Count) chaves restauradas." -ForegroundColor Green
    Write-Host "     Reinicie o computador para aplicar todas as alteracoes." -ForegroundColor Cyan
    Write-Log "restauração de tweaks: $restored/$($regFiles.Count) chaves de $BackupFolder" "SUCCESS"
    return $true
}


Export-ModuleMember -Function *
