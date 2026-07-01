<#
.SYNOPSIS
    Módulo de segurança e validação para o Windows Maintenance Suite.
.DESCRIPTION
    Este módulo fornece funções de segurança comuns para validação de
    privilégios, sanitização de input e verificação de comandos externos.
#>

function Test-Administrator {
    <#
    .SYNOPSIS
        Verifica se o script está sendo executado com privilégios de administrador.
    .OUTPUTS
        Boolean indicando se tem privilégios de administrador.
    #>
    try {
        $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Require-Administrator {
    <#
    .SYNOPSIS
        Exige privilégios de administrador e encerra o script se não tiver.
    #>
    if (-not (Test-Administrator)) {
        Write-Host "ERRO: Este script requer privilégios de administrador." -ForegroundColor Red
        Write-Host "Por favor, execute o PowerShell como administrador e tente novamente." -ForegroundColor Yellow
        exit 1
    }
}

function Test-ExternalCommand {
    <#
    .SYNOPSIS
        Verifica se um comando externo está disponível no sistema.
    .PARAMETER Command
        Nome do comando a verificar.
    .OUTPUTS
        Boolean indicando se o comando está disponível.
    #>
    param (
        [Parameter(Mandatory=$true)]
        [string]$Command
    )
    
    try {
        $null = Get-Command $Command -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Get-SafeBackupPath {
    <#
    .SYNOPSIS
        Retorna um caminho seguro para backups, usando diretório temporário se C:\ não for acessível.
    .OUTPUTS
        String com o caminho do diretório de backup.
    #>
    $primaryPath = "C:\WMS_RegistryBackups"
    $fallbackPath = Join-Path $env:TEMP "WMS_RegistryBackups"
    
    # Tentar usar caminho primário
    try {
        if (-not (Test-Path $primaryPath)) {
            New-Item -ItemType Directory -Path $primaryPath -Force -ErrorAction Stop | Out-Null
        }
        # Testar escrita
        $testFile = Join-Path $primaryPath "test_write.tmp"
        "test" | Out-File $testFile -ErrorAction Stop
        Remove-Item $testFile -Force -ErrorAction Stop
        return $primaryPath
    } catch {
        # Fallback para diretório temporário
        try {
            if (-not (Test-Path $fallbackPath)) {
                New-Item -ItemType Directory -Path $fallbackPath -Force -ErrorAction Stop | Out-Null
            }
            return $fallbackPath
        } catch {
            throw "Não foi possível criar diretório de backup em nenhum local."
        }
    }
}

function Mask-MacAddress {
    <#
    .SYNOPSIS
        Mascarar endereço MAC para privacidade.
    .PARAMETER MacAddress
        Endereço MAC a mascarar.
    .PARAMETER ShowFull
        Se true, retorna MAC completo. Se false, retorna mascarado.
    .OUTPUTS
        String com MAC mascarado ou completo.
    #>
    param (
        [Parameter(Mandatory=$true)]
        [string]$MacAddress,
        [bool]$ShowFull = $false
    )
    
    if ($ShowFull) {
        return $MacAddress
    }
    
    # Mascarar mantendo apenas os primeiros 4 caracteres
    if ($MacAddress.Length -ge 4) {
        return $MacAddress.Substring(0, 4) + ":XX:XX:XX:XX"
    }
    return "XX:XX:XX:XX:XX:XX"
}

function Test-ValidNumericInput {
    <#
    .SYNOPSIS
        Valida se input é numérico e está dentro de um range.
    .PARAMETER Input
        Input a validar.
    .PARAMETER Min
        Valor mínimo permitido.
    .PARAMETER Max
        Valor máximo permitido.
    .OUTPUTS
        Boolean indicando se input é válido.
    #>
    param (
        [Parameter(Mandatory=$true)]
        $Input,
        [int]$Min = [int]::MinValue,
        [int]$Max = [int]::MaxValue
    )

    # Remover espaços em branco
    $cleanedInput = $Input -replace '\s+', ''

    try {
        $numeric = [int]$cleanedInput
        return ($numeric -ge $Min -and $numeric -le $Max)
    } catch {
        return $false
    }
}

function Get-SafeErrorMessage {
    <#
    .SYNOPSIS
        Retorna mensagem de erreur segura sem expor detalhes técnicos.
    .PARAMETER Error
        Objeto de erro.
    .OUTPUTS
        String com mensagem de erro genérica.
    #>
    param (
        [Parameter(Mandatory=$true)]
        $Error
    )
    
    # Mensagens genéricas baseadas no tipo de erro
    if ($Error -match "access denied|unauthorized|permission") {
        return "Erro de permissão: Acesso negado."
    } elseif ($Error -match "not found|file does not exist") {
        return "Erro de arquivo: Recurso não encontrado."
    } elseif ($Error -match "registry") {
        return "Erro de registro: Não foi possível modificar o registro."
    } elseif ($Error -match "network|connection") {
        return "Erro de rede: Falha na conexão."
    } else {
        return "Erro operacional: A operação não pôde ser concluída."
    }
}

function Invoke-WithRollback {
    <#
    .SYNOPSIS
        Executa um scriptblock com rollback automático em caso de falha.
    .PARAMETER ScriptBlock
        Scriptblock a executar.
    .PARAMETER RollbackScript
        Scriptblock de rollback a executar em caso de falha.
    .OUTPUTS
        Boolean indicando sucesso da operação.
    #>
    param (
        [Parameter(Mandatory=$true)]
        [scriptblock]$ScriptBlock,
        [Parameter(Mandatory=$true)]
        [scriptblock]$RollbackScript
    )
    
    try {
        & $ScriptBlock
        return $true
    } catch {
        Write-Host "Erro detectado. Iniciando rollback..." -ForegroundColor Yellow
        try {
            & $RollbackScript
            Write-Host "Rollback concluído com sucesso." -ForegroundColor Green
        } catch {
            Write-Host "Erro durante rollback: $_" -ForegroundColor Red
        }
        return $false
    }
}
