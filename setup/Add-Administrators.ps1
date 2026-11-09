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

$rows = Import-CsvFile -Path $Path
Add-LabOutput ''
Add-LabOutput ('  ' + (L "Alta de administradores desde $Path" "Administrator enrollment from $Path")) 'TITLE'
Add-LabOutput ''

$created = New-Object System.Collections.Generic.List[object]
$updated = 0
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
    $roleText = (ConvertTo-Ascii (Get-CsvValue $r @('rol', 'role'))).ToLowerInvariant()
    $role = 'instructor'
    if (@('admin', 'administrador', 'administrator', 'domainadmin', 'dominio', 'domain', 'administrator domena') -contains $roleText) { $role = 'domainadmin' }
    if ($pw -and $pw.Length -lt [int]$c.MinPasswordLength) { $pw = '' }
    try {
        $res = Set-Administrator -First $first -Last $last -Sam $sam -Mail $mail -Password $pw -Role $role
    } catch {
        Write-LabLog (L "Linea ${line}: $($_.Exception.Message)" "Line ${line}: $($_.Exception.Message)") 'ERROR'
        $failed++
        continue
    }
    $roleLabel = L 'instructor delegado' 'delegated instructor'
    if ($role -eq 'domainadmin') { $roleLabel = L 'administrador del dominio' 'domain administrator' }
    if ($res.Created) {
        Add-LabCredential -Kind $role -Account $res.Sam -Password $res.Password
        $created.Add([pscustomobject]@{ Usuario = $res.Sam; Rol = $role; UPN = "$($res.Sam)@$($c.DomainFqdn)"; Password = $res.Password })
        Write-LabLog (L "Creado $($res.Sam) como $roleLabel" "Created $($res.Sam) as $roleLabel") 'OK'
    } else {
        $updated++
        Write-LabLog (L "$($res.Sam) ya existia; grupos revisados como $roleLabel" "$($res.Sam) already existed; groups checked as $roleLabel")
    }
}

if ($created.Count -gt 0) {
    if (-not $OutFile) { $OutFile = Join-Path $c.Paths.Data ('admins-{0}.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss')) }
    New-Folder (Split-Path -Parent $OutFile) | Out-Null
    $created | Export-Csv -LiteralPath $OutFile -NoTypeInformation -Encoding UTF8
    Set-SecureAcl -Path $OutFile
}

Add-LabOutput ''
Add-LabOutput ('  ' + (L "Creados: $($created.Count)   Revisados: $updated   Con error: $failed" "Created: $($created.Count)   Checked: $updated   Failed: $failed")) 'TITLE'
if ($created.Count -gt 0) { Add-LabOutput ('  ' + (L "Credenciales: $OutFile" "Credentials: $OutFile")) 'OK' }
Add-LabOutput ('  ' + (L "Los instructores administran la OU $($c.GroupPrefix) por delegacion y entran por RDP; no son administradores del dominio salvo con rol admin." "Instructors manage the $($c.GroupPrefix) OU through delegation and may use RDP; they are not domain administrators unless their role is admin.")) 'TEXT'
Add-LabOutput ''
if (-not $NoShow) { Show-LabOutput }
