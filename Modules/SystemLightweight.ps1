<#
.SYNOPSIS
    Modulo Sistema Leve - deixa o Windows mais leve (boot + RAM).
.DESCRIPTION
    Gerenciador de inicializacao, auditor de tarefas agendadas, desinstalador
    inteligente (por tamanho/uso), tweaker de servicos guiado e desativacao de
    apps em segundo plano. Tudo com confirmacao e backup.
#>

# Importar Core
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\SecurityHelper.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\Logger.ps1"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ---------------------------------------------------------------------------
# 1. Gerenciador de Inicializacao
# ---------------------------------------------------------------------------

function Get-StartupItems {
    $items = @()
    try {
        $items += Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue |
            Select-Object Name, Command, Location, User
    } catch {}
    # Run keys do registro (HKCU e HKLM)
    $runKeys = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
    )
    foreach ($key in $runKeys) {
        if (Test-Path $key) {
            try {
                $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
                if ($props) {
                    foreach ($p in $props.PSObject.Properties) {
                        if ($p.Name -notlike "PS*") {
                            $items += [PSCustomObject]@{
                                Name     = $p.Name
                                Command  = $p.Value
                                Location = $key
                                User     = if ($key -like "HKCU*") { "Usuario" } else { "Todos" }
                            }
                        }
                    }
                }
            } catch {}
        }
    }
    return $items | Sort-Object Name -Unique
}

function Manage-StartupItems {
    Write-Host "`n[1] Gerenciador de Inicializacao..." -ForegroundColor Yellow
    $items = Get-StartupItems
    if ($items.Count -eq 0) {
        Write-Host "      [INFO] Nenhum item de inicializacao encontrado." -ForegroundColor Cyan
        return
    }
    Write-Host "      Itens que iniciam com o Windows ($($items.Count)):`n" -ForegroundColor Green
    $i = 0
    foreach ($it in $items) {
        $i++
        Write-Host ("        {0,2}. {1}" -f $i, $it.Name) -ForegroundColor White
        Write-Host ("            Comando: {0}" -f $it.Command) -ForegroundColor DarkGray
        Write-Host ("            Origem:  {0}  |  Escopo: {1}" -f $it.Location, $it.User) -ForegroundColor DarkGray
    }
    Write-Host "`n      Digite o numero do item para DESATIVAR (remove do registro Run)," -ForegroundColor Yellow
    Write-Host "      ou 0 para voltar." -ForegroundColor Yellow
    $sel = Read-Host "      Escolha"
    $sel = $sel -replace '\s+', ''
    if ($sel -match '^\d+$' -and $sel -ge 1 -and $sel -le $items.Count) {
        $target = $items[[int]$sel - 1]
        if ($target.Location -like "HK*:\*") {
            try {
                $bk = Backup-RegistryKeySimple -KeyPath ($target.Location -replace 'HKCU:', 'HKEY_CURRENT_USER' -replace 'HKLM:', 'HKEY_LOCAL_MACHINE') -BackupName "StartupBak"
                Remove-ItemProperty -Path $target.Location -Name $target.Name -Force -ErrorAction Stop
                Write-Host "      [OK] '$($target.Name)' desativado (backup: $bk)." -ForegroundColor Green
                Write-Log "Item de inicializacao desativado: $($target.Name)" "SUCCESS"
            } catch {
                Write-Host "      [ERRO] Nao foi possivel desativar: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
            }
        } else {
            Write-Host "      [INFO] Este item nao vem do registro Run (pode ser do Gerenciador de Tarefas ou Task Manager)." -ForegroundColor Cyan
            Write-Host "      Para esses, desative manualmente no Task Manager > Startup." -ForegroundColor Cyan
        }
    }
}

# ---------------------------------------------------------------------------
# 2. Auditor de Tarefas Agendadas
# ---------------------------------------------------------------------------

