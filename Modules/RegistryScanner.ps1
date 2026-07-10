. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\SecurityHelper.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\Logger.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\ConfigManager.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\Winapp2Parser.ps1"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$script:RegistryScanConfig = $null
$script:PathCache = @{}

function Get-RegistryScanConfig {
    if (-not $script:RegistryScanConfig) {
        $cfg = Get-WMSConfig
        $script:RegistryScanConfig = @{
            ExcludePaths    = if ($cfg.RegistryExclude) { @($cfg.RegistryExclude) } else { @() }
            UseWinapp2      = if ($cfg.UseWinapp2) { $true } else { $false }
            MaxParallelism  = [Math]::Max(1, [Environment]::ProcessorCount)
            BackupEnabled   = $true
        }
    }
    $script:RegistryScanConfig
}

function Add-ExcludedPath {
    param([string]$Path)
    $cfg = Get-RegistryScanConfig
    if (-not ($cfg.ExcludePaths -contains $Path)) {
        $cfg.ExcludePaths += $Path
    }
}

function Test-ExcludedPath {
    param([string]$Path)
    $cfg = Get-RegistryScanConfig
    foreach ($ex in $cfg.ExcludePaths) {
        if ($Path -like $ex) { return $true }
    }
    foreach ($safe in $global:WMSSafeHives) {
        if ($Path -like "$safe*") { return $false }
    }
    return $false
}

function Clear-PathCache {
    param([switch]$Force)
    if ($Force -or $script:PathCache.Count -gt 50000) {
        $script:PathCache = @{}
    }
}

function Test-PathCached {
    param([string]$Path)
    if ($script:PathCache.ContainsKey($Path)) { return $script:PathCache[$Path] }
    $result = Test-Path -Path $Path -ErrorAction SilentlyContinue
    $script:PathCache[$Path] = $result
    if ($script:PathCache.Count -gt 50000) { Clear-PathCache }
    return $result
}

function Get-RegistryValueSize {
    param([string]$KeyPath, [string]$ValueName)
    try {
        $props = Get-ItemProperty -Path $KeyPath -Name $ValueName -ErrorAction SilentlyContinue
        if ($props) {
            $val = $props.$ValueName
            if ($val -is [byte[]]) { return $val.Length }
            if ($val -is [string]) { return [System.Text.Encoding]::UTF8.GetByteCount($val) * 2 }
            return 8
        }
    } catch {}
    return 0
}

function Get-RegistryKeySize {
    param([string]$KeyPath)
    $total = 0
    try {
        $props = Get-ItemProperty -Path $KeyPath -ErrorAction SilentlyContinue
        if ($props) {
            foreach ($prop in $props.PSObject.Properties) {
                if ($prop.Name -like "PS*") { continue }
                $total += Get-RegistryValueSize -KeyPath $KeyPath -ValueName $prop.Name
            }
        }
        $subKeys = Get-ChildItem -Path $KeyPath -ErrorAction SilentlyContinue
        foreach ($sub in $subKeys) {
            $total += Get-RegistryKeySize -KeyPath $sub.PSPath
        }
    } catch {}
    return $total
}

$global:WMSSafeHives = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SharedDLLs',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
    'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
    'HKLM:\SOFTWARE\Classes\*\ShellEx',
    'HKLM:\SOFTWARE\Classes\Directory\ShellEx',
    'HKLM:\SOFTWARE\Classes\Drive\ShellEx'
)

