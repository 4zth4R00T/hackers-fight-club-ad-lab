Set-StrictMode -Off

$script:Root     = Split-Path -Parent $PSScriptRoot
$script:Cfg      = $null
$script:Lang     = $null
$script:Out      = New-Object System.Collections.Generic.List[object]
$script:Secrets  = $null
$script:Catalog  = $null
$script:FlagState = $null
$script:Ru       = $null

$script:NameTable = @{
    es = @{
        OUStaff = 'Personal'; OUStudents = 'Alumnos'; OUInstructors = 'Instructores'; OUServices = 'Servicios'
        OUGroups = 'Grupos'; OUComputers = 'Equipos'; OUServers = 'Servidores'; OUWorkstations = 'Estaciones'
        OULab = 'Laboratorio'; OUSandbox = 'Sandbox'
        GStudents = 'Alumnos'; GInstructors = 'Instructores'; GLabAdmins = 'Lab-Admins'
        GSmbReaders = 'SMB-Lectores'; GSmbConfidential = 'SMB-Confidencial'; GRdpBackup = 'RDP-Respaldo'
        OddGroup = 'Los-Sin-Rostro'
        ShareHome = 'Alumnos'; SharePublic = 'Publico'; ShareDropbox = 'Entregas'; ShareConfidential = 'Confidencial'
        RoleStudent = 'Alumno'; RoleInstructor = 'Instructor'; RoleAdmin = 'Administrador'
        FolderDeliveries = 'Entregas'; FolderWork = 'Trabajo'; FolderMaterial = 'Material'; FolderTemplates = 'Plantillas'; FolderMail = 'Correo'
        Departments = @(
            @{ Key = 'DIR'; Name = 'Direccion';    Desc = 'Direccion General' }
            @{ Key = 'TI';  Name = 'TI';           Desc = 'Tecnologias de la Informacion' }
            @{ Key = 'VEN'; Name = 'Ventas';       Desc = 'Ventas y Clientes' }
            @{ Key = 'RH';  Name = 'RRHH';         Desc = 'Recursos Humanos' }
            @{ Key = 'CON'; Name = 'Contabilidad'; Desc = 'Contabilidad y Finanzas' }
            @{ Key = 'SOP'; Name = 'Soporte';      Desc = 'Mesa de Ayuda' }
        )
    }
    en = @{
        OUStaff = 'Staff'; OUStudents = 'Students'; OUInstructors = 'Instructors'; OUServices = 'Services'
        OUGroups = 'Groups'; OUComputers = 'Computers'; OUServers = 'Servers'; OUWorkstations = 'Workstations'
        OULab = 'Lab'; OUSandbox = 'Sandbox'
        GStudents = 'Students'; GInstructors = 'Instructors'; GLabAdmins = 'Lab-Admins'
        GSmbReaders = 'SMB-Readers'; GSmbConfidential = 'SMB-Confidential'; GRdpBackup = 'RDP-Backup'
        OddGroup = 'The-Faceless'
        ShareHome = 'Students'; SharePublic = 'Public'; ShareDropbox = 'Dropbox'; ShareConfidential = 'Confidential'
        RoleStudent = 'Student'; RoleInstructor = 'Instructor'; RoleAdmin = 'Administrator'
        FolderDeliveries = 'Deliveries'; FolderWork = 'Work'; FolderMaterial = 'Material'; FolderTemplates = 'Templates'; FolderMail = 'Mail'
        Departments = @(
            @{ Key = 'DIR'; Name = 'Management';  Desc = 'Executive Management' }
            @{ Key = 'IT';  Name = 'IT';          Desc = 'Information Technology' }
            @{ Key = 'SAL'; Name = 'Sales';       Desc = 'Sales and Customers' }
            @{ Key = 'HR';  Name = 'HR';          Desc = 'Human Resources' }
            @{ Key = 'ACC'; Name = 'Accounting';  Desc = 'Accounting and Finance' }
            @{ Key = 'SUP'; Name = 'Support';     Desc = 'Help Desk' }
        )
    }
}

$script:WellKnown = @{
    'Everyone'                    = 'S-1-1-0'
    'System'                      = 'S-1-5-18'
    'Authenticated Users'         = 'S-1-5-11'
    'Creator Owner'               = 'S-1-3-0'
    'Administrators'              = 'S-1-5-32-544'
    'Users'                       = 'S-1-5-32-545'
    'Account Operators'           = 'S-1-5-32-548'
    'Server Operators'            = 'S-1-5-32-549'
    'Print Operators'             = 'S-1-5-32-550'
    'Backup Operators'            = 'S-1-5-32-551'
    'Remote Desktop Users'        = 'S-1-5-32-555'
    'Remote Management Users'     = 'S-1-5-32-580'
    'Domain Admins'               = 'RID:512'
    'Domain Users'                = 'RID:513'
    'Domain Guests'               = 'RID:514'
    'Domain Computers'            = 'RID:515'
    'Domain Controllers'          = 'RID:516'
    'Schema Admins'               = 'RID:518'
    'Enterprise Admins'           = 'RID:519'
    'Group Policy Creator Owners' = 'RID:520'
    'DnsAdmins'                   = 'NAME:DnsAdmins'
}

function Get-LabRoot { return $script:Root }

