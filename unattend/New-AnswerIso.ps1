[CmdletBinding()]
param(
    [ValidateSet('en-US', 'es-MX', 'es-ES', 'ru-RU')][string]$Region = 'es-MX',
    [ValidateSet('', 'en-US', 'es-ES', 'ru-RU')][string]$MediaLanguage = '',
    [int]$ImageIndex = 2,
    [ValidateSet('uefi', 'bios')][string]$Firmware = 'uefi',
    [string]$ProductKey = '',
    [string]$TimeZone = '',
    [switch]$AutoStart,
    [switch]$GeneratePassword,
    [string]$OutFile = (Join-Path (Get-Location) 'lab-answers.iso')
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Split-Path -Parent $here
$out = New-Object System.Collections.Generic.List[string]

$profiles = @{
    'en-US' = @{ Ui = 'en-US'; Input = '0409:00000409'; Locale = 'en-US'; Tz = 'Central Standard Time' }
    'es-MX' = @{ Ui = 'es-ES'; Input = '080a:0000080a'; Locale = 'es-MX'; Tz = 'Central Standard Time (Mexico)' }
    'es-ES' = @{ Ui = 'es-ES'; Input = '0c0a:0000040a'; Locale = 'es-ES'; Tz = 'Romance Standard Time' }
    'ru-RU' = @{ Ui = 'ru-RU'; Input = '0409:00000409;0419:00000419'; Locale = 'ru-RU'; Tz = 'Russian Standard Time' }
}
$p = $profiles[$Region]
$ui = $p.Ui
if ($MediaLanguage) { $ui = $MediaLanguage }
$tz = $p.Tz
if ($TimeZone) { $tz = $TimeZone }
$admin = 'Administrador'
if ($ui -eq 'en-US') { $admin = 'Administrator' }
if ($ui -eq 'ru-RU') { $admin = -join ([char[]](0x0410, 0x0434, 0x043C, 0x0438, 0x043D, 0x0438, 0x0441, 0x0442, 0x0440, 0x0430, 0x0442, 0x043E, 0x0440)) }
$layoutFile = Join-Path $here 'disk-uefi.xml'
$part = '3'
if ($Firmware -eq 'bios') { $layoutFile = Join-Path $here 'disk-bios.xml'; $part = '2' }

$cfg = Import-PowerShellDataFile -LiteralPath (Join-Path $repo 'config\lab.config.psd1')
$prefix = 'DC'
if ($cfg.DcHostPrefix) { $prefix = ([string]$cfg.DcHostPrefix).ToUpperInvariant() }
$num = 1
if ($cfg.DcHostNumber) { $num = [int]$cfg.DcHostNumber }
$computer = '{0}{1:D2}' -f $prefix, $num
$org = 'Lab'
if ($cfg.Organization) { $org = [string]$cfg.Organization }
$orgXml = [Security.SecurityElement]::Escape($org)

if ($GeneratePassword) {
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $rng = New-Object Security.Cryptography.RNGCryptoServiceProvider
    $b = New-Object byte[] 16
    $rng.GetBytes($b)
    $plain = (-join ($b | ForEach-Object { $chars[$_ % $chars.Length] })) + '#7q'
    $rng.Dispose()
} else {
    $s1 = Read-Host -AsSecureString 'Contrasena del administrador / Administrator password'
    $s2 = Read-Host -AsSecureString 'Repitela / Repeat it'
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s1))
    $plain2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s2))
    if ($plain -ne $plain2) { throw 'No coinciden / they do not match' }
    if ($plain.Length -lt 12) { throw 'Minimo 12 caracteres / at least 12 characters' }
}
function ConvertTo-UnattendSecret {
    param([string]$Value, [string]$Suffix)
    return [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Value + $Suffix))
}

