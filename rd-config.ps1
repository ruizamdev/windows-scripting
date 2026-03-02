# === RustDesk Client Bootstrap (Windows) ===
# Configure your RustDesk self-hosted servers by editing TOML config in %APPDATA%.

$Rendezvous = "TU_DOMINIO_O_IP"   # e.g. "rustdesk.tudominio.com" or "123.45.67.89"
$Relay      = "TU_DOMINIO_O_IP"   # usually same as rendezvous
$Key        = "TU_PUBLIC_KEY"     # the ed25519 public key (string)

$AppData = $env:APPDATA
$BaseDir = Join-Path $AppData "RustDesk"

if (!(Test-Path $BaseDir)) {
  New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
}

# Candidate config files (RustDesk versions may use one or the other)
$candidates = @(
  (Join-Path $BaseDir "RustDesk.toml"),
  (Join-Path $BaseDir "RustDesk2.toml")
)

# Pick existing config if any; otherwise create RustDesk.toml
$configPath = ($candidates | Where-Object { Test-Path $_ } | Select-Object -First 1)
if (-not $configPath) {
  $configPath = $candidates[0]
  Set-Content -Path $configPath -Value "" -Encoding UTF8
}

# Stop RustDesk (ignore errors)
Get-Process -Name "RustDesk" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# Backup
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item -Path $configPath -Destination "$configPath.bak-$timestamp" -Force

# Read file
$txt = Get-Content -Path $configPath -Raw -Encoding UTF8

# Ensure [options] section exists
if ($txt -notmatch "(?m)^\[options\]\s*$") {
  $txt = $txt.TrimEnd() + "`r`n`r`n[options]`r`n"
}

function Set-TomlKey([string]$content, [string]$section, [string]$key, [string]$value) {
  # Escapes backslashes and quotes for TOML string
  $safe = $value.Replace("\", "\\").Replace('"', '\"')

  # Regex:
  # Find section header, then within that section either replace existing key or insert new line.
  $secPattern = "(?ms)^\[$section\]\s*$.*?(?=^\[|\z)"
  $m = [regex]::Match($content, $secPattern)
  if (-not $m.Success) { return $content }

  $block = $m.Value

  $keyPattern = "(?m)^\s*$key\s*=\s*""[^""]*""\s*$"
  if ([regex]::IsMatch($block, $keyPattern)) {
    $block2 = [regex]::Replace($block, $keyPattern, "$key = ""$safe""")
  } else {
    # Insert right after section header line
    $block2 = [regex]::Replace($block, "(?m)^\[$section\]\s*$", "[$section]`r`n$key = ""$safe""")
  }

  return $content.Substring(0, $m.Index) + $block2 + $content.Substring($m.Index + $m.Length)
}

$txt = Set-TomlKey $txt "options" "custom-rendezvous-server" $Rendezvous
$txt = Set-TomlKey $txt "options" "relay-server" $Relay
$txt = Set-TomlKey $txt "options" "key" $Key

# Write back
Set-Content -Path $configPath -Value $txt -Encoding UTF8

Write-Host "✅ RustDesk configured in: $configPath"
Write-Host "   Rendezvous: $Rendezvous"
Write-Host "   Relay:      $Relay"
Write-Host "   Key:        (set)"