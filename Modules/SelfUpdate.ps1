<#
.SYNOPSIS
    Módulo de auto-atualização do Windows Maintenance Suite.
.DESCRIPTION
    Realiza git pull no repositório local e reinicia o launcher se houver atualizações.
#>

function Update-WMS {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  AUTO-ATUALIZAÇÃO DO WMS" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    # Diretório raiz do repositório (um nível acima de Modules)
    $repoRoot = Split-Path -Parent $PSScriptRoot
    if (-not (Test-Path (Join-Path $repoRoot '.git'))) {
        Write-Host "  [ERRO] Não é um repositório git. Baixe o projeto via git clone." -ForegroundColor Red
        return
    }

    Push-Location $repoRoot
    try {
        Write-Host "`n[>] Verificando atualizações remotas..." -ForegroundColor Yellow
        $fetch = git fetch origin main 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [ERRO] Falha no git fetch: $fetch" -ForegroundColor Red
            return
        }

        # Verifica se há commits novos
        $behind = git rev-list --count HEAD..origin/main 2>&1
        if ($LASTEXITCODE -eq 0 -and [int]$behind -gt 0) {
            Write-Host "`n[>] Novas atualizações encontradas ($behind commit(s)). Aplicando..." -ForegroundColor Yellow
            $pull = git pull origin main 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [OK] Repositório atualizado com sucesso." -ForegroundColor Green
                Write-Host "`n[>] Reiniciando o Windows Maintenance Suite..." -ForegroundColor Yellow
                # Relança o launcher (WMS.bat) e encerra este processo
                $launcher = Join-Path $repoRoot 'WMS.bat'
                if (Test-Path $launcher) {
                    Start-Process -FilePath $launcher -WorkingDirectory $repoRoot -WindowStyle Hidden
                }
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