<# 
Ejecucion recomendada (bypass solo para este proceso):
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\rd-config.ps1
#>

# === Configure RustDesk (Windows) - RustDesk2.toml ===
$Rendezvous = "TU_DOMINIO_O_IP"
$Relay      = "TU_DOMINIO_O_IP"
$Key        = "TU_PUBLIC_KEY"

$cfgDir  = Join-Path (Join-Path $env:APPDATA "RustDesk") "config"
$cfgFile = Join-Path $cfgDir "RustDesk2.toml"

function Update-TomlOptions([string]$content, [hashtable]$updates, [string[]]$removeKeys = @()) {
  $lines = @()
  if ($null -ne $content -and $content.Length -gt 0) {
    $lines = $content -split "`r?`n"
  }

  $sectionStart = -1
  $sectionEnd = $lines.Count
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*\[options\]\s*$') {
      $sectionStart = $i
      for ($j = $i + 1; $j -lt $lines.Count; $j++) {
        if ($lines[$j] -match '^\s*\[[^\]]+\]\s*$') {
          $sectionEnd = $j
          break
        }
      }
      break
    }
  }

  if ($sectionStart -eq -1) {
    if ($lines.Count -gt 0 -and $lines[-1].Trim().Length -gt 0) {
      $lines += ""
    }
    $lines += "[options]"
    foreach ($k in $updates.Keys) {
      $safe = ([string]$updates[$k]).Replace("\", "\\").Replace('"', '\"')
      $lines += "$k = ""$safe"""
    }
  } else {
    $removeSet = @{}
    foreach ($k in $removeKeys) { $removeSet[$k] = $true }

    $found = @{}
    foreach ($k in $updates.Keys) { $found[$k] = $false }

    [System.Collections.ArrayList]$list = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($i -gt $sectionStart -and $i -lt $sectionEnd) {
        $line = $lines[$i]
        if ($line -match '^\s*([A-Za-z0-9_.-]+)\s*=') {
          $currentKey = $matches[1]
          if ($removeSet.ContainsKey($currentKey)) {
            continue
          }
          if ($updates.ContainsKey($currentKey)) {
            $safe = ([string]$updates[$currentKey]).Replace("\", "\\").Replace('"', '\"')
            [void]$list.Add("$currentKey = ""$safe""")
            $found[$currentKey] = $true
            continue
          }
        }
        [void]$list.Add($line)
      } else {
        [void]$list.Add($lines[$i])
      }
    }

    $headerIndex = -1
    for ($i = 0; $i -lt $list.Count; $i++) {
      if ($list[$i] -match '^\s*\[options\]\s*$') {
        $headerIndex = $i
        break
      }
    }
    if ($headerIndex -lt 0) { $headerIndex = 0 }

    $insertAt = $headerIndex + 1
    foreach ($k in $updates.Keys) {
      if (-not $found[$k]) {
        $safe = ([string]$updates[$k]).Replace("\", "\\").Replace('"', '\"')
        [void]$list.Insert($insertAt, "$k = ""$safe""")
        $insertAt++
      }
    }

    $lines = @($list)
  }

  return ($lines -join "`r`n")
}

function Get-RustDeskService {
  $svc = Get-Service -Name "RustDesk*" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -eq $svc) {
    $svc = Get-Service -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -like "*RustDesk*" -or $_.DisplayName -like "*RustDesk*" } |
      Select-Object -First 1
  }
  return $svc
}

try {
  $ErrorActionPreference = "Stop"

  Write-Host "[1/9] Iniciando configuracion de RustDesk..."

  Write-Host "[2/9] Verificando carpeta de configuracion..."
  if (!(Test-Path $cfgDir)) {
    New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
    Write-Host "      Carpeta creada: $cfgDir"
  } else {
    Write-Host "      Carpeta existente: $cfgDir"
  }

  Write-Host "[3/9] Buscando servicio de RustDesk..."
  $rustDeskService = Get-RustDeskService
  if ($null -ne $rustDeskService) {
    Write-Host "      Servicio detectado: $($rustDeskService.Name) ($($rustDeskService.Status))"
    if ($rustDeskService.Status -ne "Stopped") {
      Write-Host "[4/9] Deteniendo servicio RustDesk..."
      Stop-Service -Name $rustDeskService.Name -Force -ErrorAction Stop
      (Get-Service -Name $rustDeskService.Name).WaitForStatus("Stopped", (New-TimeSpan -Seconds 20))
      Write-Host "      Servicio detenido."
    } else {
      Write-Host "[4/9] Servicio ya estaba detenido."
    }
  } else {
    Write-Host "[4/9] Servicio RustDesk no encontrado. Continuando..."
  }

  Write-Host "[5/9] Cerrando proceso RustDesk si esta activo..."
  Get-Process -Name "RustDesk" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

  Write-Host "[6/9] Verificando archivo de configuracion..."
  if (!(Test-Path $cfgFile)) {
    Set-Content -Path $cfgFile -Value "" -Encoding UTF8
    Write-Host "      Archivo creado: $cfgFile"
  } else {
    Write-Host "      Archivo existente: $cfgFile"
  }

  Write-Host "[7/9] Generando respaldo..."
  $ts = Get-Date -Format "yyyyMMdd-HHmmss"
  $backupPath = "$cfgFile.bak-$ts"
  Copy-Item $cfgFile $backupPath -Force
  Write-Host "      Backup: $backupPath"

  Write-Host "[8/9] Aplicando parametros en TOML..."
  $txt = Get-Content -Path $cfgFile -Raw -Encoding UTF8
  $txt = Update-TomlOptions $txt @{
    "custom-rendezvous-server" = $Rendezvous
    "relay-server" = $Relay
    "key" = $Key
    "allow-remote-config-modification" = "Y"
  } @("stop-service")

  Write-Host "[9/9] Guardando archivo..."
  Set-Content -Path $cfgFile -Value $txt -Encoding UTF8

  if ($null -ne $rustDeskService) {
    Write-Host "      Iniciando servicio RustDesk..."
    Start-Service -Name $rustDeskService.Name -ErrorAction Stop
    (Get-Service -Name $rustDeskService.Name).WaitForStatus("Running", (New-TimeSpan -Seconds 20))
    Write-Host "      Servicio iniciado."
  }

  Write-Host ""
  Write-Host "EXITO: Config aplicado en $cfgFile"
  Write-Host "Esta ventana se cerrara en 7 segundos..."
  Start-Sleep -Seconds 7
}
catch {
  Write-Host ""
  Write-Host "ERROR: Fallo la configuracion de RustDesk."
  Write-Host "Detalle: $($_.Exception.Message)"
  Write-Host "Esta ventana se cerrara en 7 segundos..."
  Start-Sleep -Seconds 7
  exit 1
}
