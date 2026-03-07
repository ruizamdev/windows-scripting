<# 
Ejecucion recomendada (bypass solo para este proceso):
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\rd-config.ps1
#>

# === Configure RustDesk (Windows) - RustDesk2.toml ===
$Rendezvous = "TU_DOMINIO_O_IP"
$Relay      = "TU_DOMINIO_O_IP"
$Key        = "TU_PUBLIC_KEY"

function Add-UniquePath([System.Collections.Generic.List[string]]$list, [string]$path) {
  if ([string]::IsNullOrWhiteSpace($path)) { return }
  $normalized = [System.IO.Path]::GetFullPath($path.Trim())
  foreach ($existing in $list) {
    if ([string]::Equals($existing, $normalized, [System.StringComparison]::OrdinalIgnoreCase)) {
      return
    }
  }
  $list.Add($normalized) | Out-Null
}

function Read-TextFileUtf8([string]$path) {
  if (!(Test-Path $path)) { return "" }
  return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

function Write-TextFileUtf8NoBom([string]$path, [string]$content) {
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}

function Get-UserConfigDirs {
  $dirs = [System.Collections.Generic.List[string]]::new()

  if ($env:APPDATA) {
    Add-UniquePath $dirs (Join-Path (Join-Path $env:APPDATA "RustDesk") "config")
  }

  try {
    $profiles = Get-CimInstance Win32_UserProfile -ErrorAction Stop |
      Where-Object {
        $_.LocalPath -and
        $_.SID -like "S-1-5-21-*" -and
        $_.Special -eq $false
      }

    foreach ($profile in $profiles) {
      $cfgDir = Join-Path $profile.LocalPath "AppData\Roaming\RustDesk\config"
      Add-UniquePath $dirs $cfgDir
    }
  }
  catch {
    Write-Host "      Aviso: no se pudieron enumerar perfiles de usuario desde CIM."
  }

  return $dirs
}

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

function Wait-RustDeskServiceReady(
  [int]$DetectionTimeoutSeconds = 90,
  [int]$RunningTimeoutSeconds = 90,
  [int]$SettleSeconds = 8
) {
  $detectDeadline = (Get-Date).AddSeconds($DetectionTimeoutSeconds)
  $svc = $null

  while ((Get-Date) -lt $detectDeadline) {
    $svc = Get-RustDeskService
    if ($null -ne $svc) {
      break
    }
    Start-Sleep -Seconds 2
  }

  if ($null -eq $svc) {
    Write-Host "      Aviso: no se detecto servicio RustDesk dentro de $DetectionTimeoutSeconds s."
    return $null
  }

  Write-Host "      Servicio detectado: $($svc.Name) ($($svc.Status))"

  if ($svc.Status -ne "Running") {
    Write-Host "      Esperando a que el servicio RustDesk quede en ejecucion..."
    try {
      Start-Service -Name $svc.Name -ErrorAction SilentlyContinue
    }
    catch {
      # Ignore and continue polling service status.
    }

    $runningDeadline = (Get-Date).AddSeconds($RunningTimeoutSeconds)
    while ((Get-Date) -lt $runningDeadline) {
      $svc = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
      if ($null -ne $svc -and $svc.Status -eq "Running") {
        break
      }
      Start-Sleep -Seconds 2
    }
  } else {
    $svc = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
  }

  if ($null -eq $svc -or $svc.Status -ne "Running") {
    throw "El servicio RustDesk no alcanzo estado Running en $RunningTimeoutSeconds s."
  }

  if ($SettleSeconds -gt 0) {
    Write-Host "      Servicio en Running. Esperando $SettleSeconds s para estabilizar archivos..."
    Start-Sleep -Seconds $SettleSeconds
  }

  return $svc
}

function Get-ServiceConfigDirs([string]$serviceName) {
  $dirs = [System.Collections.Generic.List[string]]::new()

  Add-UniquePath $dirs "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config"
  Add-UniquePath $dirs "C:\Windows\ServiceProfiles\NetworkService\AppData\Roaming\RustDesk\config"
  Add-UniquePath $dirs "C:\Windows\System32\config\systemprofile\AppData\Roaming\RustDesk\config"
  Add-UniquePath $dirs "C:\ProgramData\RustDesk\config"

  if ([string]::IsNullOrWhiteSpace($serviceName)) {
    return $dirs
  }

  try {
    $svcInfo = Get-CimInstance -ClassName Win32_Service -Filter "Name='$serviceName'" -ErrorAction Stop
    $startName = $svcInfo.StartName
  }
  catch {
    return $dirs
  }

  if ([string]::IsNullOrWhiteSpace($startName)) {
    return $dirs
  }

  switch -Regex ($startName) {
    "^(LocalService|NT AUTHORITY\\LocalService)$" {
      Add-UniquePath $dirs "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config"
    }
    "^(NetworkService|NT AUTHORITY\\NetworkService)$" {
      Add-UniquePath $dirs "C:\Windows\ServiceProfiles\NetworkService\AppData\Roaming\RustDesk\config"
    }
    "^(LocalSystem|NT AUTHORITY\\SYSTEM)$" {
      Add-UniquePath $dirs "C:\Windows\System32\config\systemprofile\AppData\Roaming\RustDesk\config"
    }
    "^[^\\]+\\[^\\]+$" {
      $domainPart = ($startName -split "\\")[0]
      $accountName = ($startName -split "\\")[-1]

      if ([string]::Equals($domainPart, "NT SERVICE", [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-UniquePath $dirs (Join-Path "C:\Windows\ServiceProfiles" (Join-Path $accountName "AppData\Roaming\RustDesk\config"))
        break
      }

      try {
        $profile = (Get-CimInstance Win32_UserProfile -ErrorAction Stop |
          Where-Object {
            $_.LocalPath -and
            $_.LocalPath -match "\\$([Regex]::Escape($accountName))$"
          } |
          Select-Object -First 1).LocalPath
        if ($profile -and (Test-Path $profile)) {
          Add-UniquePath $dirs (Join-Path $profile "AppData\Roaming\RustDesk\config")
        }
      }
      catch {
        # Ignore, keep known fallback directories.
      }
    }
  }

  return $dirs
}

function Test-TomlKeys([string]$content, [string[]]$keys) {
  foreach ($k in $keys) {
    if ($content -notmatch ("(?m)^\s*" + [Regex]::Escape($k) + "\s*=")) {
      return $false
    }
  }
  return $true
}

try {
  $ErrorActionPreference = "Stop"

  Write-Host "[1/9] Iniciando configuracion de RustDesk..."

  Write-Host "[3/9] Buscando servicio de RustDesk y esperando inicializacion..."
  $rustDeskService = Wait-RustDeskServiceReady -DetectionTimeoutSeconds 90 -RunningTimeoutSeconds 90 -SettleSeconds 8
  $serviceCfgDirs = [System.Collections.Generic.List[string]]::new()
  if ($null -ne $rustDeskService) {
    $serviceCfgDirs = Get-ServiceConfigDirs $rustDeskService.Name
    foreach ($dir in $serviceCfgDirs) {
      Write-Host "      Ruta candidata de servicio: $dir"
    }
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

  $userCfgDirs = Get-UserConfigDirs
  $targetDirs = [System.Collections.Generic.List[string]]::new()
  foreach ($dir in $userCfgDirs) { Add-UniquePath $targetDirs $dir }
  foreach ($dir in $serviceCfgDirs) { Add-UniquePath $targetDirs $dir }

  if ($targetDirs.Count -eq 0) {
    throw "No se detectaron rutas destino para RustDesk."
  }

  Write-Host "[6/9] Aplicando configuracion en perfiles detectados..."
  $updatedFiles = [System.Collections.Generic.List[string]]::new()
  $expectedKeys = @(
    "custom-rendezvous-server",
    "relay-server",
    "key",
    "allow-remote-config-modification"
  )

  foreach ($cfgDir in $targetDirs) {
    $cfgFile = Join-Path $cfgDir "RustDesk2.toml"

    if (!(Test-Path $cfgDir)) {
      New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
      Write-Host "      Carpeta creada: $cfgDir"
    } else {
      Write-Host "      Carpeta existente: $cfgDir"
    }

    if (!(Test-Path $cfgFile)) {
      Write-TextFileUtf8NoBom -Path $cfgFile -content ""
      Write-Host "      Archivo creado: $cfgFile"
    } else {
      Write-Host "      Archivo existente: $cfgFile"
    }

    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = "$cfgFile.bak-$ts"
    Copy-Item $cfgFile $backupPath -Force
    Write-Host "      Backup: $backupPath"

    $txt = Read-TextFileUtf8 -Path $cfgFile
    $txt = Update-TomlOptions $txt @{
      "custom-rendezvous-server" = $Rendezvous
      "relay-server" = $Relay
      "key" = $Key
      "allow-remote-config-modification" = "Y"
    } @("stop-service")

    Write-TextFileUtf8NoBom -Path $cfgFile -content $txt

    $finalText = Read-TextFileUtf8 -Path $cfgFile
    if (Test-TomlKeys $finalText $expectedKeys) {
      $updatedFiles.Add($cfgFile) | Out-Null
      Write-Host "      Configuracion aplicada: $cfgFile"
    } else {
      throw "El archivo no contiene todas las claves esperadas tras escribir: $cfgFile"
    }

    $localCfgFile = Join-Path $cfgDir "RustDesk_local.toml"
    if (!(Test-Path $localCfgFile)) {
      Write-TextFileUtf8NoBom -Path $localCfgFile -content ""
      Write-Host "      Archivo local creado: $localCfgFile"
    } else {
      Write-Host "      Archivo local existente: $localCfgFile"
    }

    $localTs = Get-Date -Format "yyyyMMdd-HHmmss"
    $localBackupPath = "$localCfgFile.bak-$localTs"
    Copy-Item $localCfgFile $localBackupPath -Force
    Write-Host "      Backup local: $localBackupPath"

    $localTxt = Read-TextFileUtf8 -Path $localCfgFile
    $localTxt = Update-TomlOptions $localTxt @{
      "enable-udp-punch" = "Y"
      "enable-abr" = "Y"
      "enable-hwcodec" = "Y"
      "image-quality" = "balanced"
      "custom-fps" = "30"
      "codec-preference" = "vp9"
      "allow-remove-wallpaper" = "Y"
      "disable-audio" = "Y"
      "i444" = "N"
      "show-quality-monitor" = "Y"
    }
    Write-TextFileUtf8NoBom -Path $localCfgFile -content $localTxt

    if (Test-TomlKeys (Read-TextFileUtf8 -Path $localCfgFile) @("enable-udp-punch","enable-abr","enable-hwcodec","image-quality","custom-fps","codec-preference","allow-remove-wallpaper","disable-audio","i444","show-quality-monitor")) {
      $updatedFiles.Add($localCfgFile) | Out-Null
      Write-Host "      Configuracion local aplicada: $localCfgFile"
    } else {
      throw "No se pudieron validar todas las claves locales en: $localCfgFile"
    }
  }

  if ($null -ne $rustDeskService) {
    Write-Host "[7/9] Iniciando servicio RustDesk..."
    Start-Service -Name $rustDeskService.Name -ErrorAction Stop
    (Get-Service -Name $rustDeskService.Name).WaitForStatus("Running", (New-TimeSpan -Seconds 20))
    Write-Host "      Servicio iniciado."
  }

  Write-Host "[8/9] Validando escritura final..."
  foreach ($cfgFile in $updatedFiles) {
    Write-Host "      OK: $cfgFile"
  }

  Write-Host "[9/9] Proceso finalizado."
  Write-Host ""
  Write-Host "EXITO: Configuracion aplicada en perfiles de usuario y servicio (si existe)."
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
