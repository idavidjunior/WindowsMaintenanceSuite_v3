<#
.SYNOPSIS
    Modulo de Agendamento de Manutencao.
.DESCRIPTION
    Cria/remove tarefas agendadas no Windows (Task Scheduler) para rodar a
    manutencao essencial do WMS de forma automatica (semanal, etc.).
#>

. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\SecurityHelper.ps1"
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\Logger.ps1"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$WMS_TASK_NAME = "WMS_AutomaticMaintenance"
$WMS_BAT_PATH = Join-Path (Split-Path -Parent $PSScriptRoot) "WMS.bat"

function Get-WMSScheduledTaskInfo {
    try {
        $task = Get-ScheduledTask -TaskName $WMS_TASK_NAME -ErrorAction SilentlyContinue
        if ($task) {
            $info = Get-ScheduledTaskInfo -TaskName $WMS_TASK_NAME -ErrorAction SilentlyContinue
            return @{
                Exists       = $true
                State        = $task.State
                LastRunTime  = if ($info) { $info.LastRunTime } else { "N/D" }
                LastResult   = if ($info) { $info.LastTaskResult } else { "N/D" }
                NextRunTime  = if ($info) { $info.NextRunTime } else { "N/D" }
                Trigger      = $task.Triggers
            }
        }
    } catch {}
    return @{ Exists = $false }
}

function New-WMSMaintenanceTask {
    <#
    .SYNOPSIS
        Cria a tarefa agendada de manutencao automatica.
    .PARAMETER DayOfWeek
        Dia da semana (Sunday..Saturday). Padrao: Sunday.
    .PARAMETER Time
        Horario (HH:mm). Padrao: 03:00.
    #>
    param(
        [string]$DayOfWeek = "Sunday",
        [string]$Time = "03:00"
    )

    try {
        # Remover tarefa existente antes de recriar
        $existing = Get-ScheduledTask -TaskName $WMS_TASK_NAME -ErrorAction SilentlyContinue
        if ($existing) {
            Unregister-ScheduledTask -TaskName $WMS_TASK_NAME -Confirm:$false -ErrorAction SilentlyContinue
        }

        $action = New-ScheduledTaskAction -Execute $WMS_BAT_PATH
        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $Time
        $settings = New-ScheduledTaskSettingsSet `
            -StartWhenAvailable `
            -DontStopOnIdleEnd `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -RunOnlyIfNetworkAvailable:$false `
            -ExecutionTimeLimit (New-TimeSpan -Hours 2)

        # Rodar com privilegios elevados (SYSTEM nao precisa de senha)
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest -LogonType ServiceAccount

        Register-ScheduledTask `
            -TaskName $WMS_TASK_NAME `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Principal $principal `
            -Description "Manutencao automatica do Windows Maintenance Suite (Essencial)" | Out-Null

        Write-Host "      [OK] Tarefa agendada criada com sucesso!" -ForegroundColor Green
        Write-Host "      Dia:  $DayOfWeek as $Time" -ForegroundColor Green
        Write-Host "      Modo: SYSTEM (elevado, sem login necessario)" -ForegroundColor Green
        Write-Log "Tarefa de manutencao agendada criada: $DayOfWeek as $Time" "SUCCESS"
        return $true
    } catch {
        Write-Host "      [ERRO] Falha ao criar tarefa agendada: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
        Write-Log "Erro ao criar tarefa agendada: $_" "ERROR"
        return $false
    }
}

function Remove-WMSMaintenanceTask {
    try {
        $task = Get-ScheduledTask -TaskName $WMS_TASK_NAME -ErrorAction SilentlyContinue
        if (-not $task) {
            Write-Host "      [INFO] Nenhuma tarefa de manutencao agendada encontrada." -ForegroundColor Cyan
            return $false
        }
        Unregister-ScheduledTask -TaskName $WMS_TASK_NAME -Confirm:$false
        Write-Host "      [OK] Tarefa de manutencao agendada removida." -ForegroundColor Green
        Write-Log "Tarefa de manutencao agendada removida." "SUCCESS"
        return $true
    } catch {
        Write-Host "      [ERRO] Falha ao remover tarefa: $(Get-SafeErrorMessage $_)" -ForegroundColor Red
        Write-Log "Erro ao remover tarefa agendada: $_" "ERROR"
        return $false
    }
}

function Invoke-MaintenanceScheduler {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  MANUTENCAO AGENDADA" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    # Status atual
    $info = Get-WMSScheduledTaskInfo
    if ($info.Exists) {
        Write-Host "`n  Status da tarefa '$WMS_TASK_NAME':" -ForegroundColor Green
        Write-Host "    Estado:        $($info.State)" -ForegroundColor White
        Write-Host "    Ultima execucao: $($info.LastRunTime)" -ForegroundColor White
        Write-Host "    Proxima execucao: $($info.NextRunTime)" -ForegroundColor White
        $res = if ($info.LastResult -eq 0) { "Sucesso (0)" } else { "Codigo: $($info.LastResult)" }
        Write-Host "    Ultimo resultado: $res" -ForegroundColor White
    } else {
        Write-Host "`n  [INFO] Nenhuma tarefa de manutencao agendada no momento." -ForegroundColor Yellow
    }

    Write-Host "`nSelecione uma opcao:" -ForegroundColor Cyan
    Write-Host "  1. Agendar manutencao semanal (escolher dia/hora)"
    Write-Host "  2. Agendar padrao (Domingo as 03:00)"
    Write-Host "  3. Remover tarefa agendada"
    Write-Host "  4. Voltar ao Menu Principal"
    Write-Host "`n========================================" -ForegroundColor Cyan

    $choice = Read-Host "Digite o numero da sua escolha"
    $choice = $choice -replace '\s+', ''

    if (-not (Test-ValidNumericInput -Value $choice -Min 1 -Max 4)) {
        Write-Host "Opcao invalida. Digite um numero entre 1 e 4." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    switch ($choice) {
        "1" {
            Write-Host "`nDias disponiveis: Sunday, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday" -ForegroundColor Cyan
            $day = Read-Host "Digite o dia (ex: Sunday)"
            $time = Read-Host "Digite o horario (HH:mm, ex: 03:00)"
            if ([string]::IsNullOrWhiteSpace($day)) { $day = "Sunday" }
            if ([string]::IsNullOrWhiteSpace($time)) { $time = "03:00" }
            New-WMSMaintenanceTask -DayOfWeek $day -Time $time
        }
        "2" { New-WMSMaintenanceTask -DayOfWeek "Sunday" -Time "03:00" }
        "3" { Remove-WMSMaintenanceTask }
        "4" { return }
    }
}
