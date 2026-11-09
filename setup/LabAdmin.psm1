Set-StrictMode -Off

function Update-DnsPublishing {
    $c = Get-LabConfig
    Import-Module DnsServer -ErrorAction Stop
    $pub = @(Get-PublishedAddresses)
    $lanNic = Get-LanAdapter

    foreach ($ip in @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -ne '127.0.0.1' })) {
        $register = ($lanNic -and $ip.InterfaceIndex -eq $lanNic.ifIndex)
        try { Set-DnsClient -InterfaceIndex $ip.InterfaceIndex -RegisterThisConnectionsAddress $register -ErrorAction Stop } catch { }
    }
    if ($lanNic) { Set-DnsClientServerAddress -InterfaceIndex $lanNic.ifIndex -ServerAddresses @('127.0.0.1') }

    $p = 'HKLM:\SYSTEM\CurrentControlSet\Services\DNS\Parameters'
    New-ItemProperty -Path $p -Name 'PublishAddresses' -Value ($pub -join ' ') -PropertyType String -Force | Out-Null

    $zone = $c.DomainFqdn
    $msdcs = "_msdcs.$zone"
    $targets = @(
        @{ Zone = $zone;  Name = '@' }
        @{ Zone = $zone;  Name = $c.DcName.ToLowerInvariant() }
        @{ Zone = $zone;  Name = 'DomainDnsZones' }
        @{ Zone = $zone;  Name = 'ForestDnsZones' }
        @{ Zone = $msdcs; Name = 'gc' }
    )
    if ($c.Mail) { $targets += @{ Zone = $zone; Name = 'mail' } }
    foreach ($t in $targets) {
        if (-not (Get-DnsServerZone -Name $t.Zone -ErrorAction SilentlyContinue)) { continue }
        $have = @(Get-DnsServerResourceRecord -ZoneName $t.Zone -Name $t.Name -RRType A -ErrorAction SilentlyContinue)
        foreach ($r in $have) {
            $v = $r.RecordData.IPv4Address.IPAddressToString
            if ($pub -notcontains $v) {
                Remove-DnsServerResourceRecord -ZoneName $t.Zone -InputObject $r -Force -ErrorAction SilentlyContinue
            }
        }
        foreach ($a in $pub) {
            $exists = $have | Where-Object { $_.RecordData.IPv4Address.IPAddressToString -eq $a }
            if (-not $exists) {
                Add-DnsServerResourceRecordA -ZoneName $t.Zone -Name $t.Name -IPv4Address $a -ErrorAction SilentlyContinue
            }
        }
    }
    if ($c.Mail -and (Get-DnsServerZone -Name $zone -ErrorAction SilentlyContinue)) {
        $mx = Get-DnsServerResourceRecord -ZoneName $zone -Name '@' -RRType MX -ErrorAction SilentlyContinue
        if (-not $mx) { Add-DnsServerResourceRecordMX -ZoneName $zone -Name '@' -MailExchange "mail.$zone" -Preference 10 }
    }
    $null = & ipconfig.exe /registerdns
    $null = & nltest.exe /dsregdns
    return $pub
}

function Update-FirewallScope {
    $c = Get-LabConfig
    $cidrs = @(Get-ClientCidrs)
    $lan = Get-NetworkCidr -Ip $c.LanIPAddress -Prefix ([int]$c.LanPrefixLength)
    $ad = @($cidrs)
    if ($ad -notcontains $lan) { $ad += $lan }
    $count = 0
    foreach ($r in @(Get-NetFirewallRule -Group 'Lab' -ErrorAction SilentlyContinue)) {
        $isService = $r.Name -match '^Lab-(Web|Intranet|Banner|SMTP|POP3|Mail)'
        $scope = $ad
        if ($isService) { $scope = $cidrs }
        Set-NetFirewallRule -Name $r.Name -RemoteAddress $scope
        $count++
    }
    return $count
}

function Grant-DirectoryRight {
    param(
        [Parameter(Mandatory)][string]$TargetDN,
        [Parameter(Mandatory)][Security.Principal.SecurityIdentifier]$Sid,
        [ValidateSet('GenericAll', 'GenericRead')][string]$Right = 'GenericAll'
    )
    Import-Module ActiveDirectory -ErrorAction Stop
    $path = "AD:\$TargetDN"
    $acl = Get-Acl -Path $path
    $rights = [DirectoryServices.ActiveDirectoryRights]::$Right
    $inh = [DirectoryServices.ActiveDirectorySecurityInheritance]::All
    $rule = New-Object DirectoryServices.ActiveDirectoryAccessRule($Sid, $rights, 'Allow', $inh)
    $already = $false
    foreach ($a in $acl.Access) {
        $idSid = $null
        try { $idSid = $a.IdentityReference.Translate([Security.Principal.SecurityIdentifier]) } catch { }
        if ($idSid -and $idSid.Value -eq $Sid.Value -and $a.AccessControlType -eq 'Allow' -and (($a.ActiveDirectoryRights -band $rights) -eq $rights)) { $already = $true }
    }
    if (-not $already) {
        $acl.AddAccessRule($rule)
        Set-Acl -Path $path -AclObject $acl
    }
}

