Set-StrictMode -Off

$script:MailRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $script:MailRoot 'setup\Lab.psm1') -DisableNameChecking -ErrorAction Stop
Import-Module ActiveDirectory -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.DirectoryServices.AccountManagement -ErrorAction SilentlyContinue

$script:DirCache = @{}
$script:DirUntil = [datetime]::MinValue
$script:LocalAddresses = $null

function Get-MailNames {
    $c = Get-LabConfig
    $nl = [string]$c.NamesLanguage
    if (-not $nl) { $nl = [string]$c.Language }
    $label = 'mail'; $validation = 'validation'; $system = 'it'
    if ($nl -eq 'es') { $label = 'correo'; $validation = 'validacion'; $system = 'sistemas' }
    $folder = [string]$c.Names.FolderMail
    if (-not $folder) { $folder = 'Mail' }
    return @{
        Label      = $label
        Host       = "$label.$($c.DomainFqdn)"
        Validation = "$validation@$($c.DomainFqdn)"
        System     = "$system@$($c.DomainFqdn)"
        Folder     = $folder
    }
}

function Get-MailboxPath {
    param([Parameter(Mandatory)][string]$Sam, [string]$Slot, [switch]$Student)
    $c = Get-LabConfig
    if ($Student -and $Slot) {
        $h = Join-Path $c.Paths.Home $Slot
        $own = (Get-MailNames).Folder
        foreach ($x in (@($own, 'Correo', 'Mail') | Select-Object -Unique)) {
            $p = Join-Path $h $x
            if (Test-Path -LiteralPath $p) { return $p }
        }
        return (Join-Path $h $own)
    }
    return (Join-Path $c.Paths.Mail $Sam)
}

function Get-MailDirectory {
    param([switch]$Refresh)
    if (-not $Refresh -and (Get-Date) -lt $script:DirUntil -and $script:DirCache.Count -gt 0) { return $script:DirCache }
    $c = Get-LabConfig
    $map = @{}
    try {
        $users = Get-ADUser -Filter 'Enabled -eq $true' -Properties mail, employeeNumber, DisplayName -ErrorAction Stop
        foreach ($u in @($users)) {
            $slot = [string]$u.employeeNumber
            $isStudent = ([string]$u.DistinguishedName -like "*,$($c.OUStudents)") -and $slot
            $entry = [pscustomobject]@{
                Sam     = [string]$u.SamAccountName
                Name    = [string]$u.DisplayName
                Mailbox = (Get-MailboxPath -Sam $u.SamAccountName -Slot $slot -Student:([bool]$isStudent))
                Student = [bool]$isStudent
                Slot    = $slot
                Sid     = [string]$u.SID.Value
            }
            foreach ($k in @([string]$u.mail, ("{0}@{1}" -f $u.SamAccountName, $c.DomainFqdn))) {
                if ($k) { $map[$k.ToLowerInvariant()] = $entry }
            }
        }
    } catch {
        Write-LabLog ((L 'No se pudo leer el directorio para el correo: ' 'Could not read the directory for mail: ') + $_.Exception.Message) 'WARN' -File (Join-Path $c.Paths.Logs 'mail.log')
    }
    $script:DirCache = $map
    $script:DirUntil = (Get-Date).AddMinutes(1)
    return $map
}

function Resolve-Mailbox {
    param([Parameter(Mandatory)][string]$Address)
    $c = Get-LabConfig
    $d = $Address.Trim().Trim('<', '>').ToLowerInvariant()
    if ($d -notmatch '^[^@\s]+@[^@\s]+$') { return $null }
    if ($d.Split('@')[1] -ne $c.DomainFqdn.ToLowerInvariant()) { return $null }
    $map = Get-MailDirectory
    if ($map.ContainsKey($d)) { return $map[$d] }
    return $null
}

