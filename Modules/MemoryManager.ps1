. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\Logger.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\SecurityHelper.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\ConfigManager.ps1"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Get-MemoryStatus {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  STATUS DA MEMORIA RAM" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if (-not $os) { throw "Falha ao consultar Win32_OperatingSystem" }
        $totalGB = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $freeGB  = [Math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $usedGB  = [Math]::Round($totalGB - $freeGB, 2)
        $pct     = [Math]::Round(($usedGB / $totalGB) * 100, 1)

        $color = if ($pct -lt 50) { 'Green' } elseif ($pct -lt 80) { 'Yellow' } else { 'Red' }
        $bar = ''.PadLeft([Math]::Min(40, [int]($pct / 2.5)), '#').PadRight(40, ' ')

        Write-Host "`n      Total : $totalGB GB" -ForegroundColor White
        Write-Host "      Usado  : $usedGB GB" -ForegroundColor $color
        Write-Host "      Livre  : $freeGB GB" -ForegroundColor Green
        Write-Host ("      Uso    : " + $pct + "% " + $bar + " [" + $pct + "%]") -ForegroundColor $color

        $procs = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 8
        Write-Host "`n   -- Top 8 processos por uso de RAM --" -ForegroundColor Yellow
        foreach ($p in $procs) {
            $mb = [Math]::Round($p.WorkingSet64 / 1MB, 1)
            Write-Host ("      " + $p.ProcessName + " (" + $mb + " MB)") -ForegroundColor White
        }

        $slots = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
        if ($slots) {
            Write-Host "`n   -- Modulos Fisicos --" -ForegroundColor Yellow
            $i = 0
            foreach ($s in $slots) {
                $gb = [Math]::Round($s.Capacity / 1GB, 1)
                $speed = if ($s.ConfiguredClockSpeed) { $s.ConfiguredClockSpeed } else { $s.Speed }
                Write-Host ("      Slot " + $i + " : " + $gb + " GB " + $speed + " MHz - " + $s.Manufacturer) -ForegroundColor White
                $i++
            }
        }

        $pf = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pf) {
            $pfGB = [Math]::Round($pf.AllocatedBaseSize / 1GB, 2)
            Write-Host "`n      Pagefile: $pfGB GB" -ForegroundColor White
            Write-Host ("      Pico de uso: " + $pf.PeakUsage + "%") -ForegroundColor White
        }

        Write-Log ("Status de memoria: " + $usedGB + " GB / " + $totalGB + " GB (" + $pct + "%)") "INFO"
    } catch {
        Write-Host ("  [ERRO] " + $_.Exception.Message) -ForegroundColor Red
        Write-Log ("Falha ao obter status de memoria: " + $_) "WARNING"
    }
}

