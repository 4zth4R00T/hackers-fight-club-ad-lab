[CmdletBinding()]
param([switch]$NoShow)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Lab.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'LabAdmin.psm1') -DisableNameChecking

if (-not (Test-Administrator)) {
    Write-Host (L 'Ejecuta este script como administrador.' 'Run this script as an administrator.') -ForegroundColor Red
    exit 1
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $c = Get-LabConfig
    $n = $c.Names
    $dom = Get-ADDomain

    $rb = Get-ADOptionalFeature -Filter "Name -like 'Recycle Bin*'"
    if ($rb -and -not $rb.EnabledScopes) {
        Enable-ADOptionalFeature -Identity $rb -Scope ForestOrConfigurationSet -Target $dom.Forest -Confirm:$false
        Write-LabLog (L 'Papelera de reciclaje de AD activada' 'AD Recycle Bin enabled') 'OK'
    }

    $lock = 5
    if (Test-Weakness 'HighLockoutThreshold') { $lock = [int]$c.LockoutThreshold }
    Set-ADDefaultDomainPasswordPolicy -Identity $dom.DNSRoot -MinPasswordLength ([int]$c.MinPasswordLength) -ComplexityEnabled $true `
        -LockoutThreshold $lock -LockoutDuration '00:15:00' -LockoutObservationWindow '00:15:00' `
        -MaxPasswordAge '0.00:00:00' -MinPasswordAge '0.00:00:00' -PasswordHistoryCount 5
    Write-LabLog (L "Politica de contrasenas: minimo $($c.MinPasswordLength), bloqueo tras $lock intentos" "Password policy: minimum $($c.MinPasswordLength), lockout after $lock attempts") 'OK'

    Set-ADDomain -Identity $dom.DistinguishedName -Replace @{ 'ms-DS-MachineAccountQuota' = 0 }
    Write-LabLog (L 'Cuota de equipos por usuario en 0: solo se une donde hay delegacion' 'Machine account quota set to 0: joins only where delegated') 'OK'

    $null = New-OrganizationalUnit -Name $c.GroupPrefix -Path $c.DomainDN -Description $c.LabName
    $ous = @(
        @{ N = $n.OUStaff;        P = $c.OURoot;      D = (L 'Plantilla ficticia de la empresa' 'Fictional company staff') }
        @{ N = $n.OUStudents;     P = $c.OURoot;      D = (L 'Cuentas del alumnado' 'Student accounts') }
        @{ N = $n.OUInstructors;  P = $c.OURoot;      D = (L 'Cuentas de instructores' 'Instructor accounts') }
        @{ N = $n.OUServices;     P = $c.OURoot;      D = (L 'Cuentas de servicio' 'Service accounts') }
        @{ N = $n.OUGroups;       P = $c.OURoot;      D = (L 'Grupos del laboratorio' 'Lab groups') }
        @{ N = $n.OUComputers;    P = $c.OURoot;      D = (L 'Equipos' 'Computers') }
        @{ N = $n.OUServers;      P = $c.OUComputers; D = (L 'Servidores' 'Servers') }
        @{ N = $n.OUWorkstations; P = $c.OUComputers; D = (L 'Estaciones del alumnado' 'Student workstations') }
        @{ N = $n.OULab;          P = $c.OURoot;      D = (L 'Objetos del laboratorio' 'Lab objects') }
        @{ N = $n.OUSandbox;      P = $c.OURoot;      D = (L 'Parcelas de practica de cada alumno' 'Per student practice areas') }
    )
    $made = 0
    foreach ($o in $ous) { if (New-OrganizationalUnit -Name $o.N -Path $o.P -Description $o.D) { $made++ } }
    foreach ($d in $c.Departments) { if (New-OrganizationalUnit -Name $d.Name -Path $c.OUStaff -Description $d.Desc) { $made++ } }
    Write-LabLog (L "Unidades organizativas listas ($made nuevas)" "Organizational units ready ($made new)") 'OK'

    $groups = @(
        @{ N = $c.Groups.Students;        D = (L 'Alumnado del laboratorio' 'Lab students') }
        @{ N = $c.Groups.Instructors;     D = (L 'Instructores' 'Instructors') }
        @{ N = $c.Groups.LabAdmins;       D = (L 'Administran el laboratorio por delegacion' 'Manage the lab through delegation') }
        @{ N = $c.Groups.SmbReaders;      D = (L 'Lectura del material publico' 'Read access to public material') }
        @{ N = $c.Groups.SmbConfidential; D = (L 'Acceso al recurso confidencial' 'Access to the confidential share') }
        @{ N = $c.Groups.RdpBackup;       D = (L 'Plazas de escritorio remoto de respaldo, se conceden una a una' 'Backup remote desktop seats, granted one by one') }
    )
    foreach ($g in $groups) { $null = New-SecurityGroup -Name $g.N -Path $c.OUGroups -Description $g.D }
    foreach ($d in $c.Departments) { $null = New-SecurityGroup -Name $d.Group -Path $c.OUGroups -Description $d.Desc }
    $null = New-SecurityGroup -Name $c.Groups.Odd -Path $c.OULab -Description (L 'Grupo sin departamento' 'Group with no department')
    Add-ADGroupMember -Identity $c.Groups.LabAdmins -Members $c.Groups.Instructors -ErrorAction SilentlyContinue
    Write-LabLog (L 'Grupos del laboratorio listos' 'Lab groups ready') 'OK'

    $labAdmins = Get-ADGroup -Identity $c.Groups.LabAdmins
    Grant-DirectoryRight -TargetDN $c.OURoot -Sid $labAdmins.SID -Right GenericAll
    Grant-ComputerJoinRight -TargetDN $c.OUWorkstations -Sid (Get-ADGroup -Identity $c.Groups.Students).SID
    Grant-ComputerJoinRight -TargetDN $c.OUWorkstations -Sid $labAdmins.SID -Full
    Write-LabLog (L "Delegacion: $($c.Groups.LabAdmins) administra la OU $($c.GroupPrefix); el alumnado solo une equipos en $($n.OUWorkstations)" "Delegation: $($c.Groups.LabAdmins) manages the $($c.GroupPrefix) OU; students may only join computers in $($n.OUWorkstations)") 'OK'

    $staffCsv = Join-Path $c.Paths.Config 'staff.csv'
    if (-not (Test-Path -LiteralPath $staffCsv)) { $staffCsv = Join-Path (Split-Path -Parent $setup) 'config\staff.csv' }
    $staff = @()
    if (Test-Path -LiteralPath $staffCsv) { $staff = Import-CsvFile -Path $staffCsv }
    $newStaff = 0
    foreach ($row in $staff) {
        $first = Get-CsvValue $row @('nombre', 'firstname', 'first', 'imia')
        $last = Get-CsvValue $row @('apellidos', 'apellido', 'lastname', 'last', 'familiia')
        $key = (Get-CsvValue $row @('departamento', 'department', 'dept', 'otdel')).ToUpperInvariant()
        if ($c.Language -eq 'es') { $title = Get-CsvValue $row @('puesto', 'cargo', 'title') }
        elseif ($c.Language -eq 'ru') { $title = Get-CsvValue $row @('dolzhnost', 'title') }
        else { $title = Get-CsvValue $row @('title', 'puesto', 'cargo') }
        if (-not $first -or -not $last) { continue }
        $dept = $null
        if ($key -match '^\d+$' -and [int]$key -ge 1 -and [int]$key -le $c.Departments.Count) { $dept = $c.Departments[[int]$key - 1] }
        if (-not $dept) { $dept = $c.Departments | Where-Object { $_.Key -eq $key -or $_.Name -eq $key } | Select-Object -First 1 }
        if (-not $dept) { $dept = $c.Departments[0] }
        $sam = Get-CsvValue $row @('usuario', 'username', 'sam', 'polzovatel', 'login')
        if (-not $sam) { $sam = New-SamName -First $first -Last $last }
        if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) { continue }
        $pw = New-RandomPassword -Length 18
        $display = "$first $last"
        New-ADUser -Name $display -SamAccountName $sam -UserPrincipalName "$sam@$($c.DomainFqdn)" -EmailAddress "$sam@$($c.DomainFqdn)" `
            -GivenName $first -Surname $last -DisplayName $display -Title $title -Department $dept.Name -Company $c.Organization `
            -Path $dept.OU -AccountPassword (ConvertTo-SecureString $pw -AsPlainText -Force) -Enabled $true | Out-Null
        Add-ADGroupMember -Identity $dept.Group -Members $sam
        Add-LabCredential -Kind 'staff' -Account $sam -Password $pw -Note $dept.Name
        $newStaff++
    }
    Write-LabLog (L "Plantilla ficticia: $newStaff cuentas nuevas" "Fictional staff: $newStaff new accounts") 'OK'

    $services = @(
        @{ Sam = 'svc-sql';    Spn = "MSSQLSvc/sql.$($c.DomainFqdn):1433"; D = (L 'Servicio de base de datos' 'Database service') }
        @{ Sam = 'svc-web';    Spn = "HTTP/intranet.$($c.DomainFqdn)";     D = (L 'Servicio de la intranet' 'Intranet service') }
        @{ Sam = 'svc-backup'; Spn = $null;                                 D = (L 'Respaldos nocturnos' 'Nightly backups') }
    )
    foreach ($s in $services) {
        $u = Get-ADUser -Filter "SamAccountName -eq '$($s.Sam)'" -ErrorAction SilentlyContinue
        if (-not $u) {
            $pw = New-RandomPassword -Length 28
            New-ADUser -Name $s.Sam -SamAccountName $s.Sam -UserPrincipalName "$($s.Sam)@$($c.DomainFqdn)" -Description $s.D `
                -Path $c.OUServices -AccountPassword (ConvertTo-SecureString $pw -AsPlainText -Force) -Enabled $true `
                -PasswordNeverExpires $true -CannotChangePassword $true | Out-Null
            Add-LabCredential -Kind 'service' -Account $s.Sam -Password $pw -Note $s.D
        }
        if ($s.Spn -and (Test-Weakness 'ServiceAccountsWithSpn')) {
            Set-ADUser -Identity $s.Sam -ServicePrincipalNames @{ Replace = $s.Spn }
        }
    }
    if (Test-Weakness 'ServiceAccountsWithSpn') {
        Write-LabLog (L 'Cuentas de servicio con SPN creadas a proposito (enumeracion y Kerberoasting); sus claves son largas y aleatorias' 'Service accounts with SPN created on purpose (enumeration and Kerberoasting); their passwords are long and random') 'WARN'
    }

    $computers = @()
    for ($i = 1; $i -le 8; $i++) { $computers += @{ N = ('WS{0:D2}' -f $i); P = $c.OUWorkstations; Os = 'Windows 11 Enterprise' } }
    $computers += @{ N = 'SQL01'; P = $c.OUServers; Os = 'Windows Server 2022 Standard' }
    $computers += @{ N = 'WEB01'; P = $c.OUServers; Os = 'Windows Server 2022 Standard' }
    foreach ($pc in $computers) {
        if (-not (Get-ADComputer -Filter "Name -eq '$($pc.N)'" -ErrorAction SilentlyContinue)) {
            New-ADComputer -Name $pc.N -SamAccountName $pc.N -Path $pc.P -OperatingSystem $pc.Os -Enabled $false `
                -Description (L 'Inventario de la empresa' 'Company inventory') | Out-Null
        }
    }
    Write-LabLog (L "Inventario de equipos ficticio: $($computers.Count) objetos" "Fictional computer inventory: $($computers.Count) objects") 'OK'
} catch {
    Write-LabLog $_.Exception.Message 'ERROR'
    if ($NoShow) { throw }
    Show-LabOutput
    exit 1
}
if (-not $NoShow) { Show-LabOutput }
