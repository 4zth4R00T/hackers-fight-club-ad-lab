[CmdletBinding(DefaultParameterSetName = 'Check')]
param(
    [Parameter(ParameterSetName = 'Check')][switch]$Check,
    [Parameter(ParameterSetName = 'Prepare')][switch]$Prepare,
    [Parameter(ParameterSetName = 'Join')][switch]$Join,
    [Parameter(ParameterSetName = 'Leave')][switch]$Leave,
    [Parameter(ParameterSetName = 'Join', Mandatory)]
    [Parameter(ParameterSetName = 'Leave')]
    [string]$User,
    [string]$Domain,
    [string]$DcAddress,
    [string]$DcName,
    [string]$OUPath,
    [string]$ComputerName,
    [string]$ConfigFile,
    [ValidateSet('Auto', 'Tailscale', 'VPN', 'VMnet', 'LAN')][string]$Mode = 'Auto',
    [switch]$DnsByAdapter,
    [switch]$SkipDns,
    [switch]$KeepKit,
    [switch]$KeepTailscale,
    [switch]$NoRestart
)

$ErrorActionPreference = 'Continue'
$TS = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
$script:Lines = New-Object System.Collections.Generic.List[object]
$script:Todo = New-Object System.Collections.Generic.List[string]
$script:Yes = '^(s|si|y|yes|{0}{1}|{0})$' -f [char]0x0434, [char]0x0430

if (-not $ConfigFile) { $ConfigFile = Join-Path $PSScriptRoot 'lab.json' }
$info = $null
if (Test-Path -LiteralPath $ConfigFile) {
    try {
        $t = [IO.File]::ReadAllText($ConfigFile)
        if ($t.Length -gt 0 -and $t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }
        $info = $t | ConvertFrom-Json
    } catch { $info = $null }
}