function Audit-ScheduledTasks {
    Write-Host "`n[2] Auditor de Tarefas Agendadas..." -ForegroundColor Yellow
    try {
        $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notlike "\Microsoft\*" } |
            Select-Object TaskName, TaskPath, State, Author
        if (-not $tasks -or $tasks.Count -eq 0) {
            Write-Host "      [INFO] Nenhuma tarefa agendada de terceiros encontrada." -ForegroundColor Cyan
            return
        }
        Write-Host "      Tarefas agendadas ativas (nao-Microsoft): $($tasks.Count)`n" -ForegroundColor Green
        $i = 0
        foreach ($t in $tasks) {
            $i++
            Write-Host ("        {0,2}. {1}  [{2}]" -f $i, $t.TaskName, $t.State) -ForegroundColor White
            Write-Host ("            Caminho: {0}" -f $t.TaskPath) -ForegroundColor DarkGray
        }
        Write-Host "`n      Digite o numero para DESATIVAR, ou 0 para voltar." -ForegroundColor Yellow
        $sel = Read-Host "      Escolha"
        $sel = $sel -replace '\s+', ''
        if ($sel -match '^\d+$' -and $sel -ge 1 -and $sel -le $tasks.Count) {
            $target = $tasks[[int]$sel - 1]
            try {
                Disable-ScheduledTask -TaskPath $target.TaskPath -TaskName $target.TaskName -ErrorAction Stop | Out-Null
                Write-Host "      [OK] Tarefa '$($target.TaskName)' desativada." -ForegroundColor Green
                Write-Log "Tarefa agendada desativada: $($target.TaskName)" "SUCCESS"
            } catch {
                Write-Host "      [ERRO] Nao foi possivel desativar: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "      [ERRO] Falha ao listar tarefas: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
    }
}

# ---------------------------------------------------------------------------
# 3. Desinstalador Inteligente
# ---------------------------------------------------------------------------

function Get-InstalledAppsBySize {
    $apps = @()
    $regPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($rp in $regPaths) {
        try {
            $items = Get-ItemProperty $rp -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -and $_.UninstallString }
            foreach ($it in $items) {
                $sizeGB = 0
                if ($it.EstimatedSize) { $sizeGB = [Math]::Round($it.EstimatedSize / 1MB, 2) }  # EstimatedSize em KB
                elseif ($it.InstallLocation -and (Test-Path $it.InstallLocation)) {
                    $sizeGB = Get-FolderSizeGB -Path $it.InstallLocation
                }
                $apps += [PSCustomObject]@{
                    Name        = $it.DisplayName
                    Version     = $it.DisplayVersion
                    Publisher   = $it.Publisher
                    SizeGB      = $sizeGB
                    InstallDate = $it.InstallDate
                    Uninstall   = $it.UninstallString
                    Location    = $it.InstallLocation
                }
            }
        } catch {}
    }
    return $apps | Sort-Object SizeGB -Descending | Select-Object * -Unique
}

function Manage-InstalledApps {
    Write-Host "`n[3] Desinstalador Inteligente..." -ForegroundColor Yellow
    $apps = Get-InstalledAppsBySize
    if ($apps.Count -eq 0) {
        Write-Host "      [INFO] Nenhum aplicativo encontrado." -ForegroundColor Cyan
        return
    }
    $top = $apps | Select-Object -First 30
    Write-Host "      Top $($top.Count) aplicativos por tamanho (GB):`n" -ForegroundColor Green
    Write-Host ("        {0,3} {1,-45} {2,8} {3}" -f "#", "Nome", "GB", "Data") -ForegroundColor Cyan
    $i = 0
    foreach ($a in $top) {
        $i++
        $name = if ($a.Name.Length -gt 43) { $a.Name.Substring(0,43) + "..." } else { $a.Name }
        Write-Host ("        {0,3} {1,-45} {2,8} {3}" -f $i, $name, $a.SizeGB, $a.InstallDate) -ForegroundColor White
    }
    Write-Host "`n      Digite o numero para DESINSTALAR, ou 0 para voltar." -ForegroundColor Yellow
    $sel = Read-Host "      Escolha"
    $sel = $sel -replace '\s+', ''
    if ($sel -match '^\d+$' -and $sel -ge 1 -and $sel -le $top.Count) {
        $target = $top[[int]$sel - 1]
        Write-Host "      [AVISO] Voja vai desinstalar '$($target.Name)'." -ForegroundColor Red
        $confirm = Read-Host "      Confirmar? (S/N)"
        if ($confirm -eq 'S' -or $confirm -eq 's') {
            try {
                $uninstallCmd = $target.Uninstall
                if ($uninstallCmd -match 'msiexec') {
                    $uninstallCmd = $uninstallCmd -replace '/I', '/X'
                    $uninstallCmd = "$uninstallCmd /quiet /norestart"
                }
                Write-Host "      [INFO] Executando desinstalador..." -ForegroundColor Cyan
                cmd.exe /c $uninstallCmd
                Write-Host "      [OK] Desinstalacao iniciada/concluida para '$($target.Name)'." -ForegroundColor Green
                Write-Log "App desinstalado: $($target.Name)" "SUCCESS"
            } catch {
                Write-Host "      [ERRO] Falha: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
            }
        }
    }
}

