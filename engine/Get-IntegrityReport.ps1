[CmdletBinding()]
param(
    [string]$Student = '',
    [switch]$Export,
    [switch]$NoShow
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'setup\Lab.psm1') -DisableNameChecking
if (-not (Test-Administrator)) {
    Write-Host (L 'Ejecutalo como administrador del dominio, en el controlador.' 'Run it as a domain administrator, on the domain controller.') -ForegroundColor Red
    exit 1
}
$c = Get-LabConfig

function W { param([string]$Text = '', [string]$Level = 'TEXT') Add-LabOutput $Text $Level }
function Color-Of { param([string]$Weight) if ($Weight -eq 'ALTO') { return 'ERROR' } elseif ($Weight -eq 'MEDIO') { return 'WARN' } return 'TEXT' }
function Weight { param([string]$W) if ($W -eq 'ALTO') { return (L 'ALTO' 'HIGH') } elseif ($W -eq 'MEDIO') { return (L 'MEDIO' 'MEDIUM') } return (L 'BAJO' 'LOW') }

function Invoke-Main {
    $dbPath = Join-Path $c.Paths.Score 'db.json'
    if (-not (Test-Path -LiteralPath $dbPath)) { W (L 'Todavia no hay datos de puntuacion.' 'There is no scoring data yet.') 'WARN'; return }
    $db = Read-JsonFile -Path $dbPath
    W ''
    W (L '  INFORME DE INTEGRIDAD ACADEMICA' '  ACADEMIC INTEGRITY REPORT') 'TITLE'
    W "  $($c.Organization)   $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    W ('  ' + ('=' * 68))
    if ($Student) {
        $f = $db.Alumnos.PSObject.Properties[$Student]
        if (-not $f) { foreach ($p in $db.Alumnos.PSObject.Properties) { if ($p.Value.Sam -eq $Student) { $f = $p } } }
        if (-not $f) { W (L "No hay datos de '$Student'." "No data for '$Student'.") 'ERROR'; return }
        $f = $f.Value
        W ''
        W ((L '  DETALLE DE ' '  DETAIL FOR ') + "$($f.Sam)   $($f.Nombre)   $($f.Correo)") 'TITLE'
        W ((L '  Puntos ' '  Points ') + "$($f.Puntos)   " + (L 'Retos ' 'Challenges ') + "$($f.Resueltas)   " + (L 'Fallos ' 'Failures ') + "$($f.Fallos)   " + (L 'Penalizaciones ' 'Penalties ') + "$($f.Penas)")
        W ''
        W (L '  Senales:' '  Signals:')
        if (@($f.Senales | Where-Object { $_ }).Count -eq 0) { W (L '     Ninguna.' '     None.') 'OK' }
        foreach ($s in @($f.Senales | Where-Object { $_ })) {
            W ("     [{0,-6}] {1}" -f (Weight $s.Peso), $s.Senal) (Color-Of $s.Peso)
            W ("              {0}" -f $s.Explicacion)
        }
        W ''
        W (L '  Retos resueltos, en orden:' '  Solved challenges, in order:')
        $ord = @()
        foreach ($p in $f.Resueltos.PSObject.Properties) { $ord += [pscustomobject]@{ Id = $p.Name; When = [datetime]$p.Value.Momento; Points = $p.Value.Puntos; Via = $p.Value.Via; Host = $p.Value.Equipo } }
        $prev = $null
        foreach ($r in ($ord | Sort-Object When)) {
            $delta = ''
            if ($prev) { $delta = '(+{0} min)' -f [int](($r.When - $prev).TotalMinutes) }
            W ("     {0}  {1,-9} {2,3} pts  {3,-10} {4} {5}" -f $r.When.ToString('MM-dd HH:mm'), $r.Id, $r.Points, $r.Via, $r.Host, $delta)
            $prev = $r.When
        }
        W ''
        W (L '  Bitacora de entregas:' '  Submission log:')
        foreach ($b in @($f.Bitacora | Where-Object { $_ })) {
            $lv = 'TEXT'
            if ($b.Resultado -match 'CANARIO|COPIA|COPY') { $lv = 'ERROR' } elseif ($b.Resultado -match 'correct') { $lv = 'OK' }
            W ("     {0}  {1,-36} {2}" -f ([datetime]$b.Momento).ToString('MM-dd HH:mm:ss'), $b.Cadena, $b.Resultado) $lv
            if ($b.Declarado -and $b.Declarado -ne $b.Real) { W ((L "              El archivo decia '$($b.Declarado)' pero lo creo '$($b.Real)'" "              The file claimed '$($b.Declarado)' but it was created by '$($b.Real)'")) 'ERROR' }
        }
        return
    }
    $flagged = @(); $clean = 0
    foreach ($p in $db.Alumnos.PSObject.Properties) { if (@($p.Value.Senales | Where-Object { $_ }).Count -gt 0) { $flagged += $p.Value } else { $clean++ } }
    W ''
    W (L "  $clean persona(s) sin ninguna senal." "  $clean person(s) without any signal.") 'OK'
    $lv = 'OK'
    if ($flagged.Count -gt 0) { $lv = 'WARN' }
    W (L "  $($flagged.Count) persona(s) con algo que revisar." "  $($flagged.Count) person(s) with something to review.") $lv
    $withCanary = @($flagged | Where-Object { @($_.Alertas | Where-Object { $_ -and $_.Tipo -eq 'CANARIO' }).Count -gt 0 })
    if ($withCanary.Count -gt 0) {
        W ''
        W (L '  CANARIOS DISPARADOS' '  CANARIES TRIGGERED') 'ERROR'
        W (L '  Estas cadenas no resuelven ningun reto y no estan escondidas en ningun lugar legitimo.' '  These strings solve no challenge and are not hidden anywhere legitimate.')
        foreach ($f in $withCanary) {
            foreach ($a in @($f.Alertas | Where-Object { $_ -and $_.Tipo -eq 'CANARIO' })) {
                W ("     {0,-14} {1,-9} {2}" -f $f.Sam, $a.Canario, $a.Equipo) 'ERROR'
                W ((L '                origen: ' '                origin: ') + $a.Donde)
                if ($a.DuenyoDelFichero -and $a.DuenyoDelFichero -ne $f.Slot) { W ((L '                era el canario del kit de ' '                it was the canary from the kit of ') + $a.DuenyoDelFichero) 'ERROR' }
            }
        }
    }
    $others = @($flagged | Where-Object { @($_.Alertas | Where-Object { $_ -and $_.Tipo -eq 'CANARIO' }).Count -eq 0 })
    if ($others.Count -gt 0) {
        W ''
        W (L '  OTRAS SENALES' '  OTHER SIGNALS') 'WARN'
        foreach ($f in ($others | Sort-Object { @($_.Senales | Where-Object { $_.Peso -eq 'ALTO' }).Count } -Descending)) {
            W ''
            W "     $($f.Sam)  ($($f.Puntos) pts, $($f.Resueltas))"
            foreach ($s in @($f.Senales | Where-Object { $_ })) { W ("        [{0,-6}] {1}" -f (Weight $s.Peso), $s.Senal) (Color-Of $s.Peso) }
        }
    }
    $access = Join-Path $c.Paths.Logs 'web-access.log'
    if (Test-Path -LiteralPath $access) {
        $auto = @(Get-Content -LiteralPath $access -ErrorAction SilentlyContinue | Where-Object { $_ -match '\[AUTOMATED\]' })
        if ($auto.Count -gt 0) {
            W ''
            W (L '  ACCESOS A LA INTRANET DESDE HERRAMIENTAS AUTOMATICAS' '  INTRANET ACCESS FROM AUTOMATED TOOLS') 'WARN'
            W (L '  No prueba nada: el Dia 5 ensena Invoke-WebRequest. Cruzado con lo anterior ayuda a entender que paso.' '  It proves nothing: Day 5 teaches Invoke-WebRequest. Cross checked with the above it helps to understand what happened.')
            foreach ($l in ($auto | Select-Object -Last 15)) { W "     $l" }
        }
    }
    W ''
    W ('  ' + ('=' * 68))
    W (L '  Una senal no es una acusacion: es algo que preguntar en privado. Lo que pide explicacion es la acumulacion y, sobre todo, un canario cebo.' '  A signal is not an accusation: it is something to ask about in private. What calls for an explanation is accumulation and, above all, a bait canary.')
}

try {
    Invoke-Main
    if ($Export) {
        $out = Join-Path $c.Paths.Data ('integrity-report-{0}.txt' -f (Get-Date -Format 'yyyyMMdd-HHmm'))
        [IO.File]::WriteAllText($out, (Get-LabOutputText), (New-Object Text.UTF8Encoding($false)))
        Set-SecureAcl -Path $out
        W ''
        W ((L 'Informe guardado en ' 'Report saved to ') + $out) 'OK'
    }
}
catch {
    Write-LabLog ((L 'Fallo del informe: ' 'Report failed: ') + $_.Exception.Message) 'ERROR'
    if ($NoShow) { throw }
    Show-LabOutput
    exit 1
}
if (-not $NoShow) { Show-LabOutput }
