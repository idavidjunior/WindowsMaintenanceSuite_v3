<#
.SYNOPSIS
    Modulo de Limpeza Profunda do Sistema.
.DESCRIPTION
    Remove arquivos que realmente ocupam espaco no disco: Disk Cleanup completo,
    Windows.old/ResetBase, Lixeira, caches de navegadores, crash dumps, cache da
    Store, drivers antigos e analise do WinSxS. Mede o espaco liberado.
#>

# Importar Core
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\SecurityHelper.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\Logger.ps1"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ---------------------------------------------------------------------------
# Funcoes de limpeza individuais (cada uma retorna bytes liberados aproximados)
# ---------------------------------------------------------------------------

function Invoke-DiskCleanup {
    Write-Host "`n[>] Disk Cleanup completo (cleanmgr)..." -ForegroundColor Yellow
    try {
        # Pré-configurar via registro todas as categorias do cleanmgr (sageset:99)
        $cleanupKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
        if (Test-Path $cleanupKey) {
            Get-ChildItem $cleanupKey | ForEach-Object {
                try { Set-ItemProperty -Path $_.PSPath -Name "StateFlags0099" -Value 2 -Force -ErrorAction SilentlyContinue } catch {}
            }
        }
        Write-Host "      [INFO] Executando cleanmgr (abra e feche se uma janela aparecer)..." -ForegroundColor Cyan
        $proc = Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:99" -Wait -PassThru -NoNewWindow
        Write-Host "      [OK] Disk Cleanup concluido." -ForegroundColor Green
        Write-Log "Disk Cleanup (cleanmgr sagerun:99) concluido." "SUCCESS"
    } catch {
        Write-Host "      [ERRO] Falha no Disk Cleanup: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
        Write-Log "Falha no Disk Cleanup: $_" "ERROR"
    }
}

function Clear-RecycleBinSafe {
    Write-Host "`n[>] Esvaziando a Lixeira..." -ForegroundColor Yellow
    $before = Get-DiskFreeGB
    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        $after = Get-DiskFreeGB
        $freed = [Math]::Round($after - $before, 2)
        Write-Host "      [OK] Lixeira esvaziada. Espaco livre: ~$freed GB liberado(s)." -ForegroundColor Green
        Write-Log "Lixeira esvaziada (~$freed GB)." "SUCCESS"
    } catch {
        Write-Host "      [AVISO] Nao foi possivel esvaziar a lixeira totalmente." -ForegroundColor Yellow
        Write-Log "Lixeira: limpeza parcial." "WARNING"
    }
}

function Remove-WindowsOldAndResetBase {
    Write-Host "`n[>] Windows.old + ResetBase (DISM)..." -ForegroundColor Yellow
    Write-Host "      [AVISO] Remove versoes antigas de componentes. APOS isto, atualizacoes" -ForegroundColor Red
    Write-Host "      [AVISO] NAO poderão mais ser desfeitas. Recomendado em sistema estavel." -ForegroundColor Red
    $confirm = Read-Host "      Continuar com ResetBase? (S/N)"
    if ($confirm -ne 'S' -and $confirm -ne 's') {
        Write-Host "      [INFO] ResetBase cancelado." -ForegroundColor Cyan
        return
    }
    $before = Get-DiskFreeGB
    try {
        # Remover Windows.old se existir
        $winOld = "$env:SystemDrive\Windows.old"
        if (Test-Path $winOld) {
            Write-Host "      [INFO] Removendo Windows.old..." -ForegroundColor Cyan
            Remove-Item -Path $winOld -Recurse -Force -ErrorAction SilentlyContinue
        }
        # ResetBase
        Write-Host "      [INFO] Executando DISM StartComponentCleanup /ResetBase (pode demorar)..." -ForegroundColor Cyan
        $proc = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup /ResetBase" -Wait -PassThru -NoNewWindow
        $after = Get-DiskFreeGB
        $freed = [Math]::Round($after - $before, 2)
        if ($proc.ExitCode -eq 0) {
            Write-Host "      [OK] ResetBase concluido. Espaco livre: ~$freed GB liberado(s)." -ForegroundColor Green
            Write-Log "DISM ResetBase concluido (~$freed GB)." "SUCCESS"
        } else {
            Write-Host "      [ERRO] DISM ResetBase falhou (codigo $($proc.ExitCode))." -ForegroundColor Red
            Write-Log "DISM ResetBase falhou (codigo $($proc.ExitCode))." "ERROR"
        }
    } catch {
        Write-Host "      [ERRO] Falha no ResetBase: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
        Write-Log "Erro no ResetBase: $_" "ERROR"
    }
}

