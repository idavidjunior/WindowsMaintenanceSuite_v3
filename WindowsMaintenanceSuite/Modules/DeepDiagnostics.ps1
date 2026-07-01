<#
.SYNOPSIS
    Módulo de diagnóstico profundo do sistema.
.DESCRIPTION
    Este módulo executa diagnóstico detalhado do hardware e sistema.
#>

# Importar SecurityHelper
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\SecurityHelper.ps1"

# Validar privilégios de administrador
Require-Administrator

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
    
    $Report | Out-File -FilePath $ReportPath
    Write-Log "Relatorio gerado em: $ReportPath" "SUCCESS"
    
    # Exibe no console também
    $Report | ForEach-Object { Write-Host $_ }
    
    Update-WMSHistory -Key "LastDeepDiag" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}
