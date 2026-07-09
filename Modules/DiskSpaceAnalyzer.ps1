<#
.SYNOPSIS
    Módulo de Análise de Espaço em Disco.
.DESCRIPTION
    Examina o sistema e lista os programas e diretórios que mais consomem
    espaço no disco, auxiliando na identificação de grandes consumidores.
#>

. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\Logger.ps1"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Get-InstalledProgramsInfo {
    Write-Host "`n[>] Coletando programas instalados..." -ForegroundColor Yellow
    $results = @()
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $programs = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
            foreach ($prog in $programs) {
                $name = $prog.DisplayName
                if (-not $name) { continue }
                $size = $prog.EstimatedSize
                $installDir = $prog.InstallLocation
                if ($size) {
                    $sizeMB = [Math]::Round($size, 0)
                    if ($sizeMB -gt 100) {
                        $results += [PSCustomObject]@{
                            Name = $name
                            SizeMB = $sizeMB
                            InstallDir = $installDir
                        }
                    }
                }
            }
        }
    }
    return $results | Sort-Object SizeMB -Descending
}

function Get-TopFolderSizes {
    param([string]$Path, [int]$Top = 15)
    try {
        if (-not (Test-Path $Path)) { return @() }
        $folders = Get-ChildItem -Path $Path -Directory -Force -ErrorAction SilentlyContinue
        $results = @()
        foreach ($f in $folders) {
            $size = (Get-ChildItem -Path $f.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                     Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            if (-not $size) { $size = 0 }
            $sizeMB = [Math]::Round($size / 1MB, 0)
            if ($sizeMB -gt 50) {
                $results += [PSCustomObject]@{
                    Name = $f.Name
                    Path = $f.FullName
                    SizeMB = $sizeMB
                }
            }
        }
        return $results | Sort-Object SizeMB -Descending | Select-Object -First $Top
    } catch {
        return @()
    }
}

function Invoke-DiskSpaceAnalyzer {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  ANALISADOR DE ESPACO EM DISCO" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "`nSelecione uma Opção:" -ForegroundColor Cyan
    Write-Host "  1. Programas Instalados (maiores que 100 MB)"
    Write-Host "  2. Pastas em C:\Program Files"
    Write-Host "  3. Pastas em C:\Program Files (x86)"
    Write-Host "  4. Pastas em C:\Users (perfis de usuario)"
    Write-Host "  5. Analise Completa (todas as categorias acima)"
    Write-Host "  6. Voltar ao Menu Principal"
    Write-Host "`n========================================" -ForegroundColor Cyan

    $choice = Read-Host "Digite o numero da sua escolha"
    $choice = $choice -replace '\s+', ''

    if (-not (Test-ValidNumericInput -Value $choice -Min 1 -Max 6)) {
        Write-Host "Opção inválida. Digite um numero entre 1 e 6." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    if ($choice -eq "6") { return }

    $runAll = $choice -eq "5"

    if ($runAll) {
        Write-Host "`n========================================" -ForegroundColor Magenta
        Write-Host "  ANALISE COMPLETA DE ESPACO" -ForegroundColor Magenta
        Write-Host "========================================" -ForegroundColor Magenta
    }

    if ($choice -eq "1" -or $runAll) {
        $progs = Get-InstalledProgramsInfo
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  TOP PROGRAMAS INSTALADOS (por tamanho)" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        if ($progs.Count -eq 0) {
            Write-Host "  Nenhum programa com tamanho estimado > 100 MB encontrado." -ForegroundColor Yellow
        } else {
            Write-Host ("  {0,-50} {1,10}" -f "Programa", "Tamanho (MB)") -ForegroundColor White
            Write-Host ("  {0,-50} {1,10}" -f ("-"*50), ("-"*10)) -ForegroundColor Gray
            $total = 0
            foreach ($p in $progs) {
                $color = if ($p.SizeMB -gt 1000) { "Red" } elseif ($p.SizeMB -gt 500) { "Yellow" } else { "Green" }
                Write-Host ("  {0,-50} {1,10} MB" -f $p.Name, $p.SizeMB) -ForegroundColor $color
                $total += $p.SizeMB
            }
            Write-Host ("  {0,-50} {1,10}" -f ("-"*50), ("-"*10)) -ForegroundColor Gray
            Write-Host ("  {0,-50} {1,10} MB" -f "TOTAL", $total) -ForegroundColor White
        }
        Write-Log "Analise de programas instalados concluida: $($progs.Count) programas listados." "INFO"
    }

    if ($choice -eq "2" -or $runAll) {
        $folders = Get-TopFolderSizes -Path "$env:SystemDrive\Program Files" -Top 15
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  TOP PASTAS EM PROGRAM FILES" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        if ($folders.Count -eq 0) {
            Write-Host "  Nenhuma pasta significativa encontrada (> 50 MB)." -ForegroundColor Yellow
        } else {
            Write-Host ("  {0,-40} {1,12}" -f "Pasta", "Tamanho (MB)") -ForegroundColor White
            Write-Host ("  {0,-40} {1,12}" -f ("-"*40), ("-"*12)) -ForegroundColor Gray
            foreach ($f in $folders) {
                $color = if ($f.SizeMB -gt 2000) { "Red" } elseif ($f.SizeMB -gt 500) { "Yellow" } else { "Green" }
                Write-Host ("  {0,-40} {1,12} MB" -f $f.Name, $f.SizeMB) -ForegroundColor $color
            }
        }
    }

    if ($choice -eq "3" -or $runAll) {
        $pfx86 = "$env:SystemDrive\Program Files (x86)"
        if (Test-Path $pfx86) {
            $folders = Get-TopFolderSizes -Path $pfx86 -Top 15
            Write-Host "`n========================================" -ForegroundColor Cyan
            Write-Host "  TOP PASTAS EM PROGRAM FILES (x86)" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan
            if ($folders.Count -eq 0) {
                Write-Host "  Nenhuma pasta significativa encontrada (> 50 MB)." -ForegroundColor Yellow
            } else {
                Write-Host ("  {0,-40} {1,12}" -f "Pasta", "Tamanho (MB)") -ForegroundColor White
                Write-Host ("  {0,-40} {1,12}" -f ("-"*40), ("-"*12)) -ForegroundColor Gray
                foreach ($f in $folders) {
                    $color = if ($f.SizeMB -gt 2000) { "Red" } elseif ($f.SizeMB -gt 500) { "Yellow" } else { "Green" }
                    Write-Host ("  {0,-40} {1,12} MB" -f $f.Name, $f.SizeMB) -ForegroundColor $color
                }
            }
        } else {
            Write-Host "`n[INFO] Program Files (x86) nao encontrado neste sistema." -ForegroundColor Cyan
        }
    }

    if ($choice -eq "4" -or $runAll) {
        $usersPath = "$env:SystemDrive\Users"
        $userFolders = Get-ChildItem -Path $usersPath -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') }
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  PERFIS DE USUARIO (C:\Users)" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        if ($userFolders.Count -eq 0) {
            Write-Host "  Nenhum perfil encontrado." -ForegroundColor Yellow
        } else {
            Write-Host ("  {0,-25} {1,12}" -f "Usuario", "Tamanho (MB)") -ForegroundColor White
            Write-Host ("  {0,-25} {1,12}" -f ("-"*25), ("-"*12)) -ForegroundColor Gray
            $userResults = @()
            foreach ($u in $userFolders) {
                $sizeMB = [Math]::Round(((Get-ChildItem -Path $u.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum) / 1MB, 0)
                if (-not $sizeMB) { $sizeMB = 0 }
                $userResults += [PSCustomObject]@{ Name = $u.Name; SizeMB = $sizeMB }
            }
            $userResults = $userResults | Sort-Object SizeMB -Descending
            foreach ($u in $userResults) {
                $color = if ($u.SizeMB -gt 50000) { "Red" } elseif ($u.SizeMB -gt 10000) { "Yellow" } else { "Green" }
                Write-Host ("  {0,-25} {1,12} MB" -f $u.Name, $u.SizeMB) -ForegroundColor $color
            }
        }
    }

    $totalDisk = Get-DiskFreeGB
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  ESPACO LIVRE NO DISCO C:: $totalDisk GB" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Log "Analisador de espaco concluido. Disco C: com $totalDisk GB livres." "INFO"
}

Export-ModuleMember -Function *
