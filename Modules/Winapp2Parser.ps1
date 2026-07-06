<#
.SYNOPSIS
    Parser para o arquivo Winapp2.ini (regras de limpeza da comunidade).
.DESCRIPTION
    Baixa (se necessário) e converte as seções do Winapp2.ini em objetos compatíveis
    com Get-RegistryScanCategories (Name, Hives, IsValueScan, ValueNameIsPath, Check).
#>

function Import-Winapp2Rules {
    param(
        [string]$Winapp2Path = "$env:TEMP\Winapp2.ini",
        [switch]$ForceDownload
    )

    # Baixar a versão mais recente se não existir ou ForceDownload
    if ($ForceDownload -or -not (Test-Path $Winapp2Path)) {
        Write-Host "[>] Baixando Winapp2.ini mais recente..." -ForegroundColor Yellow
        try {
            Invoke-WebRequest -Uri "https://raw.githubusercontent.com/MoscaDotTo/Winapp2/master/Winapp2.ini" -OutFile $Winapp2Path -ErrorAction Stop
            Write-Host "  [OK] Download concluído." -ForegroundColor Green
        } catch {
            Write-Host "  [ERRO] Falha ao baixar Winapp2.ini: $_" -ForegroundColor Red
            return @()
        }
    }

    $content = Get-Content -Path $Winapp2Path -Raw -ErrorAction SilentlyContinue
    if (-not $content) { return @() }

    $rules = @()
    # Regex para capturar seções: [Nome] ... linhas até próxima seção ou fim
    $sections = [System.Text.RegularExpressions.Regex]::Matches($content, '(?ms)^\[(.+?)\](.+?)(?=^\[|\Z)')
    foreach ($m in $sections) {
        $name = $m.Groups[1].Value.Trim()
        $body = $m.Groups[2].Value
        # Procurar linhas RegKeyX ou RegValueX
        $regKeys = [System.Text.RegularExpressions.Regex]::Matches($body, '^RegKey\d+=(.+)$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
        $regValues = [System.Text.RegularExpressions.Regex]::Matches($body, '^RegValue\d+=(.+)$', [System.Text.RegularExpressions.RegexOptions]::Multiline)

        # Se não houver registro, ignora
        if ($regKeys.Count -eq 0 -and $regValues.Count -eq 0) { continue }

        $hives = @()
        $isValueScan = $false
        $valueNameIsPath = $false
        $checkScript = $null

        # Processar RegKey (chaves)
        if ($regKeys.Count -gt 0) {
            foreach ($k in $regKeys) {
                $path = $k.Groups[1].Value.Trim()
                # Converter caminhos Winapp2 (HKLM, HKCU) para PSDrives
                $psPath = $path -replace '^HKLM\\', 'HKLM:\' -replace '^HKCU\\', 'HKCU:\' -replace '\\', '\'
                $hives += $psPath
            }
        }

        # Processar RegValue (valores)
        if ($regValues.Count -gt 0) {
            $isValueScan = $true
            foreach ($v in $regValues) {
                $path = $v.Groups[1].Value.Trim()
                $psPath = $path -replace '^HKLM\\', 'HKLM:\' -replace '^HKCU\\', 'HKCU:\' -replace '\\', '\'
                $hives += $psPath
            }
        }

        # Script de verificação genérico: testa existência do caminho/valor
        $checkScript = {
            param($target)
            # Se target é caminho de arquivo ou pasta
            if ($target -match '^[A-Za-z]:\\') {
                return (-not (Test-Path -Path $target -ErrorAction SilentlyContinue))
            }
            # Se é chave/valor de registro (já validado pelo chamador)
            return $false
        }

        $rules += @{
            Name = $name
            Hives = $hives | Select-Object -Unique
            IsValueScan = $isValueScan
            ValueNameIsPath = $valueNameIsPath
            Check = $checkScript
        }
    }

    Write-Host "  [OK] $($rules.Count) regras Winapp2 carregadas." -ForegroundColor Green
    return $rules
}