function Resolve-LabLanguage {
    param([string]$Value)
    if (@('es', 'en', 'ru') -contains $Value) { return $Value }
    $ui = [Globalization.CultureInfo]::InstalledUICulture.TwoLetterISOLanguageName
    if (@('es', 'ru') -contains $ui) { return $ui }
    return 'en'
}

function Get-RussianCatalog {
    if ($script:Ru) { return $script:Ru }
    $cat = @{
        Exact    = New-Object 'System.Collections.Generic.Dictionary[string,string]'
        Cache    = New-Object 'System.Collections.Generic.Dictionary[string,string]'
        Patterns = New-Object System.Collections.Generic.List[object]
        Names    = $null
    }
    $path = Join-Path $script:Root 'lang\ru.json'
    if (Test-Path -LiteralPath $path) {
        try {
            $data = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json
            $cat.Names = $data.names
            $found = @()
            foreach ($pair in @($data.messages)) {
                $en = [string]$pair[0]
                $ru = [string]$pair[1]
                if (-not $en -or -not $ru -or $cat.Exact.ContainsKey($en)) { continue }
                $cat.Exact[$en] = $ru
                if (-not $en.Contains('[[')) { continue }
                $parts = [regex]::Split($en, '(\[\[\d+\]\])')
                $rx = New-Object Text.StringBuilder
                $order = @()
                $literal = ''
                foreach ($part in $parts) {
                    if ($part -match '^\[\[\d+\]\]$') { [void]$rx.Append('(.*?)'); $order += $part }
                    else { [void]$rx.Append([regex]::Escape($part)); $literal += $part }
                }
                $weight = ($literal -replace '[^A-Za-z]', '').Length
                if ($weight -lt 2) { continue }
                $re = New-Object Text.RegularExpressions.Regex -ArgumentList @(('^' + $rx.ToString() + '$'), [Text.RegularExpressions.RegexOptions]::Singleline)
                $found += [pscustomobject]@{ Regex = $re; Order = $order; Ru = $ru; Weight = $weight }
            }
            foreach ($f in @($found | Sort-Object Weight -Descending)) { $cat.Patterns.Add($f) }
        } catch { }
    }
    $script:Ru = $cat
    return $cat
}

function Get-RussianText {
    param([AllowEmptyString()][string]$En)
    if (-not $En) { return $En }
    $cat = Get-RussianCatalog
    $v = $null
    if ($cat.Exact.TryGetValue($En, [ref]$v)) { return $v }
    if ($cat.Cache.TryGetValue($En, [ref]$v)) { return $v }
    $out = $En
    foreach ($p in $cat.Patterns) {
        $m = $p.Regex.Match($En)
        if (-not $m.Success) { continue }
        $out = $p.Ru
        for ($i = 0; $i -lt $p.Order.Count; $i++) { $out = $out.Replace($p.Order[$i], $m.Groups[$i + 1].Value) }
        break
    }
    $cat.Cache[$En] = $out
    return $out
}

function Get-RussianNames {
    $src = (Get-RussianCatalog).Names
    if (-not $src) { return $null }
    $n = @{}
    foreach ($p in $src.PSObject.Properties) {
        if ($p.Name -eq 'Departments') {
            $n.Departments = @(foreach ($d in @($p.Value)) { @{ Key = [string]$d.Key; Name = [string]$d.Name; Desc = [string]$d.Desc } })
        } else { $n[$p.Name] = [string]$p.Value }
    }
    return $n
}

function L {
    param([string]$Es, [string]$En)
    if (-not $script:Lang) {
        try { $null = Get-LabConfig } catch { $script:Lang = Resolve-LabLanguage 'auto' }
    }
    if ($script:Lang -eq 'es') { return $Es }
    if ($script:Lang -eq 'ru') { return (Get-RussianText $En) }
    return $En
}

function Get-LabConfigPath {
    if ($env:LAB_CONFIG -and (Test-Path -LiteralPath $env:LAB_CONFIG)) { return $env:LAB_CONFIG }
    return (Join-Path $script:Root 'config\lab.config.psd1')
}

function Read-DataFile {
    param([Parameter(Mandatory)][string]$Path)
    if (Get-Command Import-PowerShellDataFile -ErrorAction SilentlyContinue) {
        return (Import-PowerShellDataFile -LiteralPath $Path)
    }
    $text = [IO.File]::ReadAllText($Path)
    return (Invoke-Expression $text)
}

function ConvertTo-DistinguishedName {
    param([Parameter(Mandatory)][string]$Fqdn)
    return (($Fqdn.Split('.') | Where-Object { $_ } | ForEach-Object { "DC=$_" }) -join ',')
}

