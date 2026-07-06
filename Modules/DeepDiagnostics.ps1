<#
.SYNOPSIS
    Módulo de diagnóstico profundo do sistema.
.DESCRIPTION
    Este módulo executa diagnóstico detalhado do hardware e sistema.
#>

# Importar SecurityHelper
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\SecurityHelper.ps1"

# NOTA: A verificação de administrador é feita UMA ÚNICA vez em MainMenu.ps1.

function Invoke-DeepDiagnostics {
    Write-Log "Iniciando Diagnostico Profundo..." "INFO"
    
    # Garantir que o diretório Reports existe
    $ReportsDir = Join-Path $PSScriptRoot "..\Reports"
    if (-not (Test-Path $ReportsDir)) {
        New-Item -ItemType Directory -Path $ReportsDir -Force | Out-Null
    }
    
    $ReportPath = Join-Path $PSScriptRoot "..\Reports\DeepDiag_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"
    $Report = @()
    $Report += "===================================================="
    $Report += "        RELATORIO DE DIAGNOSTICO PROFUNDO"
    $Report += "        Data: $(Get-Date)"
    $Report += "===================================================="
    $Report += ""
    
    # CPU
    $CPU = Get-CimInstance Win32_Processor
    $Report += "[CPU]"
    $Report += "Modelo: $($CPU.Name)"
    $Report += "Nucleos: $($CPU.NumberOfCores)"
    $Report += "Threads: $($CPU.NumberOfLogicalProcessors)"
    $Report += ""
    
    # RAM
    $RAM = Get-CimInstance Win32_PhysicalMemory
    $TotalRAM = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
    $Report += "[RAM]"
    $Report += "Total: $([Math]::Round($TotalRAM, 2)) GB"
    foreach ($module in $RAM) {
        $Report += "Modulo: $($module.Capacity / 1GB)GB | Velocidade: $($module.Speed)MHz"
    }
    $Report += ""
    
    # Discos
    $Disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
    $Report += "[ARMAZENAMENTO]"
    foreach ($disk in $Disks) {
        $Free = [Math]::Round($disk.FreeSpace / 1GB, 2)
        $Total = [Math]::Round($disk.Size / 1GB, 2)
        $Report += "Disco $($disk.DeviceID) | Livre: $Free GB / Total: $Total GB"
    }
    
    $Report | Out-File -FilePath $ReportPath -Encoding UTF8
    Write-Log "Relatorio gerado em: $ReportPath" "SUCCESS"

    # Exibe no console também
    $Report | ForEach-Object { Write-Host $_ }

    # Exportar CSV e HTML do inventario de hardware
    $hardwareData = @(
        [PSCustomObject]@{ Componente="CPU"; Detalhe="$($CPU.Name) ($($CPU.NumberOfCores) nucleos / $($CPU.NumberOfLogicalProcessors) threads)" }
        [PSCustomObject]@{ Componente="RAM"; Detalhe="$([Math]::Round($TotalRAM, 2)) GB Total" }
        foreach ($module in $RAM) {
            [PSCustomObject]@{ Componente="RAM-Modulo"; Detalhe="$($module.Capacity / 1GB)GB @ $($module.Speed)MHz" }
        }
        foreach ($disk in $Disks) {
            [PSCustomObject]@{ Componente="Disco $($disk.DeviceID)"; Detalhe="$([Math]::Round($disk.FreeSpace / 1GB, 2)) GB livres de $([Math]::Round($disk.Size / 1GB, 2)) GB" }
        }
    )
    $csvPath = Join-Path $ReportsDir "DeepDiag_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
    $htmlPath = Join-Path $ReportsDir "DeepDiag_$(Get-Date -Format 'yyyyMMdd_HHmm').html"
    try {
        $hardwareData | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        $hardwareData | ConvertTo-Html -Property Componente, Detalhe -Title "Diagnostico Profundo WMS" -PreContent "<h1>Diagnostico Profundo - $(Get-Date)</h1>" |
            Out-File -FilePath $htmlPath -Encoding UTF8
        Write-Host "`n[OK] Relatorios exportados:" -ForegroundColor Green
        Write-Host "      TXT:  $ReportPath" -ForegroundColor White
        Write-Host "      CSV:  $csvPath" -ForegroundColor White
        Write-Host "      HTML: $htmlPath" -ForegroundColor White
        Write-Log "Relatorios TXT/CSV/HTML gerados em Reports." "SUCCESS"
    } catch {
        Write-Log "Apenas TXT gerado (erro no CSV/HTML): $_" "WARNING"
    }

    Update-WMSHistory -Key "LastDeepDiag" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}

Export-ModuleMember -Function *
