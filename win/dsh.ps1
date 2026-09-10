# dsh.ps1 - DeepSeek Harness management console (Windows)
# Port of gavinlee9051/deepseek-harness-pack to Windows PowerShell.
# Usage:
#   powershell -ExecutionPolicy Bypass -File dsh.ps1
#   powershell -ExecutionPolicy Bypass -File dsh.ps1 <start|stop|restart|status|log|upgrade>
param(
    [Parameter(Position = 0)][string]$Command = ''
)

$ErrorActionPreference = 'Stop'

$DeployDir = $PSScriptRoot
$CertDir = Join-Path $DeployDir 'cert'
$LogDir = Join-Path $DeployDir 'logs'
New-Item -ItemType Directory -Force -Path $CertDir, $LogDir | Out-Null

$DshLog = Join-Path $LogDir 'dsh.stdout.log'
$DshErr = Join-Path $LogDir 'dsh.stderr.log'
$ProxyOut = Join-Path $LogDir 'proxy.stdout.log'
$ProxyErr = Join-Path $LogDir 'proxy.stderr.log'
$DshPid = Join-Path $DeployDir 'dsh.pid'
$ProxyPid = Join-Path $DeployDir 'proxy.pid'

$DshPort = if ($env:DSH_PORT) { $env:DSH_PORT } else { '3081' }
$ProxyPort = if ($env:PROXY_PORT) { $env:PROXY_PORT } else { '3080' }
$ListenHost = '127.0.0.1'

$Node = (Get-Command node).Source
$NodeDir = Split-Path $Node
$GlobalRoot = & npm root -g 2>$null
$DshBin = Join-Path $GlobalRoot '@deepseek-ai\dsh\lib\bin.js'
$PatchTarget = Join-Path $GlobalRoot '@deepseek-ai\dsh\node_modules\@deepseek-ai\dsh-client-connection\lib\client.js'
$ProxyJs = Join-Path $DeployDir 'proxy.js'

# Archive session feature (merged from gavinlee9051/dsh-modern-skin).
# The patch edits installed dsh core files, so it is version-pinned: it only
# runs against the exact dsh release its anchors were validated on. Find the
# patch either beside this script (<deploy>/patches) or in the repo layout
# (<repo-root>/patches) so both a standalone deploy and the win/ folder work.
$ArchiveRoot = Join-Path $GlobalRoot '@deepseek-ai\dsh\node_modules\@deepseek-ai'
$ArchiveMarker = 'Permanently delete one session'
$ArchiveSupportedVersion = '0.1.1-rc.2'
$ArchivePatchScript = @(
        (Join-Path $DeployDir 'patches\archive-core-rc2.mjs'),
        (Join-Path (Split-Path $DeployDir -Parent) 'patches\archive-core-rc2.mjs')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

function Get-LanIp {
    try {
        $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object {
            $_.IPAddress -notmatch '^127\.' -and $_.IPAddress -notmatch '^169\.254\.'
        } | ForEach-Object { $_.IPAddress }
        foreach ($pat in @('192.168.*', '10.*', '172.*')) {
            foreach ($ip in $ips) {
                if ($pat -eq '172.*') {
                    if ($ip -notmatch '^172\.(1[6-9]|2[0-9]|3[01])\.') { continue }
                } elseif ($ip -notlike $pat) { continue }
                return $ip
            }
        }
        if ($ips) { return $ips[0] }
    } catch { }
    return ''
}

function Test-PortOpen([int]$Port) {
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $c.BeginConnect('127.0.0.1', $Port, $null, $null)
        return $iar.AsyncWaitHandle.WaitOne(500)
    } catch { return $false }
    finally { $c.Close() }
}

