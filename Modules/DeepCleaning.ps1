<#
.SYNOPSIS
    Modulo de Limpeza Profunda do Sistema.
.DESCRIPTION
    Remove arquivos que realmente ocupam espaco no disco: Disk Cleanup completo,
    Windows.old/ResetBase, Lixeira, caches de navegadores, crash dumps, cache da
    Store, drivers antigos e analise do WinSxS. Mede o espaco liberado.
#>

. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\SecurityHelper.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\Logger.ps1"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Format-FreedSpace {
    param([double]$Gb)
    if ($Gb -lt 1) {
        return "~$([Math]::Round($Gb * 1024, 0)) MB"
    }
    return "~$([Math]::Round($Gb, 2)) GB"
}

function Test-PendingReboot {
    try {
        if (Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction SilentlyContinue) { return $true }
        if (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -Name "RebootRequired" -ErrorAction SilentlyContinue) { return $true }
        if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress") { return $true }
        if (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue) { return $true }
    } catch {}
    return $false
}

function Invoke-DiskCleanup {
    Write-Host "`n[>] Disk Cleanup completo (cleanmgr)..." -ForegroundColor Yellow
    try {
        $cleanupKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
        if (Test-Path $cleanupKey) {
            Get-ChildItem $cleanupKey | ForEach-Object {
                try { Set-ItemProperty -Path $_.PSPath -Name "StateFlags0099" -Value 2 -Force -ErrorAction SilentlyContinue } catch {}
            }
        }
        Write-Host "      [INFO] Executando cleanmgr (sagerun:99)..." -ForegroundColor Cyan
        $proc = Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:99" -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -eq 0) {
            Write-Host "      [OK] Disk Cleanup concluído." -ForegroundColor Green
        } else {
            Write-Host "      [AVISO] Disk Cleanup finalizou com codigo $($proc.ExitCode)." -ForegroundColor Yellow
        }
        Write-Log "Disk Cleanup (cleanmgr sagerun:99) concluído." "SUCCESS"
    } catch {
        Write-Host "      [ERRO] Falha no Disk Cleanup: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
        Write-Log "Falha no Disk Cleanup: $_" "ERROR"
    }
}

function Clear-RecycleBinSafe {
    Write-Host "`n[>] Esvaziando a Lixeira..." -ForegroundColor Yellow
    $before = Get-DiskFreeGB
    try {
        $shell = New-Object -ComObject Shell.Application
        $shell.NameSpace(0xa).Items() | ForEach-Object {
            try { Remove-Item -LiteralPath $_.Path -Recurse -Force -ErrorAction Stop } catch {}
        }
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null
        $after = Get-DiskFreeGB
        $freed = [Math]::Round($after - $before, 2)
        Write-Host "      [OK] Lixeira esvaziada. $(Format-FreedSpace $freed) liberado(s)." -ForegroundColor Green
        Write-Log "Lixeira esvaziada (~$freed GB)." "SUCCESS"
    } catch {
        Write-Host "      [AVISO] Nao foi possivel esvaziar a lixeira totalmente." -ForegroundColor Yellow
        Write-Log "Lixeira: limpeza parcial." "WARNING"
    }
}

