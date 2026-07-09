<#
.SYNOPSIS
    Módulo de Análise de Espaço em Disco e Programas Redundantes.
.DESCRIPTION
    Examina o sistema, lista os programas/diretórios que mais consomem
    espaço e identifica programas duplicados ou redundantes para remoção.
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

function Normalize-ProgramName {
    param([string]$Name)
    $n = $Name -replace '(?i)\s*(x64|x86|64-bit|32-bit)\s*', ''
    $n = $n -replace '(?i)\s*-\s*(Release|Update|Version|v|ver)\s*[\d.]+', ''
    $n = $n -replace '\s+', ' '
    return $n.Trim()
}

function Get-RedundantPrograms {
    Write-Host "`n[>] Examinando programas duplicados/redundantes..." -ForegroundColor Yellow
    $all = @()
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
                $prodCode = $prog.PSChildName
                $uninstallStr = $prog.UninstallString
                $size = $prog.EstimatedSize
                $installDir = $prog.InstallLocation
                $publisher = $prog.Publisher
                $version = $prog.DisplayVersion
                $all += [PSCustomObject]@{
                    Name = $name
                    Normalized = Normalize-ProgramName $name
                    Publisher = $publisher
                    ProductCode = $prodCode
                    UninstallString = $uninstallStr
                    SizeMB = if ($size) { [Math]::Round($size, 0) } else { 0 }
                    DisplayVersion = $version
                    InstallDir = $installDir
                }
            }
        }
    }

    $redundant = @()
    $groups = $all | Group-Object Normalized
    foreach ($g in $groups) {
        if ($g.Count -ge 2) {
            foreach ($item in $g.Group) {
                $redundant += [PSCustomObject]@{
                    GroupName = $g.Name
                    Name = $item.Name
                    Publisher = $item.Publisher
                    ProductCode = $item.ProductCode
                    UninstallString = $item.UninstallString
                    SizeMB = $item.SizeMB
                    DisplayVersion = $item.DisplayVersion
                    InstallDir = $item.InstallDir
                }
            }
        }
    }

    $knownPrefixes = @(
        'Microsoft Visual C\+\+',
        'Microsoft .NET',
        'Java',
        'Adobe AIR',
        'Adobe Flash',
        'Microsoft Silverlight',
        'Microsoft Office',
        'Microsoft Teams',
        'Skype',
        'Google Chrome',
        'Mozilla Firefox',
        'Mozilla Thunderbird',
        'Notepad\+\+',
        '7-Zip',
        'WinRAR',
        'WinZip',
        'Microsoft Edge',
        'Microsoft OneDrive',
        'Microsoft OneNote',
        'Microsoft Outlook',
        'Microsoft PowerPoint',
        'Microsoft Word',
        'Microsoft Excel',
        'Microsoft Access',
        'Microsoft Publisher'
    )

    $knownDups = @()
    foreach ($prefix in $knownPrefixes) {
        $matches = $all | Where-Object { $_.Name -match $prefix }
        if ($matches.Count -ge 2) {
            foreach ($m in $matches) {
                $found = $redundant | Where-Object { $_.ProductCode -eq $m.ProductCode }
                if (-not $found) {
                    $knownDups += [PSCustomObject]@{
                        GroupName = $prefix -replace '\\', ''
                        Name = $m.Name
                        Publisher = $m.Publisher
                        ProductCode = $m.ProductCode
                        UninstallString = $m.UninstallString
                        SizeMB = $m.SizeMB
                        DisplayVersion = $m.DisplayVersion
                        InstallDir = $m.InstallDir
                    }
                }
            }
        }
    }

    $merged = @()
    $seen = @{}
    foreach ($item in ($redundant + $knownDups)) {
        if (-not $seen.ContainsKey($item.ProductCode)) {
            $seen[$item.ProductCode] = $true
            $merged += $item
        }
    }

    return $merged | Sort-Object GroupName, Name
}

