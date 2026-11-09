[CmdletBinding()]
param([switch]$Rebuild, [switch]$NoShow)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'setup\Lab.psm1') -DisableNameChecking
Import-Module (Join-Path $root 'engine\Challenges.psm1') -DisableNameChecking
Import-Module ActiveDirectory -ErrorAction SilentlyContinue

$c = Get-LabConfig
$LOG = Join-Path $c.Paths.Logs 'scorer.log'
$DbFile = Join-Path $c.Paths.Score 'db.json'
$cat = Get-LabCatalog
$BONUS_FIRST = 5; $BONUS_DAY = 25; $PENALTY_COPY = 10
if ($cat.Scoring) {
    if ($cat.Scoring.FirstBlood) { $BONUS_FIRST = [int]$cat.Scoring.FirstBlood }
    if ($cat.Scoring.DayComplete) { $BONUS_DAY = [int]$cat.Scoring.DayComplete }
    if ($cat.Scoring.CopyPenalty) { $PENALTY_COPY = [int]$cat.Scoring.CopyPenalty }
}
$BAIT = @($cat.Canaries | Where-Object { $_.Bait } | ForEach-Object { $_.Id })

function Log { param([string]$Es, [string]$En, [string]$Level = 'INFO') Write-LabLog (L $Es $En) $Level -File $LOG }

function Test-NoFirstBlood { param([string]$Slot) return ($Slot -match '^(ensayo|practice|rehearsal)-') }

function New-EmptyDb {
    [pscustomobject]@{ Actualizado = $null; Alumnos = [pscustomobject]@{}; PrimerasSangres = [pscustomobject]@{}; Eventos = @() }
}

function Get-Db {
    if ($Rebuild -or -not (Test-Path -LiteralPath $DbFile)) { return (New-EmptyDb) }
    $reason = ''
    try { return (Read-JsonFile -Path $DbFile) }
    catch {
        $reason = ("$($_.Exception.Message)" -split "`r?`n")[0]
        if ($reason.Length -gt 200) { $reason = $reason.Substring(0, 200) }
    }
    Log "db.json ilegible: $reason" "db.json unreadable: $reason" 'ERROR'
    foreach ($i in 1..5) {
        $copy = "$DbFile.$i"
        if (-not (Test-Path -LiteralPath $copy)) { continue }
        try {
            $d = Read-JsonFile -Path $copy
            Log "Recuperada la copia $copy. Revisa que no falten entregas." "Recovered backup $copy. Check that no submissions are missing." 'WARN'
            return $d
        } catch { }
    }
    Log 'No hay copia legible. Se aborta para no perder la puntuacion. Rehazla con Invoke-Scorer.ps1 -Rebuild.' 'No readable backup. Aborting so the scores are not lost. Rebuild with Invoke-Scorer.ps1 -Rebuild.' 'ERROR'
    throw 'db.json'
}

function Save-Db {
    param($Data)
    $tmp = "$DbFile.tmp"
    Write-JsonFile -Path $tmp -Object $Data -Depth 8
    try { $null = Read-JsonFile -Path $tmp }
    catch {
        Log "El volcado salio ilegible; db.json no se toca: $($_.Exception.Message)" "The dump came out unreadable; db.json is left as is: $($_.Exception.Message)" 'ERROR'
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        return
    }
    $good = $false
    if (Test-Path -LiteralPath $DbFile) { try { $null = Read-JsonFile -Path $DbFile; $good = $true } catch { } }
    if ($good) {
        for ($i = 5; $i -gt 1; $i--) {
            $old = "$DbFile.$($i - 1)"
            if (Test-Path -LiteralPath $old) { Move-Item -LiteralPath $old -Destination "$DbFile.$i" -Force -ErrorAction SilentlyContinue }
        }
        Copy-Item -LiteralPath $DbFile -Destination "$DbFile.1" -Force -ErrorAction SilentlyContinue
    }
    Move-Item -LiteralPath $tmp -Destination $DbFile -Force
}

