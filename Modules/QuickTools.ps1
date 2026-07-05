<#
.SYNOPSIS
    Atalhos para ferramentas nativas do Windows ainda nao cobertas pela suite.
.DESCRIPTION
    NAO duplica o que ja existe: cleanmgr/sagerun (DeepCleaning.ps1), SFC e
    DISM /RestoreHealth (EssentialMaintenance.ps1), DISM StartComponentCleanup
    (UltimateMaintenance.ps1), CHKDSK /scan somente-leitura (EssentialMaintenance.ps1).
    Este modulo cobre apenas o que faltava: defrag GUI, diagnostico de memoria,
    consoles MMC, Steps Recorder, MRT, Driver Verifier, God Mode, o painel
    interativo do cleanmgr (/sageset), CHKDSK /f /r (reparo real, exige reboot)
    e winget upgrade --all (com preview obrigatorio antes de aplicar).
#>

. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\SecurityHelper.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\Core\Logger.ps1"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ---------------------------------------------------------------------------
# Lancadores simples (ferramentas GUI nativas, sem risco de execucao)
# ---------------------------------------------------------------------------

function Open-DiskDefrag {
    Write-Host "`n[>] Abrindo Desfragmentar e Otimizar Unidades..." -ForegroundColor Yellow
    Start-Process "dfrgui.exe"
    Write-Log "Abriu dfrgui (Desfragmentar e Otimizar Unidades)." "INFO"
}

function Open-MemoryDiagnostic {
    Write-Host "`n[>] Abrindo Diagnostico de Memoria do Windows..." -ForegroundColor Yellow
    Write-Host "      [AVISO] Isso vai pedir reinicializacao para rodar o teste de memoria." -ForegroundColor Yellow
    Start-Process "mdsched.exe"
    Write-Log "Abriu mdsched (Diagnostico de Memoria)." "INFO"
}

function Open-DiskManagement {
    Write-Host "`n[>] Abrindo Gerenciamento de Disco..." -ForegroundColor Yellow
    Start-Process "diskmgmt.msc"
    Write-Log "Abriu diskmgmt.msc (Gerenciamento de Disco)." "INFO"
}

function Open-ServicesConsole {
    Write-Host "`n[>] Abrindo Servicos..." -ForegroundColor Yellow
    Start-Process "services.msc"
    Write-Log "Abriu services.msc (Servicos)." "INFO"
}

function Open-StepsRecorder {
    Write-Host "`n[>] Abrindo Gravador de Passos..." -ForegroundColor Yellow
    Start-Process "psr.exe"
    Write-Log "Abriu psr.exe (Gravador de Passos)." "INFO"
}

function Invoke-MaliciousSoftwareRemovalTool {
    Write-Host "`n[>] Abrindo Ferramenta de Remocao de Software Malintencionado (MRT)..." -ForegroundColor Yellow
    if (-not (Test-ExternalCommand "mrt.exe")) {
        Write-Host "      [ERRO] mrt.exe nao encontrado neste sistema." -ForegroundColor Red
        Write-Log "MRT nao encontrado no sistema." "WARNING"
        return
    }
    Start-Process "mrt.exe"
    Write-Log "Abriu mrt.exe (Malicious Software Removal Tool)." "INFO"
}

function Open-DriverVerifier {
    Write-Host "`n[>] Abrindo Verificador de Drivers..." -ForegroundColor Yellow
    Write-Host "      [AVISO] So abre o assistente. NAO habilite verificacao em drivers de producao" -ForegroundColor Red
    Write-Host "      sem saber o que esta fazendo - Driver Verifier pode causar tela azul de proposito" -ForegroundColor Red
    Write-Host "      para forcar a falha de um driver com bug. Use so para diagnostico." -ForegroundColor Red
    Start-Process "verifier.exe"
    Write-Log "Abriu verifier.exe (Driver Verifier)." "WARNING"
}

function Enable-GodModeFolder {
    Write-Host "`n[>] Criando pasta God Mode na Area de Trabalho..." -ForegroundColor Yellow
    $desktop = [Environment]::GetFolderPath("Desktop")
    $godModePath = Join-Path -Path $desktop -ChildPath "ModoDeDeus.{ED7BA470-8E54-465E-825C-99712043E01C}"
    if (Test-Path $godModePath) {
        Write-Host "      [INFO] Pasta God Mode ja existe na Area de Trabalho." -ForegroundColor Cyan
        return
    }
    try {
        New-Item -ItemType Directory -Path $godModePath -Force | Out-Null
        Write-Host "      [OK] Pasta 'ModoDeDeus' criada na Area de Trabalho." -ForegroundColor Green
        Write-Log "Pasta God Mode criada em $godModePath." "SUCCESS"
    } catch {
        Write-Host "      [ERRO] Falha ao criar a pasta: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
        Write-Log "Falha ao criar pasta God Mode: $_" "ERROR"
    }
}

function Invoke-HiddenDiskCleanupConfig {
    Write-Host "`n[>] Abrindo painel de configuracao do Disk Cleanup (sageset:1)..." -ForegroundColor Yellow
    Write-Host "      [INFO] Marque as categorias que quiser e clique OK. Isso so salva a config -" -ForegroundColor Cyan
    Write-Host "      nada e apagado agora. Depois de configurado, use 'cleanmgr /sagerun:1' para aplicar." -ForegroundColor Cyan
    Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sageset:1"
    Write-Log "Abriu cleanmgr /sageset:1 (configuracao do Disk Cleanup estendido)." "INFO"
}

# ---------------------------------------------------------------------------
# CHKDSK /f /r - reparo real, diferente do /scan somente-leitura ja existente
# ---------------------------------------------------------------------------

