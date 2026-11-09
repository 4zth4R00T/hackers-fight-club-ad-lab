[CmdletBinding(DefaultParameterSetName = 'Status')]
param(
    [Parameter(ParameterSetName = 'Start')][switch]$Start,
    [Parameter(ParameterSetName = 'Resume')][switch]$Resume,
    [Parameter(ParameterSetName = 'Status')][switch]$Status,
    [Parameter(ParameterSetName = 'Reset')][switch]$Reset,
    [switch]$NoReboot
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Split-Path -Parent $here
Import-Module (Join-Path $here 'Lab.psm1') -DisableNameChecking

$TaskName = 'Lab-Install'

$Steps = @(
    @{ Id = 'Set-ServerNetwork';        Path = 'setup\Set-ServerNetwork.ps1';        Reboot = $true;  Es = 'Red fija, firewall base y nombre del servidor'; En = 'Static network, base firewall and server name' }
    @{ Id = 'Install-DomainController'; Path = 'setup\Install-DomainController.ps1'; Reboot = $true;  Es = 'Promocion a controlador de dominio';           En = 'Domain controller promotion' }
    @{ Id = 'Set-DomainDns';            Path = 'setup\Set-DomainDns.ps1';            Reboot = $false; Es = 'DNS del dominio y direcciones publicadas';     En = 'Domain DNS and published addresses' }
    @{ Id = 'New-DirectoryStructure';   Path = 'setup\New-DirectoryStructure.ps1';   Reboot = $false; Es = 'Unidades organizativas, grupos y plantilla';   En = 'Organizational units, groups and staff' }
    @{ Id = 'New-FileShares';           Path = 'setup\New-FileShares.ps1';           Reboot = $false; Es = 'Recursos compartidos y permisos';              En = 'File shares and permissions' }
    @{ Id = 'Set-GroupPolicies';        Path = 'setup\Set-GroupPolicies.ps1';        Reboot = $false; Es = 'Directivas de grupo y fondo dinamico';         En = 'Group policies and dynamic wallpaper' }
    @{ Id = 'Protect-DomainController'; Path = 'setup\Protect-DomainController.ps1'; Reboot = $false; Es = 'Blindaje del controlador';                     En = 'Domain controller hardening' }
    @{ Id = 'Initialize-Challenges';    Path = 'engine\Initialize-Challenges.ps1';   Reboot = $false; Es = 'Retos, banderas y siembra';                    En = 'Challenges, flags and seeding'; When = 'Challenges' }
    @{ Id = 'Add-Administrators';       Path = 'setup\Add-Administrators.ps1';       Reboot = $false; Es = 'Instructores desde config\admins.csv';         En = 'Instructors from config\admins.csv'; Csv = @('admins.csv', 'administrators.csv') }
    @{ Id = 'Add-Students';             Path = 'setup\Add-Students.ps1';             Reboot = $false; Es = 'Alumnado desde config\alumnos.csv';            En = 'Students from config\students.csv'; Csv = @('alumnos.csv', 'students.csv') }
    @{ Id = 'Register-Services';        Path = 'services\Register-Services.ps1';     Reboot = $false; Es = 'Servicios del laboratorio';                    En = 'Lab services' }
    @{ Id = 'Install-Web';              Path = 'web\Install-Web.ps1';                Reboot = $false; Es = 'Web del laboratorio';                          En = 'Lab website'; When = 'Web' }
    @{ Id = 'Test-Lab';                 Path = 'setup\Test-Lab.ps1';                 Reboot = $false; Es = 'Verificacion final';                           En = 'Final verification' }
)

function Get-State {
    $c = Get-LabConfig
    $s = Read-JsonFile -Path $c.Paths.State
    if (-not $s) { $s = [pscustomobject]@{ Done = @(); Started = $null; LastError = $null; Finished = $null } }
    return $s
}

function Save-State {
    param($S)
    Write-JsonFile -Path (Get-LabConfig).Paths.State -Object $S
}

function Copy-LabTree {
    $c = Get-LabConfig
    $src = (Resolve-Path $repo).Path.TrimEnd('\')
    $dst = $c.Paths.Root.TrimEnd('\')
    if ($src -ieq $dst) { return $false }
    New-Folder $dst | Out-Null
    foreach ($d in @('setup', 'engine', 'services', 'web', 'client', 'assets', 'config', 'examples', 'lang')) {
        $s = Join-Path $src $d
        if (-not (Test-Path -LiteralPath $s)) { continue }
        $null = & robocopy.exe $s (Join-Path $dst $d) /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1 /XD node_modules dist dist-astro .astro
    }
    Write-LabLog (L "Kit copiado de $src a $dst" "Kit copied from $src to $dst") 'OK'
    return $true
}

function Get-StepCsv {
    param($St)
    $c = Get-LabConfig
    foreach ($n in @($St.Csv)) {
        $p = Join-Path $c.Paths.Config $n
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Test-StepApplies {
    param($St)
    $c = Get-LabConfig
    if ($St.When -and -not $c[$St.When]) { return $false }
    if ($St.Csv -and -not (Get-StepCsv $St)) { return $false }
    return $true
}

function Show-Status {
    $s = Get-State
    $c = Get-LabConfig
    Add-LabOutput ''
    Add-LabOutput ('  HACKERS FIGHT CLUB   {0}   {1}   {2}' -f $c.DomainFqdn, $c.DcName, $c.NetworkMode) 'TITLE'
    Add-LabOutput ''
    $nextShown = $false
    foreach ($st in $Steps) {
        $mark = L 'pendiente ' 'pending   '
        $lvl = 'TEXT'
        if (@($s.Done) -contains $st.Id) { $mark = L 'listo     ' 'done      '; $lvl = 'OK' }
        elseif (-not (Test-StepApplies $st)) { $mark = L 'no aplica ' 'skipped   ' }
        elseif (-not $nextShown) { $mark = L 'siguiente ' 'next      '; $lvl = 'WARN'; $nextShown = $true }
        Add-LabOutput ('  {0}  {1,-26} {2}' -f $mark, $st.Id, (L $st.Es $st.En)) $lvl
    }
    if ($s.LastError) { Add-LabOutput ''; Add-LabOutput ('  ' + (L 'Ultimo error: ' 'Last error: ') + $s.LastError) 'ERROR' }
    if ($s.Finished) { Add-LabOutput ''; Add-LabOutput ('  ' + (L "Terminado el $($s.Finished)" "Finished on $($s.Finished)")) 'OK' }
    Add-LabOutput ''
}

function Wait-DirectoryReady {
    $end = (Get-Date).AddMinutes(15)
    while ((Get-Date) -lt $end) {
        try {
            Import-Module ActiveDirectory -ErrorAction Stop
            $null = Get-ADDomain -ErrorAction Stop
            return $true
        } catch { Start-Sleep -Seconds 15 }
    }
    return $false
}

function Write-Report {
    $c = Get-LabConfig
    New-Folder $c.Paths.Logs | Out-Null
    [IO.File]::WriteAllText((Join-Path $c.Paths.Logs 'install-report.txt'), (Get-LabOutputText), (New-Object Text.UTF8Encoding($false)))
}

if (-not (Test-Administrator)) {
    Write-Host (L 'Ejecuta este script como administrador.' 'Run this script as an administrator.') -ForegroundColor Red
    exit 1
}

$cfg = Get-LabConfig

if ($Reset) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false }
    if (Test-Path -LiteralPath $cfg.Paths.State) { Remove-Item -LiteralPath $cfg.Paths.State -Force }
    Write-LabLog (L 'Progreso reiniciado. No se toco nada del dominio.' 'Progress reset. Nothing in the domain was touched.') 'OK'
    Show-LabOutput
    exit 0
}

if ($PSCmdlet.ParameterSetName -eq 'Status') {
    Show-Status
    Show-LabOutput
    exit 0
}

if ($Start) {
    if (Copy-LabTree) {
        Show-LabOutput
        $argsList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $cfg.Paths.Setup 'Install-Lab.ps1'), '-Start')
        if ($NoReboot) { $argsList += '-NoReboot' }
        & (Get-PowerShellPath) @argsList
        exit $LASTEXITCODE
    }
    Save-State ([pscustomobject]@{ Done = @(); Started = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); LastError = $null; Finished = $null })
    Write-LabLog (L "Instalacion de $($cfg.DomainFqdn) en modo $($cfg.NetworkMode)" "Installing $($cfg.DomainFqdn) in $($cfg.NetworkMode) mode") 'STAGE'
}

