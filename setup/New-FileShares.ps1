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
    $sidStudents = (Get-ADGroup -Identity $c.Groups.Students).SID
    $sidInstr = (Get-ADGroup -Identity $c.Groups.Instructors).SID
    $sidReaders = (Get-ADGroup -Identity $c.Groups.SmbReaders).SID
    $sidConf = (Get-ADGroup -Identity $c.Groups.SmbConfidential).SID
    $sidAdmins = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
    $sidSystem = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
    $sidOwnerRights = New-Object Security.Principal.SecurityIdentifier('S-1-3-4')

    $ci = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $noInh = [Security.AccessControl.InheritanceFlags]::None
    $oi = [Security.AccessControl.InheritanceFlags]::ObjectInherit
    $none = [Security.AccessControl.PropagationFlags]::None
    $io = [Security.AccessControl.PropagationFlags]::InheritOnly

    function New-BaseAcl {
        $a = New-Object Security.AccessControl.DirectorySecurity
        $a.SetAccessRuleProtection($true, $false)
        $a.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sidSystem, 'FullControl', $ci, $none, 'Allow')))
        $a.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sidAdmins, 'FullControl', $ci, $none, 'Allow')))
        $a.SetOwner($sidAdmins)
        return $a
    }

    function Get-AccountName {
        param([Security.Principal.SecurityIdentifier]$Sid)
        return $Sid.Translate([Security.Principal.NTAccount]).Value
    }

    function Publish-Share {
        param([string]$Name, [string]$Path, [string]$Description, [hashtable[]]$Access)
        if (Get-SmbShare -Name $Name -ErrorAction SilentlyContinue) { Remove-SmbShare -Name $Name -Force }
        New-SmbShare -Name $Name -Path $Path -Description $Description -FullAccess (Get-AccountName $sidAdmins) -FolderEnumerationMode AccessBased | Out-Null
        foreach ($x in $Access) {
            Grant-SmbShareAccess -Name $Name -AccountName (Get-AccountName $x.Sid) -AccessRight $x.Right -Force | Out-Null
        }
        Write-LabLog (L "Recurso publicado: \\$($c.DcName)\$Name" "Share published: \\$($c.DcName)\$Name") 'OK'
    }

    foreach ($p in @($c.Paths.ShareRoot, $c.Paths.Home, $c.Paths.Public, (Join-Path $c.Paths.Public $c.Names.FolderMaterial), (Join-Path $c.Paths.Public $c.Names.FolderTemplates), $c.Paths.Dropbox, $c.Paths.Confidential)) {
        New-Folder $p | Out-Null
    }

    $a = New-BaseAcl
    $a.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sidStudents, 'Traverse, ReadAttributes, Synchronize', $noInh, $none, 'Allow')))
    $a.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sidInstr, 'ReadAndExecute', $ci, $none, 'Allow')))
    Set-Acl -LiteralPath $c.Paths.Home -AclObject $a
    Publish-Share -Name $c.Shares.Home -Path $c.Paths.Home -Description (L 'Carpetas personales del alumnado' 'Student home folders') -Access @(
        @{ Sid = $sidStudents; Right = 'Change' }, @{ Sid = $sidInstr; Right = 'Full' })

    $a = New-BaseAcl
    $a.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sidReaders, 'ReadAndExecute', $ci, $none, 'Allow')))
    $a.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sidInstr, 'Modify', $ci, $none, 'Allow')))
    Set-Acl -LiteralPath $c.Paths.Public -AclObject $a
    Publish-Share -Name $c.Shares.Public -Path $c.Paths.Public -Description (L 'Material del curso' 'Course material') -Access @(
        @{ Sid = $sidReaders; Right = 'Read' }, @{ Sid = $sidInstr; Right = 'Change' })

    $a = New-BaseAcl
    $a.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sidStudents, 'CreateFiles, AppendData, Synchronize', $noInh, $none, 'Allow')))
    $a.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sidStudents, 'WriteData, Synchronize', $oi, $io, 'Allow')))
    $a.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sidOwnerRights, 'WriteData, AppendData, Synchronize', $oi, $io, 'Allow')))
    $a.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sidInstr, 'ReadAndExecute', $ci, $none, 'Allow')))
    Set-Acl -LiteralPath $c.Paths.Dropbox -AclObject $a
    Publish-Share -Name $c.Shares.Dropbox -Path $c.Paths.Dropbox -Description (L 'Buzon de entrega de banderas' 'Flag drop box') -Access @(
        @{ Sid = $sidStudents; Right = 'Change' }, @{ Sid = $sidInstr; Right = 'Full' })
    Write-LabLog (L 'El buzon de banderas es ciego: se puede dejar un archivo, no listarlo ni leerlo' 'The flag drop box is blind: files can be dropped, not listed or read') 'OK'

    $a = New-BaseAcl
    $a.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sidConf, 'ReadAndExecute', $ci, $none, 'Allow')))
    $a.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sidInstr, 'Modify', $ci, $none, 'Allow')))
    Set-Acl -LiteralPath $c.Paths.Confidential -AclObject $a
    Publish-Share -Name $c.Shares.Confidential -Path $c.Paths.Confidential -Description (L 'Documentacion interna de acceso restringido' 'Restricted internal documents') -Access @(
        @{ Sid = $sidConf; Right = 'Read' }, @{ Sid = $sidInstr; Right = 'Change' })

    foreach ($p in @($c.Paths.Data, $c.Paths.Logs)) {
        New-Folder $p | Out-Null
        Set-SecureAcl -Path $p
    }
    Write-LabLog (L 'Datos y registros del laboratorio cerrados a SYSTEM y administradores' 'Lab data and logs restricted to SYSTEM and administrators') 'OK'
} catch {
    Write-LabLog $_.Exception.Message 'ERROR'
    if ($NoShow) { throw }
    Show-LabOutput
    exit 1
}
if (-not $NoShow) { Show-LabOutput }
