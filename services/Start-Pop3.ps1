[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'setup\Lab.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'services\Mail.psm1') -Force -DisableNameChecking
Import-Module ActiveDirectory -ErrorAction SilentlyContinue
$c = Get-LabConfig
$LOG = Join-Path $c.Paths.Logs 'mail.log'

function Log {
    param([string]$Text, [string]$Level = 'INFO')
    try { Add-Content -LiteralPath $LOG -Value ('{0}  [{1,-5}] POP3 {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Text) -Encoding UTF8 } catch { }
}

if (-not $c.Mail -or -not (Test-Weakness 'PlaintextMail')) {
    Log (L 'Correo desactivado en la configuracion.' 'Mail disabled in the configuration.') 'WARN'
    exit 0
}
New-Folder $c.Paths.Logs | Out-Null
$port = [int]$c.Pop3Port
$ip = Get-ServiceAddress -TimeoutSeconds 180 -LogFile $LOG
if (-not $ip) { exit 1 }
$listener = $null
for ($i = 1; $i -le 6; $i++) {
    try {
        $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Parse($ip), $port)
        $listener.Start()
        break
    } catch {
        $listener = $null
        if ($i -eq 6) { Log ((L 'No se pudo abrir ' 'Could not open ') + "${ip}:${port}: $($_.Exception.Message)") 'ERROR'; exit 1 }
        Start-Sleep -Seconds 5
    }
}
Log ((L 'Escuchando en ' 'Listening on ') + "${ip}:$port") 'OK'

function Send-Line { param($W, [string]$T) $W.Write("$T`r`n"); $W.Flush() }

function Invoke-Session {
    param($Client)
    $remote = $Client.Client.RemoteEndPoint.Address
    if (-not (Test-MailClient -Address $remote)) { Log ((L 'Rechazado ' 'Refused ') + $remote) 'WARN'; $Client.Close(); return }
    $Client.ReceiveTimeout = 120000
    $Client.SendTimeout = 120000
    $ns = $Client.GetStream()
    $rd = New-Object IO.StreamReader($ns, [Text.Encoding]::UTF8)
    $wr = New-Object IO.StreamWriter($ns, (New-Object Text.UTF8Encoding($false)))
    $user = $null; $who = $null; $msgs = @(); $del = @{}
    Send-Line $wr "+OK $($c.DcFqdn) POP3 ready"
    while ($true) {
        $line = $null
        try { $line = $rd.ReadLine() } catch { break }
        if ($null -eq $line) { break }
        $p = $line -split '\s+'
        $verb = $p[0].ToUpperInvariant()
        $arg = ''
        if ($p.Count -gt 1) { $arg = $p[1] }
        if (-not $who -and @('USER', 'PASS', 'QUIT', 'CAPA') -notcontains $verb) { Send-Line $wr '-ERR Authenticate first'; continue }
        switch ($verb) {
            'CAPA' { Send-Line $wr '+OK Capability list follows'; foreach ($x in @('USER', 'UIDL', 'TOP', '.')) { Send-Line $wr $x } }
            'USER' { $user = $arg; Send-Line $wr '+OK' }
            'PASS' {
                if (-not $user) { Send-Line $wr '-ERR USER first'; break }
                $pw = ''
                if ($line.Length -gt 5) { $pw = $line.Substring(5) }
                $who = Test-MailCredential -User $user -Password $pw
                if ($who) {
                    $msgs = @(Get-MailMessages -Mailbox $who.Mailbox)
                    Send-Line $wr "+OK $($who.Sam) has $($msgs.Count) message(s)"
                    Log "LOGIN $($who.Sam) $remote ($($msgs.Count))"
                } else { Send-Line $wr '-ERR Invalid credentials'; Log "LOGIN FAIL '$user' $remote" 'WARN'; $user = $null }
            }
            'STAT' {
                $cnt = 0; $bytes = 0
                for ($i = 0; $i -lt $msgs.Count; $i++) { if (-not $del.ContainsKey($i)) { $cnt++; $bytes += $msgs[$i].Length } }
                Send-Line $wr "+OK $cnt $bytes"
            }
            'LIST' {
                if ($arg) {
                    $i = -1
                    if ($arg -match '^\d+$') { $i = [int]$arg - 1 }
                    if ($i -lt 0 -or $i -ge $msgs.Count -or $del.ContainsKey($i)) { Send-Line $wr '-ERR No such message' }
                    else { Send-Line $wr "+OK $arg $($msgs[$i].Length)" }
                } else {
                    Send-Line $wr "+OK $($msgs.Count) message(s)"
                    for ($i = 0; $i -lt $msgs.Count; $i++) { if (-not $del.ContainsKey($i)) { Send-Line $wr "$($i + 1) $($msgs[$i].Length)" } }
                    Send-Line $wr '.'
                }
            }
            'UIDL' {
                Send-Line $wr '+OK'
                for ($i = 0; $i -lt $msgs.Count; $i++) { if (-not $del.ContainsKey($i)) { Send-Line $wr "$($i + 1) $($msgs[$i].BaseName)" } }
                Send-Line $wr '.'
            }
            'RETR' {
                $i = -1
                if ($arg -match '^\d+$') { $i = [int]$arg - 1 }
                if ($i -lt 0 -or $i -ge $msgs.Count -or $del.ContainsKey($i)) { Send-Line $wr '-ERR No such message'; break }
                $txt = [IO.File]::ReadAllText($msgs[$i].FullName)
                Send-Line $wr "+OK $($msgs[$i].Length) octets"
                foreach ($l in ($txt -split "`r?`n")) { if ($l.StartsWith('.')) { Send-Line $wr ".$l" } else { Send-Line $wr $l } }
                Send-Line $wr '.'
            }
            'TOP' {
                $i = -1
                if ($arg -match '^\d+$') { $i = [int]$arg - 1 }
                $max = 10
                if ($p.Count -gt 2 -and $p[2] -match '^\d+$') { $max = [int]$p[2] }
                if ($i -lt 0 -or $i -ge $msgs.Count -or $del.ContainsKey($i)) { Send-Line $wr '-ERR No such message'; break }
                Send-Line $wr '+OK'
                $inBody = $false; $k = 0
                foreach ($l in ([IO.File]::ReadAllText($msgs[$i].FullName) -split "`r?`n")) {
                    if (-not $inBody) { Send-Line $wr $l; if ($l -eq '') { $inBody = $true } }
                    elseif ($k -lt $max) { Send-Line $wr $l; $k++ }
                }
                Send-Line $wr '.'
            }
            'DELE' {
                $i = -1
                if ($arg -match '^\d+$') { $i = [int]$arg - 1 }
                if ($i -lt 0 -or $i -ge $msgs.Count) { Send-Line $wr '-ERR No such message' }
                else { $del[$i] = $true; Send-Line $wr "+OK message $arg deleted" }
            }
            'RSET' { $del = @{}; Send-Line $wr '+OK' }
            'NOOP' { Send-Line $wr '+OK' }
            'QUIT' {
                $n = 0
                foreach ($i in $del.Keys) { try { Remove-Item -LiteralPath $msgs[$i].FullName -Force -ErrorAction Stop; $n++ } catch { } }
                Send-Line $wr "+OK bye ($n deleted)"
                $Client.Close(); return
            }
            default { Send-Line $wr "-ERR Unknown command: $verb" }
        }
    }
    try { $Client.Close() } catch { }
}

Log (L 'Servidor POP3 en marcha.' 'POP3 server running.') 'OK'
while ($true) {
    try {
        $cl = $listener.AcceptTcpClient()
        try { Invoke-Session -Client $cl } catch { Log $_.Exception.Message 'WARN'; try { $cl.Close() } catch { } }
    } catch { Log $_.Exception.Message 'WARN'; Start-Sleep -Seconds 1 }
}