function Test-MailCredential {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$User, [Parameter(Mandatory)][AllowEmptyString()][string]$Password)
    $c = Get-LabConfig
    $u = $User
    if ($u -match '@') { $u = $u.Split('@')[0] }
    if ($u -match '\\') { $u = $u.Split('\')[-1] }
    if ([string]::IsNullOrWhiteSpace($u) -or [string]::IsNullOrEmpty($Password)) { return $null }
    try {
        $ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext([System.DirectoryServices.AccountManagement.ContextType]::Domain, $c.DomainFqdn)
        $ok = $ctx.ValidateCredentials($u, $Password)
        $ctx.Dispose()
        if ($ok) {
            $map = Get-MailDirectory
            $k = ("{0}@{1}" -f $u, $c.DomainFqdn).ToLowerInvariant()
            if ($map.ContainsKey($k)) { return $map[$k] }
        }
    } catch { }
    return $null
}

function Add-MailMessage {
    param(
        [Parameter(Mandatory)]$Recipient,
        [Parameter(Mandatory)][string]$From,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Body,
        [string]$To = '',
        [string]$Raw = ''
    )
    $c = Get-LabConfig
    $inbox = Join-Path $Recipient.Mailbox 'Inbox'
    New-Folder $inbox | Out-Null
    if (-not $To) { $To = "{0}@{1}" -f $Recipient.Sam, $c.DomainFqdn }
    if (-not $Raw) {
        $date = (Get-Date).ToUniversalTime().ToString('r')
        $id = '<{0}@{1}>' -f ([guid]::NewGuid().ToString()), $c.DomainFqdn
        $lines = @("From: $From", "To: $To", "Subject: $Subject", "Date: $date", "Message-ID: $id", 'MIME-Version: 1.0', 'Content-Type: text/plain; charset=utf-8', 'Content-Transfer-Encoding: 8bit', '', $Body)
        $Raw = ($lines -join "`r`n")
    }
    $name = '{0}_{1}.eml' -f (Get-Date -Format 'yyyyMMddHHmmssfff'), ([guid]::NewGuid().ToString().Substring(0, 8))
    $path = Join-Path $inbox $name
    [IO.File]::WriteAllText($path, ($Raw -replace "(?<!`r)`n", "`r`n"), (New-Object Text.UTF8Encoding($false)))
    if (-not $Recipient.Student) { try { Set-SecureAcl -Path $path } catch { } }
    return $path
}

function Get-MailMessages {
    param([Parameter(Mandatory)][string]$Mailbox)
    $inbox = Join-Path $Mailbox 'Inbox'
    if (-not (Test-Path -LiteralPath $inbox)) { return @() }
    return @(Get-ChildItem -LiteralPath $inbox -Filter '*.eml' -File -ErrorAction SilentlyContinue | Sort-Object Name)
}

function Test-MailClient {
    param([Parameter(Mandatory)][Net.IPAddress]$Address)
    $a = $Address
    if ($a.IsIPv4MappedToIPv6) { $a = $a.MapToIPv4() }
    $s = $a.ToString()
    if ($s -eq '127.0.0.1' -or $s -eq '::1') { return $true }
    if (-not $script:LocalAddresses) {
        $script:LocalAddresses = @(Get-NetIPAddress -ErrorAction SilentlyContinue | ForEach-Object { $_.IPAddress })
    }
    if ($script:LocalAddresses -contains $s) { return $true }
    if ($a.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { return $false }
    foreach ($cidr in @(Get-ClientCidrs)) { if (Test-AddressInCidr -Address $s -Cidr $cidr) { return $true } }
    return $false
}

function Send-WelcomeMail {
    param([Parameter(Mandatory)]$Student)
    $c = Get-LabConfig
    $n = Get-MailNames
    $entry = Resolve-Mailbox -Address ("{0}@{1}" -f $Student.Sam, $c.DomainFqdn)
    if (-not $entry) { $null = Get-MailDirectory -Refresh; $entry = Resolve-Mailbox -Address ("{0}@{1}" -f $Student.Sam, $c.DomainFqdn) }
    if (-not $entry) { return $false }
    $marker = L 'Bienvenida al correo de' 'Welcome to the mail of'
    foreach ($m in (Get-MailMessages -Mailbox $entry.Mailbox)) {
        if ([IO.File]::ReadAllText($m.FullName) -match [regex]::Escape($marker)) { return $false }
    }
    $smtp = (@($c.SmtpPorts) -join (L ' o ' ' or '))
    $body = L @"
Hola $($Student.Name):

Tu cuenta de correo de $($c.Organization) ya esta activa.

    Direccion : $($Student.Sam)@$($c.DomainFqdn)
    Servidor  : $($n.Host)
    SMTP      : puerto $smtp, con autenticacion obligatoria
    POP3      : puerto $($c.Pop3Port)

Entras con tu usuario y contrasena del dominio: aqui no hay cuentas de
correo aparte, la identidad del dominio es la unica que existe.

Desde PowerShell tienes Get-LabMail para ver la bandeja, Read-LabMail 1
para leer un mensaje y Send-LabMail para escribir.

Si quieres ver como funciona por dentro, el servidor habla SMTP
estandar: conectate con telnet al puerto 25 y hazlo a mano. Entender el
protocolo vale mas que usar el cliente.

Un aviso: el servidor exige AUTH antes de aceptar nada y comprueba que
el remitente coincida con la cuenta autenticada. No podras escribir en
nombre de otra persona, y eso es deliberado.

--
Departamento de Sistemas
$($c.Organization)
"@ @"
Hello $($Student.Name),

Your $($c.Organization) mailbox is now active.

    Address : $($Student.Sam)@$($c.DomainFqdn)
    Server  : $($n.Host)
    SMTP    : port $smtp, authentication required
    POP3    : port $($c.Pop3Port)

You sign in with your domain user and password: there are no separate
mail accounts here, the domain identity is the only one that exists.

From PowerShell you have Get-LabMail to list the inbox, Read-LabMail 1
to read a message and Send-LabMail to write.

If you want to see how it works inside, the server speaks standard
SMTP: connect with telnet to port 25 and do it by hand. Understanding
the protocol is worth more than using the client.

A warning: the server requires AUTH before accepting anything and
checks that the sender matches the authenticated account. You will not
be able to write on behalf of someone else, and that is deliberate.

--
IT Department
$($c.Organization)
"@
    $null = Add-MailMessage -Recipient $entry -From $n.System -Subject ("{0} {1}" -f $marker, $c.Organization) -Body $body
    return $true
}

function Send-ValidationReply {
    param([Parameter(Mandatory)]$Sender, [string]$LogFile)
    $c = Get-LabConfig
    $n = Get-MailNames
    if (-not $Sender.Student -or -not $Sender.Slot) {
        Write-LabLog (L "El buzon de validacion recibio correo de $($Sender.Sam), que no es alumno. Se ignora." "The validation mailbox got mail from $($Sender.Sam), who is not a student. Ignored.") 'INFO' -File $LogFile
        return $false
    }
    $flag = Get-FlagValue -Id 'D5-OPT2' -Slot $Sender.Slot
    $body = L @"
Buzon validado correctamente.

Hiciste el recorrido completo: te autenticaste contra el servidor,
compusiste un mensaje y lo entregaste por SMTP. Eso es exactamente lo
que hace tu cliente de correo cada vez que presionas Enviar, solo que
sin esconderte los comandos.

Un apunte para tu informe: este servidor exige AUTH y comprueba que el
remitente coincida con la cuenta autenticada. Un servidor que no lo
hiciera permitiria escribir en nombre de la direccion general, y eso es
la mitad de cualquier campana de phishing interno. Tampoco usa TLS:
todo lo que acabas de enviar, contrasena incluida, viajo en claro.

    $flag

--
Sistema de validacion de buzones
$($c.Organization)
"@ @"
Mailbox validated successfully.

You walked the whole path: you authenticated against the server,
composed a message and delivered it over SMTP. That is exactly what
your mail client does every time you press Send, only without hiding
the commands from you.

A note for your report: this server requires AUTH and checks that the
sender matches the authenticated account. A server that did not would
let anyone write as the executive office, and that is half of any
internal phishing campaign. It does not use TLS either: everything you
just sent, password included, traveled in clear text.

    $flag

--
Mailbox validation system
$($c.Organization)
"@
    $null = Add-MailMessage -Recipient $Sender -From $n.Validation -Subject (L 'Buzon validado' 'Mailbox validated') -Body $body
    Write-LabLog (L "Bandera D5-OPT2 entregada a $($Sender.Sam)." "Flag D5-OPT2 delivered to $($Sender.Sam).") 'OK' -File $LogFile
    return $true
}

function Initialize-MailStore {
    $c = Get-LabConfig
    New-Folder $c.Paths.Mail | Out-Null
    Set-SecureAcl -Path $c.Paths.Mail
    $map = Get-MailDirectory -Refresh
    $made = 0
    foreach ($e in ($map.Values | Sort-Object Sam -Unique)) {
        $inbox = Join-Path $e.Mailbox 'Inbox'
        if (-not (Test-Path -LiteralPath $inbox)) {
            if ($e.Student -and -not (Test-Path -LiteralPath (Split-Path -Parent $e.Mailbox))) { continue }
            New-Folder $inbox | Out-Null
            $made++
        }
    }
    $staff = @{}
    for ($i = 0; $i -lt $c.Departments.Count; $i++) {
        try {
            $staff[$i] = @(Get-ADUser -Filter * -SearchBase $c.Departments[$i].OU -SearchScope OneLevel -ErrorAction Stop | Sort-Object SamAccountName)
        } catch { $staff[$i] = @() }
    }
    $pick = {
        param([int]$Dept, [int]$Index)
        $list = @($staff[$Dept])
        if ($list.Count -gt $Index) { return [string]$list[$Index].SamAccountName }
        return $null
    }
    $threads = @(
        @{ To = (& $pick 4 0); From = (& $pick 0 0)
           Subject = (L 'Cierre trimestral' 'Quarterly close')
           Body = (L "Necesito el cierre del trimestre antes del viernes. Sube el borrador al recurso $($c.Shares.Confidential) cuando lo tengas.`n`nGracias." "I need the quarterly close before Friday. Upload the draft to the $($c.Shares.Confidential) share when you have it.`n`nThanks.") }
        @{ To = (& $pick 1 0); From = (& $pick 1 1)
           Subject = (L 'RE: cuentas de servicio' 'RE: service accounts')
           Body = (L "La cuenta svc-web sigue con SPN y con la contrasena de hace dos anos. Eso es justo lo que busca un Kerberoasting: cualquier usuario del dominio puede pedir su ticket y romperlo fuera de linea. Hay que pasarla a una cuenta administrada o rotarla con algo largo." "The svc-web account still has an SPN and a two year old password. That is exactly what Kerberoasting looks for: any domain user can request its ticket and crack it offline. It should move to a managed account or be rotated to something long.") }
        @{ To = (& $pick 3 0); From = (& $pick 0 0)
           Subject = (L 'Altas del mes' 'New hires this month')
           Body = (L 'Entran cuatro personas nuevas el dia 1. Preparales equipo y cuenta.' 'Four new people start on the 1st. Please get their computers and accounts ready.') }
        @{ To = (& $pick 5 0); From = (& $pick 1 0)
           Subject = (L 'Puerto raro en el DC' 'Odd port on the DC')
           Body = (L "Escaneando el controlador aparece abierto el $($c.BannerPort) y nadie sabe de donde sale. No lo toque. Revisalo cuando puedas: un puerto que nadie sabe explicar nunca es buena senal." "Scanning the controller shows $($c.BannerPort) open and nobody knows where it comes from. I did not touch it. Please check it when you can: a port nobody can explain is never a good sign.") }
        @{ To = (& $pick 2 0); From = (& $pick 3 0)
           Subject = (L "Acceso a $($c.Shares.Confidential)" "Access to $($c.Shares.Confidential)")
           Body = (L "No consigo entrar a \\$($c.DcName)\$($c.Shares.Confidential). Me dice que no tengo permiso. Que cuenta hay que usar?" "I cannot get into \\$($c.DcName)\$($c.Shares.Confidential). It says I have no permission. Which account are we supposed to use?") }
    )
    $sent = 0
    foreach ($t in $threads) {
        if (-not $t.To -or -not $t.From) { continue }
        $entry = $map[("{0}@{1}" -f $t.To, $c.DomainFqdn).ToLowerInvariant()]
        if (-not $entry) { continue }
        $dup = $false
        foreach ($m in (Get-MailMessages -Mailbox $entry.Mailbox)) {
            if ([IO.File]::ReadAllText($m.FullName) -match [regex]::Escape("Subject: $($t.Subject)")) { $dup = $true; break }
        }
        if ($dup) { continue }
        $null = Add-MailMessage -Recipient $entry -From ("{0}@{1}" -f $t.From, $c.DomainFqdn) -Subject $t.Subject -Body $t.Body
        $sent++
    }
    return [pscustomobject]@{ Mailboxes = $made; Threads = $sent; Addresses = $map.Count }
}

Export-ModuleMember -Function Get-MailNames, Get-MailboxPath, Get-MailDirectory, Resolve-Mailbox, Test-MailCredential, Add-MailMessage,
    Get-MailMessages, Test-MailClient, Send-WelcomeMail, Send-ValidationReply, Initialize-MailStore