function Invoke-DuplicateCleaner {
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "  PROGRAMAS DUPLICADOS / REDUNDANTES" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta

    $dups = Get-RedundantPrograms
    $groups = $dups | Group-Object GroupName

    if ($groups.Count -eq 0) {
        Write-Host "`nNenhum programa duplicado ou redundante encontrado." -ForegroundColor Green
        Write-Log "Varredura de duplicados: nenhum encontrado." "INFO"
        return
    }

    $index = 1
    $flatList = @()

    Write-Host "`nGrupos de programas potencialmente redundantes:" -ForegroundColor Yellow
    Write-Host ""
    foreach ($g in $groups) {
        Write-Host "  [$($g.Count) ocorrencias] $($g.Name)" -ForegroundColor Cyan
        foreach ($item in $g.Group) {
            $sizeTag = if ($item.SizeMB -gt 0) { " ($($item.SizeMB) MB)" } else { "" }
            $verTag = if ($item.DisplayVersion) { " [v$($item.DisplayVersion)]" } else { "" }
            Write-Host "    $index. $($item.Name)$verTag$sizeTag" -ForegroundColor White
            $flatList += $item
            $index++
        }
        Write-Host ""
    }

    Write-Host "  a. Desinstalar automaticamente (mantem apenas o mais recente de cada grupo)"
    Write-Host "  d. Desinstalar programas especificos (digite os numeros)"
    Write-Host "  v. Voltar ao menu anterior"
    $choice = Read-Host "`nDigite os numeros (ex: 1,3,5) ou a/d/v"

    if ($choice -eq 'v' -or $choice -eq 'V') { return }

    if ($choice -eq 'a' -or $choice -eq 'A') {
        Invoke-AutoCleanDuplicates -Groups $groups
        return
    }

    if ($choice -eq 'd' -or $choice -eq 'D') {
        $selected = @()
        $input = Read-Host "Digite os numeros dos programas a desinstalar (separados por virgula)"
        $nums = $input -split ',' | ForEach-Object { $_.Trim() }
        foreach ($n in $nums) {
            if ($n -match '^\d+$') {
                $idx = [int]$n
                if ($idx -ge 1 -and $idx -le $flatList.Count) {
                    $selected += $flatList[$idx - 1]
                }
            }
        }
    } else {
        $selected = @()
        $nums = $choice -split ',' | ForEach-Object { $_.Trim() }
        foreach ($n in $nums) {
            if ($n -match '^\d+$') {
                $idx = [int]$n
                if ($idx -ge 1 -and $idx -le $flatList.Count) {
                    $selected += $flatList[$idx - 1]
                }
            }
        }
    }

    if ($selected.Count -eq 0) {
        Write-Host "Nenhum programa valido selecionado." -ForegroundColor Yellow
        return
    }

    Write-Host "`nProgramas selecionados para desinstalacao:" -ForegroundColor Red
    foreach ($s in $selected) {
        Write-Host "  - $($s.Name) (Codigo: $($s.ProductCode))" -ForegroundColor Yellow
    }

    $confirm = Read-Host "`nTem certeza que deseja desinstalar ESTES programas? (S/N)"
    if ($confirm -ne 'S' -and $confirm -ne 's') {
        Write-Host "Operacao cancelada." -ForegroundColor Cyan
        return
    }

    Uninstall-ProgramList -Items $selected
    Write-Host "`nProcesso de desinstalacao concluido." -ForegroundColor Green
}

function Get-VersionScore {
    param([string]$Version)
    if (-not $Version) { return @(0,0,0,0) }
    try {
        $v = [Version]$Version
        return @($v.Major, $v.Minor, $v.Build, $v.Revision)
    } catch {
        $parts = ($Version -replace '[^\d.]', '') -split '\.'
        $nums = @(0,0,0,0)
        for ($i = 0; $i -lt [Math]::Min($parts.Count, 4); $i++) {
            $n = 0; [int]::TryParse($parts[$i], [ref]$n) | Out-Null; $nums[$i] = $n
        }
        return $nums
    }
}

function Compare-VersionScores {
    param([int[]]$A, [int[]]$B)
    for ($i = 0; $i -lt 4; $i++) {
        $va = if ($i -lt $A.Length) { $A[$i] } else { 0 }
        $vb = if ($i -lt $B.Length) { $B[$i] } else { 0 }
        if ($va -gt $vb) { return 1 }
        if ($va -lt $vb) { return -1 }
    }
    return 0
}

function Test-SideBySideGroup {
    param([string]$GroupName)
    $sideBySidePatterns = @(
        '(?i)visual\s*c\+\+'
    )
    foreach ($p in $sideBySidePatterns) {
        if ($GroupName -match $p) { return $true }
    }
    return $false
}

