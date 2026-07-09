<#
.SYNOPSIS
    Hardening básico baseado em Microsoft Security Baselines / CIS Benchmarks.
.DESCRIPTION
    Aplica configurações de segurança recomendadas (Defender, Firewall, UAC, SMBv1, etc.).
#>

function Invoke-Hardening {
    param (
        [ValidateSet('Baseline','Strict')]
        [string]$Level = 'Baseline'
    )
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  HARDENING DE SEGURANÇA - $Level" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    # Windows Defender - Proteção em tempo real
    try {
        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
        Set-MpPreference -DisableBehaviorMonitoring $false -ErrorAction Stop
        Set-MpPreference -DisableBlockAtFirstSeen $false -ErrorAction Stop
        Set-MpPreference -DisableIOAVProtection $false -ErrorAction Stop
        Set-MpPreference -DisableScriptScanning $false -ErrorAction Stop
        Write-Host "  [OK] Windows Defender configurado (proteção ativa)." -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] Não foi possível configurar Defender: $_" -ForegroundColor Yellow
    }

    # Firewall - perfis ativos
    try {
        Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction Stop
        Write-Host "  [OK] Firewall ativado em todos os perfis." -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] Falha ao ativar firewall: $_" -ForegroundColor Yellow
    }

    # UAC - nível padrão (não desativar)
    try {
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableLUA' -Value 1 -Force -ErrorAction Stop
        Write-Host "  [OK] UAC habilitado." -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] Falha ao configurar UAC: $_" -ForegroundColor Yellow
    }

    # Desativar SMBv1
    try {
        Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction Stop
        Write-Host "  [OK] SMBv1 desativado." -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] Falha ao desativar SMBv1: $_" -ForegroundColor Yellow
    }

    # Restringir execução de scripts não assinados (PowerShell)
    try {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force -ErrorAction Stop
        Write-Host "  [OK] ExecutionPolicy definido como RemoteSigned." -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] Falha ao definir ExecutionPolicy: $_" -ForegroundColor Yellow
    }

    if ($Level -eq 'Strict') {
        # Extras: desativar LLMNR, NetBIOS over TCP/IP, etc.
        try {
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' -Name 'EnableMulticast' -Value 0 -Force -ErrorAction Stop
            Write-Host "  [OK] LLMNR desativado." -ForegroundColor Green
        } catch {
            Write-Host "  [AVISO] Falha ao desativar LLMNR: $_" -ForegroundColor Yellow
        }
        try {
            $nics = Get-NetAdapter -Physical | Where-Object {$_.Status -eq 'Up'}
            foreach ($nic in $nics) {
                Set-NetIPv4Protocol -InterfaceIndex $nic.ifIndex -DhcpEnabled $true -ErrorAction SilentlyContinue
                # Desativar NetBIOS over TCP/IP
                $adapter = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "Index=$($nic.ifIndex)"
                if ($adapter) { $adapter.SetTcpipNetbios(2) | Out-Null }
            }
            Write-Host "  [OK] NetBIOS over TCP/IP desativado nas interfaces ativas." -ForegroundColor Green
        } catch {
            Write-Host "  [AVISO] Falha ao desativar NetBIOS: $_" -ForegroundColor Yellow
        }
    }

    Write-Host "`n  Hardening $Level concluído." -ForegroundColor Cyan
}

function Invoke-HardeningMenu {
    while ($true) {
        Clear-Host
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  HARDENING DE SEGURANÇA" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "`n  1. Baseline"
        Write-Host "  2. Strict"
        Write-Host "  3. Voltar"
        Write-Host "`n========================================" -ForegroundColor Cyan
        $c = Read-Host "Escolha"
        $c = $c -replace '\s+',''
        switch ($c) {
            "1" { Invoke-Hardening -Level Baseline; Wait-KeyPress }
            "2" { Invoke-Hardening -Level Strict; Wait-KeyPress }
            "3" { return }
            default { Write-Host "Opção inválida." -ForegroundColor Red; Start-Sleep 1 }
        }
    }
}