function Get-RegistryScanCategories {
    param([string]$RiskLevel = "all")

    $safeCategories = @(
        @{
            Name       = "Entradas de Desinstalação Órfãs"
            Risk       = "Segura"
            Description = "Chaves de desinstalação cujo programa foi removido manualmente"
            Hives      = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
                "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
                "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
            )
            Check = {
                param($key)
                $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
                if (-not $props) { return $false }
                $pathToCheck = $null
                if ($props.InstallLocation) { $pathToCheck = $props.InstallLocation }
                elseif ($props.UninstallString) {
                    $exe = ($props.UninstallString -replace '"', '') -split ' ' | Select-Object -First 1
                    $pathToCheck = $exe
                }
                if (-not $pathToCheck) { return $false }
                return (-not (Test-PathCached -Path $pathToCheck))
            }
        },
        @{
            Name       = "SharedDLLs Quebradas"
            Risk       = "Segura"
            Description = "Referências a DLLs que não existem mais no disco"
            Hives      = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SharedDLLs")
            IsValueScan = $true
            Check = {
                param($valuePath)
                return (-not (Test-PathCached -Path $valuePath))
            }
        },
        @{
            Name       = "App Paths Quebrados"
            Risk       = "Segura"
            Description = "Atalhos de aplicativos cujo executável foi removido"
            Hives      = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths")
            Check = {
                param($key)
                $default = (Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue).'(default)'
                if (-not $default) { return $false }
                return (-not (Test-PathCached -Path $default))
            }
        },
        @{
            Name       = "MUICache Obsoleto"
            Risk       = "Segura"
            Description = "Cache de nomes amigáveis de programas já removidos"
            Hives      = @("HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache")
            IsValueScan = $true
            ValueNameIsPath = $true
            Check = {
                param($valuePath)
                $clean = $valuePath -replace '\.FriendlyAppName$', '' -replace '\.ApplicationCompany$', ''
                return (-not (Test-PathCached -Path $clean))
            }
        },
        @{
            Name       = "Run / RunOnce Órfãos"
            Risk       = "Segura"
            Description = "Entradas de inicialização apontando para programas deletados"
            Hives      = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
                "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
                "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
            )
            IsValueScan = $true
            Check = {
                param($valuePath)
                if ([string]::IsNullOrWhiteSpace($valuePath)) { return $false }
                $cmd = $valuePath.Trim()
                if ($cmd.StartsWith('"')) { $cmd = $cmd.TrimStart('"'); $end = $cmd.IndexOf('"'); if ($end -gt 0) { $cmd = $cmd.Substring(0, $end) } }
                else { $cmd = $cmd.Split(' ')[0] }
                if ([string]::IsNullOrWhiteSpace($cmd)) { return $false }
                return (-not (Test-PathCached -Path $cmd))
            }
        },
        @{
            Name       = "Fontes Não Instaladas"
            Risk       = "Segura"
            Description = "Registros de fontes cujo arquivo .ttf/.otf foi deletado"
            Hives      = @("HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts")
            IsValueScan = $true
            Check = {
                param($fontFile)
                $fontsDir = [Environment]::GetFolderPath('Fonts')
                $full = Join-Path $fontsDir $fontFile
                return (-not (Test-PathCached -Path $full))
            }
        },
        @{
            Name       = "Extensões de Shell Órfãs"
            Risk       = "Segura"
            Description = "Extensões de shell do Explorer cujo CLSID não existe mais"
            Hives      = @(
                "HKLM:\SOFTWARE\Classes\*\ShellEx",
                "HKLM:\SOFTWARE\Classes\Directory\ShellEx",
                "HKLM:\SOFTWARE\Classes\Drive\ShellEx"
            )
            Check = {
                param($key)
                $clsid = (Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue).'(default)'
                if (-not $clsid) { return $false }
                return (-not (Test-PathCached -Path "HKCR:\CLSID\$clsid"))
            }
        }
    )

    $moderateCategories = @(
        @{
            Name       = "CLSID/COM Órfãos"
            Risk       = "Moderada"
            Description = "Componentes COM cujo arquivo de implementação foi removido"
            Hives      = @(
                "HKLM:\SOFTWARE\Classes\CLSID",
                "HKCR:\CLSID"
            )
            Check = {
                param($key)
                $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
                if (-not $props) { return $false }
                $dllPath = $null
                if ($props.'(default)' -and $props.'(default)' -match '\.(dll|exe|ocx)$') { $dllPath = $props.'(default)' }
                $inproc = $props.InprocServer32
                if ($inproc -and (Test-Path $inproc -ErrorAction SilentlyContinue)) { return $false }
                $localserver = $props.LocalServer32
                if ($localserver -and (Test-Path $localserver -ErrorAction SilentlyContinue)) { return $false }
                if ($dllPath) { return (-not (Test-PathCached -Path $dllPath)) }
                return $false
            }
            RequiresBackup = $true
        },
        @{
            Name       = "TypeLibs Perdidas"
            Risk       = "Moderada"
            Description = "Bibliotecas de tipo (TypeLib) referenciando arquivos ausentes"
            Hives      = @(
                "HKLM:\SOFTWARE\Classes\TypeLib",
                "HKCR:\TypeLib"
            )
            Check = {
                param($key)
                $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
                if (-not $props) { return $false }
                $subs = Get-ChildItem -Path $key.PSPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d+\.\d+$' }
                foreach ($sub in $subs) {
                    $flags = Get-ItemProperty -Path $sub.PSPath -ErrorAction SilentlyContinue
                    if ($flags -and $flags.'(default)') {
                        $path = $flags.'(default)'
                        if ($path -match '\.(dll|ocx|exe)$' -and (-not (Test-PathCached -Path $path))) { return $true }
                    }
                    $win64 = Get-ChildItem -Path $sub.PSPath -Filter "Win64" -ErrorAction SilentlyContinue
                    foreach ($w in $win64) {
                        $wp = (Get-ItemProperty -Path $w.PSPath -ErrorAction SilentlyContinue).'(default)'
                        if ($wp -and (-not (Test-PathCached -Path $wp))) { return $true }
                    }
                    $win32 = Get-ChildItem -Path $sub.PSPath -Filter "Win32" -ErrorAction SilentlyContinue
                    foreach ($w in $win32) {
                        $wp = (Get-ItemProperty -Path $w.PSPath -ErrorAction SilentlyContinue).'(default)'
                        if ($wp -and (-not (Test-PathCached -Path $wp))) { return $true }
                    }
                }
                return $false
            }
            RequiresBackup = $true
        },
        @{
            Name       = "Installer Components Órfãos"
            Risk       = "Moderada"
            Description = "Componentes do Windows Installer referenciando arquivos removidos"
            Hives      = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\Components",
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components"
            )
            Check = {
                param($key)
                $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
                if (-not $props) { return $false }
                foreach ($prop in $props.PSObject.Properties) {
                    if ($prop.Name -like "PS*") { continue }
                    if ($prop.Value -match '^[a-zA-Z]:\\') {
                        return (-not (Test-PathCached -Path $prop.Value))
                    }
                }
                return $false
            }
            RequiresBackup = $true
        },
        @{
            Name       = "OpenWith Lists Órfãos"
            Risk       = "Segura"
            Description = "Programas listados no 'Abrir com' que foram desinstalados"
            Hives      = @(
                "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts",
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts"
            )
            Check = {
                param($key)
                $openWith = Get-ChildItem -Path $key.PSPath -Filter "OpenWithList" -ErrorAction SilentlyContinue
                if (-not $openWith) { return $false }
                foreach ($ow in $openWith) {
                    $props = Get-ItemProperty -Path $ow.PSPath -ErrorAction SilentlyContinue
                    if (-not $props) { continue }
                    foreach ($prop in $props.PSObject.Properties) {
                        if ($prop.Name -like "PS*" -or $prop.Name -eq "MRUListEx") { continue }
                        if ($prop.Value -and $prop.Value -match '\.exe$') {
                            if (-not (Test-PathCached -Path $prop.Value)) { return $true }
                        }
                    }
                }
                return $false
            }
        },
        @{
            Name       = "Protocol Handlers Órfãos"
            Risk       = "Moderada"
            Description = "Handlers de URL/protocolo personalizados de apps removidos"
            Hives      = @("HKCR:\PROTOCOLS\Handler")
            PreCheck = {
                if (-not (Test-Path "HKCR:\PROTOCOLS\Handler" -ErrorAction SilentlyContinue)) { return @() }
                $handlers = Get-ChildItem "HKCR:\PROTOCOLS\Handler" -ErrorAction SilentlyContinue
                $result = @()
                foreach ($h in $handlers) {
                    $clsid = (Get-ItemProperty -Path $h.PSPath -ErrorAction SilentlyContinue).CLSID
                    if ($clsid) {
                        $clsidPath = "HKCR:\CLSID\$clsid"
                        if (-not (Test-PathCached -Path $clsidPath)) {
                            $result += @{ KeyPath = $h.PSPath; ValueName = $null; Detail = $h.PSChildName }
                        }
                    }
                }
                return $result
            }
            CustomScan = $true
        }
    )

    $advancedCategories = @(
        @{
            Name       = "Context Menu Handlers Órfãos"
            Risk       = "Avançada"
            Description = "Handlers de menu de contexto cujo CLSID não existe"
            Hives      = @(
                "HKLM:\SOFTWARE\Classes\*\shellex\ContextMenuHandlers",
                "HKLM:\SOFTWARE\Classes\AllFileSystemObjects\shellex\ContextMenuHandlers",
                "HKCU:\SOFTWARE\Classes\*\shellex\ContextMenuHandlers"
            )
            RequiresBackup = $true
            Check = {
                param($key)
                $clsid = (Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue).'(default)'
                if (-not $clsid) { return $false }
                return (-not (Test-PathCached -Path "HKCR:\CLSID\$clsid"))
            }
        },
        @{
            Name       = "Icon Overlay Handlers Órfãos"
            Risk       = "Avançada"
            Description = "Overlays de ícone do Explorer (Dropbox, Tortoise, etc.) cujo CLSID sumiu"
            Hives      = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers")
            RequiresBackup = $true
            Check = {
                param($key)
                $clsid = (Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue).'(default)'
                if (-not $clsid) { return $false }
                return (-not (Test-PathCached -Path "HKCR:\CLSID\$clsid"))
            }
        },
        @{
            Name       = "Serviços Órfãos"
            Risk       = "Avançada"
            Description = "Serviços do Windows cujo ImagePath não existe no disco"
            Hives      = @("HKLM:\SYSTEM\CurrentControlSet\Services")
            RequiresBackup = $true
            Check = {
                param($key)
                $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
                if (-not $props -or -not $props.ImagePath) { return $false }
                $imgPath = $props.ImagePath.Trim()
                if ($imgPath -match '^\\SystemRoot\\') { $imgPath = "$env:SystemRoot\$($imgPath.Substring(11))" }
                elseif ($imgPath -match '^\\??\\') { $imgPath = $imgPath.Substring(4) }
                elseif ($imgPath -match '^"%SystemRoot%') { $imgPath = $imgPath -replace '%SystemRoot%', $env:SystemRoot }
                $imgPath = $imgPath.Trim('"')
                if ($imgPath -match '^[a-zA-Z]:\\') {
                    return (-not (Test-PathCached -Path $imgPath))
                }
                $parts = $imgPath -split ' '
                $exePath = $parts[0].Trim('"')
                if ($exePath -match '^[a-zA-Z]:\\') {
                    return (-not (Test-PathCached -Path $exePath))
                }
                $sysPath = Join-Path $env:SystemRoot "System32" $exePath
                if (Test-PathCached -Path "$env:SystemRoot\System32\$exePath") { return $false }
                return $false
            }
        }
    )

    $all = $safeCategories + $moderateCategories + $advancedCategories

    $cfg = Get-RegistryScanConfig
    if ($cfg.UseWinapp2) {
        try {
            $winapp2Rules = Import-Winapp2Rules
            if ($winapp2Rules.Count -gt 0) {
                Write-Host "  [INFO] Adicionando $($winapp2Rules.Count) regras Winapp2..." -ForegroundColor Cyan
                foreach ($rule in $winapp2Rules) { $rule.Risk = "Segura"; $all += $rule }
            }
        } catch {
            Write-Host "  [AVISO] Falha ao importar Winapp2: $_" -ForegroundColor Yellow
        }
    }

    switch ($RiskLevel) {
        "safe"     { return $safeCategories }
        "moderate" { return $moderateCategories }
        "advanced" { return $advancedCategories }
        "all"      { return $all }
        default    { return $all }
    }
}