function Grant-ComputerJoinRight {
    param(
        [Parameter(Mandatory)][string]$TargetDN,
        [Parameter(Mandatory)][Security.Principal.SecurityIdentifier]$Sid,
        [switch]$Full
    )
    Import-Module ActiveDirectory -ErrorAction Stop
    $path = "AD:\$TargetDN"
    $acl = Get-Acl -Path $path
    $computerClass = [Guid]'bf967a86-0de6-11d0-a285-00aa003049e2'
    $desc = [DirectoryServices.ActiveDirectorySecurityInheritance]::Descendents
    $acl.AddAccessRule((New-Object DirectoryServices.ActiveDirectoryAccessRule($Sid, 'CreateChild, DeleteChild', 'Allow', $computerClass, 'All')))
    if ($Full) {
        $acl.AddAccessRule((New-Object DirectoryServices.ActiveDirectoryAccessRule($Sid, 'GenericAll', 'Allow', $desc, $computerClass)))
    } else {
        $acl.AddAccessRule((New-Object DirectoryServices.ActiveDirectoryAccessRule($Sid, 'ExtendedRight', 'Allow', [Guid]'00299570-246d-11d0-a768-00aa006e0529', $desc, $computerClass)))
        $acl.AddAccessRule((New-Object DirectoryServices.ActiveDirectoryAccessRule($Sid, 'ReadProperty, WriteProperty', 'Allow', [Guid]'4c164200-20c0-11d0-a768-00aa006e0529', $desc, $computerClass)))
        $acl.AddAccessRule((New-Object DirectoryServices.ActiveDirectoryAccessRule($Sid, 'Self', 'Allow', [Guid]'72e39547-7b18-11d1-adef-00c04fd8d5cd', $desc, $computerClass)))
        $acl.AddAccessRule((New-Object DirectoryServices.ActiveDirectoryAccessRule($Sid, 'Self', 'Allow', [Guid]'f3a64788-5306-11d1-a9c5-0000f80367c1', $desc, $computerClass)))
    }
    Set-Acl -Path $path -AclObject $acl
}

function New-OrganizationalUnit {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Path, [string]$Description = '')
    $dn = "OU=$Name,$Path"
    $ou = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue
    if (-not $ou) {
        New-ADOrganizationalUnit -Name $Name -Path $Path -Description $Description -ProtectedFromAccidentalDeletion $false | Out-Null
        return $true
    }
    return $false
}

function New-SecurityGroup {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Path, [string]$Description = '')
    $g = Get-ADGroup -Filter "Name -eq '$Name'" -ErrorAction SilentlyContinue
    if (-not $g) {
        New-ADGroup -Name $Name -SamAccountName $Name -GroupScope Global -GroupCategory Security -Path $Path -Description $Description | Out-Null
        return $true
    }
    return $false
}

$script:Cyrillic = @{}
$cyrLatin = @('a', 'b', 'v', 'g', 'd', 'e', 'zh', 'z', 'i', 'i', 'k', 'l', 'm', 'n', 'o', 'p', 'r', 's', 't', 'u', 'f', 'kh', 'ts', 'ch', 'sh', 'shch', 'ie', 'y', '', 'e', 'iu', 'ia')
for ($i = 0; $i -lt 32; $i++) { $script:Cyrillic[0x0430 + $i] = $cyrLatin[$i]; $script:Cyrillic[0x0410 + $i] = $cyrLatin[$i] }
foreach ($pair in @(@(0x0451, 'e'), @(0x0401, 'e'), @(0x0456, 'i'), @(0x0406, 'i'), @(0x0457, 'i'), @(0x0407, 'i'), @(0x0454, 'ie'), @(0x0404, 'ie'), @(0x0491, 'g'), @(0x0490, 'g'))) { $script:Cyrillic[$pair[0]] = $pair[1] }