function Clear-BrowserCaches {
    Write-Host "`n[>] Caches de Navegadores (Edge/Chrome/Firefox)..." -ForegroundColor Yellow
    $totalFreed = 0
    $before = Get-DiskFreeGB

    # Mapear pastas de cache por navegador
    $browsers = @(
        @{ Name="Edge";    Paths=@("$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
                                    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
                                    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Service Worker\CacheStorage") }
        @{ Name="Chrome";  Paths=@("$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
                                    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
                                    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Service Worker\CacheStorage") }
        @{ Name="Firefox"; Paths=@("$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2",
                                    "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\thumbnails") }
    )

    foreach ($browser in $browsers) {
        $browserFreed = 0
        foreach ($path in $browser.Paths) {
            if (Test-Path $path) {
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
        }
        $browserFreed = [Math]::Round($browserFreed, 2)
        if ($browserFreed -gt 0) {
            Write-Host "      [OK] $($browser.Name): ~$browserFreed GB liberado(s)." -ForegroundColor Green
        } else {
            Write-Host "      [INFO] $($browser.Name): nada a limpar ou em uso." -ForegroundColor Cyan
        }
        $totalFreed += $browserFreed
    }

    $after = Get-DiskFreeGB
    $realFreed = [Math]::Round($after - $before, 2)
    Write-Host "      [OK] Cache de navegadores limpo. Total: ~$realFreed GB liberado(s)." -ForegroundColor Green
    Write-Log "Cache de navegadores limpo (~$realFreed GB)." "SUCCESS"
}

function Remove-CrashDumps {
    Write-Host "`n[>] Crash Dumps e Relatorios de Erro (WER)..." -ForegroundColor Yellow
    $before = Get-DiskFreeGB
    $dumpPaths = @(
        "$env:SystemDrive\Windows\MEMORY.DMP",
        "$env:SystemDrive\Windows\Minidump",
        "$env:SystemDrive\Windows\LiveKernelReports",
        "$env:LOCALAPPDATA\CrashDumps",
        "$env:ProgramData\Microsoft\Windows\WER"
    )
    $removed = 0
    foreach ($path in $dumpPaths) {
        if (Test-Path $path) {
            try {
                $item = Get-Item $path -ErrorAction SilentlyContinue
                if ($item.PSIsContainer) {
                    Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
                        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                } else {
                    Remove-Item -Path $path -Force -ErrorAction SilentlyContinue
                }
                $removed++
            } catch {}
        }
    }
    $after = Get-DiskFreeGB
    $freed = [Math]::Round($after - $before, 2)
    Write-Host "      [OK] Crash dumps/WER limpos. Espaco livre: ~$freed GB liberado(s)." -ForegroundColor Green
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
        # DISM limpa drivers superseded do componente store
        $proc = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup" -Wait -PassThru -NoNewWindow
        $after = Get-DiskFreeGB
        $freed = [Math]::Round($after - $before, 2)
        if ($proc.ExitCode -eq 0) {
            Write-Host "      [OK] Limpeza de drivers antigos concluida. Espaco livre: ~$freed GB liberado(s)." -ForegroundColor Green
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
        $output = & dism.exe /Online /Cleanup-Image /AnalyzeComponentStore 2>&1
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
                Write-Host ("      {0}: {1} itens, {2} MB" -f $path, $count, [Math]::Round($size / 1MB, 2)) -ForegroundColor White
            } catch {
                Write-Host "      [AVISO] Nao foi possivel ler $path" -ForegroundColor Yellow
            }
        }
    }
    Write-Host ("      TOTAL: {0} itens, ~{1} MB de lixo temporario detectado." -f $totalCount, [Math]::Round($totalSizeBytes / 1MB, 2)) -ForegroundColor Cyan
    Write-Log "Deteccao de temp: $totalCount itens, ~$([Math]::Round($totalSizeBytes / 1MB, 2)) MB." "INFO"
    return [PSCustomObject]@{ Count = $totalCount; SizeBytes = $totalSizeBytes; Paths = $paths }
}

function Clear-TempFilesDeep {
    Write-Host "`n[>] Limpando arquivos temporarios..." -ForegroundColor Yellow
    $report = Get-TempFilesReport
    $removed = 0
    $failed = 0
    foreach ($path in $report.Paths) {
        if (Test-Path $path) {
            Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction Stop
                    $removed++
                } catch {
                    $failed++
                }
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
    Write-Host "`nSelecione uma opcao:" -ForegroundColor Cyan
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
    if ($choice -eq "9" -or $runAll) { Clear-TempFilesDeep }

    if ($choice -ne "8" -and $choice -ne "11") {
        $totalAfter = Get-DiskFreeGB
        $totalFreed = [Math]::Round($totalAfter - $totalBefore, 2)
        Write-Host "`n========================================" -ForegroundColor Green
        Write-Host "  ESPACO TOTAL LIBERADO: ~$totalFreed GB" -ForegroundColor Green
        Write-Host "  (Antes: $totalBefore GB livres  ->  Depois: $totalAfter GB livres)" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Log "Limpeza profunda concluida: ~$totalFreed GB liberados ($totalBefore -> $totalAfter GB)." "SUCCESS"
    }

    if ($choice -eq "11") { return }
}
