# === Configure RustDesk (Windows) - RustDesk2.toml ===
$Rendezvous = "TU_DOMINIO_O_IP"
$Relay      = "TU_DOMINIO_O_IP"
$Key        = "TU_PUBLIC_KEY"

$cfgDir  = Join-Path $env:APPDATA "RustDesk"
$cfgFile = Join-Path $cfgDir "RustDesk2.toml"

# Ensure folder exists
if (!(Test-Path $cfgDir)) {
  New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
}

# Stop RustDesk if running (so it doesn't overwrite on exit)
Get-Process -Name "RustDesk" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# Ensure file exists
if (!(Test-Path $cfgFile)) {
  Set-Content -Path $cfgFile -Value "" -Encoding UTF8
}

# Backup
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item $cfgFile "$cfgFile.bak-$ts" -Force

$txt = Get-Content -Path $cfgFile -Raw -Encoding UTF8

# Ensure [options] section exists
if ($txt -notmatch "(?m)^\[options\]\s*$") {
  $txt = $txt.TrimEnd() + "`r`n`r`n[options]`r`n"
}

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

$txt = Set-TomlKey $txt "options" "custom-rendezvous-server" $Rendezvous
$txt = Set-TomlKey $txt "options" "relay-server" $Relay
$txt = Set-TomlKey $txt "options" "key" $Key

Set-Content -Path $cfgFile -Value $txt -Encoding UTF8

Write-Host "✅ Listo. Config aplicado a: $cfgFile"