function Invoke-AutoCleanDuplicates {
    param($Groups)

    Write-Host "`n========================================" -ForegroundColor Magenta
    Write-Host "  ANALISE AUTOMATICA DE DUPLICADOS" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta

    $toRemove = @()
    $kept = @()
    $skipped = @()

    foreach ($g in $Groups) {
        $items = $g.Group | Sort-Object { [int]($_ | Get-Member -Name SizeMB -ErrorAction SilentlyContinue) }
        if ($items.Count -lt 2) { continue }

        if (Test-SideBySideGroup -GroupName $g.Name) {
            $differentMajor = @{}
            foreach ($item in $items) {
                $score = Get-VersionScore $item.DisplayVersion
                $key = "$($score[0]).$($score[1])"
                $differentMajor[$key] = $true
            }
            if ($differentMajor.Keys.Count -ge 2) {
                $skipped += $g.Name
                continue
            }
        }

        $best = $null
        $bestScore = $null
        foreach ($item in $items) {
            $score = Get-VersionScore $item.DisplayVersion
            if (-not $best -or (Compare-VersionScores $score $bestScore) -gt 0) {
                $best = $item
                $bestScore = $score
            }
        }
        if (-not $best) { $best = $items[0] }

        $kept += $best
        foreach ($item in $items) {
            if ($item.ProductCode -ne $best.ProductCode) {
                $toRemove += $item
            }
        }
    }

    if ($toRemove.Count -eq 0) {
        Write-Host "`nNenhum item redundante para remover apos analise." -ForegroundColor Green
        return
    }

    if ($skipped.Count -gt 0) {
        Write-Host "`nGrupos ignorados (versoes side-by-side mantidas):" -ForegroundColor Cyan
        foreach ($s in $skipped) {
            Write-Host "  - $s" -ForegroundColor Gray
        }
    }

    Write-Host "`nItens que SERAO MANTIDOS (1 por grupo):" -ForegroundColor Green
    foreach ($k in $kept) {
        $ver = if ($k.DisplayVersion) { " v$($k.DisplayVersion)" } else { "" }
        Write-Host "  [KEEP] $($k.Name)$ver" -ForegroundColor Green
    }

    Write-Host "`nItens que SERAO REMOVIDOS:" -ForegroundColor Red
    $totalMB = 0
    foreach ($r in $toRemove) {
        $ver = if ($r.DisplayVersion) { " v$($r.DisplayVersion)" } else { "" }
        Write-Host "  [DEL]  $($r.Name)$ver ($($r.SizeMB) MB)" -ForegroundColor Yellow
        $totalMB += $r.SizeMB
    }
    Write-Host "`nTotal estimado a liberar: $totalMB MB" -ForegroundColor White

    $confirm = Read-Host "`nDeseja desinstalar TODOS estes programas? (S/N)"
    if ($confirm -ne 'S' -and $confirm -ne 's') {
        Write-Host "Operacao cancelada." -ForegroundColor Cyan
        return
    }

    Uninstall-ProgramList -Items $toRemove
    Write-Host "`nLimpeza automatica de duplicados concluida." -ForegroundColor Green
}

function Uninstall-ProgramList {
    param($Items)
    foreach ($s in $Items) {
        Write-Host "`n[>] Desinstalando: $($s.Name)..." -ForegroundColor Yellow
        try {
            $uninst = $s.UninstallString
            if ($uninst -and $uninst -match 'msiexec') {
                $prodCode = $s.ProductCode
                if ($prodCode -and $prodCode -match '^\{') {
                    $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $prodCode /quiet /norestart" -Wait -PassThru -NoNewWindow
                    if ($proc.ExitCode -eq 0) {
                        Write-Host "      [OK] $($s.Name) desinstalado com sucesso." -ForegroundColor Green
                        Write-Log "Desinstalado: $($s.Name)" "SUCCESS"
                    } else {
                        Write-Host "      [AVISO] Codigo de saida: $($proc.ExitCode). Pode ser necessario reboot." -ForegroundColor Yellow
                        Write-Log "Desinstalacao de $($s.Name) retornou codigo $($proc.ExitCode)." "WARNING"
                    }
                }
            } elseif ($uninst) {
                $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $uninst /quiet /norestart" -Wait -PassThru -NoNewWindow
                Write-Host "      [INFO] Comando de desinstalacao executado para $($s.Name)." -ForegroundColor Cyan
                Write-Log "Desinstalacao iniciada: $($s.Name)" "INFO"
            } else {
                Write-Host "      [ERRO] Nenhum comando de desinstalacao encontrado para $($s.Name)." -ForegroundColor Red
                Write-Log "Falha ao desinstalar $($s.Name): sem UninstallString." "ERROR"
            }
        } catch {
            Write-Host "      [ERRO] Falha ao desinstalar $($s.Name): $(Get-SafeErrorMessage $_)" -ForegroundColor Red
            Write-Log "Erro ao desinstalar $($s.Name): $_" "ERROR"
        }
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
    Write-Host "  5. Programas Duplicados / Redundantes"
    Write-Host "  6. Analise Completa (todas as anteriores)"
    Write-Host "  7. Voltar ao Menu Principal"
    Write-Host "`n========================================" -ForegroundColor Cyan

    $choice = Read-Host "Digite o numero da sua escolha"
    $choice = $choice -replace '\s+', ''

    if (-not (Test-ValidNumericInput -Value $choice -Min 1 -Max 7)) {
        Write-Host "Opção inválida. Digite um numero entre 1 e 7." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    if ($choice -eq "7") { return }
    if ($choice -eq "5") { Invoke-DuplicateCleaner; return }

    $runAll = $choice -eq "6"

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

    if ($runAll) {
        Write-Host "`n[>] Incluindo varredura de programas duplicados..." -ForegroundColor Cyan
        Invoke-DuplicateCleaner
    }

    $totalDisk = Get-DiskFreeGB
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  ESPACO LIVRE NO DISCO C:: $totalDisk GB" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Log "Analisador de espaco concluido. Disco C: com $totalDisk GB livres." "INFO"
}

Export-ModuleMember -Function *