function Clear-MemoryCache {
    param([switch]$DryRun)

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  LIMPEZA DE MEMORIA RAM" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if (-not $os) { Write-Host "  [ERRO] Nao foi possivel consultar o sistema." -ForegroundColor Red; return }

    $totalGB = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeBefore = [Math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $pctBefore = [Math]::Round((($totalGB - $freeBefore) / $totalGB) * 100, 1)

    Write-Host ("`n  Antes: " + $freeBefore + " GB livre (" + $pctBefore + "% usado)") -ForegroundColor Yellow

    $freed = 0.0
    $skip = @('Idle', 'System', 'Registry', 'Memory Compression', 'Secure System', 'csrss', 'winlogon', 'smss', 'services', 'lsass', 'svchost')

    Write-Host "`n  [1/3] Esvaziando working set de processos nao criticos..." -ForegroundColor Cyan
    $procs = Get-Process | Where-Object { -not ($skip -contains $_.ProcessName) -and $_.WorkingSet64 -gt 5MB -and $_.Id -gt 4 }
    $count = 0
    foreach ($p in $procs) {
        try {
            if (-not $DryRun) {
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
                if ($p.Handle) { $p.Refresh() }
            }
            $freed += $p.WorkingSet64 / 1MB
            $count++
        } catch {}
    }
    Write-Host ("      " + $count + " processos processados.") -ForegroundColor White

    Write-Host "  [2/3] Forcando coleta de lixo .NET..." -ForegroundColor Cyan
    if (-not $DryRun) {
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        [System.GC]::Collect()
    }

    Write-Host "  [3/3] Liberando caches do sistema..." -ForegroundColor Cyan
    if (-not $DryRun) {
        try { Clear-DnsClientCache -ErrorAction SilentlyContinue } catch {}
        $procs2 = Get-Process | Where-Object { $_.WorkingSet64 -gt 50MB -and -not ($skip -contains $_.ProcessName) -and $_.Id -gt 4 }
        foreach ($p2 in $procs2) { try { $p2.Refresh() } catch {} }
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    }

    $os2 = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $freeAfter = if ($os2) { [Math]::Round($os2.FreePhysicalMemory / 1MB, 2) } else { $freeBefore }
    $pctAfter = [Math]::Round((($totalGB - $freeAfter) / $totalGB) * 100, 1)
    $diff = [Math]::Round($freeAfter - $freeBefore, 2)

    if ($DryRun) {
        Write-Host "`n  [DRY-RUN] Nenhuma alteracao real foi feita." -ForegroundColor Yellow
        Write-Host ("  Depois (estimado): " + $freeAfter + " GB livre (" + $pctAfter + "% usado, +" + $diff + " GB)") -ForegroundColor Green
    } else {
        $color = if ($diff -gt 0.5) { 'Green' } elseif ($diff -gt 0.1) { 'Yellow' } else { 'White' }
        Write-Host ("`n  Depois: " + $freeAfter + " GB livre (" + $pctAfter + "% usado)") -ForegroundColor Green
        Write-Host ("  Liberado: +" + $diff + " GB") -ForegroundColor $color
        Write-Log ("Limpeza de RAM: +" + $diff + " GB liberados (" + $pctBefore + "% -> " + $pctAfter + "%)") "SUCCESS"
    }
}

function Watch-MemoryUsage {
    param([int]$Interval = 3)

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  MONITOR DE MEMORIA EM TEMPO REAL" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ("  Atualizando a cada " + $Interval + " segundos. Pressione Q para sair.") -ForegroundColor DarkGray

    $lastKey = ""
    try {
        do {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
            if ($os) {
                $totalGB = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
                $freeGB  = [Math]::Round($os.FreePhysicalMemory / 1MB, 2)
                $usedGB  = [Math]::Round($totalGB - $freeGB, 2)
                $pct     = [Math]::Round(($usedGB / $totalGB) * 100, 1)
                $color = if ($pct -lt 50) { 'Green' } elseif ($pct -lt 80) { 'Yellow' } else { 'Red' }

                $procs = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5
                $topKey = ""
                foreach ($p in $procs) { $topKey += $p.Id.ToString() + ":" }

                if ($topKey -ne $lastKey) {
                    Clear-Host
                    $now = Get-Date -Format "HH:mm:ss"
                    Write-Host "========================================" -ForegroundColor Cyan
                    Write-Host "  MONITOR DE MEMORIA EM TEMPO REAL" -ForegroundColor Cyan
                    Write-Host "========================================" -ForegroundColor Cyan
                    Write-Host ($now + " | Total: " + $totalGB + " GB | Usado: " + $usedGB + " GB | Livre: " + $freeGB + " GB") -ForegroundColor White
                    $barCount = [Math]::Max(1, [int]($pct / 2))
                    $filled = ''.PadLeft($barCount, '#')
                    $empty = ''.PadLeft(50 - $barCount, '-')
                    Write-Host ("  " + $filled + $empty + " " + $pct + "%") -ForegroundColor $color
                    Write-Host "`n  Top 5 processos:" -ForegroundColor Yellow
                    foreach ($p in $procs) {
                        $mb = [Math]::Round($p.WorkingSet64 / 1MB, 1)
                        Write-Host ("    " + $p.ProcessName.PadRight(25) + " " + $mb.ToString().PadLeft(8) + " MB") -ForegroundColor White
                    }
                    Write-Host "`n  [Pressione Q para sair]" -ForegroundColor DarkGray
                    $lastKey = $topKey
                }
            }

            $remaining = $Interval
            do {
                if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    if ($key.KeyChar -eq 'q' -or $key.KeyChar -eq 'Q') { return }
                }
                Start-Sleep -Milliseconds 200
                $remaining -= 0.2
            } while ($remaining -gt 0)

        } while ($true)
    } finally {
        Write-Host "`nMonitor encerrado." -ForegroundColor Green
    }
}

function Invoke-MemoryManager {
    do {
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  GERENCIADOR DE MEMORIA RAM" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  1. Status da Memoria (relatorio completo)"
        Write-Host "  2. Limpeza de Memoria (libera RAM de forma segura)"
        Write-Host "  3. Monitor em Tempo Real (atualizacao continua)"
        Write-Host "  4. Simulacao (Dry-Run) - Mostra o que seria limpo"
        Write-Host "  V. Voltar"
        Write-Host "========================================" -ForegroundColor Cyan

        $choice = Read-Host "Digite sua escolha"
        $choice = $choice -replace '\s+', ''

        if ($choice -eq 'V' -or $choice -eq 'v') { return }

        switch ($choice) {
            "1" { Get-MemoryStatus }
            "2" {
                Write-Host "`n[AVISO] A limpeza de memoria vai liberar RAM reduzindo o cache do sistema." -ForegroundColor Yellow
                Write-Host "  O sistema pode ficar momentaneamente mais lento ate o cache ser refeito." -ForegroundColor DarkGray
                $confirm = Read-Host "Continuar? (S/N)"
                if ($confirm -match '^[Ss]') { Clear-MemoryCache }
                else { Write-Host "  Cancelado." -ForegroundColor Yellow }
            }
            "3" { Watch-MemoryUsage }
            "4" { Clear-MemoryCache -DryRun }
            default { Write-Host "Opcao invalida." -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    } while ($true)
}