# ---------------------------------------------------------------------------
# 4. Tweaker de Servicos Guiado
# ---------------------------------------------------------------------------

function Get-ServiceStateStorePath {
    Join-Path (Get-SafeBackupPath) "WMS_ServiceStates.json"
}

function Get-ServiceStateStore {
    $path = Get-ServiceStateStorePath
    $store = @{}
    if (-not (Test-Path $path)) { return $store }

    try {
        $raw = Get-Content $path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return $store }
        $data = $raw | ConvertFrom-Json -ErrorAction Stop
        foreach ($prop in $data.PSObject.Properties) {
            $store[$prop.Name] = [string]$prop.Value
        }
    } catch {
        Write-Log "Falha ao ler estado de servicos: $_" "WARNING"
    }

    return $store
}

function Save-ServicePreviousMode {
    param(
        [string]$ServiceName,
        [string]$StartMode
    )

    $path = Get-ServiceStateStorePath
    $store = Get-ServiceStateStore
    $store[$ServiceName] = $StartMode
    ($store | ConvertTo-Json -Compress) | Set-Content -Path $path -Encoding UTF8 -Force
}

function Get-ServicePreviousMode {
    param([string]$ServiceName)

    $store = Get-ServiceStateStore
    if ($store.ContainsKey($ServiceName) -and $store[$ServiceName]) {
        return $store[$ServiceName]
    }
    return "Manual"
}

function Get-ServiceStartModeSafe {
    param([string]$ServiceName)

    $escapedName = $ServiceName.Replace("'", "''")
    $cim = Get-CimInstance Win32_Service -Filter "Name='$escapedName'" -ErrorAction SilentlyContinue
    if ($cim -and $cim.StartMode) {
        return [string]$cim.StartMode
    }

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service -and ($service.PSObject.Properties.Name -contains "StartType")) {
        switch ([string]$service.StartType) {
            "Automatic" { return "Auto" }
            "Manual"    { return "Manual" }
            "Disabled"  { return "Disabled" }
            default     { return [string]$service.StartType }
        }
    }

    return $null
}

function Format-ServiceStartModeLabel {
    param([string]$StartMode)

    switch ($StartMode) {
        "Disabled" { return "DESATIVADO" }
        "Auto"     { return "Automatico" }
        "Manual"   { return "Manual" }
        default    { return if ($StartMode) { $StartMode } else { "Desconhecido" } }
    }
}

function ConvertTo-SetServiceStartupType {
    param([string]$StartMode)

    switch ($StartMode) {
        "Auto"     { return "Automatic" }
        "Manual"   { return "Manual" }
        "Disabled" { return "Disabled" }
        default    { return "Manual" }
    }
}

function ConvertTo-ScServiceStartArg {
    param([string]$StartMode)

    switch ($StartMode) {
        "Auto"     { return "auto" }
        "Manual"   { return "demand" }
        "Disabled" { return "disabled" }
        default    { return "demand" }
    }
}

function Test-ServiceIsDisabled {
    param([string]$ServiceName)
    return (Get-ServiceStartModeSafe -ServiceName $ServiceName) -eq "Disabled"
}

function Set-ServiceStartModeSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,
        [Parameter(Mandatory = $true)]
        [ValidateSet("Auto", "Manual", "Disabled")]
        [string]$StartMode
    )

    $service = Get-Service -Name $ServiceName -ErrorAction Stop
    if ($service.Status -eq "Running" -and $StartMode -eq "Disabled") {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    }

    $startupType = ConvertTo-SetServiceStartupType -StartMode $StartMode
    $applied = $false
    $lastError = $null

    try {
        Set-Service -Name $ServiceName -StartupType $startupType -ErrorAction Stop
        $applied = $true
    } catch {
        $lastError = $_.Exception.Message
    }

    if (-not $applied) {
        $scArg = ConvertTo-ScServiceStartArg -StartMode $StartMode
        $scOutput = & sc.exe config $ServiceName ("start= {0}" -f $scArg) 2>&1
        if ($LASTEXITCODE -ne 0) {
            $detail = if ($lastError) { $lastError } else { ($scOutput | Out-String).Trim() }
            throw "Nao foi possivel alterar o servico '$ServiceName': $detail"
        }
    }

    Start-Sleep -Milliseconds 400
    $actual = Get-ServiceStartModeSafe -ServiceName $ServiceName
    if ($actual -ne $StartMode) {
        throw "Alteracao nao confirmada para '$ServiceName' (esperado: $StartMode, atual: $actual)."
    }
}

