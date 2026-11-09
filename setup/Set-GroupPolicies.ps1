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
    Import-Module GroupPolicy -ErrorAction Stop
    $c = Get-LabConfig
    $dom = Get-ADDomain
    $root = Split-Path -Parent $PSScriptRoot

    $rdu = Get-WellKnownSid 'Remote Desktop Users'
    Add-ADGroupMember -Identity $rdu.Value -Members $c.Groups.Instructors, $c.Groups.RdpBackup -ErrorAction SilentlyContinue
    Write-LabLog (L "$($c.Groups.Instructors) y $($c.Groups.RdpBackup) pueden entrar por escritorio remoto al controlador" "$($c.Groups.Instructors) and $($c.Groups.RdpBackup) may use remote desktop on the domain controller") 'OK'

    $sidStudents = (Get-ADGroup -Identity $c.Groups.Students).SID.Value
    $sidInstr = (Get-ADGroup -Identity $c.Groups.Instructors).SID.Value
    $sidRdp = (Get-ADGroup -Identity $c.Groups.RdpBackup).SID.Value
    $dcName = '{0} {1}' -f $c.GroupPrefix, (L 'Controlador de dominio' 'Domain controller')
    $dcGpo = Get-LabGpo -Name $dcName -Comment (L 'Quien puede iniciar sesion en el controlador' 'Who may sign in to the domain controller')
    Set-GpoPrivilegeRights -Gpo $dcGpo -Rights @{
        SeDenyInteractiveLogonRight   = @($sidStudents)
        SeRemoteInteractiveLogonRight = @('S-1-5-32-544', $sidInstr, $sidRdp)
    }
    Set-LabGpoLink -Name $dcName -Target $dom.DomainControllersContainer
    Write-LabLog (L "GPO '$dcName': el alumnado no inicia sesion local en el controlador; escritorio remoto solo para administradores, instructores y plazas de respaldo" "GPO '$dcName': students cannot sign in locally to the controller; remote desktop only for administrators, instructors and backup seats") 'OK'

    if ($c.Wallpaper) {
        $netlogon = (Get-SmbShare -Name 'NETLOGON').Path
        $dst = Join-Path $netlogon 'wallpaper'
        New-Folder $dst | Out-Null
        $files = @(
            @{ S = 'client\Set-Wallpaper.ps1';          D = 'Set-Wallpaper.ps1' }
            @{ S = 'assets\wallpaper\base.png';         D = 'base.png' }
            @{ S = 'assets\wallpaper\fallback.png';     D = 'fallback.png' }
            @{ S = 'assets\logo\hfc-logo-256.png';      D = 'logo.png' }
            @{ S = 'assets\fonts\CormorantGaramond-VF.ttf'; D = 'CormorantGaramond-VF.ttf' }
            @{ S = 'assets\fonts\IBMPlexMono-Regular.ttf';  D = 'IBMPlexMono-Regular.ttf' }
            @{ S = 'assets\fonts\IBMPlexMono-Medium.ttf';   D = 'IBMPlexMono-Medium.ttf' }
        )
        foreach ($f in $files) {
            $src = Join-Path $root $f.S
            if (-not (Test-Path -LiteralPath $src)) { throw (L "Falta $($f.S) en el kit" "$($f.S) is missing from the kit") }
            Copy-Item -LiteralPath $src -Destination (Join-Path $dst $f.D) -Force
        }
        $wp = [ordered]@{
            Brand            = [string]$c.LabName
            Domain           = $c.DomainFqdn
            Language         = $c.Language
            Tagline          = (L 'Laboratorio de Active Directory' 'Active Directory lab')
            StudentsGroup    = $c.Groups.Students
            InstructorsGroup = $c.Groups.Instructors
            LabAdminsGroup   = $c.Groups.LabAdmins
            Roles            = [ordered]@{
                Student    = (L 'Alumno' 'Student')
                Instructor = (L 'Instructor' 'Instructor')
                Admin      = (L 'Administrador' 'Administrator')
                User       = (L 'Miembro' 'Member')
            }
        }
        Write-JsonFile -Path (Join-Path $dst 'wallpaper.json') -Object $wp

        $wpName = '{0} {1}' -f $c.GroupPrefix, (L 'Fondo de pantalla' 'Wallpaper')
        $wpGpo = Get-LabGpo -Name $wpName -Comment (L 'Fondo con el nombre de quien inicia sesion' 'Wallpaper with the name of whoever signs in')
        $cmd = 'powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "\\{0}\NETLOGON\wallpaper\Set-Wallpaper.ps1"' -f $dom.DNSRoot
        Set-GPRegistryValue -Guid $wpGpo.Id -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run' -ValueName 'LabWallpaper' -Type String -Value $cmd | Out-Null
        Set-LabGpoLink -Name $wpName -Target $dom.DistinguishedName
        Write-LabLog (L "GPO '$wpName': cada alumno, instructor o administrador ve su nombre en el fondo al iniciar sesion" "GPO '$wpName': every student, instructor or administrator sees their own name on the wallpaper at sign in") 'OK'
    }

    $null = & gpupdate.exe /force
    Write-LabLog (L 'Directivas aplicadas en el controlador' 'Policies applied on the controller') 'OK'
} catch {
    Write-LabLog $_.Exception.Message 'ERROR'
    if ($NoShow) { throw }
    Show-LabOutput
    exit 1
}
if (-not $NoShow) { Show-LabOutput }
