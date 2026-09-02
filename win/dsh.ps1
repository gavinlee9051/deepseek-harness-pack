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
    $s = Get-Content -Raw $PatchTarget
    if ($s -like '*dsh-lan-patch*') { Write-Host '[patch] already applied'; return $true }
    $from = 'isLoopback: pageLocation === void 0 || isLoopbackHostname(pageLocation.hostname),'
    $to = 'isLoopback: true, /*[dsh-lan-patch]*/'
    if (-not $s.Contains($from)) { Write-Host '[patch] FAILED: expected code not found (dsh layout changed?)'; return $false }
    if (-not (Test-Path "$PatchTarget.orig")) { Copy-Item $PatchTarget "$PatchTarget.orig" }
    $s = $s.Replace($from, $to)
    [System.IO.File]::WriteAllText($PatchTarget, $s, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "[patch] applied: $PatchTarget"
    return $true
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

    Write-Host ''
    Write-Host "Local:    https://127.0.0.1:$ProxyPort   (accept the self-signed cert warning)"
    if ($lan) { Write-Host "LAN:      https://$lan`:$ProxyPort" }
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
    $s = Get-Content -Raw $PatchTarget -ErrorAction SilentlyContinue
    if ($s -and $s -like '*dsh-lan-patch*') { Write-Host 'LAN patch: applied' } else { Write-Host 'LAN patch: NOT applied' }
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
    Write-Host '=== restarting (LAN patch reapplied on start) ==='
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