function Remove-WindowsOldAndResetBase {
    Write-Host "`n[>] Windows.old + ResetBase (DISM)..." -ForegroundColor Yellow
    Write-Host "      [AVISO] Remove versoes antigas de componentes. APOS isto, atualizacoes" -ForegroundColor Red
    Write-Host "      [AVISO] NAO poderao mais ser desfeitas. Recomendado em sistema estavel." -ForegroundColor Red
    $confirm = Read-Host "      Continuar com ResetBase? (S/N)"
    if ($confirm -ne 'S' -and $confirm -ne 's') {
        Write-Host "      [INFO] ResetBase cancelado." -ForegroundColor Cyan
        return
    }

    if (Test-PendingReboot) {
        Write-Host "      [ERRO] Ha operacoes pendentes de reinicializacao no sistema." -ForegroundColor Red
        Write-Host "      [DICA] Reinicie o Windows e tente novamente." -ForegroundColor Yellow
        Write-Log "ResetBase abortado: reboot pendente." "ERROR"
        return
    }

    Write-Host "      [INFO] Verificando saude do Component Store..." -ForegroundColor Cyan
    $check = & dism /Online /Cleanup-Image /CheckHealth 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "      [AVISO] Component Store com problemas. Executando ScanHealth..." -ForegroundColor Yellow
        $scan = & dism /Online /Cleanup-Image /ScanHealth 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "      [ERRO] ScanHealth falhou. Execute 'DISM /Online /Cleanup-Image /RestoreHealth' manualmente." -ForegroundColor Red
            Write-Log "ResetBase abortado: ScanHealth falhou ($LASTEXITCODE)." "ERROR"
            return
        }
    }

    $before = Get-DiskFreeGB

    $winOld = "$env:SystemDrive\Windows.old"
    if (Test-Path $winOld) {
        Write-Host "      [INFO] Removendo Windows.old..." -ForegroundColor Cyan
        try {
            takeown /F $winOld /R /D Y 2>$null | Out-Null
            icacls $winOld /grant Administradores:F /T /Q 2>$null
            Remove-Item -Path $winOld -Recurse -Force -ErrorAction Stop
            Write-Host "      [OK] Windows.old removido." -ForegroundColor Green
        } catch {
            Write-Host "      [AVISO] Nao foi possivel remover Windows.old: $(Get-SafeErrorMessage $_)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "      [INFO] Windows.old nao encontrado." -ForegroundColor Cyan
    }

    Write-Host "      [INFO] Executando DISM StartComponentCleanup /ResetBase (pode demorar)..." -ForegroundColor Cyan
    $dismExit = -1
    try {
        $proc = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup /ResetBase" -Wait -PassThru -NoNewWindow -ErrorAction Stop
        $dismExit = $proc.ExitCode
    } catch {
        $dismExit = $_.Exception.HResult
    }

    if ($dismExit -eq 0) {
        $after = Get-DiskFreeGB
        $freed = [Math]::Round($after - $before, 2)
        Write-Host "      [OK] ResetBase concluido. $(Format-FreedSpace $freed) liberado(s)." -ForegroundColor Green
        Write-Log "DISM ResetBase concluido (~$freed GB)." "SUCCESS"
        return
    }

    if ($dismExit -eq -2146498554 -or $dismExit -eq 0x800f0806) {
        Write-Host "      [ERRO] DISM ResetBase falhou devido a operacoes pendentes (0x800f0806)." -ForegroundColor Red
        Write-Host "      [DICA] Reinicie o Windows e tente novamente." -ForegroundColor Yellow
        Write-Log "DISM ResetBase falhou (0x800f0806 - operacoes pendentes)." "ERROR"
        return
    }

    Write-Host "      [AVISO] DISM ResetBase falhou (codigo $dismExit)." -ForegroundColor Red
    Write-Host "      [INFO] Tentando StartComponentCleanup sem /ResetBase..." -ForegroundColor Cyan
    try {
        $proc2 = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup" -Wait -PassThru -NoNewWindow -ErrorAction Stop
        if ($proc2.ExitCode -eq 0) {
            $after = Get-DiskFreeGB
            $freed = [Math]::Round($after - $before, 2)
            Write-Host "      [OK] StartComponentCleanup concluido. $(Format-FreedSpace $freed) liberado(s)." -ForegroundColor Green
            Write-Log "DISM StartComponentCleanup concluido (~$freed GB)." "SUCCESS"
        } else {
            Write-Host "      [ERRO] StartComponentCleanup tambem falhou (codigo $($proc2.ExitCode))." -ForegroundColor Red
            Write-Log "DISM StartComponentCleanup falhou ($($proc2.ExitCode))." "ERROR"
        }
    } catch {
        Write-Host "      [ERRO] Falha no StartComponentCleanup: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
        Write-Log "Erro no StartComponentCleanup: $_" "ERROR"
    }
}

function Clear-BrowserCaches {
    Write-Host "`n[>] Caches de Navegadores (Edge/Chrome/Firefox)..." -ForegroundColor Yellow
    $before = Get-DiskFreeGB

    $browsers = @(
        @{ Name="Edge";    Exe="msedge";  Paths=@("$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
                                                  "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
                                                  "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Service Worker\CacheStorage",
                                                  "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Media Cache") }
        @{ Name="Chrome";  Exe="chrome";  Paths=@("$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
                                                  "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
                                                  "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Service Worker\CacheStorage",
                                                  "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Media Cache") }
        @{ Name="Firefox"; Exe="firefox"; Paths=@("$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2",
                                                  "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\thumbnails",
                                                  "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\startupCache") }
    )

    foreach ($browser in $browsers) {
        $procs = Get-Process -Name $browser.Exe -ErrorAction SilentlyContinue
        if ($procs) {
            Write-Host "      [AVISO] $($browser.Name) em execucao. Fechando para liberar caches..." -ForegroundColor Yellow
            $procs | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
        }
    }

    $totalFreed = 0
    foreach ($browser in $browsers) {
        $browserFreed = 0
        foreach ($path in $browser.Paths) {
            $resolved = Resolve-Path $path -ErrorAction SilentlyContinue
            foreach ($p in @($resolved)) {
                $size = Get-FolderSizeGB -Path $p.Path
                try {
                    Get-ChildItem -Path $p.Path -Recurse -Force -ErrorAction SilentlyContinue |
                        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    $browserFreed += $size
                } catch {}
            }
        }
        $browserFreed = [Math]::Round($browserFreed, 2)
        if ($browserFreed -gt 0) {
            Write-Host "      [OK] $($browser.Name): $(Format-FreedSpace $browserFreed)." -ForegroundColor Green
        } else {
            Write-Host "      [INFO] $($browser.Name): nada a limpar ou em uso." -ForegroundColor Cyan
        }
        $totalFreed += $browserFreed
    }

    $after = Get-DiskFreeGB
    $realFreed = [Math]::Round($after - $before, 2)
    Write-Host "      [OK] Cache de navegadores limpo. Total: $(Format-FreedSpace $realFreed)." -ForegroundColor Green
    Write-Log "Cache de navegadores limpo (~$realFreed GB)." "SUCCESS"
}