function Get-RegistryJunkReport {
    param(
        [string]$RiskLevel = "all",
        [switch]$MeasureSpace,
        [switch]$Quiet
    )

    if (-not $Quiet) {
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  VARREDURA DO REGISTRO" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
    }

    $categories = Get-RegistryScanCategories -RiskLevel $RiskLevel
    $findings = [System.Collections.Generic.List[Object]]::new()
    $totalCategories = $categories.Count

    $runspacePool = [runspacefactory]::CreateRunspacePool(1, (Get-RegistryScanConfig).MaxParallelism)
    $runspacePool.Open()
    $jobs = @()
    $syncLock = [System.Threading.Mutex]::new()

    for ($catIdx = 0; $catIdx -lt $totalCategories; $catIdx++) {
        $cat = $categories[$catIdx]
        $categoryIndex = $catIdx

        $ps = [PowerShell]::Create()
        $ps.RunspacePool = $runspacePool

        $scriptBlock = {
            param($Category, $CatIndex, $TotalCats, $CacheData, $Lock)
            $localFindings = [System.Collections.Generic.List[Object]]::new()
            $counted = 0

            if ($Category.CustomScan) {
                try {
                    $results = & $Category.PreCheck
                    foreach ($r in $results) {
                        $localFindings.Add([PSCustomObject]@{
                            Category  = $Category.Name
                            Risk      = $Category.Risk
                            KeyPath   = $r.KeyPath
                            ValueName = $r.ValueName
                            Detail    = $r.Detail
                            SizeBytes = 0
                        })
                        $counted++
                    }
                } catch {}
                return @{ Findings = $localFindings; Count = $counted; CatName = $Category.Name }
            }

            foreach ($hivePath in $Category.Hives) {
                if (-not (Test-Path $hivePath -ErrorAction SilentlyContinue)) { continue }
                if ($CacheData.Excluded -and ($CacheData.Excluded | Where-Object { $hivePath -like $_ })) { continue }

                if ($Category.IsValueScan) {
                    try {
                        $props = Get-ItemProperty -Path $hivePath -ErrorAction SilentlyContinue
                        if (-not $props) { continue }
                        $valueNames = $props.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" }
                        foreach ($v in $valueNames) {
                            $checkTarget = if ($Category.ValueNameIsPath) { $v.Name } else { $v.Value }
                            if ([string]::IsNullOrWhiteSpace($checkTarget)) { continue }
                            try {
                                if (& $Category.Check $checkTarget) {
                                    $size = if ($CacheData.MeasureSpace) { Get-RegistryValueSize -KeyPath $hivePath -ValueName $v.Name } else { 0 }
                                    $localFindings.Add([PSCustomObject]@{
                                        Category  = $Category.Name
                                        Risk      = $Category.Risk
                                        KeyPath   = $hivePath
                                        ValueName = $v.Name
                                        Detail    = $checkTarget
                                        SizeBytes = $size
                                    })
                                    $counted++
                                }
                            } catch {}
                        }
                    } catch {}
                } else {
                    try {
                        $subKeys = Get-ChildItem -Path $hivePath -ErrorAction SilentlyContinue
                        foreach ($key in $subKeys) {
                            $fullPath = $key.PSPath
                            try {
                                if (& $Category.Check $key) {
                                    $psPath = $key.PSPath -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
                                    if ($psPath -match '^HKEY_LOCAL_MACHINE') { $psPath = $psPath -replace '^HKEY_LOCAL_MACHINE', 'HKLM:' }
                                    if ($psPath -match '^HKEY_CURRENT_USER') { $psPath = $psPath -replace '^HKEY_CURRENT_USER', 'HKCU:' }
                                    if ($psPath -match '^HKEY_CLASSES_ROOT') { $psPath = $psPath -replace '^HKEY_CLASSES_ROOT', 'HKCR:' }
                                    $size = if ($CacheData.MeasureSpace) { Get-RegistryKeySize -KeyPath $psPath } else { 0 }
                                    $localFindings.Add([PSCustomObject]@{
                                        Category  = $Category.Name
                                        Risk      = $Category.Risk
                                        KeyPath   = $psPath
                                        ValueName = $null
                                        Detail    = $key.PSChildName
                                        SizeBytes = $size
                                    })
                                    $counted++
                                }
                            } catch {}
                        }
                    } catch {}
                }
            }
            return @{ Findings = $localFindings; Count = $counted; CatName = $Category.Name }
        }

        $cacheData = @{
            Excluded     = (Get-RegistryScanConfig).ExcludePaths
            MeasureSpace = $MeasureSpace.IsPresent
        }

        [void]$ps.AddScript($scriptBlock).AddArgument($cat).AddArgument($categoryIndex).AddArgument($totalCategories).AddArgument($cacheData).AddArgument($syncLock)
        $jobs += [PSCustomObject]@{
            PowerShell = $ps
            AsyncResult = $ps.BeginInvoke()
            CategoryName = $cat.Name
        }
    }

    $completedCategories = 0
    foreach ($job in $jobs) {
        try {
            $result = $job.PowerShell.EndInvoke($job.AsyncResult)
            $completedCategories++
            if ($result -and $result.Findings) {
                foreach ($f in $result.Findings) { $findings.Add($f) }
            }
            $pctScan = [Math]::Min(100, [int]($completedCategories * 100 / $totalCategories))
            if (-not $Quiet) {
                Write-Progress -Activity "Varredura do Registro" -Status "Processando: $($job.CategoryName)" -PercentComplete $pctScan
            }
        } catch {
            if (-not $Quiet) {
                Write-Host "  [AVISO] Categoria '$($job.CategoryName)' teve erro: $_" -ForegroundColor Yellow
            }
        } finally {
            $job.PowerShell.Dispose()
        }
    }

    if (-not $Quiet) {
        Write-Progress -Activity "Varredura do Registro" -Completed
    }

    $runspacePool.Close()
    $runspacePool.Dispose()

    if (-not $Quiet) {
        $totalSize = ($findings | Measure-Object -Property SizeBytes -Sum).Sum
        $sizeStr = if ($totalSize -gt 0) { " (~{0:N2} KB)" -f ($totalSize / 1KB) } else { "" }
        Write-Log "Varredura de registro concluída: $($findings.Count) itens órfãos encontrados$sizeStr." "INFO"
    }

    return $findings
}

