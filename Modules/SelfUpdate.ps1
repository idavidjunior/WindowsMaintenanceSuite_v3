<#
.SYNOPSIS
    Módulo de auto-atualização do Windows Maintenance Suite.
.DESCRIPTION
    Realiza git pull no repositório local e reinicia o launcher.
#>

function Update-WMS {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  AUTO-ATUALIZAÇÃO DO WMS" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)
    Push-Location $repoRoot

    try {
        Write-Host "`n[>] Verificando atualizações remotas..." -ForegroundColor Yellow
        $fetch = git fetch origin main 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [ERRO] Falha no git fetch: $fetch" -ForegroundColor Red
            return
        }

        $status = git status -uno 2>&1
        if ($status -match 'Your branch is behind') {
            Write-Host "`n[>] Novas atualizações encontradas. Aplicando..." -ForegroundColor Yellow
            $pull = git pull origin main 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [OK] Repositório atualizado com sucesso." -ForegroundColor Green
                Write-Host "`n[>] Reiniciando o Windows Maintenance Suite..." -ForegroundColor Yellow
                Start-Process -FilePath "cmd.exe" -ArgumentList "/c start \"\" \"$repoRoot\WMS.bat\"" -NoNewWindow
                exit 0
            } else {
                Write-Host "  [ERRO] Falha no git pull: $pull" -ForegroundColor Red
            }
        } else {
            Write-Host "`n[OK] Já está na versão mais recente." -ForegroundColor Green
        }
    } catch {
        Write-Host "  [ERRO] Exceção durante atualização: $_" -ForegroundColor Red
    } finally {
        Pop-Location
    }
}