$keyLine = ''
if ($ProductKey) { $keyLine = "          <Key>$ProductKey</Key>`r`n" }
$xml = [IO.File]::ReadAllText((Join-Path $here 'autounattend.template.xml'))
$map = [ordered]@{
    '{{UI_LANGUAGE}}' = $ui; '{{INPUT_LOCALE}}' = $p.Input; '{{USER_LOCALE}}' = $p.Locale
    '{{DISK_LAYOUT}}' = ([IO.File]::ReadAllText($layoutFile)).TrimEnd("`r", "`n")
    '{{IMAGE_INDEX}}' = [string]$ImageIndex; '{{INSTALL_PARTITION}}' = $part; '{{ORGANIZATION}}' = $orgXml
    '{{PRODUCT_KEY_LINE}}' = $keyLine; '{{COMPUTER_NAME}}' = $computer; '{{TIME_ZONE}}' = $tz
    '{{ADMIN_PASSWORD}}' = (ConvertTo-UnattendSecret $plain 'AdministratorPassword')
    '{{AUTOLOGON_PASSWORD}}' = (ConvertTo-UnattendSecret $plain 'Password'); '{{ADMIN_NAME}}' = $admin
}
foreach ($k in $map.Keys) { $xml = $xml.Replace($k, [string]$map[$k]) }

$work = Join-Path ([IO.Path]::GetTempPath()) ('lab-answers-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $work 'lab') -Force | Out-Null
try {
    [IO.File]::WriteAllText((Join-Path $work 'autounattend.xml'), ($xml -replace "(?<!`r)`n", "`r`n"), (New-Object Text.UTF8Encoding($false)))
    foreach ($d in @('setup', 'engine', 'services', 'web', 'client', 'assets', 'config', 'examples', 'lang')) {
        $src = Join-Path $repo $d
        if (Test-Path -LiteralPath $src) {
            $null = & robocopy.exe $src (Join-Path $work "lab\$d") /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1 /XD node_modules dist dist-astro .astro certs
        }
    }
    Copy-Item -LiteralPath (Join-Path $here 'Start-LabSetup.ps1') -Destination (Join-Path $work 'lab')
    if ($AutoStart) { [IO.File]::WriteAllText((Join-Path $work 'lab\autostart.txt'), "yes`r`n") }

    if (-not ('LabIsoWriter' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices.ComTypes;
public static class LabIsoWriter {
    public static void Write(string path, object stream, int blockSize, int totalBlocks) {
        IStream src = (IStream)stream;
        byte[] buffer = new byte[blockSize];
        using (FileStream dst = File.Create(path)) {
            for (int i = 0; i < totalBlocks; i++) {
                src.Read(buffer, blockSize, IntPtr.Zero);
                dst.Write(buffer, 0, blockSize);
            }
        }
    }
}
'@
    }
    $fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
    $fsi.FileSystemsToCreate = 3
    $fsi.VolumeName = 'LAB_ANSWERS'
    $fsi.Root.AddTree($work, $false)
    $img = $fsi.CreateResultImage()
    if (Test-Path -LiteralPath $OutFile) { Remove-Item -LiteralPath $OutFile -Force }
    [LabIsoWriter]::Write($OutFile, $img.ImageStream, $img.BlockSize, $img.TotalBlocks)
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

$out.Add('')
$out.Add("ISO: $OutFile")
$out.Add("Region: $Region   Medio / media: $ui   Firmware: $Firmware   Indice / index: $ImageIndex")
$out.Add("Equipo / computer: $computer   Zona / time zone: $tz")
$out.Add("Cuenta / account: $admin")
$out.Add("Arranque automatico / autostart: $([bool]$AutoStart)")
if ($GeneratePassword) {
    $cred = [IO.Path]::ChangeExtension($OutFile, '.credentials.txt')
    [IO.File]::WriteAllText($cred, ("Cuenta / account: {0}`r`nContrasena / password: {1}`r`n" -f $admin, $plain))
    $acl = New-Object Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($me, 'FullControl', 'Allow')))
    Set-Acl -LiteralPath $cred -AclObject $acl
    $out.Add("Contrasena guardada en / password saved to: $cred")
}
$plain = $null
$out.Add('')
$out.Add('Adjunta esta ISO como segunda unidad de CD junto al ISO original de Windows Server 2025.')
$out.Add('Attach this ISO as a second CD drive next to the original Windows Server 2025 ISO.')
$out.Add('')
$out | ForEach-Object { Write-Host $_ }
