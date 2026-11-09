Set-StrictMode -Off

$script:Info = $null
$script:InfoPath = Join-Path $PSScriptRoot 'lab.json'
if (Test-Path -LiteralPath $script:InfoPath) {
    try {
        $t = [IO.File]::ReadAllText($script:InfoPath)
        if ($t.Length -gt 0 -and $t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }
        $script:Info = $t | ConvertFrom-Json
    } catch { $script:Info = $null }
}

$script:RuExact = $null
$script:RuPatterns = $null
function Get-RuText {
    param([AllowEmptyString()][string]$En)
    if (-not $En) { return $En }
    if ($null -eq $script:RuExact) {
        $script:RuExact = New-Object 'System.Collections.Generic.Dictionary[string,string]'
        $script:RuPatterns = New-Object System.Collections.Generic.List[object]
        $found = @()
        foreach ($p in @((Join-Path $PSScriptRoot 'ru.json'), (Join-Path (Split-Path -Parent $PSScriptRoot) 'lang\ru.json'))) {
            if (-not (Test-Path -LiteralPath $p)) { continue }
            try { $data = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { continue }
            foreach ($pair in @($data.messages)) {
                $k = [string]$pair[0]
                $v = [string]$pair[1]
                if (-not $k -or -not $v -or $script:RuExact.ContainsKey($k)) { continue }
                $script:RuExact[$k] = $v
                if (-not $k.Contains('[[')) { continue }
                $rx = New-Object Text.StringBuilder
                $order = @()
                $literal = ''
                foreach ($part in [regex]::Split($k, '(\[\[\d+\]\])')) {
                    if ($part -match '^\[\[\d+\]\]$') { [void]$rx.Append('(.*?)'); $order += $part }
                    else { [void]$rx.Append([regex]::Escape($part)); $literal += $part }
                }
                $weight = ($literal -replace '[^A-Za-z]', '').Length
                if ($weight -lt 2) { continue }
                $re = New-Object Text.RegularExpressions.Regex -ArgumentList @(('^' + $rx.ToString() + '$'), [Text.RegularExpressions.RegexOptions]::Singleline)
                $found += [pscustomobject]@{ Regex = $re; Order = $order; Ru = $v; Weight = $weight }
            }
            break
        }
        foreach ($f in @($found | Sort-Object Weight -Descending)) { $script:RuPatterns.Add($f) }
    }
    $v = $null
    if ($script:RuExact.TryGetValue($En, [ref]$v)) { return $v }
    foreach ($p in $script:RuPatterns) {
        $m = $p.Regex.Match($En)
        if (-not $m.Success) { continue }
        $out = $p.Ru
        for ($i = 0; $i -lt $p.Order.Count; $i++) { $out = $out.Replace($p.Order[$i], $m.Groups[$i + 1].Value) }
        return $out
    }
    return $En
}

function T {
    param([string]$Es, [string]$En)
    $lang = [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
    if ($script:Info -and $script:Info.Language) { $lang = [string]$script:Info.Language }
    if ($lang -eq 'es') { return $Es }
    if ($lang -eq 'ru') { return (Get-RuText $En) }
    return $En
}

function Get-LabServer {
    if ($script:Info -and $script:Info.DcFqdn) { return [string]$script:Info.DcFqdn }
    $d = $env:USERDNSDOMAIN
    if ($d) {
        try {
            $srv = Resolve-DnsName "_ldap._tcp.dc._msdcs.$d" -Type SRV -ErrorAction Stop | Where-Object { $_.NameTarget } | Select-Object -First 1
            if ($srv) { return [string]$srv.NameTarget }
        } catch { }
    }
    return $env:LOGONSERVER.TrimStart('\')
}

function Get-LabShare {
    param([ValidateSet('Home', 'Public', 'Dropbox', 'Confidential')][string]$Kind)
    $name = $Kind
    if ($script:Info -and $script:Info.Shares) { $name = [string]$script:Info.Shares.$Kind }
    return ("\\{0}\{1}" -f (Get-LabServer), $name)
}

function Write-Box {
    param([string[]]$Lines, [string]$Color = 'Gray')
    Write-Host ''
    foreach ($l in $Lines) { Write-Host "  $l" -ForegroundColor $Color }
    Write-Host ''
}

function Submit-Flag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)][string]$Flag,
        [string]$Comment = ''
    )
    process {
        $f = $Flag.Trim()
        $prefix = 'FLAG'
        if ($script:Info -and $script:Info.FlagPrefix) { $prefix = [string]$script:Info.FlagPrefix }
        if ($f -notmatch ('^' + [regex]::Escape($prefix) + '\{.+\}$')) {
            Write-Box @((T 'Eso no tiene forma de bandera.' 'That does not look like a flag.'), (T "El formato es $prefix{...}, con las llaves incluidas." "The format is $prefix{...}, braces included.")) 'Yellow'
            return
        }
        $entry = [ordered]@{ Bandera = $f; Usuario = $env:USERNAME; Equipo = $env:COMPUTERNAME; Momento = (Get-Date).ToString('o'); Comentario = $Comment }
        $name = '{0}_{1}_{2}.json' -f (Get-Date -Format 'yyyyMMddHHmmssfff'), $env:USERNAME, ([guid]::NewGuid().ToString().Substring(0, 8))
        $path = ((Get-LabShare -Kind Dropbox) + '\' + $name)
        try {
            [IO.File]::WriteAllText($path, ($entry | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
        } catch {
            Write-Box @((T 'No se pudo dejar la entrega en el servidor.' 'The submission could not be dropped on the server.'), $_.Exception.Message, (T "Comprueba que llegas al dominio: Test-NetConnection $(Get-LabServer) -Port 445" "Check that you can reach the domain: Test-NetConnection $(Get-LabServer) -Port 445")) 'Red'
            return
        }
        Write-Box @((T 'Bandera entregada.' 'Flag submitted.'), $f, (T 'El corrector pasa cada minuto. Revisa el resultado con Get-Progress.' 'The grader runs every minute. Check the result with Get-Progress.')) 'Green'
    }
}

function Get-ProgressFile {
    foreach ($p in @('H:\.progreso.json', (((Get-LabShare -Kind Home) + '\' + "$env:USERNAME\.progreso.json")))) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Get-Progress {
    [CmdletBinding()]
    param([switch]$Detail)
    $f = Get-ProgressFile
    if (-not $f) {
        Write-Box @((T 'Todavia no hay progreso registrado.' 'No progress recorded yet.'), (T 'Entrega tu primera bandera y espera un minuto.' 'Submit your first flag and wait a minute.')) 'Yellow'
        return
    }
    $p = [IO.File]::ReadAllText($f) | ConvertFrom-Json
    $out = New-Object System.Collections.Generic.List[object]
    $out.Add(@([string]$p.Nombre, 'Cyan'))
    $out.Add(@((T "Puntos    : $($p.Puntos) de $($p.PuntosPosibles)" "Points    : $($p.Puntos) of $($p.PuntosPosibles)"), 'White'))
    $out.Add(@((T "Retos     : $($p.Resueltos) de $($p.Total)" "Challenges: $($p.Resueltos) of $($p.Total)"), 'Gray'))
    $out.Add(@((T "Posicion  : $($p.Posicion)" "Position  : $($p.Posicion)"), 'Gray'))
    if ([int]$p.Copias -gt 0) { $out.Add(@((T "Copias    : $($p.Copias), banderas de otra persona" "Copies    : $($p.Copias), flags from someone else"), 'Red')) }
    $early = @($p.Adelantadas | Where-Object { $_ } | Sort-Object Reto -Unique)
    if ($early.Count -gt 0) {
        $out.Add(@((T "Entregaste $($early.Count) bandera(s) antes de que abriera su dia; vuelve a entregarlas ahora." "You submitted $($early.Count) flag(s) before their day opened; submit them again now."), 'DarkYellow'))
    }
    $days = @($p.Retos | ForEach-Object { [int]$_.Dia } | Sort-Object -Unique)
    foreach ($d in $days) {
        $rd = @($p.Retos | Where-Object { [int]$_.Dia -eq $d })
        $ok = @($rd | Where-Object { $_.Resuelto })
        $col = 'DarkGray'
        if ($ok.Count -eq $rd.Count) { $col = 'Green' } elseif ($ok.Count -gt 0) { $col = 'Yellow' }
        $closed = ''
        if (@($rd | Where-Object { -not $_.Abierto }).Count -eq $rd.Count) { $closed = T '   cerrado' '   closed' }
        $out.Add(@((T 'Dia' 'Day') + (" {0}  [{1}{2}]  {3}/{4}{5}" -f $d, ('#' * $ok.Count), ('.' * ($rd.Count - $ok.Count)), $ok.Count, $rd.Count, $closed), $col))
        if ($Detail) {
            foreach ($r in $rd) {
                $mark = '.'; $c = 'DarkGray'
                if ($r.Resuelto) { $mark = 'x'; $c = 'Green' }
                $opt = ''
                if ($r.Opcional) { $opt = T '  (opcional)' '  (optional)' }
                $out.Add(@(("   [{0}] {1,-9} {2,-40} {3,3} pts{4}" -f $mark, $r.Id, $r.Titulo, $r.Puntos, $opt), $c))
            }
        }
    }
    if ($script:Info -and $script:Info.WebUrl) { $out.Add(@(((T 'Tabla completa: ' 'Full scoreboard: ') + $script:Info.WebUrl), 'DarkGray')) }
    Write-Host ''
    foreach ($o in $out) { Write-Host "  $($o[0])" -ForegroundColor $o[1] }
    Write-Host ''
}

function Get-DayOpening {
    param([int]$Day)
    $f = ((Get-LabShare -Kind Public) + '\' + 'calendario.json')
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try {
        $cal = [IO.File]::ReadAllText($f) | ConvertFrom-Json
        $d = $cal.Dias.PSObject.Properties[[string]$Day]
        if (-not $d) { return $null }
        return [datetime]::Parse([string]$d.Value.Apertura, [Globalization.CultureInfo]::InvariantCulture)
    } catch { return $null }
}

function Get-Challenges {
    [CmdletBinding()]
    param([Parameter(Position = 0)][int]$Day = 0, [switch]$Hints)
    $f = ((Get-LabShare -Kind Public) + '\' + 'retos.json')
    if (-not (Test-Path -LiteralPath $f)) { Write-Box @(T 'No se encontro el catalogo de retos en el recurso publico.' 'The challenge catalog was not found on the public share.') 'Yellow'; return }
    $list = @([IO.File]::ReadAllText($f) | ConvertFrom-Json)
    if ($Day -gt 0) { $list = @($list | Where-Object { [int]$_.Dia -eq $Day }) }
    Write-Host ''
    $cur = -1
    foreach ($r in $list) {
        if ([int]$r.Dia -ne $cur) {
            $cur = [int]$r.Dia
            $ap = Get-DayOpening -Day $cur
            Write-Host ''
            if ($null -ne $ap -and (Get-Date) -lt $ap) { Write-Host ((T '  DIA ' '  DAY ') + "$cur   " + (T 'abre el ' 'opens on ') + $ap.ToString('yyyy-MM-dd HH:mm')) -ForegroundColor DarkYellow }
            else { Write-Host ((T '  DIA ' '  DAY ') + $cur) -ForegroundColor Cyan }
        }
        $opt = ''
        if ($r.Opcional) { $opt = T '  (opcional)' '  (optional)' }
        Write-Host ("  {0,-9} {1,-42} {2,3} pts{3}" -f $r.Id, $r.Titulo, $r.Puntos, $opt)
        if ($Hints -and $r.Pista) { Write-Host ("            {0}" -f $r.Pista) -ForegroundColor DarkGray }
    }
    Write-Host ''
    Write-Host (T '  Get-Hint D2-03 te da la siguiente pista de ese reto. No resta puntos.' '  Get-Hint D2-03 gives you the next hint for that challenge. It costs no points.') -ForegroundColor DarkGray
    Write-Host ''
}

function Get-Hint {
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$Challenge, [ValidateRange(1, 3)][int]$Level = 0)
    $id = $Challenge.Trim().ToUpperInvariant()
    $f = ((Get-LabShare -Kind Public) + '\' + 'pistas.json')
    if (-not (Test-Path -LiteralPath $f)) { Write-Box @(T 'No se encontro el archivo de pistas.' 'The hint file was not found.') 'Yellow'; return }
    $h = [IO.File]::ReadAllText($f) | ConvertFrom-Json
    $entry = $h.Retos.PSObject.Properties[$id]
    if (-not $entry) { Write-Box @((T "No hay ningun reto llamado $id." "There is no challenge called $id."), (T 'Revisa los identificadores con Get-Challenges.' 'Check the identifiers with Get-Challenges.')) 'Yellow'; return }
    $cat = ((Get-LabShare -Kind Public) + '\' + 'retos.json')
    if (Test-Path -LiteralPath $cat) {
        $def = @([IO.File]::ReadAllText($cat) | ConvertFrom-Json) | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        if ($def) {
            $ap = Get-DayOpening -Day ([int]$def.Dia)
            if ($null -ne $ap -and (Get-Date) -lt $ap) { Write-Box @((T "El dia $($def.Dia) todavia no abre. Abre el " "Day $($def.Dia) is not open yet. It opens on ") + $ap.ToString('yyyy-MM-dd HH:mm')) 'Yellow'; return }
        }
    }
    $reg = 'H:\.pistas.json'
    $used = @{}
    if (Test-Path -LiteralPath $reg) {
        try { foreach ($p in ([IO.File]::ReadAllText($reg) | ConvertFrom-Json).PSObject.Properties) { $used[$p.Name] = [int]$p.Value } } catch { }
    }
    $prev = 0
    if ($used.ContainsKey($id)) { $prev = $used[$id] }
    $n = $prev + 1
    if ($Level -gt 0) { $n = $Level }
    $lines = @()
    if ($n -gt 3) {
        $n = 3
        $lines += (T "Ya viste las tres pistas de $id. La cuarta seria la respuesta y esa no se da." "You have already seen all three hints for $id. The fourth would be the answer, and that is not given.")
    }
    $names = @{ 1 = (T 'RUMBO' 'DIRECTION'); 2 = (T 'HERRAMIENTA' 'TOOL'); 3 = (T 'SINTAXIS' 'SYNTAX') }
    $lines += ("{0}   {1} {2}/3   {3}" -f $id, (T 'pista' 'hint'), $n, $names[$n])
    $lines += [string]$entry.Value.PSObject.Properties[[string]$n].Value
    Write-Box $lines 'Cyan'
    if ($n -gt $prev) {
        $used[$id] = $n
        try {
            if (Test-Path -LiteralPath $reg) { (Get-Item -LiteralPath $reg -Force).Attributes = 'Normal' }
            [IO.File]::WriteAllText($reg, ($used | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
            (Get-Item -LiteralPath $reg -Force).Attributes = 'Hidden'
        } catch { }
    }
}

function Get-Inbox {
    $names = @('Correo', 'Mail')
    if ($script:Info -and $script:Info.Folders -and $script:Info.Folders.Mail) { $names = @([string]$script:Info.Folders.Mail) + $names }
    foreach ($n in ($names | Select-Object -Unique)) {
        $p = "H:\$n\Inbox"
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Get-LabMail {
    [CmdletBinding()]
    param([int]$Last = 20)
    $inbox = Get-Inbox
    if (-not $inbox) { Write-Box @((T 'No encuentro tu buzon.' 'Your mailbox was not found.'), (T 'Comprueba que tienes la unidad H: conectada.' 'Check that your H: drive is connected.')) 'Yellow'; return }
    $msgs = @(Get-ChildItem -LiteralPath $inbox -Filter '*.eml' -File | Sort-Object Name -Descending | Select-Object -First $Last)
    if ($msgs.Count -eq 0) { Write-Box @(T 'Bandeja vacia.' 'Inbox empty.'); return }
    Write-Host ''
    Write-Host ((T '  Bandeja de ' '  Inbox of ') + "$env:USERNAME ($($msgs.Count))") -ForegroundColor Cyan
    $i = 0
    foreach ($m in $msgs) {
        $i++
        $parts = Get-MailParts ([IO.File]::ReadAllText($m.FullName))
        $from = '?'; $subj = '?'
        if ($parts.From) { $from = $parts.From }
        if ($parts.Subject) { $subj = $parts.Subject }
        Write-Host ("  {0,2}. {1,-34} {2}" -f $i, $from, $subj)
    }
    Write-Host ''
    Write-Host (T '  Read-LabMail <numero> para leer uno.' '  Read-LabMail <number> to read one.') -ForegroundColor DarkGray
    Write-Host ''
}

function ConvertFrom-EncodedWord {
    param([AllowEmptyString()][string]$Text)
    if (-not $Text -or $Text -notmatch '=\?') { return $Text }
    $Text = [regex]::Replace($Text, '(\?=)\s+(=\?)', '$1$2')
    return [regex]::Replace($Text, '=\?([^?]+)\?([BbQq])\?([^?]*)\?=', {
        param($m)
        try {
            $enc = [Text.Encoding]::GetEncoding($m.Groups[1].Value)
            if ($m.Groups[2].Value -eq 'B' -or $m.Groups[2].Value -eq 'b') { return $enc.GetString([Convert]::FromBase64String($m.Groups[3].Value)) }
            return (ConvertFrom-QuotedPrintable $m.Groups[3].Value.Replace('_', ' ') $enc)
        } catch { return $m.Value }
    })
}

function ConvertFrom-QuotedPrintable {
    param([AllowEmptyString()][string]$Text, [Text.Encoding]$Encoding)
    $Text = $Text -replace "=\r?\n", ''
    $bytes = New-Object System.Collections.Generic.List[byte]
    for ($i = 0; $i -lt $Text.Length; $i++) {
        if ($Text[$i] -eq '=' -and $i + 2 -lt $Text.Length -and $Text.Substring($i + 1, 2) -match '^[0-9A-Fa-f]{2}$') { $bytes.Add([Convert]::ToByte($Text.Substring($i + 1, 2), 16)); $i += 2 }
        else { foreach ($b in $Encoding.GetBytes([string]$Text[$i])) { $bytes.Add($b) } }
    }
    return $Encoding.GetString($bytes.ToArray())
}

function Get-MailParts {
    param([Parameter(Mandatory)][string]$Raw)
    $split = [regex]::Match($Raw, "\r?\n\r?\n")
    $head = $Raw; $body = ''
    if ($split.Success) { $head = $Raw.Substring(0, $split.Index); $body = $Raw.Substring($split.Index + $split.Length) }
    $head = [regex]::Replace($head, "\r?\n[ \t]+", ' ')
    $headers = @($head -split "\r?\n" | ForEach-Object { ConvertFrom-EncodedWord $_ })
    $charset = 'utf-8'
    if ($head -match '(?i)charset="?([A-Za-z0-9_\-]+)') { $charset = $Matches[1] }
    try { $enc = [Text.Encoding]::GetEncoding($charset) } catch { $enc = [Text.Encoding]::UTF8 }
    if ($head -match '(?im)^Content-Transfer-Encoding:\s*base64') {
        try { $body = $enc.GetString([Convert]::FromBase64String(($body -replace '\s', ''))) } catch { }
    } elseif ($head -match '(?im)^Content-Transfer-Encoding:\s*quoted-printable') {
        $body = ConvertFrom-QuotedPrintable $body $enc
    }
    $get = { param($name) foreach ($h in $headers) { if ($h -match "^(?i)$($name):\s*(.*)$") { return $Matches[1].Trim() } }; return '' }
    return [pscustomobject]@{ Headers = $headers; Body = $body; From = (& $get 'From'); Subject = (& $get 'Subject') }
}

function Read-LabMail {
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][int]$Number)
    $inbox = Get-Inbox
    if (-not $inbox) { Write-Box @(T 'No encuentro tu buzon.' 'Your mailbox was not found.') 'Yellow'; return }
    $msgs = @(Get-ChildItem -LiteralPath $inbox -Filter '*.eml' -File | Sort-Object Name -Descending)
    if ($Number -lt 1 -or $Number -gt $msgs.Count) { Write-Box @(T "No existe el mensaje $Number." "Message $Number does not exist.") 'Yellow'; return }
    Write-Host ''
    $parts = Get-MailParts ([IO.File]::ReadAllText($msgs[$Number - 1].FullName))
    foreach ($l in $parts.Headers) {
        if ($l -match '^(From|To|Subject|Date):') { Write-Host $l -ForegroundColor Cyan } else { Write-Host $l }
    }
    Write-Host ''
    foreach ($l in ($parts.Body -split "`r?`n")) { Write-Host $l }
    Write-Host ''
}

function Send-LabMail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$To,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$Body,
        [Management.Automation.PSCredential]$Credential
    )
    $domain = $env:USERDNSDOMAIN
    if ($script:Info -and $script:Info.Domain) { $domain = [string]$script:Info.Domain }
    $domain = $domain.ToLowerInvariant()
    $server = "mail.$domain"
    $port = 587
    if ($script:Info -and $script:Info.MailHost) { $server = [string]$script:Info.MailHost }
    if ($script:Info -and $script:Info.SmtpPort) { $port = [int]$script:Info.SmtpPort }
    if (-not $Credential) { $Credential = Get-Credential -UserName "$env:USERNAME@$domain" -Message (T 'Tu contrasena del dominio: el servidor exige AUTH' 'Your domain password: the server requires AUTH') }
    if (-not $Credential) { return }
    try {
        $smtp = New-Object Net.Mail.SmtpClient($server, $port)
        $smtp.EnableSsl = $false
        $smtp.Credentials = New-Object Net.NetworkCredential($Credential.UserName.Split('@')[0], $Credential.GetNetworkCredential().Password)
        $msg = New-Object Net.Mail.MailMessage("$env:USERNAME@$domain", $To, $Subject, $Body)
        $msg.BodyEncoding = [Text.Encoding]::UTF8
        $msg.SubjectEncoding = [Text.Encoding]::UTF8
        $msg.HeadersEncoding = [Text.Encoding]::UTF8
        $msg.BodyTransferEncoding = [Net.Mime.TransferEncoding]::EightBit
        $smtp.Send($msg)
        Write-Box @((T "Enviado a $To." "Sent to $To.")) 'Green'
    } catch {
        Write-Box @((T 'No se pudo enviar.' 'Could not send.'), $_.Exception.Message, (T "Comprueba que llegas: Test-NetConnection $server -Port $port" "Check that you can reach it: Test-NetConnection $server -Port $port")) 'Red'
    }
}

try {
    $src = Join-Path ("\\{0}\{1}\module" -f (Get-LabServer), $(if ($script:Info -and $script:Info.KitShare) { $script:Info.KitShare } else { 'LabKit' })) 'Student.psm1'
    $here = $PSCommandPath
    if ($here -and (Test-Path -LiteralPath $src)) {
        $o = Get-Item -LiteralPath $src -ErrorAction Stop
        $l = Get-Item -LiteralPath $here -ErrorAction Stop
        if ($o.LastWriteTimeUtc -gt $l.LastWriteTimeUtc) {
            Copy-Item -LiteralPath $o.FullName -Destination $here -Force -ErrorAction Stop
            $j = Join-Path (Split-Path -Parent $src) 'lab.json'
            if (Test-Path -LiteralPath $j) { Copy-Item -LiteralPath $j -Destination $script:InfoPath -Force -ErrorAction SilentlyContinue }
            Write-Host (T '  El modulo del laboratorio se actualizo. Abre otra ventana para usar la version nueva.' '  The lab module was updated. Open a new window to use the new version.') -ForegroundColor DarkCyan
        }
    }
} catch { }

Set-Alias -Name submit -Value Submit-Flag
Set-Alias -Name progress -Value Get-Progress
Set-Alias -Name progreso -Value Get-Progress
Set-Alias -Name hint -Value Get-Hint
Set-Alias -Name pista -Value Get-Hint
Set-Alias -Name mail -Value Get-LabMail
Set-Alias -Name correo -Value Get-LabMail

Export-ModuleMember -Function Submit-Flag, Get-Progress, Get-Challenges, Get-Hint, Get-DayOpening, Get-LabMail, Read-LabMail, Send-LabMail -Alias submit, progress, progreso, hint, pista, mail, correo
