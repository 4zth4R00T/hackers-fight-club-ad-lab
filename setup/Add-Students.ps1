[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [string]$OutFile,
    [switch]$NoShow
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here 'Lab.psm1') -DisableNameChecking
Import-Module (Join-Path $here 'LabAdmin.psm1') -DisableNameChecking

if (-not (Test-Administrator)) {
    Write-Host (L 'Ejecuta este script como administrador en el controlador de dominio.' 'Run this script as an administrator on the domain controller.') -ForegroundColor Red
    exit 1
}
Import-Module ActiveDirectory -ErrorAction Stop
$c = Get-LabConfig

$engine = $null
if ($c.Challenges) {
    $em = Join-Path $c.Paths.Engine 'Challenges.psm1'
    if (-not (Test-Path -LiteralPath $em)) { $em = Join-Path (Split-Path -Parent $here) 'engine\Challenges.psm1' }
    if (Test-Path -LiteralPath $em) { Import-Module $em -DisableNameChecking; $engine = $em }
}

$rows = Import-CsvFile -Path $Path
Add-LabOutput ''
Add-LabOutput ('  ' + (L "Alta de alumnado desde $Path" "Student enrollment from $Path")) 'TITLE'
Add-LabOutput ''

$created = New-Object System.Collections.Generic.List[object]
$skipped = 0
$failed = 0
$line = 1
foreach ($r in $rows) {
    $line++
    $first = Get-CsvValue $r @('nombre', 'nombres', 'firstname', 'first', 'givenname', 'imia')
    $last = Get-CsvValue $r @('apellidos', 'apellido', 'lastname', 'last', 'surname', 'familiia')
    if (-not $first -or -not $last) {
        Write-LabLog (L "Linea ${line}: falta nombre o apellidos, se omite" "Line ${line}: missing first or last name, skipped") 'WARN'
        $failed++
        continue
    }
    $sam = Get-CsvValue $r @('usuario', 'username', 'user', 'sam', 'samaccountname', 'polzovatel', 'login', 'imia polzovatelia')
    $mail = Get-CsvValue $r @('correo', 'email', 'mail', 'pochta', 'elektronnaia pochta')
    $pw = Get-CsvValue $r @('contrasena', 'password', 'clave', 'parol')
    $grp = Get-CsvValue $r @('grupo', 'group', 'gruppa')
    if ($pw -and $pw.Length -lt [int]$c.MinPasswordLength) {
        Write-LabLog (L "Linea ${line}: la contrasena no cumple el minimo de $($c.MinPasswordLength); se genera una aleatoria" "Line ${line}: the password is shorter than $($c.MinPasswordLength); a random one is generated") 'WARN'
        $pw = ''
    }
    try {
        $res = New-StudentAccount -First $first -Last $last -Sam $sam -Mail $mail -Password $pw -ExtraGroups @($grp)
    } catch {
        Write-LabLog (L "Linea ${line}: $($_.Exception.Message)" "Line ${line}: $($_.Exception.Message)") 'ERROR'
        $failed++
        continue
    }
    if (-not $res.Created) {
        Write-LabLog (L "$($res.Sam) ya existia, no se toca" "$($res.Sam) already existed, left as is")
        $skipped++
        continue
    }
    Add-LabCredential -Kind 'student' -Account $res.Sam -Password $res.Password -Note $res.Slot
    if ($engine) {
        try { Initialize-Student -Sam $res.Sam | Out-Null }
        catch { Write-LabLog (L "$($res.Sam): el kit de retos fallo: $($_.Exception.Message)" "$($res.Sam): the challenge kit failed: $($_.Exception.Message)") 'WARN' }
    }
    $created.Add([pscustomobject]@{
        Slot     = $res.Slot
        Usuario  = $res.Sam
        Nombre   = $res.Display
        Correo   = $res.Mail
        UPN      = "$($res.Sam)@$($c.DomainFqdn)"
        Password = $res.Password
        Home     = ("\\{0}\{1}\{2}" -f $c.DcName, $c.Shares.Home, $res.Slot)
    })
    Write-LabLog (L "Alumno creado: $($res.Sam) ($($res.Slot))" "Student created: $($res.Sam) ($($res.Slot))") 'OK'
}

if ($created.Count -gt 0) {
    if (-not $OutFile) { $OutFile = Join-Path $c.Paths.Data ('students-{0}.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss')) }
    New-Folder (Split-Path -Parent $OutFile) | Out-Null
    $created | Export-Csv -LiteralPath $OutFile -NoTypeInformation -Encoding UTF8
    Set-SecureAcl -Path $OutFile
}

Add-LabOutput ''
Add-LabOutput ('  ' + (L "Creados: $($created.Count)   Ya existian: $skipped   Con error: $failed" "Created: $($created.Count)   Already existed: $skipped   Failed: $failed")) 'TITLE'
if ($created.Count -gt 0) {
    Add-LabOutput ('  ' + (L "Credenciales para repartir: $OutFile" "Credentials to hand out: $OutFile")) 'OK'
    Add-LabOutput ('  ' + (L 'Ese archivo solo lo leen SYSTEM y los administradores. Borralo cuando hayas repartido las claves.' 'Only SYSTEM and administrators can read that file. Delete it once the passwords are handed out.')) 'WARN'
}
Add-LabOutput ''
if (-not $NoShow) { Show-LabOutput }