function ConvertFrom-Cyrillic {
    param([AllowEmptyString()][string]$Text)
    if (-not $Text) { return '' }
    $sb = New-Object Text.StringBuilder
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int]$ch
        if (-not $script:Cyrillic.ContainsKey($code)) { [void]$sb.Append($ch); continue }
        $lat = [string]$script:Cyrillic[$code]
        if ($lat -and [char]::IsUpper($ch)) { $lat = $lat.Substring(0, 1).ToUpperInvariant() + $lat.Substring(1) }
        [void]$sb.Append($lat)
    }
    return $sb.ToString()
}

function ConvertTo-Ascii {
    param([AllowEmptyString()][string]$Text)
    if (-not $Text) { return '' }
    $n = (ConvertFrom-Cyrillic $Text).Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object Text.StringBuilder
    foreach ($ch in $n.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    return $sb.ToString().Normalize([Text.NormalizationForm]::FormC)
}

function New-SamName {
    param([Parameter(Mandatory)][string]$First, [Parameter(Mandatory)][string]$Last)
    $f = (ConvertTo-Ascii $First).ToLowerInvariant() -replace '[^a-z]', ''
    $l = (ConvertTo-Ascii (($Last -split '\s+')[0])).ToLowerInvariant() -replace '[^a-z]', ''
    if (-not $f) { $f = 'x' }
    if (-not $l) { $l = 'user' }
    $base = "$($f.Substring(0, 1)).$l"
    if ($base.Length -gt 20) { $base = $base.Substring(0, 20) }
    $sam = $base
    $i = 2
    while (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        $suffix = [string]$i
        $cut = [Math]::Min($base.Length, 20 - $suffix.Length)
        $sam = $base.Substring(0, $cut) + $suffix
        $i++
    }
    return $sam
}

function Get-CsvValue {
    param([Parameter(Mandatory)]$Row, [Parameter(Mandatory)][string[]]$Names)
    foreach ($n in $Names) {
        foreach ($p in $Row.PSObject.Properties) {
            if ((ConvertTo-Ascii $p.Name).Trim().ToLowerInvariant() -eq $n.ToLowerInvariant()) {
                $v = [string]$p.Value
                if ($v) { return $v.Trim() }
            }
        }
    }
    return ''
}

function Import-CsvFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw (L "No existe el CSV: $Path" "CSV not found: $Path") }
    $bytes = [IO.File]::ReadAllBytes($Path)
    try { $text = (New-Object Text.UTF8Encoding($false, $true)).GetString($bytes) }
    catch { $text = [Text.Encoding]::Default.GetString($bytes) }
    $text = $text.TrimStart([char]0xFEFF)
    $lines = @($text -split "`r?`n" | Where-Object { $_.Trim() })
    if (-not $lines) { return @() }
    $delim = ','
    if ($lines[0].Split(';').Count -gt $lines[0].Split(',').Count) { $delim = ';' }
    return @($lines | ConvertFrom-Csv -Delimiter $delim)
}

function Set-HomeFolder {
    param([Parameter(Mandatory)]$User, [Parameter(Mandatory)][string]$Folder)
    $c = Get-LabConfig
    $path = Join-Path $c.Paths.Home $Folder
    foreach ($sub in @($path, (Join-Path $path $c.Names.FolderDeliveries), (Join-Path $path $c.Names.FolderWork))) { New-Folder $sub | Out-Null }
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $inh = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $none = [Security.AccessControl.PropagationFlags]::None
    foreach ($s in @('S-1-5-18', 'S-1-5-32-544')) {
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($s)), 'FullControl', $inh, $none, 'Allow')))
    }
    $ins = Get-ADGroup -Filter "Name -eq '$($c.Groups.Instructors)'" -ErrorAction SilentlyContinue
    if ($ins) { $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($ins.SID, 'ReadAndExecute', $inh, $none, 'Allow'))) }
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($User.SID, 'Modify', $inh, $none, 'Allow')))
    $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    Set-Acl -LiteralPath $path -AclObject $acl
    Set-ADUser -Identity $User -HomeDirectory ("\\{0}\{1}\{2}" -f $c.DcName, $c.Shares.Home, $Folder) -HomeDrive 'H:'
    return $path
}