function Set-Prop {
    param($Obj, [string]$Name, $Value)
    if ($Obj.PSObject.Properties[$Name]) { $Obj.$Name = $Value }
    else { $Obj | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Has-Prop { param($Obj, [string]$Name) return [bool]($Obj -and $Obj.PSObject.Properties[$Name]) }

function Add-Event {
    param($Data, [string]$Type, [string]$Who, [string]$Text)
    $e = [pscustomobject]@{ Momento = (Get-Date).ToString('o'); Tipo = $Type; Alumno = $Who; Texto = $Text }
    $Data.Eventos = @(@($e) + @($Data.Eventos) | Select-Object -First 200)
}

function Invoke-Pass {
    $db = Get-Db
    $challenges = @(Get-Challenges)
    $byId = @{}
    foreach ($ch in $challenges) { $byId[$ch.Id] = $ch }
    $students = @(Get-Students)
    if ($students.Count -eq 0) { Log 'No hay alumnos en el directorio.' 'There are no students in the directory.' 'WARN'; return }
    $slots = @($students | ForEach-Object { $_.Slot })

    foreach ($a in $students) {
        if (-not (Has-Prop $db.Alumnos $a.Slot)) {
            Set-Prop $db.Alumnos $a.Slot ([pscustomobject]@{
                Slot = $a.Slot; Sam = $a.Sam; Nombre = $a.Name; Correo = $a.Mail
                Resueltos = [pscustomobject]@{}; Copias = @(); Fallos = 0; Puntos = 0; Bonos = 0; Penas = 0
            })
        }
        $f = $db.Alumnos.($a.Slot)
        $f.Sam = $a.Sam; $f.Nombre = $a.Name; $f.Correo = $a.Mail
    }

    $processed = Join-Path $c.Paths.Score 'processed'
    $dropWeb = Join-Path $c.Paths.Score 'drop-web'
    New-Folder $processed | Out-Null
    New-Folder $dropWeb | Out-Null
    $items = @(
        @(Get-ChildItem -LiteralPath $c.Paths.Dropbox -Filter '*.json' -File -ErrorAction SilentlyContinue) +
        @(Get-ChildItem -LiteralPath $dropWeb -Filter '*.json' -File -ErrorAction SilentlyContinue)
    ) | Sort-Object CreationTimeUtc

    foreach ($e in $items) {
        try {
            $viaWeb = ($e.DirectoryName -eq $dropWeb)
            $json = Read-JsonFile -Path $e.FullName
            if ($viaWeb) {
                $realSam = [string]$json.Usuario
                $owner = "web:$realSam"
            } else {
                $owner = (Get-Acl -LiteralPath $e.FullName).Owner
                $realSam = $owner.Split('\')[-1]
            }
            $slot = $null
            foreach ($a in $students) { if ($a.Sam -eq $realSam) { $slot = $a.Slot; break } }
            if (-not $slot) {
                Log "Entrega de '$owner', que no es alumno. Se descarta: $($e.Name)" "Submission from '$owner', who is not a student. Discarded: $($e.Name)" 'WARN'
                Move-Item -LiteralPath $e.FullName -Destination (Join-Path $processed $e.Name) -Force
                continue
            }
            $value = ([string]$json.Bandera).Trim()
            $card = $db.Alumnos.$slot
            if (-not (Has-Prop $card 'Bitacora')) { Set-Prop $card 'Bitacora' @() }
            $via = 'smb'
            if ($viaWeb) { $via = 'web' }
            $entry = [pscustomobject]@{
                Momento = (Get-Date).ToString('o'); Cadena = $value; Equipo = [string]$json.Equipo
                Declarado = [string]$json.Usuario; Real = $realSam; Via = $via; Comentario = [string]$json.Comentario; Resultado = 'pendiente'
            }

            $can = Resolve-Canary -Value $value -Slots $slots
            if ($can) {
                if (-not (Has-Prop $card 'Alertas')) { Set-Prop $card 'Alertas' @() }
                $card.Alertas = @(@($card.Alertas) + @([pscustomobject]@{
                    Momento = (Get-Date).ToString('o'); Tipo = 'CANARIO'; Canario = $can.Id; Donde = (Expand-EngineText ([string]$can.Where))
                    DuenyoDelFichero = $can.Owner; Equipo = [string]$json.Equipo }))
                $entry.Resultado = "CANARIO $($can.Id)"
                $card.Bitacora = @(@($card.Bitacora) + @($entry) | Select-Object -Last 200)
                $whose = L 'suyo' 'their own'
                if ($can.Owner -and $can.Owner -ne $slot) { $whose = L "del kit de $($can.Owner)" "from the kit of $($can.Owner)" }
                Add-Event $db 'ALERTA' $realSam (L "entrego un CANARIO ($($can.Id), $whose). Esa cadena no resuelve ningun reto." "submitted a CANARY ($($can.Id), $whose). That string solves no challenge.")
                $origin = Expand-EngineText ([string]$can.Where)
                Log "CANARIO: $realSam entrego $($can.Id) ($whose). Origen: $origin" "CANARY: $realSam submitted $($can.Id) ($whose). Origin: $origin" 'ERROR'
                Move-Item -LiteralPath $e.FullName -Destination (Join-Path $processed $e.Name) -Force
                continue
            }

            $res = Resolve-FlagOwner -Value $value -Slots $slots
            if (-not $res) {
                $card.Fallos = [int]$card.Fallos + 1
                $entry.Resultado = L 'no corresponde a ningun reto' 'matches no challenge'
            }
            elseif ((-not $res.Shared) -and ($res.Owner -ne $slot)) {
                $card.Copias = @(@($card.Copias) + @([pscustomobject]@{ Momento = (Get-Date).ToString('o'); Reto = $res.Id; De = $res.Owner }))
                $card.Penas = [int]$card.Penas + $PENALTY_COPY
                $entry.Resultado = (L 'COPIA de ' 'COPY from ') + "$($res.Owner) ($($res.Id))"
                Add-Event $db 'COPIA' $realSam (L "entrego la bandera de $($res.Id) que pertenece a $($res.Owner)" "submitted the $($res.Id) flag that belongs to $($res.Owner)")
                Log "COPIA: $realSam entrego $($res.Id) de $($res.Owner)." "COPY: $realSam submitted $($res.Id) of $($res.Owner)." 'WARN'
            }
            elseif (Has-Prop $card.Resueltos $res.Id) {
                $entry.Resultado = (L 'repetida ' 'repeated ') + "($($res.Id))"
            }
            elseif (-not (Test-DayOpen -Day ([int]$byId[$res.Id].Day))) {
                $day = [int]$byId[$res.Id].Day
                $ap = Get-DayOpening -Day $day
                $entry.Resultado = (L 'cerrado hasta el ' 'closed until ') + $ap.ToString('yyyy-MM-dd HH:mm') + " ($($res.Id))"
                if (-not (Has-Prop $card 'Adelantadas')) { Set-Prop $card 'Adelantadas' @() }
                $card.Adelantadas = @(@($card.Adelantadas) + @([pscustomobject]@{ Momento = (Get-Date).ToString('o'); Reto = $res.Id; Dia = $day; Abre = $ap.ToString('o') }) | Select-Object -Last 100)
                Add-Event $db 'CERRADO' $realSam (L "entrego $($res.Id) antes de que abriera el Dia $day" "submitted $($res.Id) before Day $day opened")
            }
            else {
                $def = $byId[$res.Id]
                $first = -not (Has-Prop $db.PrimerasSangres $res.Id)
                if ($first -and (Test-NoFirstBlood $slot)) { $first = $false }
                if ($first) { Set-Prop $db.PrimerasSangres $res.Id $slot }
                Set-Prop $card.Resueltos $res.Id ([pscustomobject]@{
                    Momento = (Get-Date).ToString('o'); Puntos = [int]$def.Points; Primero = $first; Via = 'entrega'
                    Equipo = [string]$json.Equipo; Dia = [int]$def.Day; FallosPrevios = [int]$card.Fallos })
                $entry.Resultado = (L 'correcto' 'correct') + " ($($res.Id), +$($def.Points))"
                $txt = (L 'resolvio ' 'solved ') + "$($res.Id) - $(Get-LabText $def.Title) (+$($def.Points))"
                if ($first) { $txt += (L ' PRIMERA SANGRE' ' FIRST BLOOD') + " (+$BONUS_FIRST)" }
                Add-Event $db 'RETO' $realSam $txt
                Log "$realSam resolvio $($res.Id)." "$realSam solved $($res.Id)." 'OK'
            }
            $card.Bitacora = @(@($card.Bitacora) + @($entry) | Select-Object -Last 200)
            Move-Item -LiteralPath $e.FullName -Destination (Join-Path $processed $e.Name) -Force
        }
        catch {
            Log "Entrega ilegible ($($e.Name)): $($_.Exception.Message)" "Unreadable submission ($($e.Name)): $($_.Exception.Message)" 'WARN'
            Move-Item -LiteralPath $e.FullName -Destination (Join-Path $processed $e.Name) -Force -ErrorAction SilentlyContinue
        }
    }

    foreach ($a in $students) {
        $card = $db.Alumnos.($a.Slot)
        foreach ($ch in $challenges) {
            if ($ch.Kind -ne 'check' -and $ch.Kind -ne 'deliverable') { continue }
            if (Has-Prop $card.Resueltos $ch.Id) { continue }
            if (-not (Test-DayOpen -Day ([int]$ch.Day))) { continue }
            $ok = $false
            try {
                if ($ch.Kind -eq 'deliverable') { $ok = Test-Deliverable -Student $a -Challenge $ch }
                else { $ok = & ([string]$ch.Check) -Student $a -Challenge $ch }
            } catch { Log "Comprobador de $($ch.Id) fallo con $($a.Sam): $($_.Exception.Message)" "Checker for $($ch.Id) failed with $($a.Sam): $($_.Exception.Message)" 'WARN' }
            if ($ok) {
                $first = -not (Has-Prop $db.PrimerasSangres $ch.Id)
                if ($first -and (Test-NoFirstBlood $a.Slot)) { $first = $false }
                if ($first) { Set-Prop $db.PrimerasSangres $ch.Id $a.Slot }
                Set-Prop $card.Resueltos $ch.Id ([pscustomobject]@{ Momento = (Get-Date).ToString('o'); Puntos = [int]$ch.Points; Primero = $first; Via = 'comprobado'; Dia = [int]$ch.Day })
                Add-Event $db 'RETO' $a.Sam ((L 'completo ' 'completed ') + "$($ch.Id) - $(Get-LabText $ch.Title) (+$($ch.Points))")
                Log "$($a.Sam) completo $($ch.Id) por comprobacion." "$($a.Sam) completed $($ch.Id) by check." 'OK'
            }
        }
    }

    $days = @($cat.Days | ForEach-Object { [int]$_.Day })
    $perDay = @{}
    foreach ($d in $days) { $perDay[$d] = @($challenges | Where-Object { [int]$_.Day -eq $d -and -not $_.Optional }) }
    foreach ($a in $students) {
        $card = $db.Alumnos.($a.Slot)
        $base = 0; $bonus = 0
        foreach ($p in $card.Resueltos.PSObject.Properties) {
            $base += [int]$p.Value.Puntos
            if ($p.Value.Primero) { $bonus += $BONUS_FIRST }
        }
        $complete = @()
        foreach ($d in $days) {
            if ($perDay[$d].Count -eq 0) { continue }
            $all = $true
            foreach ($ch in $perDay[$d]) { if (-not (Has-Prop $card.Resueltos $ch.Id)) { $all = $false; break } }
            if ($all) { $bonus += $BONUS_DAY; $complete += $d }
        }
        $card.Bonos = $bonus
        $card.Puntos = [math]::Max(0, $base + $bonus - [int]$card.Penas)
        Set-Prop $card 'DiasCompletos' $complete
        Set-Prop $card 'Resueltas' @($card.Resueltos.PSObject.Properties).Count
    }

    $hashes = @{}
    foreach ($a in $students) {
        $dir = Get-StudentFolder -Student $a -Kind Deliver
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)) {
            try {
                $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
                if (-not $hashes.ContainsKey($h)) { $hashes[$h] = @() }
                $hashes[$h] += "$($a.Slot):$($f.Name)"
            } catch { }
        }
    }
    foreach ($a in $students) {
        $card = $db.Alumnos.($a.Slot)
        $signals = @()
        $canaries = @(@($card.Alertas) | Where-Object { $_ -and $_.Tipo -eq 'CANARIO' })
        $nBait = @($canaries | Where-Object { $BAIT -contains $_.Canario }).Count
        $nSide = @($canaries | Where-Object { $BAIT -notcontains $_.Canario }).Count
        if ($nBait -gt 0) {
            $signals += [pscustomobject]@{ Peso = 'ALTO'; Senal = (L "$nBait canario(s) cebo entregado(s)" "$nBait bait canary(ies) submitted")
                Explicacion = (L 'Esa cadena solo aparece en un lugar que ningun reto pide revisar, junto a una nota que invita a entregarla sin trabajar. Hay que preguntar como llego hasta ella.' 'That string only appears where no challenge asks you to look, next to a note that invites submitting it without doing the work. Ask how they got there.') }
        }
        if ($nSide -gt 0) {
            $signals += [pscustomobject]@{ Peso = 'BAJO'; Senal = (L "$nSide canario(s) de validacion entregado(s)" "$nSide validation canary(ies) submitted")
                Explicacion = (L 'Aparece junto a la bandera buena al resolver bien el reto. Indica que entrega toda cadena con forma de bandera sin comprobar a que reto pertenece, no que haya copiado.' 'It sits next to the real flag when the challenge is solved properly. It means they submit every flag shaped string without checking which challenge it belongs to, not that they copied.') }
        }
        $nCopy = @($card.Copias).Count
        if ($nCopy -gt 0) {
            $signals += [pscustomobject]@{ Peso = 'ALTO'; Senal = (L "$nCopy bandera(s) de otra persona" "$nCopy flag(s) belonging to someone else")
                Explicacion = (L 'Las banderas personales se derivan de la cuenta. Entregar la de otra persona exige que alguien se la haya pasado.' 'Personal flags are derived from the account. Submitting someone else''s flag requires that someone handed it over.') }
        }
        $times = @()
        foreach ($p in $card.Resueltos.PSObject.Properties) { try { $times += [datetime]$p.Value.Momento } catch { } }
        if ($times.Count -ge 5) {
            $ord = @($times | Sort-Object)
            $span = ($ord[-1] - $ord[0]).TotalMinutes
            if ($span -lt 10) {
                $signals += [pscustomobject]@{ Peso = 'MEDIO'; Senal = (L "$($times.Count) retos en $([int]$span) minutos" "$($times.Count) challenges in $([int]$span) minutes")
                    Explicacion = (L 'Un ritmo asi es dificil incluso sabiendolo todo: hay que teclear los comandos.' 'Such a pace is hard even knowing everything: the commands still have to be typed.') }
            }
        }
        $solvedDays = @{}
        foreach ($p in $card.Resueltos.PSObject.Properties) {
            $d = 0
            if ($byId.ContainsKey($p.Name)) { $d = [int]$byId[$p.Name].Day }
            if ($d) { if (-not $solvedDays.ContainsKey($d)) { $solvedDays[$d] = 0 }; $solvedDays[$d]++ }
        }
        if ($solvedDays.ContainsKey(6) -or $solvedDays.ContainsKey(7)) {
            $basic = 0
            foreach ($d in @(2, 3)) { if ($solvedDays.ContainsKey($d)) { $basic += $solvedDays[$d] } }
            if ($basic -eq 0) {
                $signals += [pscustomobject]@{ Peso = 'BAJO'; Senal = (L 'Retos de los dias 6 o 7 sin ninguno de los dias 2 y 3' 'Day 6 or 7 challenges without any from days 2 and 3')
                    Explicacion = (L 'Puede ser experiencia previa. O que empezo por donde le dieron la respuesta.' 'It may be prior experience. Or they started where someone handed them the answer.') }
            }
        }
        $dir = Get-StudentFolder -Student $a -Kind Deliver
        if (Test-Path -LiteralPath $dir) {
            foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)) {
                try {
                    $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
                    $others = @($hashes[$h] | Where-Object { $_ -notlike "$($a.Slot):*" })
                    if ($others.Count -gt 0) {
                        $signals += [pscustomobject]@{ Peso = 'ALTO'; Senal = (L "$($f.Name) es identico al de: $($others -join ', ')" "$($f.Name) is identical to: $($others -join ', ')")
                            Explicacion = (L 'Dos writeups iguales byte a byte no salen de dos personas escribiendo por separado.' 'Two byte identical writeups do not come from two people writing separately.') }
                    }
                } catch { }
            }
        }
        if ([int]$card.Resueltas -ge 8 -and [int]$card.Fallos -eq 0) {
            $signals += [pscustomobject]@{ Peso = 'BAJO'; Senal = (L "$($card.Resueltas) retos sin un solo intento fallido" "$($card.Resueltas) challenges without a single failed attempt")
                Explicacion = (L 'Posible, pero poco frecuente: lo normal es equivocarse al copiar alguna cadena.' 'Possible but unusual: people usually mistype at least one string.') }
        }
        Set-Prop $card 'Senales' $signals
        Set-Prop $card 'RevisarIntegridad' (@($signals | Where-Object { $_.Peso -eq 'ALTO' }).Count -gt 0)
    }

    $db.Actualizado = (Get-Date).ToString('o')
    Save-Db -Data $db

    $possible = 0; $mandatory = 0
    foreach ($ch in $challenges) { $possible += [int]$ch.Points; if (-not $ch.Optional) { $mandatory += [int]$ch.Points } }
    $order = @($students | Sort-Object -Property @{ Expression = { [int]$db.Alumnos.($_.Slot).Puntos }; Descending = $true }, @{ Expression = { $_.Sam } })
    $pos = 0
    foreach ($a in $order) {
        $pos++
        $card = $db.Alumnos.($a.Slot)
        $list = @()
        foreach ($ch in $challenges) {
            $ap = Get-DayOpening -Day ([int]$ch.Day)
            $opens = $null
            if ($ap) { $opens = $ap.ToString('o') }
            $list += [pscustomobject]@{
                Id = $ch.Id; Dia = [int]$ch.Day; Titulo = (Get-LabText $ch.Title); Puntos = [int]$ch.Points; Opcional = [bool]$ch.Optional
                Resuelto = (Has-Prop $card.Resueltos $ch.Id); Abierto = (Test-DayOpen -Day ([int]$ch.Day)); Abre = $opens
            }
        }
        $prog = [pscustomobject]@{
            Nombre = $card.Nombre; Usuario = $a.Sam; Puntos = $card.Puntos; PuntosPosibles = $possible
            PuntosObligatorios = $mandatory; PuntosOpcionales = ($possible - $mandatory)
            PuntosBase = [int]$card.Puntos - [int]$card.Bonos + [int]$card.Penas; PuntosBonos = [int]$card.Bonos; PuntosPenas = [int]$card.Penas
            Resueltos = $card.Resueltas; Total = $challenges.Count; Posicion = (L "$pos de $($students.Count)" "$pos of $($students.Count)")
            Copias = @($card.Copias).Count; DiasCompletos = $card.DiasCompletos; Actualizado = $db.Actualizado
            Adelantadas = @($card.Adelantadas | Where-Object { $_ }); Retos = $list
        }
        $homeDir = Get-StudentHome -Student $a
        if (Test-Path -LiteralPath $homeDir) {
            $fp = Join-Path $homeDir '.progreso.json'
            try {
                if (Test-Path -LiteralPath $fp) { (Get-Item -LiteralPath $fp -Force).Attributes = 'Normal' }
                Write-JsonFile -Path $fp -Object $prog -Depth 6
                (Get-Item -LiteralPath $fp -Force).Attributes = 'Hidden'
            } catch { }
        }
    }
    Log "Pasada completa: $($items.Count) entregas y $($students.Count) alumnos." "Pass complete: $($items.Count) submissions and $($students.Count) students." 'OK'
}

try { Invoke-Pass }
catch {
    Log "FALLO DEL MOTOR: $($_.Exception.Message)" "SCORER FAILURE: $($_.Exception.Message)" 'ERROR'
    if ($NoShow) { throw }
    Show-LabOutput
    exit 1
}
if (-not $NoShow) { Show-LabOutput }