function Invoke-CheckDiskRepair {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  CHKDSK /f /r - REPARO DE DISCO" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  [AVISO] Isso e DIFERENTE do CHKDSK /scan que a Manutencao Essencial" -ForegroundColor Red
    Write-Host "  ja roda. /f corrige erros e /r localiza setores defeituosos e recupera" -ForegroundColor Red
    Write-Host "  dados legiveis - mas exige acesso exclusivo ao volume. Se for o disco" -ForegroundColor Red
    Write-Host "  do sistema (C:), o Windows vai AGENDAR para o proximo reboot, e a" -ForegroundColor Red
    Write-Host "  maquina fica indisponivel durante a checagem (pode levar horas em" -ForegroundColor Red
    Write-Host "  discos grandes ou com muitos setores defeituosos)." -ForegroundColor Red

    $drive = Read-Host "`nDigite a letra do drive a verificar (ex: C)"
    $drive = ($drive -replace '[^a-zA-Z]', '').ToUpper()
    if ([string]::IsNullOrWhiteSpace($drive)) {
        Write-Host "      Letra de drive invalida. Abortando." -ForegroundColor Red
        return
    }
    $driveLetter = "$drive`:"
    if (-not (Test-Path $driveLetter)) {
        Write-Host "      [ERRO] Drive $driveLetter nao encontrado." -ForegroundColor Red
        return
    }

    $confirm = Read-Host "Confirma rodar 'chkdsk $driveLetter /f /r'? Pode exigir reboot e travar a maquina por horas. (S/N)"
    if ($confirm -notmatch '^[Ss]') {
        Write-Host "      Cancelado pelo usuario." -ForegroundColor Yellow
        Write-Log "CHKDSK /f /r cancelado pelo usuario para $driveLetter." "INFO"
        return
    }

    Write-Log "Iniciando CHKDSK /f /r para $driveLetter (usuario confirmou)." "WARNING"
    # Alimenta "Y" automaticamente caso o chkdsk pergunte se quer agendar para o proximo boot
    $output = "Y" | & chkdsk.exe $driveLetter /f /r 2>&1
    $output | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }
    Write-Log "CHKDSK /f /r para $driveLetter finalizado ou agendado." "INFO"
}

# ---------------------------------------------------------------------------
# Winget upgrade --all - com preview obrigatorio antes de aplicar
# ---------------------------------------------------------------------------

function Invoke-WingetUpgradeAll {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  WINGET - ATUALIZAR TODOS OS PROGRAMAS" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    if (-not (Test-ExternalCommand "winget")) {
        Write-Host "      [ERRO] winget nao esta instalado ou nao esta no PATH." -ForegroundColor Red
        Write-Log "Winget nao encontrado no sistema." "WARNING"
        return
    }

    Write-Host "      [INFO] Listando atualizacoes disponiveis (nada sera alterado ainda)..." -ForegroundColor Cyan
    & winget.exe upgrade

    $confirm = Read-Host "`nAplicar TODAS as atualizacoes listadas acima com 'winget upgrade --all'? (S/N)"
    if ($confirm -notmatch '^[Ss]') {
        Write-Host "      Cancelado. Nenhum programa foi atualizado." -ForegroundColor Yellow
        Write-Log "Winget upgrade --all cancelado pelo usuario apos preview." "INFO"
        return
    }

    Write-Log "Iniciando winget upgrade --all (usuario confirmou apos preview)." "INFO"
    & winget.exe upgrade --all --silent --accept-source-agreements --accept-package-agreements
    Write-Host "      [OK] winget upgrade --all concluido." -ForegroundColor Green
    Write-Log "Winget upgrade --all concluido." "SUCCESS"
}

# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------

function Invoke-QuickToolsMenu {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  FERRAMENTAS NATIVAS DO WINDOWS" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  1. Desfragmentar e Otimizar Unidades (dfrgui)"
    Write-Host "  2. Diagnostico de Memoria do Windows (mdsched)"
    Write-Host "  3. Gerenciamento de Disco (diskmgmt.msc)"
    Write-Host "  4. Servicos (services.msc)"
    Write-Host "  5. Gravador de Passos (psr)"
    Write-Host "  6. Ferramenta de Remocao de Software Malintencionado (mrt)"
    Write-Host "  7. Verificador de Drivers (verifier) [AVISO: pode causar BSOD proposital]"
    Write-Host "  8. Criar Pasta God Mode na Area de Trabalho"
    Write-Host "  9. Configurar Disk Cleanup Estendido (cleanmgr /sageset:1)"
    Write-Host " 10. CHKDSK /f /r - Reparo de Disco [AVISO: pode exigir reboot]"
    Write-Host " 11. Winget - Atualizar Todos os Programas [com preview antes de aplicar]"
    Write-Host " 12. Voltar ao Menu Principal"
    Write-Host "`n========================================" -ForegroundColor Cyan

    $choice = Read-Host "Digite o numero da sua escolha"
    $choice = $choice -replace '\s+', ''

    if (-not (Test-ValidNumericInput -Value $choice -Min 1 -Max 12)) {
        Write-Host "Opcao invalida." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    switch ($choice) {
        "1"  { Open-DiskDefrag }
        "2"  { Open-MemoryDiagnostic }
        "3"  { Open-DiskManagement }
        "4"  { Open-ServicesConsole }
        "5"  { Open-StepsRecorder }
        "6"  { Invoke-MaliciousSoftwareRemovalTool }
        "7"  { Open-DriverVerifier }
        "8"  { Enable-GodModeFolder }
        "9"  { Invoke-HiddenDiskCleanupConfig }
        "10" { Invoke-CheckDiskRepair }
        "11" { Invoke-WingetUpgradeAll }
        "12" { return }
    }
}
