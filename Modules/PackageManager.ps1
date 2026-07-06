<#
.SYNOPSIS
    Wrapper para gerenciadores de pacotes (WinGet, Chocolatey, Scoop).
.DESCRIPTION
    Funções unificadas para instalar, atualizar e remover aplicativos.
#>

function Test-Winget {
    return (Get-Command winget -ErrorAction SilentlyContinue) -ne $null
}

function Test-Choco {
    return (Get-Command choco -ErrorAction SilentlyContinue) -ne $null
}

function Test-Scoop {
    return (Get-Command scoop -ErrorAction SilentlyContinue) -ne $null
}

function Install-App {
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [ValidateSet('winget','choco','scoop')][string]$Source = 'winget'
    )
    Write-Host "`n[>] Instalando $Id via $Source..." -ForegroundColor Yellow
    switch ($Source) {
        'winget' { if (Test-Winget) { winget install --id $Id --silent --accept-source-agreements --accept-package-agreements } else { Write-Host "  [ERRO] winget não encontrado." -ForegroundColor Red } }
        'choco'  { if (Test-Choco) { choco install $Id -y } else { Write-Host "  [ERRO] Chocolatey não encontrado." -ForegroundColor Red } }
        'scoop'  { if (Test-Scoop) { scoop install $Id } else { Write-Host "  [ERRO] Scoop não encontrado." -ForegroundColor Red } }
    }
}

function Update-AllApps {
    Write-Host "`n[>] Atualizando todos os pacotes..." -ForegroundColor Yellow
    if (Test-Winget) { winget upgrade --all --silent --accept-source-agreements --accept-package-agreements }
    if (Test-Choco) { choco upgrade all -y }
    if (Test-Scoop) { scoop update * }
    Write-Host "  [OK] Atualização concluída." -ForegroundColor Green
}

function Uninstall-Bloat {
    param([string[]]$Ids = @(
        'Microsoft.ZuneMusic','Microsoft.ZuneVideo','Microsoft.XboxApp','Microsoft.XboxGameOverlay',
        'Microsoft.XboxIdentityProvider','Microsoft.XboxSpeechToTextOverlay','Microsoft.YourPhone',
        'Microsoft.People','Microsoft.MicrosoftSolitaireCollection','Microsoft.MicrosoftStickyNotes',
        'Microsoft.Office.OneNote','Microsoft.SkypeApp','Microsoft.3DBuilder','Microsoft.GetHelp',
        'Microsoft.Getstarted','Microsoft.Messaging','Microsoft.Microsoft3DViewer','Microsoft.OneConnect',
        'Microsoft.Print3D','Microsoft.Wallet','Microsoft.WebMediaExtensions','Microsoft.WebpImageExtension'
    ))
    Write-Host "`n[>] Removendo bloatware pré-definido..." -ForegroundColor Yellow
    foreach ($id in $Ids) {
        Write-Host "  - $id" -ForegroundColor DarkGray
        if (Test-Winget) { winget uninstall --id $id --silent 2>$null }
    }
    Write-Host "  [OK] Limpeza de bloatware concluída." -ForegroundColor Green
}

function Invoke-PackageManagerMenu {
    while ($true) {
        Clear-Host
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  GERENCIADOR DE PACOTES" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "`n  1. Instalar aplicativo (informar ID)"
        Write-Host "  2. Atualizar todos os pacotes"
        Write-Host "  3. Remover bloatware padrão"
        Write-Host "  4. Voltar"
        Write-Host "`n========================================" -ForegroundColor Cyan
        $c = Read-Host "Escolha"
        $c = $c -replace '\s+',''
        switch ($c) {
            "1" { $id = Read-Host "ID do pacote (ex: Microsoft.VSCode)"; Install-App -Id $id; Wait-KeyPress }
            "2" { Update-AllApps; Wait-KeyPress }
            "3" { Uninstall-Bloat; Wait-KeyPress }
            "4" { return }
            default { Write-Host "Opção inválida." -ForegroundColor Red; Start-Sleep 1 }
        }
    }
}

Export-ModuleMember -Function *