function Get-LabConfig {
    param([switch]$Reload)
    if ($script:Cfg -and -not $Reload) { return $script:Cfg }

    $path = Get-LabConfigPath
    if (-not (Test-Path -LiteralPath $path)) {
        throw ("Config not found / No existe la configuracion: {0}" -f $path)
    }
    $raw = Read-DataFile -Path $path
    $c = @{}
    foreach ($k in $raw.Keys) { $c[$k] = $raw[$k] }

    $c.Language = Resolve-LabLanguage ([string]$c.Language)
    $nl = [string]$c.NamesLanguage
    if (-not $nl -or $nl -eq 'auto') { $nl = $c.Language }
    $c.NamesLanguage = Resolve-LabLanguage $nl
    $script:Lang = $c.Language

    $prefix = ([string]$c.DomainPrefix).Trim().ToLowerInvariant()
    $suffix = ([string]$c.DomainSuffix).Trim().Trim('.').ToLowerInvariant()
    if (-not $prefix -or -not $suffix) { throw 'DomainPrefix / DomainSuffix' }
    $c.DomainFqdn = "$prefix.$suffix"
    $c.DomainDN   = ConvertTo-DistinguishedName $c.DomainFqdn
    if (-not $c.NetBIOSName) { $c.NetBIOSName = $prefix.ToUpperInvariant() }
    $c.NetBIOSName = ([string]$c.NetBIOSName).ToUpperInvariant()
    if ($c.NetBIOSName.Length -gt 15) { $c.NetBIOSName = $c.NetBIOSName.Substring(0, 15) }
    $num = 1
    if ($c.DcHostNumber) { $num = [int]$c.DcHostNumber }
    $c.DcName = ('{0}{1:D2}' -f ([string]$c.DcHostPrefix).ToUpperInvariant(), $num)
    if ($c.DcName.Length -gt 15) { throw 'DcHostPrefix: max 13 chars' }
    $c.DcFqdn = "$($c.DcName).$($c.DomainFqdn)".ToLowerInvariant()

    if (-not $c.GroupPrefix) { $c.GroupPrefix = 'Lab' }
    if (-not $c.FlagPrefix)  { $c.FlagPrefix  = 'FLAG' }
    if (-not $c.StudentPrefix) { if ($c.NamesLanguage -eq 'es') { $c.StudentPrefix = 'alumno' } else { $c.StudentPrefix = 'student' } }
    if (-not $c.StudentSlots) { $c.StudentSlots = 100 }

    $n = $script:NameTable[$c.NamesLanguage]
    if ($c.NamesLanguage -eq 'ru') {
        $n = Get-RussianNames
        if (-not $n) { $n = $script:NameTable['en']; $c.NamesLanguage = 'en' }
    }
    $c.Names = $n
    $gp = $c.GroupPrefix

    $c.OURoot         = "OU=$gp,$($c.DomainDN)"
    $c.OUStaff        = "OU=$($n.OUStaff),$($c.OURoot)"
    $c.OUStudents     = "OU=$($n.OUStudents),$($c.OURoot)"
    $c.OUInstructors  = "OU=$($n.OUInstructors),$($c.OURoot)"
    $c.OUServices     = "OU=$($n.OUServices),$($c.OURoot)"
    $c.OUGroups       = "OU=$($n.OUGroups),$($c.OURoot)"
    $c.OUComputers    = "OU=$($n.OUComputers),$($c.OURoot)"
    $c.OUServers      = "OU=$($n.OUServers),$($c.OUComputers)"
    $c.OUWorkstations = "OU=$($n.OUWorkstations),$($c.OUComputers)"
    $c.OULab          = "OU=$($n.OULab),$($c.OURoot)"
    $c.OUSandbox      = "OU=$($n.OUSandbox),$($c.OURoot)"

    $c.Groups = @{
        Students        = "$gp-$($n.GStudents)"
        Instructors     = "$gp-$($n.GInstructors)"
        LabAdmins       = "$gp-$($n.GLabAdmins)"
        SmbReaders      = "$gp-$($n.GSmbReaders)"
        SmbConfidential = "$gp-$($n.GSmbConfidential)"
        RdpBackup       = "$gp-$($n.GRdpBackup)"
        Odd             = $n.OddGroup
    }
    $c.Departments = @()
    foreach ($d in $n.Departments) {
        $c.Departments += @{
            Key   = $d.Key
            Name  = $d.Name
            Desc  = $d.Desc
            OU    = "OU=$($d.Name),$($c.OUStaff)"
            Group = "$gp-$($d.Name)"
        }
    }

    $c.Shares = @{
        Home         = $n.ShareHome
        Public       = $n.SharePublic
        Dropbox      = $n.ShareDropbox
        Confidential = $n.ShareConfidential
    }

    $r = [string]$c.Root
    $c.Paths = @{
        Root         = $r
        Setup        = "$r\setup"
        Engine       = "$r\engine"
        Services     = "$r\services"
        Web          = "$r\web"
        Client       = "$r\client"
        Assets       = "$r\assets"
        Config       = "$r\config"
        Data         = "$r\data"
        Logs         = "$r\logs"
        Score        = "$r\score"
        Mail         = "$r\mail"
        Kits         = "$r\kits"
        Content      = "$r\content"
        Intranet     = "$r\intranet"
        WebData      = "$r\data\web"
        ShareRoot    = "$r\shares"
        Home         = "$r\shares\home"
        Public       = "$r\shares\public"
        Dropbox      = "$r\shares\dropbox"
        Confidential = "$r\shares\confidential"
        Secrets      = "$r\data\secrets.json"
        FlagState    = "$r\data\flag-state.json"
        Credentials  = "$r\data\credentials.csv"
        State        = "$r\data\install-state.json"
        Catalog      = "$r\engine\challenges.json"
    }

    if (-not $c.Weaknesses) { $c.Weaknesses = @{} }
    $script:Cfg = $c
    return $c
}

function Test-Weakness {
    param([Parameter(Mandatory)][string]$Name)
    $c = Get-LabConfig
    if ($c.Weaknesses.ContainsKey($Name)) { return [bool]$c.Weaknesses[$Name] }
    return $false
}

