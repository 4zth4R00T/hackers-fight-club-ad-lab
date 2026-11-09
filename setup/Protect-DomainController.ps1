[CmdletBinding()]
param([switch]$NoShow)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Lab.psm1') -DisableNameChecking

if (-not (Test-Administrator)) {
    Write-Host (L 'Ejecuta este script como administrador.' 'Run this script as an administrator.') -ForegroundColor Red
    exit 1
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $c = Get-LabConfig

    $off = @()
    foreach ($svc in @('Spooler', 'XblAuthManager', 'XblGameSave', 'MapsBroker', 'RemoteRegistry')) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) {
            if ($s.Status -eq 'Running') { Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue }
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            $off += $svc
        }
    }
    Write-LabLog (L "Servicios innecesarios deshabilitados: $($off -join ', ')" "Unneeded services disabled: $($off -join ', ')") 'OK'

    $ts = 'HKLM:\System\CurrentControlSet\Control\Terminal Server'
    Set-ItemProperty -Path $ts -Name fDenyTSConnections -Value 0
    Set-ItemProperty -Path "$ts\WinStations\RDP-Tcp" -Name UserAuthentication -Value 1
    Set-ItemProperty -Path "$ts\WinStations\RDP-Tcp" -Name SecurityLayer -Value 2
    Write-LabLog (L 'Escritorio remoto activo con autenticacion a nivel de red obligatoria' 'Remote desktop enabled with mandatory network level authentication') 'OK'

    foreach ($i in @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces' -ErrorAction SilentlyContinue)) {
        Set-ItemProperty -Path $i.PSPath -Name NetbiosOptions -Value 2 -ErrorAction SilentlyContinue
    }
    Write-LabLog (L 'NetBIOS sobre TCP/IP deshabilitado en todos los adaptadores' 'NetBIOS over TCP/IP disabled on every adapter') 'OK'

    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name RunAsPPL -Value 1 -PropertyType DWord -Force | Out-Null
    $wd = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest'
    if (-not (Test-Path $wd)) { New-Item -Path $wd -Force | Out-Null }
    New-ItemProperty -Path $wd -Name UseLogonCredential -Value 0 -PropertyType DWord -Force | Out-Null
    Write-LabLog (L 'LSA protegida y WDigest sin credenciales en claro (efectivo tras el proximo reinicio)' 'LSA protection on and WDigest without cleartext credentials (effective after the next reboot)') 'OK'

    $guest = Get-ADUser -Filter * -SearchBase (Get-ADDomain).UsersContainer | Where-Object { $_.SID.Value -like '*-501' }
    if ($guest) { Disable-ADAccount -Identity $guest; Write-LabLog (L 'Cuenta de invitado del dominio deshabilitada' 'Domain guest account disabled') 'OK' }

    $audit = @(
        '{0CCE9215-69AE-11D9-BED3-505054503030}', '{0CCE9216-69AE-11D9-BED3-505054503030}', '{0CCE9217-69AE-11D9-BED3-505054503030}',
        '{0CCE923F-69AE-11D9-BED3-505054503030}', '{0CCE9242-69AE-11D9-BED3-505054503030}', '{0CCE9240-69AE-11D9-BED3-505054503030}',
        '{0CCE9224-69AE-11D9-BED3-505054503030}', '{0CCE9244-69AE-11D9-BED3-505054503030}', '{0CCE922F-69AE-11D9-BED3-505054503030}',
        '{0CCE9237-69AE-11D9-BED3-505054503030}', '{0CCE9235-69AE-11D9-BED3-505054503030}', '{0CCE923C-69AE-11D9-BED3-505054503030}'
    )
    $ok = 0
    foreach ($g in $audit) {
        $null = & auditpol.exe /set /subcategory:"$g" /success:enable /failure:enable
        if ($LASTEXITCODE -eq 0) { $ok++ }
    }
    Write-LabLog (L "Auditoria avanzada activa en $ok de $($audit.Count) subcategorias (inicios de sesion, Kerberos, recursos compartidos, cuentas y grupos, cambios en el directorio)" "Advanced auditing enabled on $ok of $($audit.Count) subcategories (logons, Kerberos, file shares, accounts and groups, directory changes)") 'OK'
    Write-LabLog (L 'La auditoria de creacion de procesos queda apagada a proposito: es un ejercicio del alumnado' 'Process creation auditing stays off on purpose: it is a student exercise') 'WARN'

    $null = & wevtutil.exe sl Security /ms:536870912
    if ($LASTEXITCODE -eq 0) { Write-LabLog (L 'Registro de seguridad ampliado a 512 MB' 'Security log enlarged to 512 MB') 'OK' }

    Get-ADOrganizationalUnit -Filter * -SearchBase $c.OURoot | Where-Object { $_.DistinguishedName -notlike "*,$($c.OUSandbox)" } |
        ForEach-Object { Set-ADOrganizationalUnit -Identity $_ -ProtectedFromAccidentalDeletion $true }
    Write-LabLog (L 'OUs del laboratorio protegidas contra borrado accidental (las parcelas del alumnado no)' 'Lab OUs protected from accidental deletion (student sandboxes are not)') 'OK'

    foreach ($p in @($c.Paths.Data, $c.Paths.Logs)) {
        New-Folder $p | Out-Null
        Set-SecureAcl -Path $p
    }
    Write-LabLog (L 'Secretos, credenciales y registros solo para SYSTEM y administradores' 'Secrets, credentials and logs restricted to SYSTEM and administrators') 'OK'

    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        if ($mp.RealTimeProtectionEnabled) { Write-LabLog (L 'Microsoft Defender con proteccion en tiempo real activa' 'Microsoft Defender real time protection is on') 'OK' }
        else { Write-LabLog (L 'Microsoft Defender tiene la proteccion en tiempo real apagada; revisala' 'Microsoft Defender real time protection is off; review it') 'WARN' }
    } catch { }

    $da = Get-ADGroupMember -Identity (Get-WellKnownSid 'Domain Admins').Value | ForEach-Object { $_.SamAccountName }
    Write-LabLog (L "Miembros de administradores del dominio: $($da -join ', ')" "Domain admin members: $($da -join ', ')")
    Write-LabLog (L "Los instructores administran por delegacion ($($c.Groups.LabAdmins)), no como administradores del dominio" "Instructors manage through delegation ($($c.Groups.LabAdmins)), not as domain admins")
} catch {
    Write-LabLog $_.Exception.Message 'ERROR'
    if ($NoShow) { throw }
    Show-LabOutput
    exit 1
}
if (-not $NoShow) { Show-LabOutput }