$script:RuExact = $null
$script:RuPatterns = $null
function Get-RuText {
    param([AllowEmptyString()][string]$En)
    if (-not $En) { return $En }
    if ($null -eq $script:RuExact) {
        $script:RuExact = New-Object 'System.Collections.Generic.Dictionary[string,string]'
        $script:RuPatterns = New-Object System.Collections.Generic.List[object]
        $found = @()
        foreach ($p in @((Join-Path $PSScriptRoot 'ru.json'), (Join-Path (Split-Path -Parent $PSScriptRoot) 'lang\ru.json'))) {
            if (-not (Test-Path -LiteralPath $p)) { continue }
            try { $data = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { continue }
            foreach ($pair in @($data.messages)) {
                $k = [string]$pair[0]
                $v = [string]$pair[1]
                if (-not $k -or -not $v -or $script:RuExact.ContainsKey($k)) { continue }
                $script:RuExact[$k] = $v
                if (-not $k.Contains('[[')) { continue }
                $rx = New-Object Text.StringBuilder
                $order = @()
                $literal = ''
                foreach ($part in [regex]::Split($k, '(\[\[\d+\]\])')) {
                    if ($part -match '^\[\[\d+\]\]$') { [void]$rx.Append('(.*?)'); $order += $part }
                    else { [void]$rx.Append([regex]::Escape($part)); $literal += $part }
                }
                $weight = ($literal -replace '[^A-Za-z]', '').Length
                if ($weight -lt 2) { continue }
                $re = New-Object Text.RegularExpressions.Regex -ArgumentList @(('^' + $rx.ToString() + '$'), [Text.RegularExpressions.RegexOptions]::Singleline)
                $found += [pscustomobject]@{ Regex = $re; Order = $order; Ru = $v; Weight = $weight }
            }
            break
        }
        foreach ($f in @($found | Sort-Object Weight -Descending)) { $script:RuPatterns.Add($f) }
    }
    $v = $null
    if ($script:RuExact.TryGetValue($En, [ref]$v)) { return $v }
    foreach ($p in $script:RuPatterns) {
        $m = $p.Regex.Match($En)
        if (-not $m.Success) { continue }
        $out = $p.Ru
        for ($i = 0; $i -lt $p.Order.Count; $i++) { $out = $out.Replace($p.Order[$i], $m.Groups[$i + 1].Value) }
        return $out
    }
    return $En
}

function T {
    param([string]$Es, [string]$En)
    $lang = [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
    if ($info -and $info.Language) { $lang = [string]$info.Language }
    if ($lang -eq 'es') { return $Es }
    if ($lang -eq 'ru') { return (Get-RuText $En) }
    return $En
}
function Out-Line { param([string]$Text = '', [string]$Color = 'Gray') $script:Lines.Add(@($Text, $Color)) }
function Title { param([string]$Es, [string]$En) Out-Line ''; Out-Line ('  ' + (T $Es $En)) 'Cyan' }
function Ok { param([string]$Text) Out-Line "   OK    $Text" 'Green' }
function Bad { param([string]$Text) Out-Line "   FAIL  $Text" 'Red' }
function Warn { param([string]$Text) Out-Line "   WARN  $Text" 'Yellow' }
function Note { param([string]$Text) Out-Line "         $Text" 'DarkGray' }
function Todo { param([string]$Es, [string]$En) $script:Todo.Add((T $Es $En)) }
function Flush {
    foreach ($l in $script:Lines) { Write-Host $l[0] -ForegroundColor $l[1] }
    $script:Lines.Clear()
}

if (-not $Domain -and $info) { $Domain = [string]$info.Domain }
if (-not $DcName -and $info) { $DcName = [string]$info.DcName }
if (-not $DcAddress -and $info) { $DcAddress = [string]$info.DcAddress }
if (-not $OUPath -and $info) { $OUPath = [string]$info.WorkstationsOU }
if ($Mode -eq 'Auto' -and $info -and $info.NetworkMode) { $Mode = [string]$info.NetworkMode }
if ($Mode -eq 'Auto') {
    if ($DcAddress -and $DcAddress -match '^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.') { $Mode = 'Tailscale' } else { $Mode = 'LAN' }
}
$kitShare = 'LabKit'
if ($info -and $info.KitShare) { $kitShare = [string]$info.KitShare }
$deployTask = 'Lab-Kit-Deploy'
if ($info -and $info.DeployTask) { $deployTask = [string]$info.DeployTask }

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Port {
    param([string]$Address, [int]$Port, [int]$Timeout = 2500)
    try {
        $cl = New-Object Net.Sockets.TcpClient
        $ar = $cl.BeginConnect($Address, $Port, $null, $null)
        $ok = $ar.AsyncWaitHandle.WaitOne($Timeout) -and $cl.Connected
        $cl.Close()
        return [bool]$ok
    } catch { return $false }
}

function Get-TunnelIp {
    $ip = Get-NetIPAddress -InterfaceAlias 'Tailscale' -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ip) { return $ip.IPAddress }
    return $null
}

function Resolve-Settings {
    if (-not $Domain) {
        $script:Domain = Read-Host (T 'Dominio del laboratorio (por ejemplo lab.local)' 'Lab domain (for example lab.local)')
    }
    if (-not $DcAddress -and $Domain) {
        try {
            $srv = Resolve-DnsName "_ldap._tcp.dc._msdcs.$Domain" -Type SRV -ErrorAction Stop | Where-Object { $_.NameTarget } | Select-Object -First 1
            if ($srv) {
                $a = Resolve-DnsName $srv.NameTarget -Type A -ErrorAction Stop | Select-Object -First 1
                if ($a) { $script:DcAddress = $a.IPAddress }
                if (-not $DcName) { $script:DcName = ($srv.NameTarget -split '\.')[0] }
            }
        } catch { }
    }
}

function Test-Requirements {
    Title 'Requisitos' 'Requirements'
    $ready = $true
    $ed = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).EditionID
    if ($ed -match '^Core') {
        Bad ((T 'Edicion Home ' 'Home edition ') + "($ed)")
        Note (T 'Windows Home no puede unirse a un dominio. Usa Pro, Enterprise o Education.' 'Windows Home cannot join a domain. Use Pro, Enterprise or Education.')
        Todo 'usar una edicion de Windows compatible' 'use a compatible Windows edition'
        $ready = $false
    } else { Ok ((T 'Edicion compatible: ' 'Compatible edition: ') + $ed) }
    if (-not $Domain -or -not $DcAddress) {
        Bad (T 'Faltan el dominio o la IP del DC. Usa -Domain y -DcAddress o deja lab.json junto al script.' 'Domain or DC address missing. Use -Domain and -DcAddress or keep lab.json next to the script.')
        Todo 'indicar el dominio y la IP del DC' 'provide the domain and the DC address'
        return $false
    }
    Ok ((T 'Dominio ' 'Domain ') + "$Domain, DC $DcAddress, " + (T 'modo ' 'mode ') + $Mode)
    if ($Mode -eq 'Tailscale') {
        if (-not (Test-Path -LiteralPath $TS)) {
            Bad (T 'Tailscale no esta instalado.' 'Tailscale is not installed.')
            Note 'https://tailscale.com/download'
            Todo 'instalar Tailscale y entrar a la red del curso' 'install Tailscale and join the course network'
            return $false
        }
        $tip = Get-TunnelIp
        if (-not $tip) {
            Bad (T 'Tailscale instalado pero sin tunel.' 'Tailscale installed but no tunnel.')
            Todo 'levantar el tunel con -Prepare o tailscale up' 'bring the tunnel up with -Prepare or tailscale up'
            return $false
        }
        Ok ((T 'Tunel Tailscale con IP ' 'Tailscale tunnel with IP ') + $tip)
    }
    if ($Mode -eq 'VPN') {
        $route = Find-NetRoute -RemoteIPAddress $DcAddress -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($route) { Ok ((T 'Ruta hacia el DC por la interfaz ' 'Route to the DC through interface ') + $route.InterfaceAlias) }
        else { Warn (T 'No hay ruta hacia el DC: revisa que la VPN este conectada.' 'No route to the DC: check that the VPN is connected.') }
    }
    foreach ($p in @(53, 88, 389, 445)) {
        if (Test-Port -Address $DcAddress -Port $p) { Note ((T 'puerto ' 'port ') + "$p " + (T 'abierto' 'open')) }
        else {
            Bad ((T 'puerto ' 'port ') + "$p " + (T 'cerrado' 'closed'))
            Todo "abrir el paso al puerto $p" "allow traffic to port $p"
            if ($p -eq 445 -or $p -eq 389) { $ready = $false }
        }
    }
    return $ready
}