function Write-LabLog {
    param(
        [Parameter(Mandatory, Position = 0)][AllowEmptyString()][string]$Message,
        [Parameter(Position = 1)][ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'STAGE')][string]$Level = 'INFO',
        [string]$File
    )
    if (-not $File) {
        $logs = 'C:\Windows\Temp'
        try { $logs = (Get-LabConfig).Paths.Logs } catch { }
        $File = Join-Path $logs 'setup.log'
    }
    $line = '{0}  [{1,-5}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try {
        $dir = Split-Path -Parent $File
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -LiteralPath $File -Value $line -Encoding UTF8
    } catch { }
    $script:Out.Add([pscustomobject]@{ Level = $Level; Text = $line })
}

function Add-LabOutput {
    param([Parameter(Position = 0)][AllowEmptyString()][string]$Text = '', [Parameter(Position = 1)][string]$Level = 'TEXT')
    $script:Out.Add([pscustomobject]@{ Level = $Level; Text = $Text })
}

function Show-LabOutput {
    param([switch]$Keep)
    foreach ($o in $script:Out) {
        $color = 'Gray'
        switch ($o.Level) {
            'OK'    { $color = 'Green' }
            'WARN'  { $color = 'Yellow' }
            'ERROR' { $color = 'Red' }
            'STAGE' { $color = 'Cyan' }
            'TITLE' { $color = 'Cyan' }
            'TEXT'  { $color = 'Gray' }
        }
        Write-Host $o.Text -ForegroundColor $color
    }
    if (-not $Keep) { $script:Out.Clear() }
}

function Get-LabOutputText {
    return (($script:Out | ForEach-Object { $_.Text }) -join [Environment]::NewLine)
}

function Test-Administrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DomainSid {
    try { return (Get-ADDomain -ErrorAction Stop).DomainSID.Value } catch { }
    try {
        $root = [ADSI]'LDAP://RootDSE'
        $dom = [ADSI]("LDAP://" + $root.defaultNamingContext)
        return (New-Object Security.Principal.SecurityIdentifier($dom.objectSid[0], 0)).Value
    } catch { return $null }
}

function Get-WellKnownSid {
    param([Parameter(Mandatory, Position = 0)][string]$Canonical)
    $e = $script:WellKnown[$Canonical]
    if (-not $e) { return $null }
    if ($e -like 'RID:*') {
        $ds = Get-DomainSid
        if (-not $ds) { return $null }
        return New-Object Security.Principal.SecurityIdentifier("$ds-$($e.Substring(4))")
    }
    if ($e -like 'NAME:*') {
        try {
            $g = Get-ADGroup -Identity $e.Substring(5) -ErrorAction Stop
            return $g.SID
        } catch { return $null }
    }
    return New-Object Security.Principal.SecurityIdentifier($e)
}

function Get-PrincipalName {
    param([Parameter(Mandatory, Position = 0)][string]$Canonical, [switch]$Qualified)
    $sid = Get-WellKnownSid $Canonical
    if (-not $sid) { return $Canonical }
    try {
        $acc = $sid.Translate([Security.Principal.NTAccount]).Value
        if ($Qualified) { return $acc }
        return $acc.Split('\')[-1]
    } catch { return $Canonical }
}

function New-RandomPassword {
    param([int]$Length = 20)
    if ($Length -lt 12) { $Length = 12 }
    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower = 'abcdefghijkmnopqrstuvwxyz'
    $digit = '23456789'
    $sym   = '!@#%*_-=?'
    $all   = $upper + $lower + $digit + $sym
    $rng = New-Object Security.Cryptography.RNGCryptoServiceProvider
    $pick = {
        param($set)
        $b = New-Object byte[] 4
        $rng.GetBytes($b)
        $set[[int]([BitConverter]::ToUInt32($b, 0) % [uint32]$set.Length)]
    }
    $chars = New-Object System.Collections.Generic.List[char]
    $chars.Add((& $pick $upper)); $chars.Add((& $pick $lower)); $chars.Add((& $pick $digit)); $chars.Add((& $pick $sym))
    while ($chars.Count -lt $Length) { $chars.Add((& $pick $all)) }
    $arr = $chars.ToArray()
    for ($i = $arr.Length - 1; $i -gt 0; $i--) {
        $b = New-Object byte[] 4
        $rng.GetBytes($b)
        $j = [int]([BitConverter]::ToUInt32($b, 0) % [uint32]($i + 1))
        $t = $arr[$i]; $arr[$i] = $arr[$j]; $arr[$j] = $t
    }
    $rng.Dispose()
    if ($arr[-1] -eq '!') { $arr[-1] = 'x' }
    return (-join $arr)
}

function New-RandomBytes {
    param([int]$Count = 32)
    $b = New-Object byte[] $Count
    $rng = New-Object Security.Cryptography.RNGCryptoServiceProvider
    $rng.GetBytes($b)
    $rng.Dispose()
    return $b
}

function New-Folder {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
    return $Path
}

function Set-SecureAcl {
    param([Parameter(Mandatory)][string]$Path, [Security.Principal.SecurityIdentifier[]]$ExtraRead)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    $isDir = $item.PSIsContainer
    if ($isDir) { $acl = New-Object Security.AccessControl.DirectorySecurity } else { $acl = New-Object Security.AccessControl.FileSecurity }
    $acl.SetAccessRuleProtection($true, $false)
    $inh = [Security.AccessControl.InheritanceFlags]::None
    if ($isDir) { $inh = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit' }
    $prop = [Security.AccessControl.PropagationFlags]::None
    foreach ($s in @('S-1-5-18', 'S-1-5-32-544')) {
        $sid = New-Object Security.Principal.SecurityIdentifier($s)
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', $inh, $prop, 'Allow')))
    }
    foreach ($sid in @($ExtraRead)) {
        if ($sid) { $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid, 'ReadAndExecute', $inh, $prop, 'Allow'))) }
    }
    $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Write-JsonFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Object, [int]$Depth = 8)
    New-Folder (Split-Path -Parent $Path) | Out-Null
    $json = $Object | ConvertTo-Json -Depth $Depth
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $t = [IO.File]::ReadAllText($Path)
    if ($t.Length -gt 0 -and $t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }
    if ([string]::IsNullOrWhiteSpace($t)) { return $null }
    return ($t | ConvertFrom-Json)
}

