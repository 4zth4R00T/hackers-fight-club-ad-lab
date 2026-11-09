[CmdletBinding()]
param(
    [switch]$NoShow,
    [switch]$Remove,
    [int]$ScorerMinutes = 1
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'setup\Lab.psm1') -DisableNameChecking
if (-not (Test-Administrator)) {
    Write-Host (L 'Ejecutalo como administrador del dominio, en el controlador.' 'Run it as a domain administrator, on the domain controller.') -ForegroundColor Red
    exit 1
}
$c = Get-LabConfig

function Get-ServiceTable {
    $ch = [bool]$c.Challenges
    $mail = [bool]$c.Mail -and (Test-Weakness 'PlaintextMail')
    return @(
        [pscustomobject]@{ Task = 'Lab-Scorer';   Script = 'engine\Invoke-Scorer.ps1';   Args = '-NoShow'; Enabled = $ch; Ports = @(); Interval = $ScorerMinutes
            Es = 'Motor de puntuacion'; En = 'Scoring engine' }
        [pscustomobject]@{ Task = 'Lab-Intranet'; Script = 'services\Start-Intranet.ps1'; Args = ''; Enabled = ($ch -and (Test-Weakness 'InternalHttpIntranet')); Ports = @([int]$c.IntranetPort); Interval = 0
            Es = 'Intranet HTTP de la empresa ficticia'; En = 'HTTP intranet of the fictional company' }
        [pscustomobject]@{ Task = 'Lab-Banner';   Script = 'services\Start-Banner.ps1';   Args = ''; Enabled = ($ch -and (Test-Weakness 'UnexpectedBannerPort')); Ports = @([int]$c.BannerPort); Interval = 0
            Es = 'Servicio de diagnostico en un puerto inesperado'; En = 'Diagnostic service on an unexpected port' }
        [pscustomobject]@{ Task = 'Lab-SMTP';     Script = 'services\Start-Smtp.ps1';     Args = ''; Enabled = $mail; Ports = @($c.SmtpPorts | ForEach-Object { [int]$_ }); Interval = 0
            Es = 'Correo interno SMTP sin TLS'; En = 'Internal SMTP mail without TLS' }
        [pscustomobject]@{ Task = 'Lab-POP3';     Script = 'services\Start-Pop3.ps1';     Args = ''; Enabled = $mail; Ports = @([int]$c.Pop3Port); Interval = 0
            Es = 'Lectura de buzones POP3 sin TLS'; En = 'POP3 mailbox access without TLS' }
        [pscustomobject]@{ Task = 'Lab-Monitor';  Script = 'services\Start-Monitor.ps1';  Args = ''; Enabled = [bool]$c.Web; Ports = @(); Interval = 0
            Es = 'Monitor en vivo para la web del instructor'; En = 'Live monitor for the instructor web' }
    )
}

function Stop-LabService {
    param($Svc)
    if (Get-ScheduledTask -TaskName $Svc.Task -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $Svc.Task -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $Svc.Task -Confirm:$false -ErrorAction SilentlyContinue
    }
    $leaf = Split-Path -Leaf $Svc.Script
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*$leaf*" -and $_.ProcessId -ne $PID } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if ($Svc.Ports.Count -gt 0) { Get-NetFirewallRule -Name $Svc.Task -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue }
}

function Invoke-Main {
    $table = Get-ServiceTable
    $ps = Get-PowerShellPath
    foreach ($s in $table) { Stop-LabService $s }
    if ($Remove) {
        Write-LabLog (L 'Servicios del laboratorio detenidos y dados de baja.' 'Lab services stopped and unregistered.') 'OK'
        return
    }
    Start-Sleep -Seconds 2
    $started = @()
    foreach ($s in $table) {
        if (-not $s.Enabled) {
            Write-LabLog (L "$($s.Task) desactivado por la configuracion." "$($s.Task) disabled by the configuration.") 'INFO'
            continue
        }
        $script = Join-Path $root $s.Script
        if (-not (Test-Path -LiteralPath $script)) { Write-LabLog (L "Falta $script." "Missing $script.") 'ERROR'; continue }
        $taskArgs = Get-ScriptArguments -Script $script -Extra $s.Args
        $desc = L $s.Es $s.En
        if ($s.Interval -gt 0) { Register-LabTask -Name $s.Task -Execute $ps -Arguments $taskArgs -EveryMinutes $s.Interval -Description $desc -Start }
        else { Register-LabTask -Name $s.Task -Execute $ps -Arguments $taskArgs -AtStartup -Description $desc -Start }
        if ($s.Ports.Count -gt 0) { Set-LabFirewallRule -Name $s.Task -Port ([string[]]($s.Ports | ForEach-Object { [string]$_ })) }
        $started += $s
        Write-LabLog (L "$($s.Task) registrado: $desc." "$($s.Task) registered: $desc.") 'OK'
    }
    $ip = Get-ServiceAddress -TimeoutSeconds 30
    if (-not $ip) {
        Write-LabLog (L "La direccion del modo $($c.NetworkMode) no esta disponible: los servicios esperaran hasta que aparezca." "The $($c.NetworkMode) mode address is not available: services will wait until it shows up.") 'WARN'
        return
    }
    $ports = @($started | ForEach-Object { $_.Ports } | Where-Object { $_ })
    if ($ports.Count -eq 0) { return }
    $deadline = (Get-Date).AddSeconds(40)
    $pending = New-Object System.Collections.Generic.List[int]
    foreach ($p in $ports) { $pending.Add([int]$p) }
    while ($pending.Count -gt 0 -and (Get-Date) -lt $deadline) {
        foreach ($p in @($pending)) {
            if (Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -eq $ip }) { [void]$pending.Remove($p) }
        }
        if ($pending.Count -gt 0) { Start-Sleep -Seconds 2 }
    }
    foreach ($p in $ports) {
        if ($pending.Contains([int]$p)) { Write-LabLog (L "El puerto $p todavia no escucha en $ip. Revisa los registros en $($c.Paths.Logs)." "Port $p is not listening on $ip yet. Check the logs in $($c.Paths.Logs).") 'WARN' }
        else { Write-LabLog (L "Puerto $p escuchando en $ip." "Port $p listening on $ip.") 'OK' }
    }
    $wild = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $ports -contains [int]$_.LocalPort -and ($_.LocalAddress -eq '0.0.0.0' -or $_.LocalAddress -eq '::') })
    foreach ($w in $wild) { Write-LabLog (L "Aviso: el puerto $($w.LocalPort) escucha en todas las interfaces ($($w.LocalAddress)); otro proceso lo ocupa." "Warning: port $($w.LocalPort) listens on every interface ($($w.LocalAddress)); another process owns it.") 'WARN' }
}

try { Invoke-Main }
catch {
    Write-LabLog ((L 'Fallo al registrar los servicios: ' 'Service registration failed: ') + $_.Exception.Message) 'ERROR'
    if ($NoShow) { throw }
    Show-LabOutput
    exit 1
}
if (-not $NoShow) { Show-LabOutput }
