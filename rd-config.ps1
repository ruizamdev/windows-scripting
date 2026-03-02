<# 
Ejecucion recomendada (bypass solo para este proceso):
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\rd-config.ps1
#>

# === Configure RustDesk (Windows) - RustDesk2.toml ===
$Rendezvous = "TU_DOMINIO_O_IP"
$Relay      = "TU_DOMINIO_O_IP"
$Key        = "TU_PUBLIC_KEY"

$cfgDir  = Join-Path $env:APPDATA "RustDesk"
$cfgFile = Join-Path $cfgDir "RustDesk2.toml"

function Set-TomlKey([string]$content, [string]$section, [string]$key, [string]$value) {
  $safe = $value.Replace("\", "\\").Replace('"', '\"')
  $secPattern = "(?ms)^\[$section\]\s*$.*?(?=^\[|\z)"
  $m = [regex]::Match($content, $secPattern)
  if (-not $m.Success) { return $content }

  $block = $m.Value
  $keyPattern = "(?m)^\s*$key\s*=\s*""[^""]*""\s*$"

  if ([regex]::IsMatch($block, $keyPattern)) {
    $block2 = [regex]::Replace($block, $keyPattern, "$key = ""$safe""")
  } else {
    $block2 = [regex]::Replace($block, "(?m)^\[$section\]\s*$", "[$section]`r`n$key = ""$safe""")
  }

  return $content.Substring(0, $m.Index) + $block2 + $content.Substring($m.Index + $m.Length)
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
  if ($txt -notmatch "(?m)^\[options\]\s*$") {
    $txt = $txt.TrimEnd() + "`r`n`r`n[options]`r`n"
  }

  $txt = Set-TomlKey $txt "options" "custom-rendezvous-server" $Rendezvous
  $txt = Set-TomlKey $txt "options" "relay-server" $Relay
  $txt = Set-TomlKey $txt "options" "key" $Key

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
