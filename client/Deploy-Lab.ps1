[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Server,
    [string]$Share = 'LabKit',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$logDir = Join-Path $env:ProgramData 'Lab'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$log = Join-Path $logDir 'deploy.log'

function Log {
    param([string]$Text, [string]$Level = 'INFO')
    Add-Content -LiteralPath $log -Value ('{0}  [{1,-5}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Text) -Encoding UTF8
}

function Read-Json {
    param([string]$Path)
    $t = [IO.File]::ReadAllText($Path)
    if ($t.Length -gt 0 -and $t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }
    return ($t | ConvertFrom-Json)
}

try {
    $session = (Get-CimInstance Win32_ComputerSystem).UserName
    if (-not $session) { Log 'No interactive session.'; exit 0 }
    $sam = $session.Split('\')[-1]
    $dom = $session.Split('\')[0]
    if ($dom -eq $env:COMPUTERNAME) { Log "$session is a local account. Skipped."; exit 0 }
    $sid = (New-Object Security.Principal.NTAccount($session)).Translate([Security.Principal.SecurityIdentifier]).Value
    $userProfile = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -ErrorAction SilentlyContinue).ProfileImagePath
    if (-not $userProfile -or -not (Test-Path -LiteralPath $userProfile)) { Log "Profile of $session not found." 'WARN'; exit 0 }

    $slot = $null
    try {
        $de = New-Object DirectoryServices.DirectoryEntry("LDAP://$Server")
        $ds = New-Object DirectoryServices.DirectorySearcher($de)
        $ds.Filter = "(&(objectClass=user)(sAMAccountName=$sam))"
        [void]$ds.PropertiesToLoad.Add('employeenumber')
        $r = $ds.FindOne()
        if ($r -and $r.Properties['employeenumber'].Count -gt 0) { $slot = [string]$r.Properties['employeenumber'][0] }
    } catch { Log "LDAP query failed: $($_.Exception.Message)" 'WARN' }
    if (-not $slot) { Log "$sam has no lab slot. Not a student."; exit 0 }

    $base = "\\$Server\$Share"
    $kit = Join-Path $base "personal\$slot"
    $applyPath = Join-Path $kit 'apply.json'
    if (-not (Test-Path -LiteralPath $applyPath)) { Log "Kit $kit not found." 'WARN'; exit 0 }
    $info = $null
    $infoPath = Join-Path $base 'module\lab.json'
    if (Test-Path -LiteralPath $infoPath) { $info = Read-Json $infoPath }
    $markerName = '.lab-kit-deployed'
    if ($info -and $info.Marker) { $markerName = [string]$info.Marker }
    $marker = Join-Path $userProfile $markerName
    $stamp = (Get-Item -LiteralPath $applyPath).LastWriteTimeUtc.ToString('s')
    if ((Test-Path -LiteralPath $marker) -and -not $Force) {
        if (([IO.File]::ReadAllText($marker)).Trim() -eq $stamp) { Log 'Kit already deployed and up to date.' 'OK'; exit 0 }
    }
    $a = Read-Json $applyPath

    $dest = Join-Path $userProfile $a.KitDir
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue }
    $null = robocopy.exe (Join-Path $kit $a.KitDir) $dest /E /R:1 /W:1 /NFL /NDL /NJH /NJS
    $acl = Get-Acl -LiteralPath $dest
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')))
    Set-Acl -LiteralPath $dest -AclObject $acl
    foreach ($h in @($a.Hidden)) {
        $p = Join-Path $userProfile $h
        if (Test-Path -LiteralPath $p) { (Get-Item -LiteralPath $p -Force).Attributes = 'Directory, Hidden' }
    }
    Log "Kit copied to $dest"

    $hku = "Registry::HKEY_USERS\$sid"
    if (Test-Path -LiteralPath $hku) {
        foreach ($e in @($a.Registry)) {
            $k = Join-Path $hku $e.Key
            if (-not (Test-Path -LiteralPath $k)) { New-Item -Path $k -Force | Out-Null }
            New-ItemProperty -Path $k -Name $e.Name -Value $e.Value -PropertyType String -Force | Out-Null
        }
        $envKey = Join-Path $hku 'Environment'
        if (-not (Test-Path -LiteralPath $envKey)) { New-Item -Path $envKey -Force | Out-Null }
        New-ItemProperty -Path $envKey -Name $a.EnvVar.Name -Value $a.EnvVar.Value -PropertyType String -Force | Out-Null
        $bin = Join-Path $userProfile $a.PathExtra
        $cur = (Get-ItemProperty -Path $envKey -Name Path -ErrorAction SilentlyContinue).Path
        if (-not $cur) { $cur = '' }
        if ($cur -notlike "*$bin*") {
            $new = $bin
            if ($cur) { $new = "$cur;$bin" }
            New-ItemProperty -Path $envKey -Name Path -Value $new -PropertyType ExpandString -Force | Out-Null
        }
        if ($a.CanaryRegistry) {
            $rk = Join-Path $hku $a.CanaryRegistry.Key
            if (-not (Test-Path -LiteralPath $rk)) { New-Item -Path $rk -Force | Out-Null }
            New-ItemProperty -Path $rk -Name $a.CanaryRegistry.Name -Value $a.CanaryRegistry.Value -PropertyType String -Force | Out-Null
        }
        if ($info -and [string]$info.Language -eq 'ru') {
            $con = Join-Path $hku 'Console'
            if (-not (Test-Path -LiteralPath $con)) { New-Item -Path $con -Force | Out-Null }
            New-ItemProperty -Path $con -Name 'CodePage' -Value 65001 -PropertyType DWord -Force | Out-Null
        }
        Log 'Registry, environment variable and PATH updated'
    } else { Log 'User hive not loaded; registry skipped.' 'WARN' }

    foreach ($s in @($a.Stream, $a.CanaryStream)) {
        if (-not $s) { continue }
        $fp = Join-Path $userProfile $s.File
        if (Test-Path -LiteralPath $fp) { Set-Content -LiteralPath $fp -Stream $s.Name -Value $s.Value -Encoding UTF8 }
    }
    Log 'Alternate data streams written'

    $lb = Join-Path $userProfile $a.Links.Base
    if (Test-Path -LiteralPath $lb) {
        $pre = [string]$a.Links.Prefix
        $target = Join-Path $lb $a.Links.Target
        $pairs = @(@("$($pre)3", $target), @("$($pre)2", (Join-Path $lb "$($pre)3")), @("$($pre)1", (Join-Path $lb "$($pre)2")))
        foreach ($p in $pairs) {
            $link = Join-Path $lb $p[0]
            if (Test-Path -LiteralPath $link) { cmd.exe /c "rmdir `"$link`"" 2>&1 | Out-Null }
            cmd.exe /c "mklink /J `"$link`" `"$($p[1])`"" 2>&1 | Out-Null
        }
        Log 'Junction chain created'
    }

    $idDir = Join-Path $userProfile $a.Identity.Folder
    if (-not (Test-Path -LiteralPath $idDir)) { New-Item -ItemType Directory -Path $idDir -Force | Out-Null }
    $rnd = New-Object Random(4242)
    for ($i = 0; $i -lt 25; $i++) {
        $fake = 'S-1-5-21-{0}-{1}-{2}-{3}' -f $rnd.Next(1000000000, 2147483647), $rnd.Next(1000000000, 2147483647), $rnd.Next(1000000000, 2147483647), $rnd.Next(1000, 9999)
        Set-Content -LiteralPath (Join-Path $idDir "$fake.txt") -Value $a.Identity.Other -Encoding UTF8
    }
    Set-Content -LiteralPath (Join-Path $idDir "$sid.txt") -Value ($a.Identity.Mine + "`r`n`r`n" + $a.Identity.Flag) -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $idDir $a.Identity.ReadmeName) -Value $a.Identity.Readme -Encoding UTF8
    Log 'Identity folder seeded'

    try {
        Unregister-ScheduledTask -TaskName $a.Task.Name -Confirm:$false -ErrorAction SilentlyContinue
        $act = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c exit 0'
        $trg = New-ScheduledTaskTrigger -Daily -At '03:30'
        $prn = New-ScheduledTaskPrincipal -UserId $session -LogonType Interactive
        Register-ScheduledTask -TaskName $a.Task.Name -Action $act -Trigger $trg -Principal $prn -Description $a.Task.Description | Out-Null
        Log "Scheduled task $($a.Task.Name) registered"
    } catch { Log "Scheduled task failed: $($_.Exception.Message)" 'WARN' }

    try {
        $docs = (Get-ItemProperty "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name Personal -ErrorAction SilentlyContinue).Personal
        if ($docs) { $docs = $docs.Replace('%USERPROFILE%', $userProfile) } else { $docs = Join-Path $userProfile 'Documents' }
        if ($docs -like '\\*') { $docs = Join-Path $userProfile 'Documents' }
        $modDir = Join-Path $docs 'WindowsPowerShell\Modules\Student'
        if (-not (Test-Path -LiteralPath $modDir)) { New-Item -ItemType Directory -Path $modDir -Force | Out-Null }
        Copy-Item -LiteralPath (Join-Path $base 'module\Student.psm1') -Destination $modDir -Force
        $ruFile = Join-Path $base 'module\ru.json'
        if (Test-Path -LiteralPath $ruFile) { Copy-Item -LiteralPath $ruFile -Destination $modDir -Force }
        if (Test-Path -LiteralPath $infoPath) { Copy-Item -LiteralPath $infoPath -Destination $modDir -Force }
        $prof = Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
        $line = 'Import-Module Student -ErrorAction SilentlyContinue'
        if (-not (Test-Path -LiteralPath $prof) -or -not (Select-String -LiteralPath $prof -SimpleMatch $line -Quiet)) { Add-Content -LiteralPath $prof -Value $line -Encoding UTF8 }
        $acl = Get-Acl -LiteralPath (Split-Path -Parent $modDir)
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')))
        Set-Acl -LiteralPath (Split-Path -Parent $modDir) -AclObject $acl
        Log 'Student module installed'
    } catch { Log "Student module failed: $($_.Exception.Message)" 'WARN' }

    Set-Content -LiteralPath $marker -Value $stamp -Encoding UTF8
    (Get-Item -LiteralPath $marker -Force).Attributes = 'Hidden'
    Log "Lab kit for $sam deployed." 'OK'
}
catch {
    Log "FAILED: $($_.Exception.Message)" 'ERROR'
    exit 1
}
