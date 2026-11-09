[CmdletBinding()]
param(
    [string]$OutFile,
    [string]$UserName,
    [string]$DisplayName,
    [string]$Role,
    [int]$Width = 0,
    [int]$Height = 0,
    [switch]$NoApply
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$workDir = Join-Path $env:LOCALAPPDATA 'LabWallpaper'
if (-not (Test-Path -LiteralPath $workDir)) { New-Item -ItemType Directory -Path $workDir -Force | Out-Null }
$logFile = Join-Path $workDir 'wallpaper.log'

function Write-Note {
    param([string]$Text)
    try { Add-Content -LiteralPath $logFile -Value ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Text) } catch { }
}

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class LabDesktop {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SystemParametersInfo(int action, int param, string value, int flags);
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
'@

$cfg = $null
$cfgPath = Join-Path $here 'wallpaper.json'
if (Test-Path -LiteralPath $cfgPath) {
    try { $cfg = [IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json } catch { Write-Note "wallpaper.json: $($_.Exception.Message)" }
}
if (-not $cfg) {
    $cfg = [pscustomobject]@{
        Brand = 'Hackers Fight Club'; Domain = $env:USERDNSDOMAIN; Language = 'en'
        Tagline = 'Active Directory lab'; StudentsGroup = ''; InstructorsGroup = ''; LabAdminsGroup = ''
        Roles = [pscustomobject]@{ Student = 'Student'; Instructor = 'Instructor'; Admin = 'Administrator'; User = 'Member' }
    }
}

function Get-Account {
    $sam = $env:USERNAME
    $name = $sam
    $groups = @()
    try {
        $s = New-Object DirectoryServices.DirectorySearcher
        $s.Filter = "(&(objectCategory=person)(sAMAccountName=$sam))"
        $s.PropertiesToLoad.AddRange(@('displayName', 'memberOf'))
        $r = $s.FindOne()
        if ($r) {
            if ($r.Properties['displayname'].Count -gt 0) { $name = [string]$r.Properties['displayname'][0] }
            foreach ($g in $r.Properties['memberof']) { $groups += ([string]$g -replace '^CN=([^,]+),.*$', '$1') }
        }
    } catch { Write-Note "LDAP: $($_.Exception.Message)" }
    $sids = @()
    try { $sids = @([Security.Principal.WindowsIdentity]::GetCurrent().Groups | ForEach-Object { $_.Value }) } catch { }
    $role = $cfg.Roles.User
    if ($sids | Where-Object { $_ -match '-(512|519)$' }) { $role = $cfg.Roles.Admin }
    elseif ($cfg.LabAdminsGroup -and ($groups -contains $cfg.LabAdminsGroup -or $groups -contains $cfg.InstructorsGroup)) { $role = $cfg.Roles.Instructor }
    elseif ($cfg.StudentsGroup -and $groups -contains $cfg.StudentsGroup) { $role = $cfg.Roles.Student }
    return [pscustomobject]@{ Sam = $sam; Name = $name; Role = $role }
}

function Get-FontFamily {
    param([Drawing.Text.PrivateFontCollection]$Collection, [string[]]$Names)
    foreach ($n in $Names) {
        foreach ($f in $Collection.Families) { if ($f.Name -like "$n*") { return $f } }
    }
    foreach ($n in $Names) {
        try { return New-Object Drawing.FontFamily($n) } catch { }
    }
    return [Drawing.FontFamily]::GenericSansSerif
}

function Get-TypographicFormat {
    $f = [Drawing.StringFormat]::GenericTypographic.Clone()
    $f.FormatFlags = $f.FormatFlags -bor [Drawing.StringFormatFlags]::MeasureTrailingSpaces
    return $f
}

function Measure-SpacedText {
    param($G, [string]$Text, $Font, [double]$Tracking)
    $fmt = Get-TypographicFormat
    $w = 0.0
    foreach ($ch in $Text.ToCharArray()) { $w += $G.MeasureString([string]$ch, $Font, 10000, $fmt).Width + $Tracking }
    if ($Text.Length -gt 0) { $w -= $Tracking }
    return $w
}

function Write-SpacedText {
    param($G, [string]$Text, $Font, $Brush, [double]$CenterX, [double]$Y, [double]$Tracking)
    $fmt = Get-TypographicFormat
    $x = $CenterX - (Measure-SpacedText $G $Text $Font $Tracking) / 2
    foreach ($ch in $Text.ToCharArray()) {
        $G.DrawString([string]$ch, $Font, $Brush, [single]$x, [single]$Y, $fmt)
        $x += $G.MeasureString([string]$ch, $Font, 10000, $fmt).Width + $Tracking
    }
}

try {
    [void][LabDesktop]::SetProcessDPIAware()
    if ($Width -le 0 -or $Height -le 0) {
        $b = [Windows.Forms.Screen]::PrimaryScreen.Bounds
        $Width = [Math]::Max(1280, $b.Width)
        $Height = [Math]::Max(720, $b.Height)
    }
    $acc = Get-Account
    if ($UserName) { $acc.Sam = $UserName }
    if ($DisplayName) { $acc.Name = $DisplayName }
    if ($Role) { $acc.Role = $Role }

    $fonts = New-Object Drawing.Text.PrivateFontCollection
    foreach ($f in @(Get-ChildItem -LiteralPath $here -Filter '*.ttf' -ErrorAction SilentlyContinue)) {
        try { $fonts.AddFontFile($f.FullName) } catch { Write-Note "font $($f.Name): $($_.Exception.Message)" }
    }
    $serif = Get-FontFamily $fonts @('Cormorant Garamond', 'Cormorant', 'Georgia', 'Cambria', 'Times New Roman')
    $mono = Get-FontFamily $fonts @('IBM Plex Mono', 'Consolas', 'Courier New')

    $bmp = New-Object Drawing.Bitmap($Width, $Height)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.Clear([Drawing.Color]::FromArgb(3, 5, 4))

    $basePath = Join-Path $here 'base.png'
    if (Test-Path -LiteralPath $basePath) {
        $base = [Drawing.Image]::FromFile($basePath)
        $scale = [Math]::Max($Width / $base.Width, $Height / $base.Height)
        $bw = $base.Width * $scale
        $bh = $base.Height * $scale
        $g.DrawImage($base, [single](($Width - $bw) / 2), [single](($Height - $bh) / 2), [single]$bw, [single]$bh)
        $base.Dispose()
    }

    $u = $Height / 1080.0
    $cx = $Width / 2.0
    $neon = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(0, 255, 163))
    $text = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(201, 214, 210))
    $muted = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(122, 154, 144))
    $deep = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(71, 131, 107))

    $logoPath = Join-Path $here 'logo.png'
    $top = $Height * 0.2
    if (Test-Path -LiteralPath $logoPath) {
        $logo = [Drawing.Image]::FromFile($logoPath)
        $ls = [Math]::Round(168 * $u)
        $g.InterpolationMode = 'NearestNeighbor'
        $g.PixelOffsetMode = 'Half'
        $g.DrawImage($logo, [single]($cx - $ls / 2), [single]$top, [single]$ls, [single]$ls)
        $g.InterpolationMode = 'HighQualityBicubic'
        $g.PixelOffsetMode = 'Default'
        $logo.Dispose()
        $top += $ls + 36 * $u
    }

    $eyebrow = ('{0}   {1}' -f ([string]$cfg.Brand).ToUpperInvariant(), ([string]$cfg.Domain).ToUpperInvariant())
    $fEyebrow = New-Object Drawing.Font($mono, [single](15 * $u), [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
    Write-SpacedText $g $eyebrow $fEyebrow $neon $cx $top (7 * $u)
    $top += 44 * $u

    $title = [string]$acc.Name
    $size = 112 * $u
    $track = 14 * $u
    $fTitle = New-Object Drawing.Font($serif, [single]$size, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
    while ((Measure-SpacedText $g $title.ToUpperInvariant() $fTitle $track) -gt $Width * 0.86 -and $size -gt 40 * $u) {
        $size -= 6 * $u
        $track = $size / 8
        $fTitle.Dispose()
        $fTitle = New-Object Drawing.Font($serif, [single]$size, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
    }
    Write-SpacedText $g $title.ToUpperInvariant() $fTitle $text $cx $top $track
    $top += $size * 1.25

    $fRole = New-Object Drawing.Font($mono, [single](17 * $u), [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
    $who = ('{0}   {1}\{2}' -f ([string]$acc.Role).ToUpperInvariant(), $env:USERDOMAIN, $acc.Sam)
    Write-SpacedText $g $who $fRole $muted $cx $top (5 * $u)
    $top += 40 * $u

    $fTag = New-Object Drawing.Font($serif, [single](30 * $u), [Drawing.FontStyle]::Italic, [Drawing.GraphicsUnit]::Pixel)
    $fmt = New-Object Drawing.StringFormat
    $fmt.Alignment = 'Center'
    $g.DrawString([string]$cfg.Tagline, $fTag, $deep, [single]$cx, [single]$top, $fmt)

    $fFoot = New-Object Drawing.Font($mono, [single](12 * $u), [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
    $foot = ('{0}   {1}' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd')).ToUpperInvariant()
    Write-SpacedText $g $foot $fFoot $muted $cx ($Height - 64 * $u) (4 * $u)

    $g.Dispose()
    if (-not $OutFile) { $OutFile = Join-Path $workDir ('wallpaper-{0}.png' -f $acc.Sam) }
    $bmp.Save($OutFile, [Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()

    if (-not $NoApply) {
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10'
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value '0'
        [void][LabDesktop]::SystemParametersInfo(20, 0, $OutFile, 3)
    }
    Write-Note "ok $($acc.Sam) $Width x $Height"
} catch {
    Write-Note "error: $($_.Exception.Message)"
    $fallback = Join-Path $here 'fallback.png'
    if (-not $NoApply -and (Test-Path -LiteralPath $fallback)) {
        try { [void][LabDesktop]::SystemParametersInfo(20, 0, $fallback, 3) } catch { }
    }
}
