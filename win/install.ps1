# install.ps1 - One-click Windows deployment of DeepSeek Harness (dsh) with LAN access.
# Mirrors gavinlee9051/deepseek-harness-pack (Linux) on Windows.
#
# Steps:
#   1. Ensure Node.js >= 22
#   2. Install @deepseek-ai/dsh globally (native deps allowed)
#   3. Start dsh web (127.0.0.1:3081) + LAN HTTPS proxy (0.0.0.0:3080);
#      auto-applies the LAN unlock patch and (re)generates the self-signed cert.
#
# Usage (from this folder, in PowerShell):
#   powershell -ExecutionPolicy Bypass -File install.ps1
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot

Write-Host '=============================================='
Write-Host ' DeepSeek Harness (dsh) LAN installer - Windows'
Write-Host '=============================================='

# ---------- 1. Node.js ----------
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) {
    Write-Host '[1/4] Node.js not found.'
    Write-Host '      Install Node.js LTS (>= 22): https://nodejs.org'
    Write-Host '      or run:  winget install OpenJS.NodeJS.LTS'
    exit 1
}
$verText = (& node -v).TrimStart('v')
$ver = [version]$verText
if ($ver -lt [version]'22.0.0') {
    Write-Host "[1/4] Node.js $verText is too old (need >= 22). Upgrade Node.js first."
    exit 1
}
Write-Host "[1/4] Node.js $verText detected"

# ---------- 2. dsh ----------
Write-Host '[2/4] Installing @deepseek-ai/dsh globally ...'
& npm install -g --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs @deepseek-ai/dsh
if ($LASTEXITCODE -ne 0) { Write-Host 'npm install failed'; exit 1 }
$dsv = & dsh --version 2>$null
Write-Host "      dsh $dsv installed"

# ---------- 3. start ----------
Write-Host '[3/4] Starting dsh + LAN proxy (this applies the LAN patch and cert)...'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Here 'dsh.ps1') start

Write-Host ''
Write-Host 'Installation complete.'
Write-Host ''
Write-Host "Access (LAN IP varies by machine):"
Write-Host '  Local:  https://127.0.0.1:3080'
Write-Host '  LAN:    https://<your-LAN-IP>:3080    (self-signed cert warning is expected)'
Write-Host ''
Write-Host "Manage:  $Here\dsh-manage.cmd   (status|start|stop|restart|log|upgrade)"
Write-Host ''
Write-Host 'Warning: LAN access unlocks full agent control (command execution, credentials).'
Write-Host '         Only deploy on a trusted network.'
