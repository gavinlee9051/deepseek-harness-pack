# uninstall.ps1 - Remove the DeepSeek Harness (dsh) LAN deployment on Windows.
# Stops the service, then optionally uninstalls the global package, deletes
# ~/.dsh data and local runtime files.
$ErrorActionPreference = 'Continue'
$Here = $PSScriptRoot

Write-Host 'Stopping running service...'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Here 'dsh.ps1') stop

$ans = Read-Host 'Remove global @deepseek-ai/dsh package? [y/N]'
if ($ans -match '^[yY]') {
    Write-Host 'Uninstalling @deepseek-ai/dsh globally...'
    & npm uninstall -g @deepseek-ai/dsh
    if ($LASTEXITCODE -eq 0) { Write-Host '  done' }
}

$ans = Read-Host 'Delete local data (~/.dsh: settings, credentials, sessions)? [y/N]'
if ($ans -match '^[yY]') {
    $dshHome = Join-Path $HOME '.dsh'
    if (Test-Path $dshHome) {
        Remove-Item -Recurse -Force $dshHome
        Write-Host '  ~/.dsh removed'
    } else {
        Write-Host '  ~/.dsh not found'
    }
}

$ans = Read-Host 'Delete runtime files in this folder (logs/, cert/, *.pid)? [y/N]'
if ($ans -match '^[yY]') {
    Remove-Item -Recurse -Force (Join-Path $Here 'logs'), (Join-Path $Here 'cert') -ErrorAction SilentlyContinue
    Remove-Item -Force (Join-Path $Here '*.pid') -ErrorAction SilentlyContinue
    Write-Host '  runtime files removed'
}

Write-Host 'Done.'
