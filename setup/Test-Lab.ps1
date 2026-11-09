[CmdletBinding()]
param([switch]$NoShow)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Lab.psm1') -DisableNameChecking

if (-not (Test-Administrator)) {
    Write-Host (L 'Ejecuta este script como administrador.' 'Run this script as an administrator.') -ForegroundColor Red
    exit 1
}

$script:pass = 0
$script:fail = 0
function Add-Check {
    param([string]$Name, [scriptblock]$Test, [switch]$Soft)
    $ok = $false
    $detail = ''
    try {
        $r = & $Test
        if ($r -is [bool]) { $ok = $r } elseif ($r) { $ok = $true; $detail = [string]$r }
    } catch { $detail = $_.Exception.Message }
    if ($ok) {
        $script:pass++
        Add-LabOutput ('  {0,-6} {1} {2}' -f 'OK', $Name, $detail) 'OK'
    } elseif ($Soft) {
        Add-LabOutput ('  {0,-6} {1} {2}' -f (L 'AVISO' 'WARN'), $Name, $detail) 'WARN'
    } else {
        $script:fail++
        Add-LabOutput ('  {0,-6} {1} {2}' -f (L 'FALLA' 'FAIL'), $Name, $detail) 'ERROR'
    }
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $c = Get-LabConfig
    $dom = Get-ADDomain
    Add-LabOutput ''
    Add-LabOutput ('  HACKERS FIGHT CLUB   {0}   {1}   {2}' -f $c.DomainFqdn, $c.DcName, (Get-Date -Format 'yyyy-MM-dd HH:mm')) 'TITLE'
    Add-LabOutput ''
    Add-LabOutput ('  ' + (L 'Dominio' 'Domain')) 'TITLE'
    Add-Check (L "Controlador del dominio $($c.DomainFqdn)" "Domain controller for $($c.DomainFqdn)") { $dom.DNSRoot -eq $c.DomainFqdn -and $env:COMPUTERNAME -eq $c.DcName }
    foreach ($s in @('NTDS', 'DNS', 'Netlogon', 'Kdc', 'ADWS', 'W32Time')) {
        Add-Check (L "Servicio $s en marcha" "Service $s running") { (Get-Service -Name $s).Status -eq 'Running' }
    }
    Add-Check (L 'DNS resuelve el dominio' 'DNS resolves the domain') { (Resolve-DnsName -Name $c.DomainFqdn -Server 127.0.0.1 -Type A -ErrorAction Stop | ForEach-Object { $_.IPAddress }) -join ', ' }
    Add-Check (L 'Registro SRV de los controladores' 'Domain controller SRV record') { [bool](Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$($c.DomainFqdn)" -Type SRV -Server 127.0.0.1 -ErrorAction Stop) }
    Add-Check (L 'Salida a Internet por los reenviadores' 'Internet resolution through forwarders') { [bool](Resolve-DnsName -Name 'www.microsoft.com' -Server 127.0.0.1 -DnsOnly -ErrorAction Stop) } -Soft

    Add-LabOutput ''
    Add-LabOutput ('  ' + (L 'Directorio' 'Directory')) 'TITLE'
    foreach ($ou in @($c.OURoot, $c.OUStudents, $c.OUInstructors, $c.OUStaff, $c.OUServices, $c.OUWorkstations, $c.OULab, $c.OUSandbox)) {
        Add-Check ("OU " + ($ou -split ',')[0].Substring(3)) { [bool](Get-ADOrganizationalUnit -Identity $ou) }
    }
    foreach ($g in @($c.Groups.Students, $c.Groups.Instructors, $c.Groups.LabAdmins, $c.Groups.SmbReaders, $c.Groups.SmbConfidential, $c.Groups.RdpBackup, $c.Groups.Odd)) {
        Add-Check ((L 'Grupo ' 'Group ') + $g) { [bool](Get-ADGroup -Identity $g) }
    }
    $st = @(Get-ADUser -Filter * -SearchBase $c.OUStudents).Count
    $ins = @(Get-ADGroupMember -Identity $c.Groups.Instructors).Count
    Add-Check (L "Alumnado: $st cuentas" "Students: $st accounts") { $st -gt 0 } -Soft
    Add-Check (L "Instructores: $ins cuentas" "Instructors: $ins accounts") { $ins -gt 0 } -Soft
    Add-Check (L 'Cuota de equipos por usuario en 0' 'Machine account quota is 0') { (Get-ADObject -Identity $dom.DistinguishedName -Properties 'ms-DS-MachineAccountQuota').'ms-DS-MachineAccountQuota' -eq 0 }

    Add-LabOutput ''
    Add-LabOutput ('  ' + (L 'Recursos y directivas' 'Shares and policies')) 'TITLE'
    foreach ($sh in @($c.Shares.Home, $c.Shares.Public, $c.Shares.Dropbox, $c.Shares.Confidential)) {
        Add-Check ("\\$($c.DcName)\$sh") { [bool](Get-SmbShare -Name $sh) }
    }
    try {
        Import-Module GroupPolicy -ErrorAction Stop
        foreach ($gn in @(('{0} {1}' -f $c.GroupPrefix, (L 'Controlador de dominio' 'Domain controller')), ('{0} {1}' -f $c.GroupPrefix, (L 'Fondo de pantalla' 'Wallpaper')))) {
            Add-Check "GPO $gn" { [bool](Get-GPO -Name $gn) } -Soft
        }
    } catch { }
    $nl = (Get-SmbShare -Name 'NETLOGON').Path
    Add-Check (L 'Fondo dinamico publicado en NETLOGON' 'Dynamic wallpaper published in NETLOGON') { Test-Path -LiteralPath (Join-Path $nl 'wallpaper\Set-Wallpaper.ps1') } -Soft

    Add-LabOutput ''
    Add-LabOutput ('  ' + (L "Servicios del laboratorio, modo $($c.NetworkMode)" "Lab services, $($c.NetworkMode) mode")) 'TITLE'
    $addr = Get-ModeAddress
    Add-Check (L "Direccion de servicio: $addr" "Service address: $addr") { [bool]$addr }
    Add-Check (L "Clientes permitidos: $((Get-ClientCidrs) -join ', ')" "Allowed clients: $((Get-ClientCidrs) -join ', ')") { $true }
    $ports = @()
    if ($c.Web) { $ports += @{ N = 'Web'; P = [int]$c.WebPort } }
    if ($c.Challenges) {
        if (Test-Weakness 'InternalHttpIntranet') { $ports += @{ N = 'Intranet'; P = [int]$c.IntranetPort } }
        if (Test-Weakness 'UnexpectedBannerPort') { $ports += @{ N = 'Banner'; P = [int]$c.BannerPort } }
    }
    if ($c.Mail) {
        foreach ($sp in @($c.SmtpPorts)) { $ports += @{ N = 'SMTP'; P = [int]$sp } }
        $ports += @{ N = 'POP3'; P = [int]$c.Pop3Port }
    }
    foreach ($p in $ports) {
        Add-Check ('{0} {1}/tcp' -f $p.N, $p.P) { [bool](Get-NetTCPConnection -State Listen -LocalPort $p.P -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -eq $addr -or $_.LocalAddress -eq '0.0.0.0' }) }
    }
    foreach ($t in @(Get-ScheduledTask -TaskName 'Lab-*' -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -ne 'Lab-Install' })) {
        Add-Check ((L 'Tarea ' 'Task ') + $t.TaskName + ' ' + $t.State) { $t.State -eq 'Running' -or $t.State -eq 'Ready' } -Soft
    }

    Add-LabOutput ''
    Add-LabOutput ('  ' + (L 'Debilidades deliberadas activas' 'Deliberate weaknesses enabled')) 'TITLE'
    $desc = @{
        ServiceAccountsWithSpn = (L 'cuentas de servicio con SPN, objetivo de Kerberoasting' 'service accounts with SPN, a Kerberoasting target')
        DirectoryNotes         = (L 'datos sensibles en Description e info de objetos del directorio' 'sensitive data in Description and info attributes')
        TokenInDnsSuffix       = (L 'secreto repartido en la lista de sufijos DNS por GPO' 'secret distributed in the DNS suffix list by GPO')
        SharedSmbAccount       = (L 'cuenta compartida de SMB cuya clave es ese secreto' 'shared SMB account whose password is that secret')
        InternalHttpIntranet   = (L 'intranet HTTP sin cifrar que revela nombres internos' 'plaintext HTTP intranet that leaks internal names')
        UnexpectedBannerPort   = (L 'servicio inesperado escuchando en el controlador' 'unexpected service listening on the controller')
        PlaintextMail          = (L 'correo interno SMTP y POP3 sin TLS' 'internal SMTP and POP3 mail without TLS')
        DelegatedSandboxOUs    = (L 'control total del alumnado sobre su propia OU' 'students hold full control over their own OU')
        StudentsCreateGpos     = (L 'alumnado en Propietarios del creador de directivas de grupo' 'students in Group Policy Creator Owners')
        HighLockoutThreshold   = (L "bloqueo de cuenta tras $($c.LockoutThreshold) intentos, permite rociado de claves" "account lockout after $($c.LockoutThreshold) attempts, allows password spraying")
    }
    foreach ($k in ($c.Weaknesses.Keys | Sort-Object)) {
        $state = L 'apagada  ' 'disabled '
        if ($c.Weaknesses[$k]) { $state = L 'ACTIVA   ' 'ENABLED  ' }
        Add-LabOutput ('  {0} {1,-24} {2}' -f $state, $k, $desc[$k]) 'TEXT'
    }

    Add-LabOutput ''
    $lvl = 'OK'
    if ($script:fail -gt 0) { $lvl = 'ERROR' }
    Add-LabOutput ('  ' + (L "Comprobaciones correctas: $($script:pass)   Fallidas: $($script:fail)" "Checks passed: $($script:pass)   Failed: $($script:fail)")) $lvl
    Add-LabOutput ''
} catch {
    Write-LabLog $_.Exception.Message 'ERROR'
    if ($NoShow) { throw }
    Show-LabOutput
    exit 1
}
if (-not $NoShow) { Show-LabOutput }