function Test-Chain {
    Title 'Verificacion' 'Verification'
    $nrpt = @(Get-DnsClientNrptRule -ErrorAction SilentlyContinue | Where-Object { $_.Namespace -contains ".$Domain" })
    if ($nrpt.Count -gt 0) { Ok ((T 'Regla NRPT para ' 'NRPT rule for ') + ".$Domain") } else { Note ((T 'Sin regla NRPT para ' 'No NRPT rule for ') + $Domain) }
    $dcOk = $false
    try {
        $null = Resolve-DnsName "$DcName.$Domain" -Server $DcAddress -Type A -ErrorAction Stop
        Ok (T 'El DC responde consultas DNS.' 'The DC answers DNS queries.')
        $dcOk = $true
    } catch {
        Bad (T 'El DC no responde consultas DNS.' 'The DC does not answer DNS queries.')
        Todo 'avisar al instructor: el DNS del laboratorio no responde' 'tell the instructor: the lab DNS does not answer'
    }
    Clear-DnsClientCache
    try {
        $null = Resolve-DnsName "$DcName.$Domain" -Type A -ErrorAction Stop
        Ok (T 'Windows resuelve el nombre del DC por su cuenta.' 'Windows resolves the DC name on its own.')
    } catch {
        Bad (T 'Windows no resuelve el nombre del DC.' 'Windows does not resolve the DC name.')
        if ($dcOk) { Note (T 'El DC responde si le preguntas directo, pero Windows no le pregunta. Ejecuta -Prepare.' 'The DC answers when asked directly, but Windows does not ask it. Run -Prepare.') }
        Todo 'desviar el dominio al DC con -Prepare' 'send the domain to the DC with -Prepare'
    }
    try {
        $srv = Resolve-DnsName "_ldap._tcp.dc._msdcs.$Domain" -Type SRV -ErrorAction Stop
        Ok ((T 'Registros SRV localizados: ' 'SRV records found: ') + @($srv).Count)
    } catch {
        Bad (T 'No aparecen los registros SRV del dominio. El archivo hosts no sirve: no publica SRV.' 'Domain SRV records not found. The hosts file is not enough: it does not publish SRV.')
    }
    if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
        try {
            if (Test-ComputerSecureChannel -Server "$DcName.$Domain" -ErrorAction Stop) { Ok (T 'Canal seguro correcto.' 'Secure channel is healthy.') }
            else { Bad (T 'Canal seguro roto.' 'Secure channel is broken.'); Todo 'reparar el canal seguro' 'repair the secure channel' }
        } catch { Warn $_.Exception.Message }
        if ((klist 2>&1 | Out-String) -match 'krbtgt') { Ok (T 'Ticket de Kerberos presente: la sesion es real.' 'Kerberos ticket present: the session is real.') }
        else {
            Warn (T 'Sin ticket de Kerberos: entraste con credenciales en cache y tu trabajo no llega al servidor.' 'No Kerberos ticket: you signed in with cached credentials and your work does not reach the server.')
            Todo 'cerrar sesion y entrar con la red del laboratorio ya activa' 'sign out and sign in again with the lab network already up'
        }
    } else { Note (T 'Todavia no estas en el dominio. Usa -Join -User <tu usuario>.' 'You are not in the domain yet. Use -Join -User <your user>.') }
}

