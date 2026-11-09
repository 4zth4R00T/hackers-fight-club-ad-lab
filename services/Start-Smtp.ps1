[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'setup\Lab.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'services\Mail.psm1') -Force -DisableNameChecking
Import-Module ActiveDirectory -ErrorAction SilentlyContinue
$c = Get-LabConfig
$LOG = Join-Path $c.Paths.Logs 'mail.log'
$MAX_SIZE = 5MB
$MAX_RCPT = 20

function Log {
    param([string]$Text, [string]$Level = 'INFO')
    try { Add-Content -LiteralPath $LOG -Value ('{0}  [{1,-5}] SMTP {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Text) -Encoding UTF8 } catch { }
}

if (-not $c.Mail -or -not (Test-Weakness 'PlaintextMail')) {
    Log (L 'Correo desactivado en la configuracion.' 'Mail disabled in the configuration.') 'WARN'
    exit 0
}
New-Folder $c.Paths.Logs | Out-Null
$names = Get-MailNames
$BANNER = "$($c.DcFqdn) ESMTP $($c.Organization)"

$ip = Get-ServiceAddress -TimeoutSeconds 180 -LogFile $LOG
if (-not $ip) { exit 1 }

function Open-Listener {
    param([string]$Address, [int]$Port, [int]$Tries = 6)
    for ($i = 1; $i -le $Tries; $i++) {
        try {
            $l = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Parse($Address), $Port)
            $l.Start()
            Log ((L 'Escuchando en ' 'Listening on ') + "${Address}:$Port") 'OK'
            return $l
        } catch {
            if ($i -eq $Tries) { Log ((L 'No se pudo abrir ' 'Could not open ') + "${Address}:${Port}: $($_.Exception.Message)") 'ERROR'; return $null }
            Start-Sleep -Seconds 5
        }
    }
}

$listeners = @()
foreach ($p in @($c.SmtpPorts)) { $l = Open-Listener -Address $ip -Port ([int]$p); if ($l) { $listeners += $l } }
if ($ip -ne '127.0.0.1') { $l = Open-Listener -Address '127.0.0.1' -Port 25 -Tries 2; if ($l) { $listeners += $l } }
if ($listeners.Count -eq 0) { exit 1 }

function Send-Line { param($W, [string]$T) $W.Write("$T`r`n"); $W.Flush() }
function Read-B64 { param([string]$S) try { return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($S)) } catch { return '' } }

function Invoke-Session {
    param($Client)
    $remote = $Client.Client.RemoteEndPoint.Address
    if (-not (Test-MailClient -Address $remote)) {
        Log ((L 'Conexion rechazada desde ' 'Connection refused from ') + $remote) 'WARN'
        $Client.Close(); return
    }
    $Client.ReceiveTimeout = 60000
    $Client.SendTimeout = 60000
    $ns = $Client.GetStream()
    $rd = New-Object IO.StreamReader($ns, [Text.Encoding]::UTF8)
    $wr = New-Object IO.StreamWriter($ns, (New-Object Text.UTF8Encoding($false)))
    $st = @{ Auth = $null; From = $null; To = @(); Helo = '' }
    $domain = $c.DomainFqdn.ToLowerInvariant()
    Send-Line $wr "220 $BANNER"
    while ($true) {
        $line = $null
        try { $line = $rd.ReadLine() } catch { break }
        if ($null -eq $line) { break }
        $verb = ($line -split '\s+')[0].ToUpperInvariant()
        $rest = $line.Substring([math]::Min($verb.Length, $line.Length)).Trim()
        switch ($verb) {
            'QUIT' { Send-Line $wr "221 $domain bye"; $Client.Close(); return }
            'NOOP' { Send-Line $wr '250 OK' }
            'RSET' { $st.From = $null; $st.To = @(); Send-Line $wr '250 OK' }
            'HELO' { $st.Helo = $rest; Send-Line $wr "250 $($c.DcFqdn)" }
            'EHLO' {
                $st.Helo = $rest
                Send-Line $wr "250-$($c.DcFqdn) hello $rest"
                Send-Line $wr '250-AUTH LOGIN PLAIN'
                Send-Line $wr "250-SIZE $MAX_SIZE"
                Send-Line $wr '250-8BITMIME'
                Send-Line $wr '250 HELP'
            }
            'VRFY' { Send-Line $wr '252 Cannot VRFY user, but will accept message and attempt delivery' }
            'EXPN' { Send-Line $wr '502 Not implemented' }
            'HELP' { Send-Line $wr '214 HELO EHLO AUTH MAIL RCPT DATA RSET NOOP QUIT' }
            'AUTH' {
                $mode = ($rest -split '\s+')[0].ToUpperInvariant()
                $user = $null; $pass = $null
                if ($mode -eq 'LOGIN') {
                    Send-Line $wr '334 VXNlcm5hbWU6'
                    $user = Read-B64 ($rd.ReadLine())
                    Send-Line $wr '334 UGFzc3dvcmQ6'
                    $pass = Read-B64 ($rd.ReadLine())
                } elseif ($mode -eq 'PLAIN') {
                    $arg = ($rest -split '\s+')[1]
                    if (-not $arg) { Send-Line $wr '334 '; $arg = $rd.ReadLine() }
                    $parts = (Read-B64 $arg) -split "`0"
                    if ($parts.Count -ge 3) { $user = $parts[1]; $pass = $parts[2] }
                } else { Send-Line $wr '504 Unrecognized authentication type'; break }
                if (-not $user) { $user = '' }
                if (-not $pass) { $pass = '' }
                $who = Test-MailCredential -User $user -Password $pass
                if ($who) { $st.Auth = $who; Send-Line $wr '235 2.7.0 Authentication successful'; Log "AUTH $($who.Sam) $remote" }
                else { Send-Line $wr '535 5.7.8 Authentication credentials invalid'; Log "AUTH FAIL '$user' $remote" 'WARN' }
            }
            'MAIL' {
                if (-not $st.Auth) { Send-Line $wr '530 5.7.0 Authentication required'; break }
                if ($rest -notmatch '(?i)^FROM:\s*<?([^>\s]+)>?') { Send-Line $wr '501 Syntax: MAIL FROM:<address>'; break }
                $from = $Matches[1].ToLowerInvariant()
                $own = ("{0}@{1}" -f $st.Auth.Sam, $domain).ToLowerInvariant()
                if ($from -ne $own) { Send-Line $wr "550 5.7.1 You may only send as $own"; Log "SPOOF $($st.Auth.Sam) as '$from'" 'WARN'; break }
                $st.From = $from; $st.To = @()
                Send-Line $wr '250 OK'
            }
            'RCPT' {
                if (-not $st.From) { Send-Line $wr '503 MAIL FROM first'; break }
                if ($st.To.Count -ge $MAX_RCPT) { Send-Line $wr '452 Too many recipients'; break }
                if ($rest -notmatch '(?i)^TO:\s*<?([^>\s]+)>?') { Send-Line $wr '501 Syntax: RCPT TO:<address>'; break }
                $to = $Matches[1].ToLowerInvariant()
                if ($to -eq $names.Validation.ToLowerInvariant()) {
                    $st.To += , ([pscustomobject]@{ Sam = 'validation'; Special = $true })
                    Send-Line $wr '250 OK'; break
                }
                $dest = Resolve-Mailbox -Address $to
                if (-not $dest) { Send-Line $wr "550 5.1.1 Unknown recipient or relay denied: $to"; break }
                $st.To += , $dest
                Send-Line $wr '250 OK'
            }
            'DATA' {
                if ($st.To.Count -eq 0) { Send-Line $wr '503 RCPT TO first'; break }
                Send-Line $wr '354 End data with <CR><LF>.<CR><LF>'
                $sb = New-Object Text.StringBuilder
                $size = 0
                while ($true) {
                    $l = $rd.ReadLine()
                    if ($null -eq $l -or $l -eq '.') { break }
                    if ($l.StartsWith('..')) { $l = $l.Substring(1) }
                    $size += $l.Length + 2
                    if ($size -gt $MAX_SIZE) { continue }
                    [void]$sb.Append("$l`r`n")
                }
                if ($size -gt $MAX_SIZE) { Send-Line $wr '552 Message too large'; $st.From = $null; $st.To = @(); break }
                $body = $sb.ToString()
                $subject = '(no subject)'
                if ($body -match '(?im)^Subject:\s*(.+)$') { $subject = $Matches[1].Trim() }
                $rcv = "Received: from $($st.Helo) ([$remote])`r`n        by $($c.DcFqdn) with ESMTP;`r`n        $((Get-Date).ToUniversalTime().ToString('r'))`r`nX-Authenticated-User: $($st.Auth.Sam)`r`n"
                $ok = 0
                foreach ($d in $st.To) {
                    if ($d.PSObject.Properties['Special'] -and $d.Special) {
                        try { if (Send-ValidationReply -Sender $st.Auth -LogFile $LOG) { $ok++ } } catch { Log $_.Exception.Message 'WARN' }
                        continue
                    }
                    try { $null = Add-MailMessage -Recipient $d -From $st.From -Subject $subject -Body $body -Raw ($rcv + $body); $ok++ }
                    catch { Log "DELIVERY $($d.Sam): $($_.Exception.Message)" 'WARN' }
                }
                Send-Line $wr "250 OK queued for $ok recipient(s)"
                Log "$($st.Auth.Sam) to $(($st.To | ForEach-Object { $_.Sam }) -join ',') '$subject'"
                $st.From = $null; $st.To = @()
            }
            default { Send-Line $wr "500 Command not recognized: $verb" }
        }
    }
    try { $Client.Close() } catch { }
}

Log (L 'Servidor SMTP en marcha.' 'SMTP server running.') 'OK'
while ($true) {
    $busy = $false
    foreach ($l in $listeners) {
        try {
            if ($l.Pending()) {
                $busy = $true
                $cl = $l.AcceptTcpClient()
                try { Invoke-Session -Client $cl } catch { Log $_.Exception.Message 'WARN'; try { $cl.Close() } catch { } }
            }
        } catch { Log $_.Exception.Message 'WARN'; Start-Sleep -Seconds 1 }
    }
    if (-not $busy) { Start-Sleep -Milliseconds 50 }
}