function Get-Openssl {
    $o = Get-Command openssl -ErrorAction SilentlyContinue
    if ($o) { return $o.Source }
    $candidates = @(
        "$env:ProgramFiles\Git\usr\bin\openssl.exe",
        "$env:ProgramFiles\Git\mingw64\bin\openssl.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    throw 'openssl not found; install Git for Windows or OpenSSL'
}

function Write-Status([string]$Msg) { Write-Host "[dsh] $Msg" }

function Apply-LanPatch {
    if (-not (Test-Path $PatchTarget)) { Write-Host "[patch] target not found: $PatchTarget"; return $false }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $s = [System.IO.File]::ReadAllText($PatchTarget, $utf8)
    if ($s.Contains('dsh-lan-patch')) { Write-Host '[patch] already applied'; return $true }
    # The isLoopback expression changed across dsh releases (0.1.1: pageLocation
    # === void 0 || ...; 0.1.5: transport?.ownsHost === true || pageLocation ===
    # void 0 || ...). Match the whole expression up to isLoopbackHostname(...).
    if (-not $s.Contains('isLoopbackHostname(pageLocation.hostname),')) {
        Write-Host '[patch] FAILED: expected code not found (dsh layout changed?)'
        return $false
    }
    if (-not (Test-Path "$PatchTarget.orig")) { Copy-Item $PatchTarget "$PatchTarget.orig" }
    $re = [regex]'isLoopback:[^\r\n]*?isLoopbackHostname\(pageLocation\.hostname\),'
    $patched = $re.Replace($s, 'isLoopback: true, /*[dsh-lan-patch]*/', 1)
    if ($patched -eq $s) { Write-Host '[patch] FAILED: substitution did not take effect'; return $false }
    [System.IO.File]::WriteAllText($PatchTarget, $patched, $utf8)
    Write-Host "[patch] applied: $PatchTarget"
    return $true
}

function Get-WebToken {
    if (-not (Test-Path $DshLog)) { return '' }
    try {
        $fs = [System.IO.File]::Open($DshLog, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $sr = New-Object System.IO.StreamReader($fs)
        $text = $sr.ReadToEnd()
        $sr.Close(); $fs.Close()
    } catch { return '' }
    $m = [regex]::Match($text, 'token=([A-Za-z0-9_\-]+)')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

function Apply-ArchivePatch {
    if (-not $ArchivePatchScript) {
        Write-Host '[archive] patch script not found (expected patches\archive-core-rc2.mjs next to this script or in the repo root)'
        return $false
    }
    $ws = Join-Path $ArchiveRoot 'dsh-workspace\lib\index.js'
    if (-not (Test-Path $ws)) {
        Write-Host "[archive] dsh workspace not found: $ws"
        Write-Host '[archive] run the installer first (install.ps1)'
        return $false
    }
    $ver = (& dsh --version 2>$null)
    if (($ver | Out-String).Trim() -ne $ArchiveSupportedVersion) {
        Write-Host "[archive] skipped: dsh '$((($ver | Out-String).Trim()))' does not match supported '$ArchiveSupportedVersion'"
        return $false
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    if ([System.IO.File]::ReadAllText($ws, $utf8).Contains($ArchiveMarker)) {
        Write-Host '[archive] already applied'
        return $true
    }
    Write-Host "[archive] applying archive session feature to dsh $($ArchiveSupportedVersion) ..."
    & $Node $ArchivePatchScript --root $ArchiveRoot
    $ok = ($LASTEXITCODE -eq 0)
    if ($ok) {
        Write-Host '[archive] applied'
    } else {
        Write-Host '[archive] WARNING: apply reported a failure (dsh layout changed?)'
        Write-Host '[archive]          reinstall dsh, then start again to retry'
    }
    return $ok
}

function Ensure-Cert {
    $lan = Get-LanIp
    $crt = Join-Path $CertDir 'cert.pem'
    $key = Join-Path $CertDir 'key.pem'
    $need = -not (Test-Path $crt)
    if (-not $need -and $lan) {
        $san = & (Get-Openssl) x509 -in $crt -noout -ext subjectAltName 2>$null
        if ($san -and -not ($san -like "*$lan*")) { $need = $true }
    }
    if (-not $need) { Write-Host '[cert] reusing existing certificate'; return }
    $san = "DNS:localhost,DNS:$env:COMPUTERNAME,IP:127.0.0.1"
    if ($lan) { $san = "$san,IP:$lan" }
    Write-Host "[cert] generating self-signed cert (SAN: $san)"
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $env:MSYS_NO_PATHCONV = '1'
    & (Get-Openssl) req -x509 -newkey rsa:2048 -nodes -keyout $key -out $crt -days 825 -subj '/CN=deepseek-harness' -addext "subjectAltName=$san" 2>&1 | Out-Null
    $code = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($code -ne 0 -or -not (Test-Path $crt)) { throw 'cert generation failed' }
    Write-Host '[cert] written'
}

function Get-RunningPids {
    $ids = @()
    Get-CimInstance Win32_Process -Filter "name='node.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
        $cl = $_.CommandLine
        if ($cl -and ($cl -like '*@deepseek-ai\dsh*lib\bin.js*web*' -or ($cl -like '*proxy.js*' -and $cl -like "*$DeployDir*"))) {
            $ids += $_.ProcessId
        }
    }
    return $ids
}

function Stop-Dsh {
    $ids = Get-RunningPids
    if ($ids.Count -eq 0) { Write-Host 'No running instance found.'; return }
    Write-Host 'Stopping DeepSeek Harness (dsh) and proxy...'
    foreach ($id in $ids) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
    Remove-Item $DshPid, $ProxyPid -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host 'Stopped.'
}

function Start-Dsh {
    Stop-Dsh
    Apply-LanPatch | Out-Null
    Apply-ArchivePatch | Out-Null
    Ensure-Cert

    $lan = Get-LanIp
    $hosts = @('127.0.0.1', 'localhost', $env:COMPUTERNAME)
    if ($lan) { $hosts += $lan }
    $trusted = @()
    foreach ($h in $hosts) { $trusted += "$h`:$DshPort"; $trusted += "$h`:$ProxyPort" }

    Write-Host "[run] starting dsh web on $ListenHost`:$DshPort ..."
    $argsWeb = @($DshBin, 'web', '--host', $ListenHost, '--port', $DshPort, '--no-open')
    foreach ($t in $trusted) { $argsWeb += '--trusted-host'; $argsWeb += $t }
    $env:PATH = "$NodeDir;$env:PATH"
    $p1 = Start-Process -FilePath $Node -ArgumentList $argsWeb -WorkingDirectory $DeployDir -WindowStyle Hidden -RedirectStandardOutput $DshLog -RedirectStandardError $DshErr -PassThru
    Set-Content -Path $DshPid -Value $p1.Id

    for ($i = 0; $i -lt 30; $i++) {
        if (Test-PortOpen ([int]$DshPort)) { break }
        Start-Sleep -Seconds 1
    }

    Write-Host "[run] starting LAN proxy (HTTPS) on 0.0.0.0:$ProxyPort ..."
    $env:PROXY_PORT = "$ProxyPort"
    $env:DSH_PORT = "$DshPort"
    $p2 = Start-Process -FilePath $Node -ArgumentList @($ProxyJs) -WorkingDirectory $DeployDir -WindowStyle Hidden -RedirectStandardOutput $ProxyOut -RedirectStandardError $ProxyErr -PassThru
    Set-Content -Path $ProxyPid -Value $p2.Id

    # dsh 0.1.5+ prints a one-time auth URL (?token=...) to stdout. Surface it
    # through the proxy so the browser can sign in from localhost or LAN.
    $token = ''
    for ($i = 0; $i -lt 10 -and -not $token; $i++) {
        $token = Get-WebToken
        if (-not $token) { Start-Sleep -Milliseconds 500 }
    }
    $suffix = if ($token) { "/?token=$token" } else { '/' }

    Write-Host ''
    Write-Host "Local:    https://127.0.0.1:$ProxyPort$suffix   (accept the self-signed cert warning)"
    if ($lan) { Write-Host "LAN:      https://$lan`:$ProxyPort$suffix" }
    if ($token) { Write-Host '(open this URL once per start to sign in; the token rotates on restart)' }
    Write-Host ''
    Write-Host "Logs:     $LogDir"
}

function Show-Status {
    $ids = Get-RunningPids
    $dshUp = Test-PortOpen ([int]$DshPort)
    $proxyUp = Test-PortOpen ([int]$ProxyPort)
    Write-Host '=== processes ==='
    if ($ids.Count -gt 0) { $ids | ForEach-Object { Write-Host "running pid: $_" } } else { Write-Host 'dsh/proxy: not running' }
    Write-Host ''
    Write-Host '=== endpoints ==='
    Write-Host "dsh web (localhost):  $dshUp   http://127.0.0.1:$DshPort"
    Write-Host "lan proxy (https):    $proxyUp  https://127.0.0.1:$ProxyPort"
    Write-Host ''
    Write-Host '=== version / patch ==='
    & dsh --version 2>$null
    $s = [System.IO.File]::ReadAllText($PatchTarget, (New-Object System.Text.UTF8Encoding($false)))
    if ($s -and $s -like '*dsh-lan-patch*') { Write-Host 'LAN patch: applied' } else { Write-Host 'LAN patch: NOT applied' }
    $wsFile = Join-Path $ArchiveRoot 'dsh-workspace\lib\index.js'
    if (Test-Path $wsFile) {
        $wss = [System.IO.File]::ReadAllText($wsFile, (New-Object System.Text.UTF8Encoding($false)))
        if ($wss.Contains($ArchiveMarker)) { Write-Host 'archive patch: applied' } else { Write-Host 'archive patch: NOT applied' }
    } else { Write-Host 'archive patch: dsh workspace not found' }
    $token = Get-WebToken
    if ($token) { Write-Host "web token: https://127.0.0.1:$ProxyPort/?token=$token" }
}

function Show-Log {
    Write-Host '(Ctrl+C to exit)'
    Get-Content -Path $DshLog, $ProxyOut -Tail 50 -Wait -ErrorAction SilentlyContinue
}

function Do-Upgrade {
    Write-Host '=== current version ==='
    & dsh --version 2>$null
    Write-Host '=== upgrading @deepseek-ai/dsh ==='
    & npm install -g --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs @deepseek-ai/dsh
    Write-Host '=== upgraded version ==='
    & dsh --version
    Write-Host '=== restarting (LAN + archive patches reapplied on start) ==='
    Stop-Dsh
    Start-Sleep -Seconds 1
    Start-Dsh
    Write-Host 'Done. If the browser behaves oddly, hard-refresh (Ctrl+Shift+R).'
}

function Show-Menu {
    while ($true) {
        Write-Host ''
        Write-Host '======== DeepSeek Harness management ========'
        Write-Host ' 1) start        2) stop        3) restart'
        Write-Host ' 4) status       5) log         6) upgrade'
        Write-Host ' 0) exit'
        $c = Read-Host 'choose'
        switch ($c) {
            '1' { Start-Dsh }
            '2' { Stop-Dsh }
            '3' { Stop-Dsh; Start-Sleep 1; Start-Dsh }
            '4' { Show-Status }
            '5' { Show-Log }
            '6' { Do-Upgrade }
            '0' { return }
            default { Write-Host 'invalid choice' }
        }
    }
}

switch ($Command) {
    'start' { Start-Dsh }
    'stop' { Stop-Dsh }
    'restart' { Stop-Dsh; Start-Sleep 1; Start-Dsh }
    'status' { Show-Status }
    'log' { Show-Log }
    'upgrade' { Do-Upgrade }
    default { Show-Menu }
}
