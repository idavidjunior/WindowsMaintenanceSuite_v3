<#
.SYNOPSIS
    Perfis de otimização pré-definidos para diferentes cenários de uso.
.DESCRIPTION
    Aplica conjuntos de tweaks (serviços, plano de energia, configurações de rede) conforme o perfil escolhido.
#>

function Set-WMSProfile {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet('Gamer','Developer','Server','BatterySaver','Default')]
        [string]$Profile
    )
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  APLICANDO PERFIL: $Profile" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    switch ($Profile) {
        'Gamer' {
            # Plano de energia Alto Desempenho
            powercfg -setactive SCHEME_MIN
            # Desativar serviços desnecessários
            $svcs = @('SysMain','DiagTrack','WSearch','PrintNotify')
            foreach ($s in $svcs) { Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue; Stop-Service -Name $s -Force -ErrorAction SilentlyContinue }
            Write-Host "  [OK] Perfil Gamer aplicado (Alto Desempenho, serviços desativados)." -ForegroundColor Green
        }
        'Developer' {
            # Manter balanceado, habilitar Hyper-V, WSL, etc.
            Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -NoRestart -ErrorAction SilentlyContinue
            Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart -ErrorAction SilentlyContinue
            Write-Host "  [OK] Perfil Developer aplicado (Hyper-V, WSL habilitados)." -ForegroundColor Green
        }
        'Server' {
            # Otimizar para serviços de rede, desativar UI desnecessária
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 26 -Force -ErrorAction SilentlyContinue
            Write-Host "  [OK] Perfil Server aplicado (prioridade de background)." -ForegroundColor Green
        }
        'BatterySaver' {
            powercfg -setactive SCHEME_MAX
            # Ativar economia de energia
            powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 50
            powercfg /setactive SCHEME_CURRENT
            Write-Host "  [OK] Perfil BatterySaver aplicado (Economia de energia)." -ForegroundColor Green
        }
        'Default' {
            powercfg -setactive SCHEME_BALANCED
            Write-Host "  [OK] Perfil Default (Balanceado) restaurado." -ForegroundColor Green
        }
    }
}