function Backup-ServiceRegistryKey {
    param([string]$ServiceName)

    $regPath = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\$ServiceName"
    return Backup-RegistryKeySimple -KeyPath $regPath -BackupName "Svc_$ServiceName"
}

function Get-NonEssentialServicesCatalog {
    return @(
        @{ Name="DiagTrack";      Desc="Telemetria e Dados de Diagnostico";               Risk="Baixo" }
        @{ Name="SysMain";        Desc="Superfetch/SysMain (recomendado desativar em SSD)"; Risk="Baixo" }
        @{ Name="WSearch";        Desc="Windows Search (indexacao; desative se nao usa)";   Risk="Medio" }
        @{ Name="Fax";            Desc="Servico de Fax (raramente usado)";                  Risk="Baixo" }
        @{ Name="fhsvc";          Desc="Historico de Arquivos (File History)";              Risk="Medio" }
        @{ Name="XblAuthManager"; Desc="Xbox Live Auth Manager";                            Risk="Baixo" }
        @{ Name="XboxGipSvc";     Desc="Xbox Accessory Management Service";                   Risk="Baixo" }
        @{ Name="XboxNetApiSvc";  Desc="Xbox Live Networking Service";                        Risk="Baixo" }
        @{ Name="WMPNetworkSvc";  Desc="Compartilhamento de Rede do WMP";                     Risk="Baixo" }
        @{ Name="Spooler";        Desc="Print Spooler (desative se NAO usa impressora)";      Risk="Medio" }
        @{ Name="RetailDemo";     Desc="Modo de Demonstracao de Varejo";                      Risk="Baixo" }
        @{ Name="RemoteRegistry"; Desc="Registro Remoto (seguranca: desative)";               Risk="Baixo" }
        @{ Name="WerSvc";         Desc="Relatorio de Erros do Windows";                       Risk="Medio" }
    )
}

function Get-AvailableNonEssentialServices {
    param($Catalog)

    $available = @()
    $i = 0
    foreach ($svc in $Catalog) {
        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($service) {
            $i++
            $startMode = Get-ServiceStartModeSafe -ServiceName $svc.Name
            $available += [PSCustomObject]@{
                Index     = $i
                Info      = $svc
                Service   = $service
                StartMode = $startMode
            }
        }
    }
    return $available
}

function Show-NonEssentialServicesList {
    param($Available)

    Write-Host "      Servicos nao-essenciais que podem ser desativados:`n" -ForegroundColor Green
    foreach ($entry in $Available) {
        $riskColor = if ($entry.Info.Risk -eq "Baixo") { "Green" } else { "Yellow" }
        $status = Format-ServiceStartModeLabel -StartMode $entry.StartMode
        Write-Host ("        {0,2}. {1,-22} [{2}] Risco: " -f $entry.Index, $entry.Info.Name, $status) -NoNewline -ForegroundColor White
        Write-Host "$($entry.Info.Risk)" -ForegroundColor $riskColor
        Write-Host ("            $($entry.Info.Desc)") -ForegroundColor DarkGray
    }
}

function Invoke-ServiceToggle {
    param($Target)

    $serviceName = $Target.Info.Name
    $currentMode = Get-ServiceStartModeSafe -ServiceName $serviceName
    if (-not $currentMode) {
        Write-Host "      [ERRO] Nao foi possivel ler o estado atual de '$serviceName'." -ForegroundColor Red
        return
    }

    $isDisabled = ($currentMode -eq "Disabled")
    if (-not $isDisabled -and $Target.Info.Risk -eq "Medio") {
        Write-Host "      [AVISO] '$serviceName' tem risco MEDIO: $($Target.Info.Desc)" -ForegroundColor Yellow
        $confirm = Read-Host "      Confirmar desativacao? (S/N)"
        if ($confirm -notin @("S", "s")) {
            Write-Host "      [INFO] Operacao cancelada." -ForegroundColor Cyan
            return
        }
    }

    try {
        $backupFile = Backup-ServiceRegistryKey -ServiceName $serviceName
        if ($isDisabled) {
            $restoreMode = Get-ServicePreviousMode -ServiceName $serviceName
            Set-ServiceStartModeSafe -ServiceName $serviceName -StartMode $restoreMode
            $label = Format-ServiceStartModeLabel -StartMode $restoreMode
            Write-Host "      [OK] '$serviceName' reativado ($label). Backup: $backupFile" -ForegroundColor Green
            Write-Log "Servico reativado: $serviceName ($restoreMode)" "SUCCESS"
        } else {
            Save-ServicePreviousMode -ServiceName $serviceName -StartMode $currentMode
            Set-ServiceStartModeSafe -ServiceName $serviceName -StartMode "Disabled"
            Write-Host "      [OK] '$serviceName' DESATIVADO. Backup: $backupFile" -ForegroundColor Green
            Write-Log "Servico desativado: $serviceName" "SUCCESS"
        }
    } catch {
        $detail = if ($_.Exception -and $_.Exception.Message) { $_.Exception.Message } else { Get-SafeErrorMessage $_ }
        Write-Host "      [ERRO] Nao foi possivel alterar '$serviceName': $detail" -ForegroundColor Red
        Write-Log "Erro ao alterar servico $serviceName : $_" "ERROR"
    }
}

