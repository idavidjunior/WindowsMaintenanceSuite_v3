$ConfigPath = Join-Path $PSScriptRoot "..\Config\Settings.json"
$HistoryPath = Join-Path $PSScriptRoot "..\History\MaintenanceHistory.json"
$ConfigDir = Join-Path $PSScriptRoot "..\Config"
$HistoryDir = Join-Path $PSScriptRoot "..\History"

# Configurações padrão com valores centralizados
$DefaultConfig = @{
    "Theme" = "Dark"
    "AutoLogCleanup" = $true
    "Language" = "PT-BR"
    "ShowFullMacAddress" = $false  # Privacidade: mostrar MAC completo
    "LogRetentionDays" = 7  # Dias para manter logs
    "BackupPath" = ""  # Vazio usa caminho seguro automático
}

function Get-WMSConfig {
    # Garantir que o diretório existe
    if (-not (Test-Path $ConfigDir)) {
        New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    }

    if (Test-Path $ConfigPath) {
        return Get-Content $ConfigPath | ConvertFrom-Json
    } else {
        $DefaultConfig | ConvertTo-Json | Set-Content $ConfigPath
        return $DefaultConfig
    }
}

function Get-WMSHistory {
    # Garantir que o diretório existe
    if (-not (Test-Path $HistoryDir)) {
        New-Item -ItemType Directory -Path $HistoryDir -Force | Out-Null
    }
    
    if (Test-Path $HistoryPath) {
        return Get-Content $HistoryPath | ConvertFrom-Json
    } else {
        $DefaultHistory = @{
            "LastEssential" = "Never"
            "LastUltimate" = "Never"
            "LastDeepDiag" = "Never"
            "LastSmartDiag" = "Never"
        }
        $DefaultHistory | ConvertTo-Json | Set-Content $HistoryPath
        return $DefaultHistory
    }
}

function Update-WMSHistory {
    param ($Key, $Value)
    $History = Get-WMSHistory
    $History.$Key = $Value
    $History | ConvertTo-Json | Set-Content $HistoryPath
}

