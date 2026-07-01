<#
.SYNOPSIS
    Módulo de diagnóstico SMART dos discos.
.DESCRIPTION
    Este módulo executa diagnóstico SMART dos discos físicos.
#>

# Importar SecurityHelper
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\SecurityHelper.ps1"

# Validar privilégios de administrador
Require-Administrator

function Invoke-SmartDiagnostics {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  DIAGNOSTICO SMART DOS DISCOS" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Log "Iniciando Diagnostico SMART dos Discos..." "INFO"
    
    $Disks = Get-PhysicalDisk
    $diskCount = $Disks.Count
    
    Write-Host "`nEncontrado(s) $diskCount disco(s) fisico(s)." -ForegroundColor Yellow
    
    foreach ($disk in $Disks) {
        Write-Host "`n----------------------------------------" -ForegroundColor Cyan
        Write-Host "Disco: $($disk.FriendlyName)" -ForegroundColor Cyan
        Write-Host "Modelo: $($disk.Model)"
        
        if ($disk.HealthStatus -eq "Healthy") {
            Write-Host "Saude: $($disk.HealthStatus) [OK]" -ForegroundColor Green
        } else {
            Write-Host "Saude: $($disk.HealthStatus) [ATENCAO]" -ForegroundColor Red
        }
        
        Write-Host "Status Operacional: $($disk.OperationalStatus)"
        Write-Host "Tipo: $($disk.BusType)"
        Write-Host "Tamanho: $([Math]::Round($disk.Size / 1GB, 2)) GB"
        
        if ($disk.BusType -eq "NVMe" -or $disk.BusType -eq "SSD") {
            # Tentar pegar desgaste se disponivel via StorageReliabilityCounter
            $Reliability = Get-StorageReliabilityCounter -PhysicalDisk $disk -ErrorAction SilentlyContinue
            if ($Reliability) {
                Write-Host "Desgaste (Wear): $($Reliability.Wear)%"
                Write-Host "Temperatura: $($Reliability.Temperature)C"
            } else {
                Write-Host "Informacoes de desgaste nao disponiveis." -ForegroundColor Gray
            }
        }
    }
    
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  DIAGNOSTICO SMART CONCLUIDO!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    
    Update-WMSHistory -Key "LastSmartDiag" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    Write-Log "Diagnostico SMART concluido." "SUCCESS"
}