function Get-LabSecrets {
    param([switch]$Reload)
    if ($script:Secrets -and -not $Reload) { return $script:Secrets }
    $p = (Get-LabConfig).Paths.Secrets
    $s = Read-JsonFile -Path $p
    if (-not $s) { $s = New-Object psobject }
    $script:Secrets = $s
    return $s
}

function Get-LabSecret {
    param([Parameter(Mandatory)][string]$Name)
    $s = Get-LabSecrets
    $p = $s.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

function Set-LabSecret {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Value)
    $s = Get-LabSecrets -Reload
    $s | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    $p = (Get-LabConfig).Paths.Secrets
    Write-JsonFile -Path $p -Object $s
    Set-SecureAcl -Path $p
    $script:Secrets = $s
}

function Get-FlagSalt {
    $v = Get-LabSecret -Name 'FlagSalt'
    if (-not $v) {
        $v = [Convert]::ToBase64String((New-RandomBytes 32))
        Set-LabSecret -Name 'FlagSalt' -Value $v
    }
    return [Convert]::FromBase64String($v)
}

function Add-LabCredential {
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Account,
        [Parameter(Mandatory)][string]$Password,
        [string]$Note = ''
    )
    $p = (Get-LabConfig).Paths.Credentials
    New-Folder (Split-Path -Parent $p) | Out-Null
    $row = [pscustomobject]@{
        Date     = (Get-Date -Format 'yyyy-MM-dd HH:mm')
        Kind     = $Kind
        Account  = $Account
        Password = $Password
        Note     = $Note
    }
    $exists = Test-Path -LiteralPath $p
    $row | Export-Csv -LiteralPath $p -NoTypeInformation -Encoding UTF8 -Append:$exists
    Set-SecureAcl -Path $p
}

function Get-LabCatalog {
    param([switch]$Reload)
    if ($script:Catalog -and -not $Reload) { return $script:Catalog }
    $c = Get-LabConfig
    $p = $c.Paths.Catalog
    if (-not (Test-Path -LiteralPath $p)) { $p = Join-Path $script:Root 'engine\challenges.json' }
    $j = Read-JsonFile -Path $p
    if (-not $j) { throw ("Catalog not found / No existe el catalogo: {0}" -f $p) }
    $script:Catalog = $j
    return $j
}

function Get-Challenges {
    $cat = Get-LabCatalog
    return [object[]]$cat.Challenges
}

function Get-Challenge {
    param([Parameter(Mandatory)][string]$Id)
    foreach ($ch in (Get-Challenges)) { if ($ch.Id -eq $Id) { return $ch } }
    return $null
}

function Expand-LabText {
    param([AllowEmptyString()][string]$Text)
    if (-not $Text) { return '' }
    $c = Get-LabConfig
    $map = @{
        '{ORG}' = $c.Organization; '{LAB}' = $c.LabName; '{DOMAIN}' = $c.DomainFqdn; '{NETBIOS}' = $c.NetBIOSName
        '{DC}' = $c.DcName; '{DCFQDN}' = $c.DcFqdn; '{FLAG}' = $c.FlagPrefix; '{GROUP_PREFIX}' = $c.GroupPrefix
        '{STUDENT_PREFIX}' = $c.StudentPrefix; '{ODD_GROUP}' = $c.Groups.Odd
        '{SHARE_HOME}' = $c.Shares.Home; '{SHARE_PUBLIC}' = $c.Shares.Public; '{SHARE_DROPBOX}' = $c.Shares.Dropbox
        '{SHARE_CONFIDENTIAL}' = $c.Shares.Confidential; '{OU_SANDBOX}' = $c.Names.OUSandbox
        '{WEB_PORT}' = [string]$c.WebPort; '{INTRANET_PORT}' = [string]$c.IntranetPort; '{BANNER_PORT}' = [string]$c.BannerPort
    }
    foreach ($k in $map.Keys) { $Text = $Text.Replace($k, [string]$map[$k]) }
    return $Text
}

function Get-LabText {
    param($Value, [switch]$Raw)
    $t = ''
    if ($null -eq $Value) { $t = '' }
    elseif ($Value -is [string]) { $t = $Value }
    else {
        $lang = (Get-LabConfig).Language
        $p = $Value.PSObject.Properties[$lang]
        if (-not $p) { $p = $Value.PSObject.Properties['en'] }
        if ($p) { $t = [string]$p.Value } else { $t = [string]$Value }
    }
    if ($Raw) { return $t }
    return (Expand-LabText $t)
}