function Show-RegistryJunkReport {
    param($Findings)

    if ($Findings.Count -eq 0) {
        Write-Host "`n      [OK] Nenhuma chave órfã encontrada nas categorias verificadas." -ForegroundColor Green
        return
    }

    Write-Host "`n      $($Findings.Count) item(ns) órfão(s) encontrado(s):" -ForegroundColor Yellow
    $grouped = $Findings | Group-Object Category
    $grandTotal = ($Findings | Measure-Object -Property SizeBytes -Sum).Sum

    foreach ($group in $grouped) {
        $first = $group.Group | Select-Object -First 1
        $riskColor = switch ($first.Risk) {
            "Segura"    { "Green" }
            "Moderada"  { "Yellow" }
            "Avançada"  { "Red" }
            default     { "White" }
        }
        $groupSize = ($group.Group | Measure-Object -Property SizeBytes -Sum).Sum
        $sizeStr = if ($groupSize -gt 0) { " (~{0:N2} KB)" -f ($groupSize / 1KB) } else { "" }
        Write-Host "`n      -- $($group.Name) ($($group.Count))[$($first.Risk)]$sizeStr --" -ForegroundColor $riskColor
        $group.Group | Select-Object -First 15 | ForEach-Object {
            $label = if ($_.ValueName) { "$($_.KeyPath)\$($_.ValueName)" } else { $_.KeyPath }
            Write-Host "        $label" -ForegroundColor White
        }
        if ($group.Count -gt 15) {
            Write-Host "        ... e mais $($group.Count - 15) item(ns)." -ForegroundColor DarkGray
        }
    }

    if ($grandTotal -gt 0) {
        Write-Host "`n      Espaço total estimado: ~{0:N2} KB" -f ($grandTotal / 1KB) -ForegroundColor Cyan
    }
}