function Set-LabDns {
    Title 'DNS' 'DNS'
    if ($SkipDns) { Note (T 'No se toca el DNS (-SkipDns).' 'DNS left untouched (-SkipDns).'); return }
    $dir = Join-Path $env:ProgramData 'Lab'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if ($DnsByAdapter) {
        foreach ($a in @(Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceAlias -ne 'Tailscale' })) {
            $prev = (Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4).ServerAddresses
            ([ordered]@{ Alias = $a.Name; Index = $a.ifIndex; Previous = @($prev) } | ConvertTo-Json) | Set-Content -LiteralPath (Join-Path $dir "dns-previous-$($a.ifIndex).json") -Encoding UTF8
            Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $DcAddress
            Note "$($a.Name): DNS $DcAddress"
        }
        Ok (T 'DNS de los adaptadores apuntando al laboratorio.' 'Adapter DNS pointing to the lab.')
        Clear-DnsClientCache
        return
    }
    $ns = ".$Domain"
    foreach ($r in @(Get-DnsClientNrptRule -ErrorAction SilentlyContinue | Where-Object { $_.Namespace -contains $ns })) { Remove-DnsClientNrptRule -Name $r.Name -Force -ErrorAction SilentlyContinue }
    Add-DnsClientNrptRule -Namespace $ns -NameServers $DcAddress -Comment 'Lab' -ErrorAction Stop
    Clear-DnsClientCache
    Ok ((T 'Regla NRPT: ' 'NRPT rule: ') + "*$ns " + (T 'se resuelve en ' 'resolves at ') + $DcAddress)
    Note (T 'Tu DNS habitual no cambio: solo el dominio del laboratorio va al DC.' 'Your usual DNS is unchanged: only the lab domain goes to the DC.')
}

function Set-Tunnel {
    if ($Mode -ne 'Tailscale' -or -not (Test-Path -LiteralPath $TS)) { return }
    Title 'Tunel' 'Tunnel'
    $r = & $TS set --unattended=true 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { Ok (T 'Modo desatendido activado: el tunel sube sin sesion.' 'Unattended mode on: the tunnel comes up without a session.') }
    else { Warn ($r.Trim()); Todo 'activar Run unattended desde la bandeja de Tailscale' 'enable Run unattended from the Tailscale tray' }
    $svc = Get-Service | Where-Object { $_.Name -like 'Tailscale*' } | Select-Object -First 1
    if ($svc) {
        Set-Service -Name $svc.Name -StartupType Automatic -ErrorAction SilentlyContinue
        & sc.exe failure $svc.Name reset= 86400 actions= restart/30000/restart/60000/restart/120000 | Out-Null
        Ok ((T 'Servicio ' 'Service ') + $svc.Name + (T ' en arranque automatico.' ' set to automatic start.'))
    }
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'ServicesPipeTimeout' -Value 180000 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
}

function Start-Tunnel {
    if ($Mode -ne 'Tailscale') { return }
    if (Get-TunnelIp) { return }
    $svc = Get-Service | Where-Object { $_.Name -like 'Tailscale*' } | Select-Object -First 1
    if (-not $svc) { return }
    Start-Service -Name $svc.Name -ErrorAction SilentlyContinue
    foreach ($i in 1..24) { Start-Sleep -Seconds 5; if (Get-TunnelIp) { break } }
}