function New-StudentAccount {
    param(
        [Parameter(Mandatory)][string]$First,
        [Parameter(Mandatory)][string]$Last,
        [string]$Sam,
        [string]$Mail,
        [string]$Password,
        [string[]]$ExtraGroups
    )
    $c = Get-LabConfig
    if (-not $Sam) { $Sam = New-SamName -First $First -Last $Last }
    $Sam = $Sam.ToLowerInvariant()
    $existing = Get-ADUser -Filter "SamAccountName -eq '$Sam'" -Properties employeeNumber -ErrorAction SilentlyContinue
    if ($existing) {
        return [pscustomobject]@{ Sam = $Sam; Slot = [string]$existing.employeeNumber; Password = $null; Created = $false; User = $existing }
    }
    $slot = Get-NextStudentSlot
    if (-not $slot) { throw (L "No quedan plazas de alumno (StudentSlots = $($c.StudentSlots))" "No student slots left (StudentSlots = $($c.StudentSlots))") }
    if (-not $Password) { $Password = New-RandomPassword -Length 16 }
    $upn = "$Sam@$($c.DomainFqdn)"
    if (-not $Mail) { $Mail = $upn }
    $display = ('{0} {1}' -f $First, $Last).Trim()
    $name = $display
    if (Get-ADObject -Filter "Name -eq '$name'" -SearchBase $c.OUStudents -SearchScope OneLevel -ErrorAction SilentlyContinue) { $name = "$display ($Sam)" }
    New-ADUser -Name $name -SamAccountName $Sam -UserPrincipalName $upn -EmailAddress $Mail `
        -GivenName $First -Surname $Last -DisplayName $display -Path $c.OUStudents `
        -Company $c.Organization -Title (L 'Alumno' 'Student') `
        -AccountPassword (ConvertTo-SecureString $Password -AsPlainText -Force) `
        -Enabled $true -ChangePasswordAtLogon $false | Out-Null
    $u = Get-ADUser -Identity $Sam
    Set-ADUser -Identity $u -Replace @{ employeeNumber = $slot }
    Add-ADGroupMember -Identity $c.Groups.Students -Members $u
    Add-ADGroupMember -Identity $c.Groups.SmbReaders -Members $u
    if (Test-Weakness 'StudentsCreateGpos') {
        $gco = Get-WellKnownSid 'Group Policy Creator Owners'
        if ($gco) { Add-ADGroupMember -Identity $gco.Value -Members $u -ErrorAction SilentlyContinue }
    }
    foreach ($g in @($ExtraGroups | Where-Object { $_ })) {
        $grp = Get-ADGroup -Filter "Name -eq '$g'" -ErrorAction SilentlyContinue
        if ($grp) { Add-ADGroupMember -Identity $grp -Members $u -ErrorAction SilentlyContinue }
    }
    $null = Set-HomeFolder -User $u -Folder $slot
    if (Test-Weakness 'DelegatedSandboxOUs') {
        $null = New-OrganizationalUnit -Name $slot -Path $c.OUSandbox -Description (L "Parcela de practica de $Sam" "Practice area for $Sam")
        Grant-DirectoryRight -TargetDN "OU=$slot,$($c.OUSandbox)" -Sid $u.SID -Right GenericAll
    }
    return [pscustomobject]@{ Sam = $Sam; Slot = $slot; Password = $Password; Created = $true; User = $u; Display = $display; Mail = $Mail }
}

function Set-Administrator {
    param(
        [Parameter(Mandatory)][string]$First,
        [Parameter(Mandatory)][string]$Last,
        [string]$Sam,
        [string]$Mail,
        [string]$Password,
        [ValidateSet('instructor', 'domainadmin')][string]$Role = 'instructor'
    )
    $c = Get-LabConfig
    if (-not $Sam) { $Sam = 'adm.' + ((ConvertTo-Ascii $First).ToLowerInvariant() -replace '[^a-z]', '') }
    $Sam = $Sam.ToLowerInvariant()
    if ($Sam.Length -gt 20) { $Sam = $Sam.Substring(0, 20) }
    $u = Get-ADUser -Filter "SamAccountName -eq '$Sam'" -ErrorAction SilentlyContinue
    $created = $false
    if (-not $u) {
        if (-not $Password) { $Password = New-RandomPassword -Length 20 }
        $upn = "$Sam@$($c.DomainFqdn)"
        if (-not $Mail) { $Mail = $upn }
        $display = ('{0} {1}' -f $First, $Last).Trim()
        New-ADUser -Name $display -SamAccountName $Sam -UserPrincipalName $upn -EmailAddress $Mail `
            -GivenName $First -Surname $Last -DisplayName $display -Path $c.OUInstructors `
            -Company $c.Organization -Title (L 'Instructor' 'Instructor') `
            -AccountPassword (ConvertTo-SecureString $Password -AsPlainText -Force) `
            -Enabled $true -ChangePasswordAtLogon $false | Out-Null
        $u = Get-ADUser -Identity $Sam
        $created = $true
    } else { $Password = $null }
    Add-ADGroupMember -Identity $c.Groups.Instructors -Members $u -ErrorAction SilentlyContinue
    Add-ADGroupMember -Identity $c.Groups.LabAdmins -Members $u -ErrorAction SilentlyContinue
    $rdu = Get-WellKnownSid 'Remote Desktop Users'
    if ($rdu) { Add-ADGroupMember -Identity $rdu.Value -Members $u -ErrorAction SilentlyContinue }
    if ($Role -eq 'domainadmin') {
        $da = Get-WellKnownSid 'Domain Admins'
        Add-ADGroupMember -Identity $da.Value -Members $u
    }
    return [pscustomobject]@{ Sam = $Sam; Password = $Password; Created = $created; Role = $Role; User = $u }
}