function Export-RegistryHtmlReport {
    param($Findings)

    $reportDir = Join-Path (Split-Path $PSScriptRoot -Parent) "Reports"
    if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $reportPath = Join-Path $reportDir "RegistryScan_$timestamp.html"

    $grouped = $Findings | Group-Object Category
    $totalSize = ($Findings | Measure-Object -Property SizeBytes -Sum).Sum

    $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<title>Relatório de Varredura do Registro</title>
<style>
* { margin:0; padding:0; box-sizing:border-box; }
body { font-family:'Segoe UI',sans-serif; background:#0f0f1a; color:#e0e0e0; padding:20px; }
h1 { color:#64ffda; font-size:20px; margin-bottom:4px; }
.sub { color:#8892b0; font-size:13px; margin-bottom:20px; }
.summary { background:#1a1a2e; border:1px solid #64ffda; border-radius:8px; padding:12px 16px; margin-bottom:20px; }
.summary span { font-size:28px; font-weight:700; color:#64ffda; }
.cat { background:rgba(26,26,46,0.75); border:1px solid rgba(100,255,218,0.08); border-radius:8px; margin-bottom:12px; overflow:hidden; }
.cat h2 { padding:10px 14px; font-size:13px; font-weight:600; border-bottom:1px solid rgba(255,255,255,0.04); }
.tag { display:inline-block; font-size:10px; padding:1px 7px; border-radius:4px; margin-left:8px; font-weight:700; }
.tag-safe { background:rgba(107,203,119,0.15); color:#6bcb77; }
.tag-moderate { background:rgba(255,217,61,0.15); color:#ffd93d; }
.tag-advanced { background:rgba(255,107,107,0.15); color:#ff6b6b; }
.cat-body { padding:8px 14px 10px; }
.item { font-size:12px; padding:3px 0; color:#8892b0; word-break:break-all; font-family:'Cascadia Code','Fira Code','Consolas',monospace; }
.item:hover { color:#e0e0e0; }
.count { float:right; color:#4a5568; font-size:11px; }
.footer { text-align:center; font-size:11px; color:#4a5568; margin-top:20px; padding-top:12px; border-top:1px solid rgba(255,255,255,0.04); }
</style>
</head>
<body>
<h1>Relatório de Varredura do Registro</h1>
<p class="sub">Windows Maintenance Suite — $(Get-Date -Format "dd/MM/yyyy HH:mm:ss")</p>
<div class="summary">
  <span>$($Findings.Count)</span> itens órfãos encontrados
  $(if ($totalSize -gt 0) { " — ~{0:N2} KB estimados" -f ($totalSize / 1KB) })
</div>
"@

    foreach ($group in $grouped) {
        $first = $group.Group | Select-Object -First 1
        $riskTag = switch ($first.Risk) {
            "Segura"    { '<span class="tag tag-safe">Segura</span>' }
            "Moderada"  { '<span class="tag tag-moderate">Moderada</span>' }
            "Avançada"  { '<span class="tag tag-advanced">Avançada</span>' }
            default     { '' }
        }
        $groupSize = ($group.Group | Measure-Object -Property SizeBytes -Sum).Sum
        $sizeInfo = if ($groupSize -gt 0) { " (~{0:N2} KB)" -f ($groupSize / 1KB) } else { "" }

        $html += @"
<div class="cat">
  <h2>$($group.Name) $riskTag<span class="count">$($group.Count)$sizeInfo</span></h2>
  <div class="cat-body">
"@
        foreach ($item in $group.Group) {
            $label = if ($item.ValueName) { "$($item.KeyPath)\$($item.ValueName)" } else { $item.KeyPath }
            $html += "    <div class=""item"">$label</div>`n"
        }
        $html += "  </div>`n</div>`n"
    }

    $html += @"
<div class="footer">Gerado pelo Windows Maintenance Suite — Registry Scanner v2.0</div>
</body>
</html>
"@

    $html | Set-Content -Path $reportPath -Encoding UTF8
    Write-Host "      [OK] Relatório HTML salvo: $reportPath" -ForegroundColor Green
    Write-Log "Relatório HTML do Registry Scanner gerado: $reportPath" "INFO"
    return $reportPath
}

function Backup-RegistryFindings {
    param($Findings)

    $backupPath = Get-SafeBackupPath
    if (-not (Test-Path $backupPath)) {
        New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupFile = Join-Path -Path $backupPath -ChildPath "RegistryScanBackup_$timestamp.reg"

    $uniqueRoots = $Findings | Select-Object -ExpandProperty KeyPath -Unique | ForEach-Object {
        $_ -replace '^HKCU:', 'HKEY_CURRENT_USER' -replace '^HKLM:', 'HKEY_LOCAL_MACHINE' -replace '^HKCR:', 'HKEY_CLASSES_ROOT'
    } | Select-Object -Unique

    $exported = 0
    $failed = 0
    $total = $uniqueRoots.Count
    $i = 0

    foreach ($root in $uniqueRoots) {
        $i++
        Write-Progress -Activity "Backup do Registro" -Status "Exportando: $root" -PercentComplete ([int]($i * 100 / $total))
        try {
            $safeName = ($root -replace '[^\w\:]', '_').Substring(0, [Math]::Min(80, $root.Length))
            $individualFile = Join-Path -Path $backupPath -ChildPath "RegScan_${timestamp}_${safeName}.reg"
            $proc = Start-Process -FilePath "reg.exe" -ArgumentList "export `"$root`" `"$individualFile`" /y" -Wait -PassThru -NoNewWindow -ErrorAction SilentlyContinue
            if ($proc.ExitCode -eq 0) { $exported++ } else { $failed++ }
        } catch { $failed++ }
    }

    Write-Progress -Activity "Backup do Registro" -Completed
    Write-Host "      [OK] Backup de $exported chave(s) salvo em: $backupPath" -ForegroundColor Green
    if ($failed -gt 0) {
        Write-Host "      [AVISO] $failed chave(s) não puderam ser exportadas." -ForegroundColor Yellow
    }
    Write-Log "Backup: $exported chaves exportadas, $failed falhas." "SUCCESS"
    return $exported -gt 0
}

function Clear-RegistryJunk {
    param(
        $Findings,
        [switch]$DryRun,
        [switch]$SkipBackup
    )

    if ($Findings.Count -eq 0) { return }

    if ($DryRun) {
        Write-Host "`n[DRY-RUN] Simulação de limpeza - nenhuma alteração será feita." -ForegroundColor Yellow
    } elseif (-not $SkipBackup) {
        Write-Host "`n[>] Fazendo backup das chaves afetadas antes de excluir..." -ForegroundColor Yellow
        $backupOk = Backup-RegistryFindings -Findings $Findings
        if (-not $backupOk) {
            Write-Host "      [ERRO] Backup falhou. Abortando limpeza por segurança." -ForegroundColor Red
            Write-Log "Limpeza de registro abortada: backup falhou." "ERROR"
            return
        }
    }

    $total = $Findings.Count
    $removed = 0
    $failed = 0
    $undoLog = @()
    $i = 0

    foreach ($item in $Findings) {
        $i++
        Write-Progress -Activity "Limpando registro" -Status "$($item.Category): $($item.Detail)" -PercentComplete ([int]($i * 100 / $total))
        try {
            if ($item.ValueName) {
                if (-not $DryRun) {
                    Remove-ItemProperty -Path $item.KeyPath -Name $item.ValueName -Force -ErrorAction Stop
                }
                $undoLog += "# $($item.Category)`nRemove-ItemProperty -Path '$($item.KeyPath)' -Name '$($item.ValueName)' -Force"
            } else {
                if (-not $DryRun) {
                    Remove-Item -Path $item.KeyPath -Recurse -Force -ErrorAction Stop
                }
                $undoLog += "# $($item.Category)`nRemove-Item -Path '$($item.KeyPath)' -Recurse -Force"
            }
            $removed++
        } catch {
            $failed++
            Write-Log "Falha ao remover $($item.KeyPath) ($($item.ValueName)): $_" "WARNING"
        }
    }
    Write-Progress -Activity "Limpando registro" -Completed

    if (-not $DryRun -and $undoLog.Count -gt 0) {
        $backupPath = Get-SafeBackupPath
        $undoFile = Join-Path $backupPath "Undo_RegistryCleanup_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"
        $undoHeader = @"
# ============================================
# UNDO SCRIPT - Registry Cleanup
# Gerado em: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# Para restaurar, execute este script como Administrador.
# ============================================

"@
        $undoHeader + ($undoLog -join "`r`n`r`n") | Set-Content -Path $undoFile -Encoding UTF8
        Write-Host "      [OK] Script de desfazer salvo em: $undoFile" -ForegroundColor Green
    }

    Write-Host "`n      [OK] $removed chave(s)/valor(es) removido(s). $failed falha(s)." -ForegroundColor Green
    Write-Log "Limpeza de registro: $removed removidos, $failed falhas." "SUCCESS"
}

function Invoke-RegistryScan {
    param(
        [switch]$DryRun
    )

    $categories = Get-RegistryScanCategories -RiskLevel "all"
    $safeCount = ($categories | Where-Object { $_.Risk -eq "Segura" }).Count
    $modCount  = ($categories | Where-Object { $_.Risk -eq "Moderada" }).Count
    $advCount  = ($categories | Where-Object { $_.Risk -eq "Avançada" }).Count

    do {
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  VARREDURA E LIMPEZA DO REGISTRO" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  Categorias disponíveis: $safeCount Seguras, $modCount Moderadas, $advCount Avançadas" -ForegroundColor DarkGray
        Write-Host "  (Nunca mexe em SAM/SECURITY/SYSTEM ou hives críticos do Windows)" -ForegroundColor DarkGray
        Write-Host "`n  --- Escopo da Varredura ---"
        Write-Host "  1. Apenas categorias Seguras (rápido, 100% seguro)"
        Write-Host "  2. Seguras + Moderadas (recomendado, pede confirmação)"
        Write-Host "  3. Todas (Seguras + Moderadas + Avançadas, requer backup)"
        Write-Host "`n  --- Ações ---"
        Write-Host "  4. Relatório completo (varrer + exibir + HTML)"
        Write-Host "  5. Varrer e Limpar (com backup automático + confirmação)"
        if ($DryRun) { Write-Host "  6. Modo Simulação (Dry-Run)" }
        Write-Host "  V. Voltar ao Menu Principal"
        Write-Host "`n========================================" -ForegroundColor Cyan

        $choice = Read-Host "Digite sua escolha"
        $choice = $choice -replace '\s+', ''

        if ($choice -eq 'V' -or $choice -eq 'v') { return }

        $maxOpt = if ($DryRun) { 6 } else { 5 }
        if (-not (Test-ValidNumericInput -Value $choice -Min 1 -Max $maxOpt)) {
            Write-Host "Opção inválida." -ForegroundColor Red
            Start-Sleep -Seconds 1
            continue
        }

        $riskLevel = switch ($choice) {
            "1" { "safe" }
            "2" { "moderate" }
            "3" { "advanced" }
            default { $null }
        }

        $measureSpace = $true

        if ($choice -in @("1", "2", "3")) {
            if ($choice -eq "3") {
                Write-Host "`n[AVISO] Varredura Avançada inclui CLSID/COM, Serviços, TypeLibs." -ForegroundColor Yellow
                Write-Host "  Estas categorias podem gerar falsos positivos. Revise antes de limpar." -ForegroundColor Yellow
                $confirm = Read-Host "`nContinuar com varredura avançada? (S/N)"
                if ($confirm -notmatch '^[Ss]') { continue }
            }
            $findings = Get-RegistryJunkReport -RiskLevel $riskLevel -MeasureSpace
            Show-RegistryJunkReport -Findings $findings

            if ($findings.Count -gt 0) {
                $clean = Read-Host "`nLimpar itens encontrados? Backup será feito antes. (S/N)"
                if ($clean -match '^[Ss]') {
                    $requiresBackup = ($findings | Where-Object { $_.Risk -ne "Segura" }).Count -gt 0
                    Clear-RegistryJunk -Findings $findings
                } else {
                    Write-Host "      Nenhuma alteração feita." -ForegroundColor Yellow
                }
            }
            continue
        }

        if ($choice -eq "4") {
            Write-Host "`n--- Escolha o escopo do relatório ---" -ForegroundColor Cyan
            Write-Host "  1. Seguras  2. Seguras+Moderadas  3. Todas"
            $scope = Read-Host "Escopo"
            $scope = $scope -replace '\s+', ''
            $scopeLevel = switch ($scope) {
                "1" { "safe" }
                "2" { "moderate" }
                "3" { "advanced" }
                default { "all" }
            }
            $findings = Get-RegistryJunkReport -RiskLevel $scopeLevel -MeasureSpace
            Show-RegistryJunkReport -Findings $findings
            if ($findings.Count -gt 0) {
                $exportHtml = Read-Host "`nExportar relatório HTML? (S/N)"
                if ($exportHtml -match '^[Ss]') {
                    Export-RegistryHtmlReport -Findings $findings
                }
            }
            continue
        }

        if ($choice -eq "5") {
            Write-Host "`n--- Escolha o escopo da limpeza ---" -ForegroundColor Cyan
            Write-Host "  1. Seguras  2. Seguras+Moderadas  3. Todas"
            $scope = Read-Host "Escopo"
            $scope = $scope -replace '\s+', ''
            $scopeLevel = switch ($scope) {
                "1" { "safe" }
                "2" { "moderate" }
                "3" { "advanced" }
                default { "all" }
            }
            $findings = Get-RegistryJunkReport -RiskLevel $scopeLevel -MeasureSpace
            Show-RegistryJunkReport -Findings $findings

            if ($findings.Count -gt 0) {
                $requiresBackup = ($findings | Where-Object { $_.Risk -ne "Segura" }).Count -gt 0
                $warnMsg = if ($requiresBackup) { " (backup OBRIGATÓRIO para itens Moderados/Avançados)" } else { "" }
                $confirm = Read-Host "`nConfirmar exclusão dos $($findings.Count) itens$warnMsg? (S/N)"
                if ($confirm -match '^[Ss]') {
                    Clear-RegistryJunk -Findings $findings
                } else {
                    Write-Host "      Limpeza cancelada." -ForegroundColor Yellow
                }
            }
            continue
        }

        if ($choice -eq "6" -and $DryRun) {
            $findings = Get-RegistryJunkReport -RiskLevel "all" -MeasureSpace
            Write-Host "`n[DRY-RUN] Simulação de limpeza - nada será alterado." -ForegroundColor Yellow
            Clear-RegistryJunk -Findings $findings -DryRun
            continue
        }

    } while ($true)
}