function Set-Boot {
    Title 'Arranque' 'Startup'
    $k = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Winlogon'
    if (-not (Test-Path -LiteralPath $k)) { New-Item -Path $k -Force | Out-Null }
    Set-ItemProperty -Path $k -Name 'SyncForegroundPolicy' -Value 1 -Type DWord
    Ok (T 'Windows esperara a la red antes de pedir credenciales.' 'Windows will wait for the network before asking for credentials.')
}

function Join-Domain {
    Title 'Union al dominio' 'Domain join'
    if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
        Bad ((T 'Ya estas en el dominio ' 'Already in domain ') + (Get-CimInstance Win32_ComputerSystem).Domain)
        Note (T 'Para rehacer la union, sal primero con -Leave.' 'To redo the join, leave first with -Leave.')
        return $false
    }
    $prefix = 'WS-'
    if ($info -and $info.ComputerPrefix) { $prefix = [string]$info.ComputerPrefix }
    $new = $ComputerName
    if (-not $new) { $new = (($prefix + $User).ToUpperInvariant() -replace '[^A-Z0-9\-]', '') }
    if ($new.Length -gt 15) { $new = $new.Substring(0, 15) }
    Flush
    $cred = Get-Credential -UserName "$Domain\$User" -Message (T 'Cuenta del laboratorio' 'Lab account')
    if (-not $cred) { Bad (T 'Sin credenciales no se puede unir.' 'Cannot join without credentials.'); return $false }
    $p = @{ DomainName = $Domain; Credential = $cred; Force = $true; ErrorAction = 'Stop' }
    if ($OUPath) { $p.OUPath = $OUPath }
    if ($env:COMPUTERNAME -ne $new) { $p.NewName = $new }
    try {
        Add-Computer @p
        Ok ((T 'Equipo unido a ' 'Computer joined to ') + $Domain + (T ' como ' ' as ') + $new)
        return $true
    } catch {
        Bad $_.Exception.Message
        Note (T 'Suele ser una contrasena mal escrita, una cuenta que no es de alumno o un equipo con ese nombre ya existente.' 'Usually a mistyped password, an account that is not a student, or a computer with that name already in the domain.')
        Todo 'repetir la union' 'retry the join'
        return $false
    }
}