$state = Get-State
$domainReady = $false
foreach ($st in $Steps) {
    if (@($state.Done) -contains $st.Id) { continue }
    if (-not (Test-StepApplies $st)) { continue }
    $file = Join-Path $cfg.Paths.Root $st.Path
    if (-not (Test-Path -LiteralPath $file)) { $file = Join-Path $repo $st.Path }
    if ($st.Id -ne 'Set-ServerNetwork' -and $st.Id -ne 'Install-DomainController' -and -not $domainReady) {
        if (-not (Wait-DirectoryReady)) {
            $state.LastError = L 'Active Directory no respondio en 15 minutos' 'Active Directory did not answer within 15 minutes'
            Save-State $state
            Write-LabLog $state.LastError 'ERROR'
            Write-Report
            Show-LabOutput
            exit 1
        }
        $domainReady = $true
    }
    Write-LabLog ('{0}  {1}' -f $st.Id, (L $st.Es $st.En)) 'STAGE'
    try {
        if ($st.Csv) { & $file -Path (Get-StepCsv $st) -NoShow }
        else { & $file -NoShow }
    } catch {
        $state.LastError = ('{0}: {1}' -f $st.Id, $_.Exception.Message)
        Save-State $state
        Write-LabLog $state.LastError 'ERROR'
        Write-LabLog (L "Corrige la causa y ejecuta Install-Lab.ps1 -Resume, o sigue a mano desde $($st.Id).ps1" "Fix the cause and run Install-Lab.ps1 -Resume, or continue by hand from $($st.Id).ps1") 'WARN'
        Write-Report
        Show-LabOutput
        exit 1
    }
    $state.Done = @(@($state.Done) + $st.Id)
    $state.LastError = $null
    Save-State $state

    if ($st.Reboot) {
        Register-LabTask -Name $TaskName -Execute (Get-PowerShellPath) `
            -Arguments (Get-ScriptArguments -Script (Join-Path $cfg.Paths.Setup 'Install-Lab.ps1') -Extra '-Resume') -AtStartup `
            -Description (L 'Continua la instalacion del laboratorio tras reiniciar' 'Resumes the lab installation after a reboot')
        Write-Report
        if ($NoReboot) {
            Write-LabLog (L 'Reinicia el servidor; la instalacion seguira sola.' 'Reboot the server; the installation resumes by itself.') 'WARN'
            Show-LabOutput
            exit 0
        }
        Write-LabLog (L 'Reiniciando; la instalacion seguira sola.' 'Rebooting; the installation resumes by itself.') 'WARN'
        Show-LabOutput
        Start-Sleep -Seconds 5
        Restart-Computer -Force
        exit 0
    }
}

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false }
$state.Finished = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Save-State $state
Write-LabLog (L 'Instalacion completa.' 'Installation complete.') 'OK'
Show-Status
Write-Report
Show-LabOutput
exit 0
