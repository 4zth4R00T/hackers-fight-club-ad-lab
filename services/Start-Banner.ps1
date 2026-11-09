[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'setup\Lab.psm1') -Force -DisableNameChecking
$c = Get-LabConfig
$LOG = Join-Path $c.Paths.Logs 'banner.log'

function Log {
    param([string]$Text, [string]$Level = 'INFO')
    try { Add-Content -LiteralPath $LOG -Value ('{0}  [{1,-5}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Text) -Encoding UTF8 } catch { }
}

if (-not $c.Challenges -or -not (Test-Weakness 'UnexpectedBannerPort')) {
    Log (L 'Servicio del puerto raro desactivado en la configuracion.' 'Odd port service disabled in the configuration.') 'WARN'
    exit 0
}
New-Folder $c.Paths.Logs | Out-Null

$flag = $null
try { $flag = Get-FlagValue -Id 'D5-OPT1' } catch { }
if (-not $flag) {
    Log (L 'La bandera D5-OPT1 todavia no esta sembrada. Ejecuta engine\Initialize-Challenges.ps1.' 'Flag D5-OPT1 is not seeded yet. Run engine\Initialize-Challenges.ps1.') 'ERROR'
    exit 1
}

$port = [int]$c.BannerPort
$org = [string]$c.Organization
$text = L @"
  ==============================================================
     $org  servicio de diagnostico  puerto $port/tcp
  ==============================================================

  Este puerto no aparece en ninguna tabla de puertos conocidos.
  Ahi esta la gracia: en un reconocimiento, lo que no encaja es
  justo lo que hay que mirar.

  Un puerto abierto que nadie sabe explicar es un hallazgo, y en
  un informe real se reporta como tal.

  $flag

"@ @"
  ==============================================================
     $org  diagnostic service  port $port/tcp
  ==============================================================

  This port does not appear in any table of well known ports.
  That is the point: during reconnaissance, whatever does not fit
  is exactly what you need to look at.

  An open port that nobody can explain is a finding, and a real
  report lists it as one.

  $flag

"@
$bytes = [Text.Encoding]::ASCII.GetBytes(($text -replace "(?<!`r)`n", "`r`n"))

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
Log ((L 'Servicio de diagnostico escuchando en ' 'Diagnostic service listening on ') + "${ip}:$port") 'OK'

while ($true) {
    try {
        $cl = $listener.AcceptTcpClient()
        $remote = $cl.Client.RemoteEndPoint.ToString()
        $cl.SendTimeout = 3000
        $s = $cl.GetStream()
        $s.Write($bytes, 0, $bytes.Length)
        $s.Flush()
        Start-Sleep -Milliseconds 200
        $cl.Close()
        Log ((L 'Banner servido a ' 'Banner served to ') + $remote)
    } catch {
        Log $_.Exception.Message 'WARN'
        Start-Sleep -Seconds 1
    }
}