function Manage-NonEssentialServices {
    Write-Host "`n[4] Tweaker de Servicos Guiado..." -ForegroundColor Yellow

    if (-not (Test-Administrator)) {
        Write-Host "      [ERRO] Privilegios de administrador necessarios para alterar servicos." -ForegroundColor Red
        Write-Host "      Execute o WMS.bat como administrador." -ForegroundColor Yellow
        return
    }

    $catalog = Get-NonEssentialServicesCatalog

    while ($true) {
        $available = Get-AvailableNonEssentialServices -Catalog $catalog
        if ($available.Count -eq 0) {
            Write-Host "      [INFO] Nenhum dos servicos catalogados esta presente no sistema." -ForegroundColor Cyan
            return
        }

        Show-NonEssentialServicesList -Available $available
        Write-Host "`n      Digite o numero para ALTERNAR (ativar/desativar), ou 0 para voltar." -ForegroundColor Yellow
        $sel = Read-Host "      Escolha"
        $sel = $sel -replace '\s+', ''

        if ($sel -eq "0") { return }

        if (-not (Test-ValidNumericInput -Value $sel -Min 1 -Max $available.Count)) {
            Write-Host "      [AVISO] Escolha inválida. Digite um numero entre 0 e $($available.Count)." -ForegroundColor Red
            continue
        }

        $target = $available[[int]$sel - 1]
        Invoke-ServiceToggle -Target $target
        Write-Host "`n      Lista atualizada:" -ForegroundColor Cyan
    }
}

# ---------------------------------------------------------------------------
# 5. Desativar apps em segundo plano
# ---------------------------------------------------------------------------

function Disable-BackgroundApps {
    Write-Host "`n[5] Desativar apps em segundo plano..." -ForegroundColor Yellow
    try {
        $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        Set-ItemProperty -Path $key -Name "GlobalUserDisabled" -Value 1 -Force
        Write-Host "      [OK] Apps em segundo plano desativados para o usuario atual." -ForegroundColor Green
        Write-Log "Apps em segundo plano desativados." "SUCCESS"
    } catch {
        Write-Host "      [ERRO] Falha: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
        Write-Log "Erro ao desativar apps em segundo plano: $_" "ERROR"
    }
}

# ---------------------------------------------------------------------------
# Helper: backup simples de chave (nativa)
# ---------------------------------------------------------------------------
function Backup-RegistryKeySimple {
    param([string]$KeyPath, [string]$BackupName)
    $dir = Get-SafeBackupPath
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $file = Join-Path $dir "$($BackupName)_$ts.reg"
    & reg.exe export $KeyPath $file /y 2>$null | Out-Null
    return $file
}

# ---------------------------------------------------------------------------
# Funcao principal
# ---------------------------------------------------------------------------

function Invoke-SystemLightweight {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  SISTEMA LEVE" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "`nSelecione uma Opção:" -ForegroundColor Cyan
    Write-Host "  1. Gerenciador de Inicializacao (boot)"
    Write-Host "  2. Auditor de Tarefas Agendadas"
    Write-Host "  3. Desinstalador Inteligente (por tamanho)"
    Write-Host "  4. Tweaker de Servicos Guiado"
    Write-Host "  5. Desativar apps em segundo plano"
    Write-Host "  6. Voltar ao Menu Principal"
    Write-Host "`n========================================" -ForegroundColor Cyan

    $choice = Read-Host "Digite o numero da sua escolha"
    $choice = $choice -replace '\s+', ''

    if (-not (Test-ValidNumericInput -Value $choice -Min 1 -Max 6)) {
        Write-Host "Opção inválida. Digite um numero entre 1 e 6." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    switch ($choice) {
        "1" { Manage-StartupItems }
        "2" { Audit-ScheduledTasks }
        "3" { Manage-InstalledApps }
        "4" { Manage-NonEssentialServices }
        "5" { Disable-BackgroundApps }
        "6" { return }
    }
}

Export-ModuleMember -Function *
