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

function Update-TomlOptions([string]$content, [hashtable]$updates) {
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
    $found = @{}
    foreach ($k in $updates.Keys) { $found[$k] = $false }

    for ($i = $sectionStart + 1; $i -lt $sectionEnd; $i++) {
      foreach ($k in $updates.Keys) {
        if ($lines[$i] -match "^\s*$([regex]::Escape($k))\s*=") {
          $safe = ([string]$updates[$k]).Replace("\", "\\").Replace('"', '\"')
          $lines[$i] = "$k = ""$safe"""
          $found[$k] = $true
        }
      }
    }

    [System.Collections.ArrayList]$list = @($lines)
    $insertAt = $sectionStart + 1
    foreach ($k in $updates.Keys) {
      if (-not $found[$k]) {
        $safe = ([string]$updates[$k]).Replace("\", "\\").Replace('"', '\"')
        [void]$list.Insert($insertAt, "$k = ""$safe""")
        $insertAt++
        $sectionEnd++
      }
    }
    $lines = @($list)
  }

  return ($lines -join "`r`n")
}

try {
  $ErrorActionPreference = "Stop"

  Write-Host "[1/7] Iniciando configuracion de RustDesk..."

  Write-Host "[2/7] Verificando carpeta de configuracion..."
  if (!(Test-Path $cfgDir)) {
    New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
    Write-Host "      Carpeta creada: $cfgDir"
  } else {
    Write-Host "      Carpeta existente: $cfgDir"
  }

  Write-Host "[3/7] Cerrando proceso RustDesk si esta activo..."
  Get-Process -Name "RustDesk" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

  Write-Host "[4/7] Verificando archivo de configuracion..."
  if (!(Test-Path $cfgFile)) {
    Set-Content -Path $cfgFile -Value "" -Encoding UTF8
    Write-Host "      Archivo creado: $cfgFile"
  } else {
    Write-Host "      Archivo existente: $cfgFile"
  }

  Write-Host "[5/7] Generando respaldo..."
  $ts = Get-Date -Format "yyyyMMdd-HHmmss"
  $backupPath = "$cfgFile.bak-$ts"
  Copy-Item $cfgFile $backupPath -Force
  Write-Host "      Backup: $backupPath"

  Write-Host "[6/7] Aplicando parametros en TOML..."
  $txt = Get-Content -Path $cfgFile -Raw -Encoding UTF8
  $txt = Update-TomlOptions $txt @{
    "custom-rendezvous-server" = $Rendezvous
    "relay-server" = $Relay
    "key" = $Key
  }

  Write-Host "[7/7] Guardando archivo..."
  Set-Content -Path $cfgFile -Value $txt -Encoding UTF8

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