function Remove-CrashDumps {
    Write-Host "`n[>] Crash Dumps e Relatorios de Erro (WER)..." -ForegroundColor Yellow
    $before = Get-DiskFreeGB
    $dumpPaths = @(
        "$env:SystemDrive\Windows\MEMORY.DMP",
        "$env:SystemDrive\Windows\Minidump\*.dmp",
        "$env:SystemDrive\Windows\LiveKernelReports\*.dmp",
        "$env:LOCALAPPDATA\CrashDumps\*.dmp",
        "$env:ProgramData\Microsoft\Windows\WER\ReportArchive\*",
        "$env:ProgramData\Microsoft\Windows\WER\ReportQueue\*"
    )
    $removed = 0
    foreach ($pattern in $dumpPaths) {
        try {
            $items = Get-ChildItem -Path $pattern -Force -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                try { Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop; $removed++ } catch {}
            }
        } catch {}
    }
    $after = Get-DiskFreeGB
    $freed = [Math]::Round($after - $before, 2)
    Write-Host "      [OK] Crash dumps/WER limpos ($removed itens). $(Format-FreedSpace $freed) liberado(s)." -ForegroundColor Green
    Write-Log "Crash dumps/WER limpos (~$freed GB)." "SUCCESS"
}

function Clear-StoreCache {
    Write-Host "`n[>] Cache da Microsoft Store (wsreset)..." -ForegroundColor Yellow
    try {
        $proc = Start-Process -FilePath "wsreset.exe" -Wait -PassThru -NoNewWindow
        Write-Host "      [OK] Cache da Microsoft Store limpo." -ForegroundColor Green
        Write-Log "Cache da Microsoft Store limpo (wsreset)." "SUCCESS"
    } catch {
        Write-Host "      [AVISO] Falha ao limpar cache da Store: $(Get-SafeErrorMessage $_)" -ForegroundColor Yellow
        Write-Log "Falha ao limpar cache da Store." "WARNING"
    }
}

function Remove-OldDrivers {
    Write-Host "`n[>] Removendo drivers antigos/superseded..." -ForegroundColor Yellow
    $before = Get-DiskFreeGB
    try {
        $proc = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup" -Wait -PassThru -NoNewWindow
        $after = Get-DiskFreeGB
        $freed = [Math]::Round($after - $before, 2)
        if ($proc.ExitCode -eq 0) {
            Write-Host "      [OK] Limpeza de drivers antigos concluida. $(Format-FreedSpace $freed) liberado(s)." -ForegroundColor Green
            Write-Log "Limpeza de drivers antigos (~$freed GB)." "SUCCESS"
        } else {
            Write-Host "      [AVISO] Limpeza parcial (codigo $($proc.ExitCode))." -ForegroundColor Yellow
            Write-Log "Limpeza de drivers antigos parcial." "WARNING"
        }
    } catch {
        Write-Host "      [ERRO] Falha: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
    }
}

function Invoke-WinSxSAnalysis {
    Write-Host "`n[>] Analise do WinSxS (Component Store)..." -ForegroundColor Yellow
    try {
        $output = & dism /Online /Cleanup-Image /AnalyzeComponentStore 2>&1
        $output | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }
        Write-Log "Analise do Component Store executada." "INFO"
    } catch {
        Write-Host "      [ERRO] Falha na analise: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
    }
}