function Get-FlagState {
    param([switch]$Reload)
    if ($script:FlagState -and -not $Reload) { return $script:FlagState }
    $s = Read-JsonFile -Path (Get-LabConfig).Paths.FlagState
    if (-not $s) { $s = New-Object psobject }
    $script:FlagState = $s
    return $s
}

function Set-SharedFlagValue {
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Value)
    $s = Get-FlagState -Reload
    $s | Add-Member -NotePropertyName $Id -NotePropertyValue $Value -Force
    $p = (Get-LabConfig).Paths.FlagState
    Write-JsonFile -Path $p -Object $s
    Set-SecureAcl -Path $p
    $script:FlagState = $s
}

function Get-HmacHex {
    param([Parameter(Mandatory)][string]$Message, [int]$Bytes = 4)
    $salt = Get-FlagSalt
    $h = New-Object Security.Cryptography.HMACSHA256(, $salt)
    $hash = $h.ComputeHash([Text.Encoding]::UTF8.GetBytes($Message))
    $h.Dispose()
    return (-join ($hash[0..($Bytes - 1)] | ForEach-Object { $_.ToString('x2') }))
}

function Format-Flag {
    param([Parameter(Mandatory)][string]$Slug, [Parameter(Mandatory)][string]$Hex)
    $prefix = (Get-LabConfig).FlagPrefix
    return ('{0}{{{1}_{2}}}' -f $prefix, $Slug, $Hex)
}

function New-SharedFlag {
    param([Parameter(Mandatory)][string]$Id)
    $ch = Get-Challenge -Id $Id
    if (-not $ch) { throw "Unknown challenge: $Id" }
    $hex = -join ((New-RandomBytes 4) | ForEach-Object { $_.ToString('x2') })
    $v = Format-Flag -Slug $ch.Slug -Hex $hex
    Set-SharedFlagValue -Id $Id -Value $v
    return $v
}

function Get-FlagValue {
    param([Parameter(Mandatory)][string]$Id, [string]$Slot = '')
    $ch = Get-Challenge -Id $Id
    if (-not $ch) { throw "Unknown challenge: $Id" }
    if ($ch.Kind -eq 'shared') {
        $p = (Get-FlagState).PSObject.Properties[$Id]
        if ($p) { return [string]$p.Value }
        return $null
    }
    if ($ch.Kind -ne 'personal') { return $null }
    if ([string]::IsNullOrWhiteSpace($Slot)) { throw "Personal flag $Id needs -Slot" }
    $hex = Get-HmacHex -Message ('{0}|{1}' -f $ch.Id, $Slot.ToLowerInvariant())
    return (Format-Flag -Slug $ch.Slug -Hex $hex)
}

function Get-Canaries {
    $cat = Get-LabCatalog
    return [object[]]$cat.Canaries
}

function Get-CanaryValue {
    param([Parameter(Mandatory)][string]$Id, [string]$Slot = '')
    $can = $null
    foreach ($x in (Get-Canaries)) { if ($x.Id -eq $Id) { $can = $x } }
    if (-not $can) { throw "Unknown canary: $Id" }
    if ($can.Shared) {
        $key = "canary:$Id"
        $p = (Get-FlagState).PSObject.Properties[$key]
        if ($p) { return [string]$p.Value }
        $hex = -join ((New-RandomBytes 4) | ForEach-Object { $_.ToString('x2') })
        $v = Format-Flag -Slug $can.Slug -Hex $hex
        Set-SharedFlagValue -Id $key -Value $v
        return $v
    }
    if ([string]::IsNullOrWhiteSpace($Slot)) { throw "Personal canary $Id needs -Slot" }
    $hex = Get-HmacHex -Message ('canary|{0}|{1}' -f $Id, $Slot.ToLowerInvariant())
    return (Format-Flag -Slug $can.Slug -Hex $hex)
}

function Resolve-Canary {
    param([Parameter(Mandatory)][string]$Value, [Parameter(Mandatory)][string[]]$Slots)
    $v = $Value.Trim()
    foreach ($can in (Get-Canaries)) {
        if ($can.Shared) {
            if ($v -eq (Get-CanaryValue -Id $can.Id)) {
                return [pscustomobject]@{ Id = $can.Id; Owner = $null; Where = (Get-LabText $can.Where); What = (Get-LabText $can.What) }
            }
            continue
        }
        foreach ($s in $Slots) {
            if ($v -eq (Get-CanaryValue -Id $can.Id -Slot $s)) {
                return [pscustomobject]@{ Id = $can.Id; Owner = $s; Where = (Get-LabText $can.Where); What = (Get-LabText $can.What) }
            }
        }
    }
    return $null
}

function Resolve-FlagOwner {
    param([Parameter(Mandatory)][string]$Value, [Parameter(Mandatory)][string[]]$Slots)
    $v = $Value.Trim()
    foreach ($ch in (Get-Challenges)) {
        if ($ch.Kind -eq 'shared') {
            $sv = Get-FlagValue -Id $ch.Id
            if ($sv -and $v -eq $sv) { return [pscustomobject]@{ Id = $ch.Id; Owner = $null; Shared = $true } }
            continue
        }
        if ($ch.Kind -ne 'personal') { continue }
        foreach ($s in $Slots) {
            if ($v -eq (Get-FlagValue -Id $ch.Id -Slot $s)) {
                return [pscustomobject]@{ Id = $ch.Id; Owner = $s; Shared = $false }
            }
        }
    }
    return $null
}

