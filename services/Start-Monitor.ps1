[CmdletBinding()]
param([int]$IntervalSeconds = 60, [switch]$Once)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'setup\Lab.psm1') -Force -DisableNameChecking
Import-Module ActiveDirectory -ErrorAction SilentlyContinue
$c = Get-LabConfig
$LOG = Join-Path $c.Paths.Logs 'monitor.log'

function Log {
    param([string]$Text, [string]$Level = 'INFO')
    try { Add-Content -LiteralPath $LOG -Value ('{0}  [{1,-5}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Text) -Encoding UTF8 } catch { }
}

$logonTypes = @{
    '2' = (L 'Consola' 'Console'); '3' = (L 'Red (SMB/LDAP)' 'Network (SMB/LDAP)'); '4' = (L 'Lote' 'Batch'); '5' = (L 'Servicio' 'Service')
    '7' = (L 'Desbloqueo' 'Unlock'); '8' = (L 'Red en claro' 'Cleartext network'); '9' = (L 'Credenciales nuevas' 'New credentials')
    '10' = (L 'Escritorio remoto' 'Remote desktop'); '11' = (L 'En cache' 'Cached')
}

function Get-EventData {
    param($Evt)
    $h = @{}
    try {
        $x = [xml]$Evt.ToXml()
        foreach ($d in $x.Event.EventData.Data) { if ($d.Name) { $h[$d.Name] = [string]$d.'#text' } }
    } catch { }
    return $h
}

function Read-Security {
    param([int[]]$Ids, [int]$Max = 400, [int]$Minutes = 120)
    try { return @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; ID = $Ids; StartTime = (Get-Date).AddMinutes(-$Minutes) } -MaxEvents $Max -ErrorAction Stop) }
    catch { return @() }
}

function Test-Person {
    param([string]$U)
    if (-not $U -or $U -eq '-' -or $U.EndsWith('$')) { return $false }
    if ($U -like 'DWM-*' -or $U -like 'UMFD-*') { return $false }
    if (@('SYSTEM', 'LOCAL SERVICE', 'NETWORK SERVICE', 'ANONYMOUS LOGON') -contains $U.ToUpperInvariant()) { return $false }
    return $true
}

function Test-PersonFast {
    param($Evt, [int]$Index)
    try {
        $v = [string]$Evt.Properties[$Index].Value
        if ($v -and ($v.EndsWith('$') -or $v -eq '-' -or $v -eq 'SYSTEM')) { return $false }
    } catch { }
    return $true
}