function Get-TempFilesReport {
    Write-Host "`n[>] Detectando arquivos temporarios..." -ForegroundColor Yellow
    $paths = @($env:TEMP, $env:TMP, "$env:WINDIR\Temp") | Select-Object -Unique
    $totalSizeBytes = 0
    $totalCount = 0
    foreach ($path in $paths) {
        if (Test-Path $path) {
            try {
                $items = Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                $count = ($items | Measure-Object).Count
                $size = ($items | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                if (-not $size) { $size = 0 }
                $totalCount += $count
                $totalSizeBytes += $size
                $sizeMB = [Math]::Round($size / 1MB, 2)
                Write-Host "      $path : $count itens, ~$sizeMB MB" -ForegroundColor White
            } catch {
                Write-Host "      [AVISO] Nao foi possivel ler $path" -ForegroundColor Yellow
            }
        }
    }
    $totalMB = [Math]::Round($totalSizeBytes / 1MB, 2)
    Write-Host "      TOTAL: $totalCount itens, ~$totalMB MB de lixo temporario detectado." -ForegroundColor Cyan
    Write-Log "Deteccao de temp: $totalCount itens, ~$totalMB MB." "INFO"
    return [PSCustomObject]@{ Count = $totalCount; SizeBytes = $totalSizeBytes; Paths = $paths }
}

function Clear-TempFilesDeep {
    Write-Host "`n[>] Limpando arquivos temporarios..." -ForegroundColor Yellow
    $paths = @($env:TEMP, $env:TMP, "$env:WINDIR\Temp") | Select-Object -Unique
    $removed = 0; $failed = 0
    foreach ($path in $paths) {
        if (Test-Path $path) {
            Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
                    $removed++
                } catch { $failed++ }
            }
        }
    }
    Write-Host "      [OK] $removed itens removidos. $failed itens em uso (ignorados)." -ForegroundColor Green
    Write-Log "Limpeza de temp: $removed removidos, $failed em uso." "SUCCESS"
}

# ---------------------------------------------------------------------------
# Funcao principal
# ---------------------------------------------------------------------------

function Invoke-DeepCleaning {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  LIMPEZA PROFUNDA DO SISTEMA" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "`nSelecione uma Opcao:" -ForegroundColor Cyan
    Write-Host "  1. Disk Cleanup completo (cleanmgr)"
    Write-Host "  2. Esvaziar Lixeira"
    Write-Host "  3. Windows.old + ResetBase (libera muito espaco)"
    Write-Host "  4. Caches de Navegadores (Edge/Chrome/Firefox)"
    Write-Host "  5. Crash Dumps e Relatorios de Erro (WER)"
    Write-Host "  6. Cache da Microsoft Store (wsreset)"
    Write-Host "  7. Limpar drivers antigos/superseded"
    Write-Host "  8. Analisar WinSxS (apenas relatorio)"
    Write-Host "  9. Detectar e Limpar Arquivos Temporarios (%TEMP%/%TMP%/Windows Temp)"
    Write-Host " 10. APLICAR TODA a Limpeza Profunda"
    Write-Host " 11. Voltar ao Menu Principal"
    Write-Host "`n========================================" -ForegroundColor Cyan

    $choice = Read-Host "Digite o numero da sua escolha"
    $choice = $choice -replace '\s+', ''

    if (-not (Test-ValidNumericInput -Value $choice -Min 1 -Max 11)) {
        Write-Host "Opcao invalida. Digite um numero entre 1 e 11." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    $runAll = $choice -eq "10"
    if ($runAll) {
        Write-Host "`n========================================" -ForegroundColor Magenta
        Write-Host "  LIMPEZA PROFUNDA COMPLETA" -ForegroundColor Magenta
        Write-Host "========================================" -ForegroundColor Magenta
    }

    $totalBefore = Get-DiskFreeGB

    if ($choice -eq "1" -or $runAll) { Invoke-DiskCleanup }
    if ($choice -eq "2" -or $runAll) { Clear-RecycleBinSafe }
    if ($choice -eq "3" -or $runAll) { Remove-WindowsOldAndResetBase }
    if ($choice -eq "4" -or $runAll) { Clear-BrowserCaches }
    if ($choice -eq "5" -or $runAll) { Remove-CrashDumps }
    if ($choice -eq "6" -or $runAll) { Clear-StoreCache }
    if ($choice -eq "7" -or $runAll) { Remove-OldDrivers }
    if ($choice -eq "8") { Invoke-WinSxSAnalysis }
    if ($choice -eq "9") { Get-TempFilesReport; Clear-TempFilesDeep }
    if ($runAll) { Clear-TempFilesDeep }

    if ($choice -ne "8" -and $choice -ne "11") {
        $totalAfter = Get-DiskFreeGB
        $totalFreed = [Math]::Round($totalAfter - $totalBefore, 2)
        Write-Host "`n========================================" -ForegroundColor Green
        Write-Host "  ESPACO TOTAL LIBERADO: $(Format-FreedSpace $totalFreed)" -ForegroundColor Green
        Write-Host "  (Antes: $totalBefore GB livres  ->  Depois: $totalAfter GB livres)" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Log "Limpeza profunda concluida: ~$totalFreed GB liberados ($totalBefore -> $totalAfter GB)." "SUCCESS"
    }

    if ($choice -eq "11") { return }
}