function Get-Students {
    $c = Get-LabConfig
    try {
        $us = Get-ADUser -Filter * -SearchBase $c.OUStudents -SearchScope Subtree `
            -Properties employeeNumber, DisplayName, mail, Enabled, GivenName, Surname -ErrorAction Stop
    } catch { return @() }
    $list = @()
    foreach ($u in @($us)) {
        $slot = [string]$u.employeeNumber
        if ([string]::IsNullOrWhiteSpace($slot)) { $slot = [string]$u.SamAccountName }
        $list += [pscustomobject]@{
            Sam     = [string]$u.SamAccountName
            Slot    = $slot
            Name    = [string]$u.DisplayName
            Mail    = [string]$u.mail
            Enabled = [bool]$u.Enabled
            Sid     = [string]$u.SID.Value
            DN      = [string]$u.DistinguishedName
        }
    }
    return $list
}

function Get-StudentSlot {
    param([Parameter(Mandatory)][string]$Sam)
    foreach ($a in @(Get-Students)) { if ($a.Sam -eq $Sam) { return $a.Slot } }
    return $Sam
}

function Get-NextStudentSlot {
    $c = Get-LabConfig
    $used = @{}
    foreach ($a in @(Get-Students)) { $used[$a.Slot.ToLowerInvariant()] = $true }
    for ($i = 1; $i -le [int]$c.StudentSlots; $i++) {
        $s = ('{0}{1}' -f $c.StudentPrefix, $i).ToLowerInvariant()
        if (-not $used.ContainsKey($s)) { return $s }
    }
    return $null
}

function ConvertTo-UInt32Address {
    param([Parameter(Mandatory)][string]$Ip)
    $b = ([Net.IPAddress]::Parse($Ip)).GetAddressBytes()
    [Array]::Reverse($b)
    return [BitConverter]::ToUInt32($b, 0)
}

function ConvertFrom-UInt32Address {
    param([Parameter(Mandatory)][uint32]$Value)
    $b = [BitConverter]::GetBytes($Value)
    [Array]::Reverse($b)
    return ([Net.IPAddress]$b).ToString()
}

function Get-NetworkCidr {
    param([Parameter(Mandatory)][string]$Ip, [Parameter(Mandatory)][int]$Prefix)
    $v = ConvertTo-UInt32Address $Ip
    $mask = [uint32]0
    if ($Prefix -gt 0) { $mask = [uint32]([uint64]4294967295 -shl (32 - $Prefix) -band [uint64]4294967295) }
    return ('{0}/{1}' -f (ConvertFrom-UInt32Address ($v -band $mask)), $Prefix)
}

function Test-AddressInCidr {
    param([Parameter(Mandatory)][string]$Address, [Parameter(Mandatory)][string]$Cidr)
    $a = $Address -replace '^::ffff:', ''
    $parts = $Cidr.Split('/')
    $prefix = 32
    if ($parts.Count -gt 1) { $prefix = [int]$parts[1] }
    try {
        $net = ConvertTo-UInt32Address $parts[0]
        $ip = ConvertTo-UInt32Address $a
    } catch { return $false }
    $mask = [uint32]0
    if ($prefix -gt 0) { $mask = [uint32]([uint64]4294967295 -shl (32 - $prefix) -band [uint64]4294967295) }
    return (($ip -band $mask) -eq ($net -band $mask))
}

function Get-LanAdapter {
    $c = Get-LabConfig
    if ($c.LanInterface) {
        $a = Get-NetAdapter -Name $c.LanInterface -ErrorAction SilentlyContinue
        if ($a) { return $a }
    }
    $ip = Get-NetIPAddress -AddressFamily IPv4 -IPAddress $c.LanIPAddress -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ip) { return (Get-NetAdapter -InterfaceIndex $ip.InterfaceIndex -ErrorAction SilentlyContinue) }
    $r = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1
    if ($r) {
        $a = Get-NetAdapter -InterfaceIndex $r.InterfaceIndex -ErrorAction SilentlyContinue
        if ($a -and $a.HardwareInterface) { return $a }
    }
    return (Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | Sort-Object ifIndex | Select-Object -First 1)
}

function Get-ModeAddress {
    $c = Get-LabConfig
    switch ($c.NetworkMode) {
        'Tailscale' {
            $ip = Get-NetIPAddress -InterfaceAlias $c.TailscaleInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($ip) { return $ip.IPAddress }
            return $null
        }
        'VPN' {
            $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.InterfaceAlias -like $c.VpnInterface -and $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1
            if ($ip) { return $ip.IPAddress }
            return $null
        }
        default { return [string]$c.LanIPAddress }
    }
}

function Test-Bindable {
    param([Parameter(Mandatory)][string]$Ip)
    try {
        $l = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Parse($Ip), 0)
        $l.Start(); $l.Stop()
        return $true
    } catch { return $false }
}

function Get-ServiceAddress {
    param([int]$TimeoutSeconds = 180, [string]$LogFile)
    $end = (Get-Date).AddSeconds($TimeoutSeconds)
    $warned = $false
    while ($true) {
        $ip = Get-ModeAddress
        if ($ip -and (Test-Bindable $ip)) { return $ip }
        if (-not $warned) {
            Write-LabLog (L ("Esperando la direccion del modo {0}" -f (Get-LabConfig).NetworkMode) ("Waiting for the {0} mode address" -f (Get-LabConfig).NetworkMode)) 'WARN' -File $LogFile
            $warned = $true
        }
        if ((Get-Date) -ge $end) { break }
        Start-Sleep -Seconds 5
    }
    Write-LabLog (L 'No aparecio la direccion de servicio a tiempo' 'The service address did not show up in time') 'ERROR' -File $LogFile
    return $null
}

function Get-ClientCidrs {
    $c = Get-LabConfig
    $list = New-Object System.Collections.Generic.List[string]
    switch ($c.NetworkMode) {
        'Tailscale' { $list.Add('100.64.0.0/10') }
        'VPN'       { if ($c.VpnClientCidr) { $list.Add([string]$c.VpnClientCidr) } }
        default     { $list.Add((Get-NetworkCidr -Ip $c.LanIPAddress -Prefix ([int]$c.LanPrefixLength))) }
    }
    foreach ($x in @($c.ExtraClientCidrs)) { if ($x -and -not $list.Contains([string]$x)) { $list.Add([string]$x) } }
    return $list.ToArray()
}

function Get-PublishedAddresses {
    $c = Get-LabConfig
    $list = New-Object System.Collections.Generic.List[string]
    $list.Add([string]$c.LanIPAddress)
    if ($c.NetworkMode -eq 'Tailscale' -or $c.NetworkMode -eq 'VPN') {
        $m = Get-ModeAddress
        if ($m -and -not $list.Contains($m)) { $list.Add($m) }
    }
    return $list.ToArray()
}

function Register-LabTask {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Execute,
        [string]$Arguments = '',
        [switch]$AtStartup,
        [int]$EveryMinutes = 0,
        [string]$Description = '',
        [switch]$Disabled,
        [switch]$Start
    )
    $act = New-ScheduledTaskAction -Execute $Execute -Argument $Arguments
    $trig = @()
    if ($AtStartup) { $trig += New-ScheduledTaskTrigger -AtStartup }
    if ($EveryMinutes -gt 0) {
        $t = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) -RepetitionInterval (New-TimeSpan -Minutes $EveryMinutes)
        $trig += $t
    }
    $pr = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
        -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
    if (Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $Name -Confirm:$false
    }
    $params = @{ TaskName = $Name; Action = $act; Principal = $pr; Settings = $set; Description = $Description }
    if ($trig.Count -gt 0) { $params.Trigger = $trig }
    Register-ScheduledTask @params | Out-Null
    if ($Disabled) { Disable-ScheduledTask -TaskName $Name | Out-Null }
    elseif ($Start) { Start-ScheduledTask -TaskName $Name }
}

function Get-PowerShellPath {
    return (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
}

function Get-ScriptArguments {
    param([Parameter(Mandatory)][string]$Script, [string]$Extra = '')
    $a = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Script`""
    if ($Extra) { $a = "$a $Extra" }
    return $a
}

function Set-LabFirewallRule {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$Port,
        [ValidateSet('TCP', 'UDP')][string]$Protocol = 'TCP',
        [string[]]$RemoteAddress
    )
    if (-not $RemoteAddress) { $RemoteAddress = Get-ClientCidrs }
    $existing = Get-NetFirewallRule -Name $Name -ErrorAction SilentlyContinue
    if ($existing) { Remove-NetFirewallRule -Name $Name }
    New-NetFirewallRule -Name $Name -DisplayName $Name -Group 'Lab' -Direction Inbound -Action Allow `
        -Protocol $Protocol -LocalPort $Port -RemoteAddress $RemoteAddress -Profile Any | Out-Null
}

Export-ModuleMember -Function Get-LabRoot, Resolve-LabLanguage, L, Get-RussianText, Get-LabConfigPath, Read-DataFile,
    ConvertTo-DistinguishedName, Get-LabConfig, Test-Weakness, Write-LabLog, Add-LabOutput,
    Show-LabOutput, Get-LabOutputText, Test-Administrator, Get-DomainSid, Get-WellKnownSid, Get-PrincipalName,
    New-RandomPassword, New-RandomBytes, New-Folder, Set-SecureAcl, Write-JsonFile, Read-JsonFile,
    Get-LabSecrets, Get-LabSecret, Set-LabSecret, Get-FlagSalt, Add-LabCredential,
    Get-LabCatalog, Get-Challenges, Get-Challenge, Expand-LabText, Get-LabText, Get-FlagState, Set-SharedFlagValue,
    Get-HmacHex, Format-Flag, New-SharedFlag, Get-FlagValue, Get-Canaries, Get-CanaryValue,
    Resolve-Canary, Resolve-FlagOwner, Get-Students, Get-StudentSlot, Get-NextStudentSlot,
    ConvertTo-UInt32Address, ConvertFrom-UInt32Address, Get-NetworkCidr, Test-AddressInCidr, Get-LanAdapter,
    Get-ModeAddress, Test-Bindable, Get-ServiceAddress, Get-ClientCidrs, Get-PublishedAddresses,
    Register-LabTask, Get-PowerShellPath, Get-ScriptArguments, Set-LabFirewallRule
