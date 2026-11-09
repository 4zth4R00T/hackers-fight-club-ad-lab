[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'setup\Lab.psm1') -Force -DisableNameChecking
$c = Get-LabConfig
$LOG = Join-Path $c.Paths.Logs 'intranet.log'
$ACCESS = Join-Path $c.Paths.Logs 'web-access.log'
$BOTS = '(?i)(python|curl|wget|httpx|aiohttp|node-fetch|axios|undici|go-http|java/|libwww|okhttp|powershell|winhttp|headless|selenium|playwright|puppeteer|scrapy|spider|crawler|bot\b|bot/)'

function Log {
    param([string]$Text, [string]$Level = 'INFO')
    try { Add-Content -LiteralPath $LOG -Value ('{0}  [{1,-5}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Text) -Encoding UTF8 } catch { }
}

if (-not $c.Challenges -or -not (Test-Weakness 'InternalHttpIntranet')) {
    Log (L 'Intranet desactivada en la configuracion.' 'Intranet disabled in the configuration.') 'WARN'
    exit 0
}
New-Folder $c.Paths.Logs | Out-Null

$ip = Get-ServiceAddress -TimeoutSeconds 180 -LogFile $LOG
if (-not $ip) { exit 1 }

$listeners = @()
foreach ($addr in @($ip, '127.0.0.1') | Select-Object -Unique) {
    for ($i = 1; $i -le 6; $i++) {
        try {
            $l = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Parse($addr), [int]$c.IntranetPort)
            $l.Start()
            $listeners += $l
            Log ((L 'Intranet escuchando en ' 'Intranet listening on ') + "${addr}:$($c.IntranetPort)") 'OK'
            break
        } catch {
            if ($i -eq 6) { Log ((L 'No se pudo abrir ' 'Could not open ') + "${addr}:$($c.IntranetPort): $($_.Exception.Message)") 'ERROR' }
            Start-Sleep -Seconds 5
        }
    }
}
if ($listeners.Count -eq 0) { exit 1 }

$cidrs = @(Get-ClientCidrs)

function Test-Client {
    param([Net.IPAddress]$Address)
    $a = $Address
    if ($a.IsIPv4MappedToIPv6) { $a = $a.MapToIPv4() }
    $s = $a.ToString()
    if ($s -eq '127.0.0.1' -or $s -eq $ip) { return $true }
    foreach ($x in $cidrs) { if (Test-AddressInCidr -Address $s -Cidr $x) { return $true } }
    return $false
}

function Send-Http {
    param($Stream, [int]$Code, [string]$Reason, [string]$Body, [switch]$HeadOnly)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Body)
    $head = "HTTP/1.1 $Code $Reason`r`nContent-Type: text/html; charset=utf-8`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`nX-Content-Type-Options: nosniff`r`nCache-Control: no-store`r`n`r`n"
    $hb = [Text.Encoding]::ASCII.GetBytes($head)
    $Stream.Write($hb, 0, $hb.Length)
    if (-not $HeadOnly) { $Stream.Write($bytes, 0, $bytes.Length) }
    $Stream.Flush()
}

function Invoke-Request {
    param($Client)
    $remote = $Client.Client.RemoteEndPoint.Address
    if (-not (Test-Client $remote)) { $Client.Close(); return }
    $Client.ReceiveTimeout = 4000
    $Client.SendTimeout = 4000
    $stream = $Client.GetStream()
    $buf = New-Object byte[] 16384
    $total = 0
    $text = ''
    while ($total -lt $buf.Length) {
        $n = 0
        try { $n = $stream.Read($buf, $total, $buf.Length - $total) } catch { break }
        if ($n -le 0) { break }
        $total += $n
        $text = [Text.Encoding]::ASCII.GetString($buf, 0, $total)
        if ($text.Contains("`r`n`r`n")) { break }
    }
    if (-not $text) { $Client.Close(); return }
    $lines = $text -split "`r`n"
    $parts = $lines[0] -split ' '
    $method = $parts[0].ToUpperInvariant()
    $path = '/'
    if ($parts.Count -gt 1) { $path = $parts[1] }
    $hostName = ''; $ua = ''
    foreach ($h in $lines[1..($lines.Count - 1)]) {
        if ($h -match '^(?i)host:\s*(.+)$') { $hostName = $Matches[1].Trim().ToLowerInvariant() }
        elseif ($h -match '^(?i)user-agent:\s*(.+)$') { $ua = $Matches[1].Trim() }
    }
    if (-not $ua) { $ua = '-' }
    $tag = ''
    if ($ua -eq '-' -or $ua -match $BOTS) { $tag = '  [AUTOMATED]' }
    try { Add-Content -LiteralPath $ACCESS -Value ('{0}  {1,-15} {2,-32} {3} {4}  UA={5}{6}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $remote, $hostName, $method, $path, $ua, $tag) -Encoding UTF8 } catch { }
    if ($method -ne 'GET' -and $method -ne 'HEAD') {
        Send-Http -Stream $stream -Code 405 -Reason 'Method Not Allowed' -Body '<h1>405</h1>'
        $Client.Close(); return
    }
    $short = ($hostName -split '[:.]')[0]
    $file = Join-Path $c.Paths.Intranet 'index.html'
    if ($short -match '^srv\d{2}$') {
        $cand = Join-Path $c.Paths.Intranet "$short.html"
        if (Test-Path -LiteralPath $cand) { $file = $cand }
        else {
            Send-Http -Stream $stream -Code 404 -Reason 'Not Found' -Body '<h1>404</h1>' -HeadOnly:($method -eq 'HEAD')
            $Client.Close(); return
        }
    }
    $body = '<h1>Intranet</h1>'
    if (Test-Path -LiteralPath $file) { $body = [IO.File]::ReadAllText($file) }
    Send-Http -Stream $stream -Code 200 -Reason 'OK' -Body $body -HeadOnly:($method -eq 'HEAD')
    $Client.Close()
}

Log (L 'Intranet en marcha.' 'Intranet running.') 'OK'
while ($true) {
    $busy = $false
    foreach ($l in $listeners) {
        try {
            if ($l.Pending()) {
                $busy = $true
                $cl = $l.AcceptTcpClient()
                try { Invoke-Request -Client $cl } catch { Log $_.Exception.Message 'WARN'; try { $cl.Close() } catch { } }
            }
        } catch { Log $_.Exception.Message 'WARN'; Start-Sleep -Seconds 1 }
    }
    if (-not $busy) { Start-Sleep -Milliseconds 40 }
}