function Install-Deploy {
    Title 'Despliegue del kit' 'Kit deployment'
    try {
        $script = "\\$DcName.$Domain\$kitShare\module\Deploy-Lab.ps1"
        Unregister-ScheduledTask -TaskName $deployTask -Confirm:$false -ErrorAction SilentlyContinue
        $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`" -Server $DcName.$Domain -Share $kitShare"
        $trg = New-ScheduledTaskTrigger -AtLogOn
        $trg.Delay = 'PT30S'
        $prn = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
        $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 20)
        Register-ScheduledTask -TaskName $deployTask -Action $act -Trigger $trg -Principal $prn -Settings $set -Description (T 'Despliega el kit del laboratorio al iniciar sesion.' 'Deploys the lab kit at sign in.') | Out-Null
        Ok ((T 'Tarea ' 'Task ') + $deployTask + (T ' instalada.' ' installed.'))
    } catch {
        Bad $_.Exception.Message
        Note (T 'La union si se hizo. Avisa al instructor para desplegar el kit a mano.' 'The join did succeed. Ask the instructor to deploy the kit by hand.')
    }
}

function Remove-All {
    Title 'Limpieza del laboratorio' 'Lab cleanup'
    Unregister-ScheduledTask -TaskName $deployTask -Confirm:$false -ErrorAction SilentlyContinue
    if (-not $KeepKit -and $info) {
        foreach ($p in @((Join-Path $env:USERPROFILE ([string]$info.KitDir)), (Join-Path $env:USERPROFILE ([string]$info.Marker)))) {
            if ($p -and (Test-Path -LiteralPath $p)) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue; Ok ((T 'Eliminado: ' 'Removed: ') + $p) }
        }
        $reg = "HKCU:\$($info.RegRoot)"
        if (Test-Path -LiteralPath $reg) { Remove-Item -LiteralPath $reg -Recurse -Force -ErrorAction SilentlyContinue; Ok ((T 'Eliminado: ' 'Removed: ') + $reg) }
        if ($info.HintVar) { Remove-ItemProperty -Path 'HKCU:\Environment' -Name ([string]$info.HintVar) -ErrorAction SilentlyContinue }
        $path = (Get-ItemProperty -Path 'HKCU:\Environment' -Name Path -ErrorAction SilentlyContinue).Path
        if ($path -and $info.KitDir -and $path -match [regex]::Escape([string]$info.KitDir)) {
            Set-ItemProperty -Path 'HKCU:\Environment' -Name Path -Value (($path -split ';' | Where-Object { $_ -and $_ -notmatch [regex]::Escape([string]$info.KitDir) }) -join ';')
            Ok (T 'Carpeta del kit quitada del PATH.' 'Kit folder removed from PATH.')
        }
        if ($info.TaskName) { Unregister-ScheduledTask -TaskName ([string]$info.TaskName) -Confirm:$false -ErrorAction SilentlyContinue }
        $mod = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules\Student'
        if (Test-Path -LiteralPath $mod) { Remove-Item -LiteralPath $mod -Recurse -Force -ErrorAction SilentlyContinue; Ok (T 'Modulo del alumno eliminado.' 'Student module removed.') }
    }
    $ns = ".$Domain"
    foreach ($r in @(Get-DnsClientNrptRule -ErrorAction SilentlyContinue | Where-Object { $_.Namespace -contains $ns })) {
        Remove-DnsClientNrptRule -Name $r.Name -Force -ErrorAction SilentlyContinue
        Ok ((T 'Regla NRPT eliminada para ' 'NRPT rule removed for ') + $Domain)
    }
    $dir = Join-Path $env:ProgramData 'Lab'
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter 'dns-previous-*.json' -ErrorAction SilentlyContinue)) {
        try {
            $g = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json
            if (@($g.Previous).Count -gt 0) { Set-DnsClientServerAddress -InterfaceIndex $g.Index -ServerAddresses @($g.Previous) }
            else { Set-DnsClientServerAddress -InterfaceIndex $g.Index -ResetServerAddresses }
            Remove-Item -LiteralPath $f.FullName -Force
            Ok ((T 'DNS restaurado en ' 'DNS restored on ') + $g.Alias)
        } catch { Warn $_.Exception.Message }
    }
    Clear-DnsClientCache
    Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'SyncForegroundPolicy' -ErrorAction SilentlyContinue
    if ($Mode -eq 'Tailscale' -and (Test-Path -LiteralPath $TS)) {
        $null = & $TS set --unattended=false 2>&1
        if (-not $KeepTailscale) { $null = & $TS logout 2>&1; Ok (T 'Sesion de Tailscale cerrada.' 'Tailscale session closed.') }
    }
    Title 'Salida del dominio' 'Leaving the domain'
    if (-not (Get-CimInstance Win32_ComputerSystem).PartOfDomain) { Note (T 'El equipo no estaba en ningun dominio.' 'The computer was not in any domain.'); return $true }
    Warn (T 'Al salir, tu perfil de dominio deja de poder entrar. Necesitas una cuenta LOCAL de administrador.' 'After leaving, your domain profile can no longer sign in. You need a LOCAL administrator account.')
    Note ((T 'Cuentas locales activas: ' 'Enabled local accounts: ') + ((@(Get-LocalUser | Where-Object { $_.Enabled } | Select-Object -ExpandProperty Name)) -join ', '))
    Flush
    $ans = Read-Host (T 'Sabes la contrasena de alguna? (si/no)' 'Do you know the password of one of them? (yes/no)')
    if ($ans -notmatch $script:Yes) { Bad (T 'Detenido. Habilita antes una cuenta local de administrador.' 'Stopped. Enable a local administrator account first.'); return $false }
    $u = $User
    if (-not $u) { $u = Read-Host (T 'Cuenta del dominio para sacar el equipo' 'Domain account used to remove the computer') }
    $cred = Get-Credential -UserName "$Domain\$u" -Message (T 'Credenciales del dominio' 'Domain credentials')
    if (-not $cred) { return $false }
    try { Remove-Computer -UnjoinDomainCredential $cred -WorkgroupName 'WORKGROUP' -Force -ErrorAction Stop; Ok (T 'Equipo fuera del dominio.' 'Computer removed from the domain.'); return $true }
    catch { Bad $_.Exception.Message; return $false }
}

function Show-Summary {
    param([string]$Next)
    Out-Line ''
    if ($script:Todo.Count -eq 0) {
        Out-Line ('  ' + (T 'TODO CORRECTO' 'ALL GOOD')) 'Green'
        if ($Next) { Out-Line "  $Next" 'White' }
    } else {
        Out-Line ('  ' + (T 'QUEDA POR RESOLVER' 'STILL TO FIX')) 'Yellow'
        $i = 0
        foreach ($p in ($script:Todo | Select-Object -Unique)) { $i++; Out-Line "   $i. $p" 'Yellow' }
    }
    Out-Line ''
    Flush
}

if (-not (Test-IsAdmin)) {
    Write-Host (T 'Ejecutalo en PowerShell como administrador.' 'Run it in PowerShell as administrator.') -ForegroundColor Red
    exit 1
}
Resolve-Settings
if (-not $DcName) { $DcName = 'DC01' }
Out-Line ("  {0}  {1}" -f (T 'Laboratorio de Windows y Active Directory' 'Windows and Active Directory lab'), $PSCmdlet.ParameterSetName) 'Cyan'

switch ($PSCmdlet.ParameterSetName) {
    'Check' {
        [void](Test-Requirements)
        Test-Chain
        Show-Summary (T 'Para dejar el equipo listo: .\Join-Lab.ps1 -Prepare' 'To get the computer ready: .\Join-Lab.ps1 -Prepare')
    }
    'Prepare' {
        Start-Tunnel
        if (-not (Test-Requirements)) { Show-Summary; exit 1 }
        Set-LabDns; Set-Tunnel; Set-Boot; Test-Chain
        Show-Summary (T 'Para unir el equipo: .\Join-Lab.ps1 -Join -User <tu usuario>' 'To join the computer: .\Join-Lab.ps1 -Join -User <your user>')
    }
    'Join' {
        Start-Tunnel
        if (-not (Test-Requirements)) { Show-Summary; exit 1 }
        Set-LabDns; Set-Tunnel; Set-Boot
        try { $null = Resolve-DnsName "_ldap._tcp.dc._msdcs.$Domain" -Type SRV -ErrorAction Stop }
        catch { Bad (T 'El dominio no se localiza: sin registros SRV no se puede unir.' 'The domain cannot be located: no SRV records, no join.'); Todo 'resolver el dominio antes de unir' 'resolve the domain before joining'; Show-Summary; exit 1 }
        if (-not (Join-Domain)) { Show-Summary; exit 1 }
        Install-Deploy
        $web = ''
        if ($info -and $info.WebUrl) { $web = [string]$info.WebUrl }
        Out-Line ''
        Out-Line ('  ' + (T 'Inicia sesion con ' 'Sign in with ') + "$Domain\$User") 'White'
        Out-Line ('  ' + (T 'Espera un minuto despues de entrar: tendras el kit en tu perfil, la unidad H: y los comandos Submit-Flag y Get-Progress.' 'Wait a minute after signing in: you will get the kit in your profile, the H: drive and the Submit-Flag and Get-Progress commands.')) 'Gray'
        if ($web) { Out-Line ('  ' + (T 'Tabla: ' 'Scoreboard: ') + $web) 'Gray' }
        Show-Summary
        if (-not $NoRestart) {
            Write-Host (T '  Reiniciando en 20 segundos. Ctrl+C para cancelar.' '  Restarting in 20 seconds. Ctrl+C to cancel.') -ForegroundColor Yellow
            Start-Sleep -Seconds 20
            Restart-Computer -Force
        }
    }
    'Leave' {
        if (-not (Remove-All)) { Show-Summary; exit 1 }
        Show-Summary (T 'Reinicia e inicia sesion con tu cuenta local.' 'Restart and sign in with your local account.')
        if (-not $NoRestart) {
            $a = Read-Host (T 'Reiniciar ahora? (si/no)' 'Restart now? (yes/no)')
            if ($a -match $script:Yes) { Restart-Computer -Force }
        }
    }
}