function Write-MonitorData {
    $sessions = @{}
    foreach ($ev in (Read-Security -Ids 4624 -Max 4000 -Minutes 240)) {
        if (-not (Test-PersonFast $ev 5)) { continue }
        $d = Get-EventData $ev
        $u = $d['TargetUserName']
        if (-not (Test-Person $u)) { continue }
        $t = $d['LogonType']
        if ($t -eq '5' -or $t -eq '0') { continue }
        $k = "$u|$($d['IpAddress'])"
        if (-not $sessions.ContainsKey($k)) {
            $src = $d['IpAddress']
            if (-not $src -or $src -eq '-' -or $src -eq '::1') { $src = $d['WorkstationName'] }
            $label = "Type $t"
            if ($logonTypes.ContainsKey($t)) { $label = $logonTypes[$t] }
            $sessions[$k] = [pscustomobject]@{ Usuario = $u; Tipo = $label; Origen = [string]$src; Cuando = $ev.TimeCreated }
        }
    }
    $active = @($sessions.Values | Sort-Object Cuando -Descending | Select-Object -First 20)

    $tickets = @()
    foreach ($ev in (Read-Security -Ids 4768, 4769 -Max 300 -Minutes 60)) {
        $d = Get-EventData $ev
        $u = ([string]$d['TargetUserName'] -split '@')[0]
        if (-not (Test-Person $u)) { continue }
        $tgt = ($ev.Id -eq 4768)
        $what = L "boleto de servicio: $($d['ServiceName'])" "service ticket: $($d['ServiceName'])"
        $cls = 'TGS'
        if ($tgt) { $what = L 'boleto maestro: inicio de sesion' 'master ticket: signed in'; $cls = 'TGT' }
        $tickets += [pscustomobject]@{ Usuario = $u; Clase = $cls; Que = $what; Cuando = $ev.TimeCreated }
    }
    $tickets = @($tickets | Sort-Object Cuando -Descending | Select-Object -First 25)

    $shares = @()
    foreach ($ev in (Read-Security -Ids 5140, 5145 -Max 2500 -Minutes 60)) {
        if (-not (Test-PersonFast $ev 1)) { continue }
        $d = Get-EventData $ev
        $u = $d['SubjectUserName']
        if (-not (Test-Person $u)) { continue }
        $sh = $d['ShareName']
        if (-not $sh -or $sh -eq '\\*\IPC$') { continue }
        $shares += [pscustomobject]@{ Usuario = $u; Recurso = [string]$sh; Fichero = [string]$d['RelativeTargetName']; Cuando = $ev.TimeCreated }
    }
    $shares = @($shares | Sort-Object Cuando -Descending | Select-Object -First 20)

    $fails = @()
    foreach ($ev in (Read-Security -Ids 4625, 4771, 4776 -Max 300 -Minutes 120)) {
        $d = Get-EventData $ev
        $u = ([string]$d['TargetUserName'] -split '@')[0]
        if (-not $u -or $u -eq '-') { continue }
        $how = ''
        if ($ev.Id -eq 4776) { $how = 'NTLM' } elseif ($ev.Id -eq 4771) { $how = 'Kerberos' }
        $src = $d['IpAddress']
        if (-not $src -or $src -eq '-') { $src = $d['Workstation'] }
        if (-not $src) { $src = $d['WorkstationName'] }
        $fails += [pscustomobject]@{ Usuario = $u; Desde = [string]$src; Motivo = $how; Cuando = $ev.TimeCreated }
    }
    $fails = @($fails | Sort-Object Cuando -Descending | Select-Object -First 12)

    $computers = @()
    try {
        foreach ($pc in @(Get-ADComputer -Filter 'Enabled -eq $true' -Properties LastLogonDate -ErrorAction Stop)) {
            $computers += [pscustomobject]@{ Nombre = $pc.Name; Visto = $pc.LastLogonDate }
        }
        $computers = @($computers | Sort-Object Visto -Descending)
    } catch { }

    $data = [ordered]@{
        Generado = (Get-Date).ToString('o')
        Sesiones = @($active | ForEach-Object { [ordered]@{ Usuario = $_.Usuario; Tipo = $_.Tipo; Origen = $_.Origen; Cuando = $_.Cuando.ToString('o') } })
        Tickets  = @($tickets | ForEach-Object { [ordered]@{ Usuario = $_.Usuario; Clase = $_.Clase; Que = $_.Que; Cuando = $_.Cuando.ToString('o') } })
        Shares   = @($shares | ForEach-Object { [ordered]@{ Usuario = $_.Usuario; Recurso = $_.Recurso; Fichero = $_.Fichero; Cuando = $_.Cuando.ToString('o') } })
        Fallos   = @($fails | ForEach-Object { [ordered]@{ Usuario = $_.Usuario; Desde = $_.Desde; Motivo = $_.Motivo; Cuando = $_.Cuando.ToString('o') } })
        Equipos  = @($computers | Select-Object -First 14 | ForEach-Object { $seen = ''; if ($_.Visto) { $seen = $_.Visto.ToString('o') }; [ordered]@{ Nombre = $_.Nombre; Visto = $seen } })
    }
    New-Folder $c.Paths.Score | Out-Null
    Write-JsonFile -Path (Join-Path $c.Paths.Score 'monitor.json') -Object $data -Depth 6

    try {
        $mode = L 'Presencial' 'On site'
        $roll = @(Get-ADUser -Filter * -SearchBase $c.OUStudents -Properties employeeNumber, DisplayName, mail, physicalDeliveryOfficeName, Enabled -ErrorAction Stop |
            Where-Object { $_.employeeNumber } |
            Sort-Object { [int](([string]$_.employeeNumber) -replace '\D', '0') } |
            ForEach-Object {
                $m = $mode
                if ($_.physicalDeliveryOfficeName) { $m = [string]$_.physicalDeliveryOfficeName }
                [ordered]@{ Slot = [string]$_.employeeNumber; Usuario = [string]$_.SamAccountName; Nombre = [string]$_.DisplayName; Correo = [string]$_.mail; Modalidad = $m; Activa = [bool]$_.Enabled }
            })
        $path = Join-Path $c.Paths.Score 'padron.json'
        if ($roll.Count -eq 1) { [IO.File]::WriteAllText($path, '[' + ($roll[0] | ConvertTo-Json -Depth 4 -Compress) + ']', (New-Object Text.UTF8Encoding($false))) }
        else { Write-JsonFile -Path $path -Object $roll -Depth 4 }
    } catch { Log ((L 'No se pudo publicar el padron: ' 'Could not publish the roster: ') + $_.Exception.Message) 'WARN' }
    return $data
}

if ($Once) {
    $d = Write-MonitorData
    Add-LabOutput (L "Monitor generado: $(@($d.Sesiones).Count) sesiones, $(@($d.Tickets).Count) tickets, $(@($d.Shares).Count) accesos y $(@($d.Fallos).Count) fallos." "Monitor generated: $(@($d.Sesiones).Count) sessions, $(@($d.Tickets).Count) tickets, $(@($d.Shares).Count) share accesses and $(@($d.Fallos).Count) failures.") 'OK'
    Show-LabOutput
    exit 0
}

Log (L "Monitor en marcha, refresco cada $IntervalSeconds s." "Monitor running, refresh every $IntervalSeconds s.") 'OK'
$errors = 0
$rounds = 0
while ($true) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try { $null = Write-MonitorData; $errors = 0 }
    catch {
        $errors++
        Log $_.Exception.Message 'WARN'
        if ($errors -ge 5) { Start-Sleep -Seconds 120; $errors = 0 }
    }
    $sw.Stop()
    $rounds++
    [GC]::Collect()
    if ($rounds -ge [int](6 * 3600 / $IntervalSeconds)) { Log (L 'Reciclando el monitor tras seis horas.' 'Recycling the monitor after six hours.'); exit 1 }
    $rest = $IntervalSeconds - [int]$sw.Elapsed.TotalSeconds
    if ($rest -lt 5) { $rest = 5 }
    Start-Sleep -Seconds $rest
}