function Get-GpoFolder {
    param([Parameter(Mandatory)]$Gpo)
    $dom = Get-ADDomain
    $share = Get-SmbShare -Name 'SYSVOL' -ErrorAction SilentlyContinue
    $base = "$env:SystemRoot\SYSVOL\sysvol"
    if ($share) { $base = $share.Path }
    return (Join-Path $base ("{0}\Policies\{{{1}}}" -f $dom.DNSRoot, $Gpo.Id.ToString().ToUpperInvariant()))
}

function Set-GpoPrivilegeRights {
    param([Parameter(Mandatory)]$Gpo, [Parameter(Mandatory)][hashtable]$Rights)
    $dom = Get-ADDomain
    $folder = Get-GpoFolder -Gpo $Gpo
    $dir = Join-Path $folder 'Machine\Microsoft\Windows NT\SecEdit'
    New-Folder $dir | Out-Null
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('[Unicode]'); $lines.Add('Unicode=yes')
    $lines.Add('[Version]'); $lines.Add('signature="$CHICAGO$"'); $lines.Add('Revision=1')
    $lines.Add('[Privilege Rights]')
    foreach ($k in $Rights.Keys) {
        $sids = @($Rights[$k] | Where-Object { $_ } | ForEach-Object { '*' + [string]$_ })
        $lines.Add(('{0} = {1}' -f $k, ($sids -join ',')))
    }
    [IO.File]::WriteAllText((Join-Path $dir 'GptTmpl.inf'), (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::Unicode)
    $dn = "CN={{{0}}},CN=Policies,CN=System,{1}" -f $Gpo.Id.ToString().ToUpperInvariant(), $dom.DistinguishedName
    $obj = Get-ADObject -Identity $dn -Properties gPCMachineExtensionNames, versionNumber
    $ext = '[{827D319E-6EAC-11D2-A4EA-00C04F79F83A}{803E14A0-B4FB-11D0-A0D0-00A0C90F574B}]'
    $cur = [string]$obj.gPCMachineExtensionNames
    if ($cur -notlike '*827D319E-6EAC-11D2-A4EA-00C04F79F83A*') { $cur = $cur + $ext }
    $ver = [int]$obj.versionNumber + 1
    Set-ADObject -Identity $dn -Replace @{ gPCMachineExtensionNames = $cur; versionNumber = $ver }
    $ini = Join-Path $folder 'GPT.INI'
    [IO.File]::WriteAllText($ini, ("[General]`r`nVersion={0}`r`n" -f $ver), [Text.Encoding]::ASCII)
}

function Get-LabGpo {
    param([Parameter(Mandatory)][string]$Name, [string]$Comment = '')
    Import-Module GroupPolicy -ErrorAction Stop
    $g = Get-GPO -Name $Name -ErrorAction SilentlyContinue
    if (-not $g) { $g = New-GPO -Name $Name -Comment $Comment }
    return $g
}

function Set-LabGpoLink {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Target)
    Import-Module GroupPolicy -ErrorAction Stop
    $inh = Get-GPInheritance -Target $Target
    $linked = $false
    foreach ($l in @($inh.GpoLinks)) { if ($l.DisplayName -eq $Name) { $linked = $true } }
    if (-not $linked) {
        try { New-GPLink -Name $Name -Target $Target -LinkEnabled Yes | Out-Null } catch { }
    }
}

Export-ModuleMember -Function Update-DnsPublishing, Update-FirewallScope, Grant-DirectoryRight, Grant-ComputerJoinRight,
    New-OrganizationalUnit, New-SecurityGroup, ConvertTo-Ascii, ConvertFrom-Cyrillic, New-SamName, Get-CsvValue, Import-CsvFile,
    Set-HomeFolder, New-StudentAccount, Set-Administrator, Get-GpoFolder, Set-GpoPrivilegeRights, Get-LabGpo, Set-LabGpoLink
