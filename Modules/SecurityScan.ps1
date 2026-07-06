<#
.SYNOPSIS
    Modulo de Verificacao de Virus e Ameacas.
.DESCRIPTION
    Utiliza o Windows Defender nativo (cmdlets do modulo ConfigDefender) para
    detectar ameacas no sistema e em arquivos temporarios, sem depender de
    binarios externos (ex: ClamAV).
#>

. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\SecurityHelper.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\Logger.ps1"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Test-DefenderActive {
    try {
        $status = Get-MpComputerStatus -ErrorAction Stop
        return [bool]($status.AntivirusEnabled -and $status.RealTimeProtectionEnabled)
    } catch {
        return $false
    }
}

function Invoke-VirusScan {
    param(
        [ValidateSet("Quick", "Full", "TempOnly")]
        [string]$ScanType = "Quick"
    )

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  VERIFICACAO DE VIRUS (Windows Defender)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    if (-not (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue)) {
        Write-Host "      [ERRO] Windows Defender nao esta disponivel neste sistema (modulo ConfigDefender ausente)." -ForegroundColor Red
        Write-Host "      [INFO] Isso e comum quando um antivirus terceiro substituiu o Defender." -ForegroundColor Yellow
        Write-Log "Verificacao de virus abortada: ConfigDefender indisponivel." "WARNING"
        return
    }

    if (-not (Test-DefenderActive)) {
        Write-Host "      [AVISO] Windows Defender parece desativado ou substituido por outro antivirus." -ForegroundColor Yellow
        Write-Host "      [INFO] A varredura sera tentada mesmo assim, mas pode falhar." -ForegroundColor Yellow
        Write-Log "Defender inativo no momento da verificacao de virus." "WARNING"
    }

    try {
        switch ($ScanType) {
            "Quick" {
                Write-Host "      [INFO] Iniciando varredura rapida..." -ForegroundColor Cyan
                Start-MpScan -ScanType QuickScan -ErrorAction Stop
            }
            "Full" {
                Write-Host "      [INFO] Iniciando varredura completa (pode demorar bastante)..." -ForegroundColor Cyan
                Start-MpScan -ScanType FullScan -ErrorAction Stop
            }
            "TempOnly" {
                $targets = @($env:TEMP, $env:TMP, "$env:WINDIR\Temp") | Select-Object -Unique | Where-Object { Test-Path $_ }
                foreach ($t in $targets) {
                    Write-Host "      [INFO] Verificando $t ..." -ForegroundColor Cyan
                    Start-MpScan -ScanType CustomScan -ScanPath $t -ErrorAction Stop
                }
            }
        }
        Write-Host "      [OK] Varredura concluida." -ForegroundColor Green
        Write-Log "Varredura de virus ($ScanType) concluida." "SUCCESS"
    } catch {
        Write-Host "      [ERRO] Falha na varredura: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
        Write-Log "Falha na varredura de virus ($ScanType): $_" "ERROR"
        return
    }

    try {
        $threats = Get-MpThreatDetection -ErrorAction SilentlyContinue
        if ($threats -and $threats.Count -gt 0) {
            Write-Host "`n      [ALERTA] $($threats.Count) ameaca(s) detectada(s) no historico recente:" -ForegroundColor Red
            $threats | Select-Object -First 10 | ForEach-Object {
                Write-Host "        - $($_.ThreatName)  [Status: $($_.ThreatStatusID)]" -ForegroundColor Red
            }
            Write-Log "$($threats.Count) ameacas detectadas na varredura." "WARNING"
        } else {
            Write-Host "      [OK] Nenhuma ameaca detectada." -ForegroundColor Green
            Write-Log "Nenhuma ameaca detectada na varredura ($ScanType)." "SUCCESS"
        }
    } catch {
        Write-Host "      [AVISO] Nao foi possivel consultar o historico de ameacas: $(Get-SafeErrorMessage $_)" -ForegroundColor Yellow
    }
}

function Invoke-SecurityScan {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  VERIFICACAO DE VIRUS" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  1. Varredura Rapida (Quick Scan)"
    Write-Host "  2. Varredura Completa (Full Scan - demorado)"
    Write-Host "  3. Verificar apenas Arquivos Temporarios"
    Write-Host "  4. Voltar ao Menu Principal"
    Write-Host "`n========================================" -ForegroundColor Cyan

    $choice = Read-Host "Digite o numero da sua escolha"
    $choice = $choice -replace '\s+', ''

    if (-not (Test-ValidNumericInput -Value $choice -Min 1 -Max 4)) {
        Write-Host "Opção inválida." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    switch ($choice) {
        "1" { Invoke-VirusScan -ScanType Quick }
        "2" { Invoke-VirusScan -ScanType Full }
        "3" { Invoke-VirusScan -ScanType TempOnly }
        "4" { return }
    }
}

Export-ModuleMember -Function *
