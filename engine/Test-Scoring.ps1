[CmdletBinding()]
param(
    [string]$Student = '',
    [switch]$CleanOnly,
    [switch]$NoShow
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'setup\Lab.psm1') -DisableNameChecking
if (-not (Test-Administrator)) {
    Write-Host (L 'Ejecutalo como administrador del dominio, en el controlador.' 'Run it as a domain administrator, on the domain controller.') -ForegroundColor Red
    exit 1
}
Import-Module (Join-Path $root 'engine\Challenges.psm1') -DisableNameChecking
Import-Module ActiveDirectory -ErrorAction Stop
Import-Module GroupPolicy -ErrorAction Stop

$c = Get-LabConfig
$tag = 'TEST-LAB'
$gpoNames = @("$tag-Wallpaper", "$tag-LogonHours", "$tag-Audit")
$groupName = "$tag-Filter"
$userName = 'test.lab.d7'
$created = New-Object System.Collections.Generic.List[string]
$script:Fails = 0

function Ok { param([string]$Es, [string]$En) Write-LabLog (L $Es $En) 'OK' }
function Bad { param([string]$Es, [string]$En) $script:Fails++; Write-LabLog (L $Es $En) 'ERROR' }
function Note { param([string]$Es, [string]$En) Write-LabLog (L $Es $En) 'INFO' }

function Get-Target {
    $all = @(Get-Students)
    if ($all.Count -eq 0) { throw (L 'No hay alumnos. Crea al menos uno con Add-Students.ps1.' 'There are no students. Create at least one with Add-Students.ps1.') }
    if ($Student) {
        $t = $all | Where-Object { $_.Slot -eq $Student -or $_.Sam -eq $Student } | Select-Object -First 1
        if (-not $t) { throw (L "No existe el alumno $Student." "Student $Student does not exist.") }
        return $t
    }
    return $all[0]
}

function Remove-TestObjects {
    param($Target)
    $ou = "OU=$($Target.Slot),$($c.OUSandbox)"
    foreach ($g in $gpoNames) {
        $x = Get-GPO -Name $g -ErrorAction SilentlyContinue
        if ($x) {
            try { Remove-GPLink -Guid $x.Id -Target $ou -ErrorAction SilentlyContinue | Out-Null } catch { }
            Remove-GPO -Guid $x.Id -ErrorAction SilentlyContinue
        }
    }
    $u = Get-ADUser -Filter "SamAccountName -eq '$userName'" -ErrorAction SilentlyContinue
    if ($u) { Remove-ADUser -Identity $u -Confirm:$false }
    $g = Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue
    if ($g) { Remove-ADGroup -Identity $g -Confirm:$false }
    $work = Get-StudentFolder -Student $Target -Kind Work
    $k = Get-KitNames
    $ch2 = Join-Path (Join-Path $work $k.Day4) $k.Ch2
    if (Test-Path -LiteralPath $ch2) { Get-ChildItem -LiteralPath $ch2 -Directory -Filter "$tag*" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force }
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $work $k.Day4) -File -Filter "$tag*" -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $f.FullName -Force }
    $del = Get-StudentFolder -Student $Target -Kind Deliver
    foreach ($f in @(Get-ChildItem -LiteralPath $del -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$tag*" -or ($created -contains $_.FullName) })) { Remove-Item -LiteralPath $f.FullName -Force }
    foreach ($p in $created) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue } }
}

function Send-Test {
    param([string]$Sam, [string]$Value, [string]$Name)
    $dir = Join-Path $c.Paths.Score 'drop-web'
    New-Folder $dir | Out-Null
    $p = Join-Path $dir ("{0}_{1}.json" -f $tag, $Name)
    $obj = [ordered]@{ Bandera = $Value; Usuario = $Sam; Equipo = $tag; Momento = (Get-Date).ToString('o'); Comentario = $tag }
    [IO.File]::WriteAllText($p, ($obj | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
}

function Invoke-Main {
    $target = Get-Target
    Note "Alumno de prueba: $($target.Sam) ($($target.Slot))" "Test student: $($target.Sam) ($($target.Slot))"
    if ($CleanOnly) {
        Remove-TestObjects -Target $target
        Ok 'Objetos de prueba eliminados.' 'Test objects removed.'
        return
    }
    $db = Join-Path $c.Paths.Score 'db.json'
    $cal = Join-Path $c.Paths.Content 'calendario.json'
    $studentHome = Get-StudentHome -Student $target
    $backup = Join-Path $c.Paths.Data ("test-backup-{0}" -f (Get-Date -Format 'yyyyMMddHHmmss'))
    New-Folder $backup | Out-Null
    foreach ($f in @($db, $cal, (Join-Path $studentHome '.progreso.json'), (Join-Path $studentHome '.entregas.json'))) {
        if (Test-Path -LiteralPath $f) { Copy-Item -LiteralPath $f -Destination (Join-Path $backup ((Split-Path -Leaf $f) + '.bak')) -Force }
    }
    $processed = Join-Path $c.Paths.Score 'processed'
    $before = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath $processed -File -ErrorAction SilentlyContinue)) { $before[$f.Name] = $true }
    $task = Get-ScheduledTask -TaskName 'Lab-Scorer' -ErrorAction SilentlyContinue
    if ($task) { Disable-ScheduledTask -TaskName 'Lab-Scorer' | Out-Null }
    try {
        $calObj = Read-JsonFile -Path $cal
        if ($calObj -and $calObj.Dias) {
            foreach ($p in $calObj.Dias.PSObject.Properties) { $p.Value.Apertura = (Get-Date).AddDays(-1).ToString('yyyy-MM-ddTHH:mm:ss') }
            Write-JsonFile -Path $cal -Object $calObj
        }
        $ou = "OU=$($target.Slot),$($c.OUSandbox)"
        if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ou'" -ErrorAction SilentlyContinue)) { throw (L "No existe la OU $ou." "OU $ou does not exist.") }
        Remove-TestObjects -Target $target

        $k = Get-KitNames
        $del = Get-StudentFolder -Student $target -Kind Deliver
        New-Folder $del | Out-Null
        $map = Join-Path $del 'dia1-mapa.md'
        if (Test-Path -LiteralPath $map) { Note 'Ya hay un dia1-mapa real: se omite la prueba de entrega.' 'A real dia1-mapa already exists: the deliverable test is skipped.' }
        else {
            [IO.File]::WriteAllText($map, ("# test`r`n" + ('Lorem ipsum dolor sit amet. ' * 40)), (New-Object Text.UTF8Encoding($false)))
            $created.Add($map)
        }
        $ch2 = Join-Path (Join-Path (Get-StudentFolder -Student $target -Kind Work) $k.Day4) $k.Ch2
        foreach ($i in 1..3) {
            $d = Join-Path $ch2 "$tag-$i"
            New-Folder $d | Out-Null
            foreach ($j in 1..3) { Set-Content -LiteralPath (Join-Path $d "f$j.txt") -Value 'x' }
        }

        $grp = New-ADGroup -Name $groupName -GroupScope Global -GroupCategory Security -Path $ou -PassThru
        New-ADUser -Name $userName -SamAccountName $userName -Path $ou -Enabled $false
        Add-ADGroupMember -Identity $grp -Members $userName
        $g1 = New-GPO -Name "$tag-Wallpaper"
        Set-GPRegistryValue -Guid $g1.Id -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop' -ValueName 'NoChangingWallPaper' -Type DWord -Value 1 | Out-Null
        Set-GPPermission -Guid $g1.Id -TargetName $groupName -TargetType Group -PermissionLevel GpoApply | Out-Null
        Set-GPPermission -Guid $g1.Id -TargetName (Get-PrincipalName 'Authenticated Users') -TargetType Group -PermissionLevel GpoRead -Replace | Out-Null
        New-GPLink -Guid $g1.Id -Target $ou | Out-Null
        $g2 = New-GPO -Name "$tag-LogonHours"
        Set-GPRegistryValue -Guid $g2.Id -Key 'HKLM\Software\Policies\Lab\Test' -ValueName 'ForceLogoffWhenHourExpire' -Type DWord -Value 1 | Out-Null
        New-GPLink -Guid $g2.Id -Target $ou | Out-Null
        $g3 = New-GPO -Name "$tag-Audit"
        Set-GPRegistryValue -Guid $g3.Id -Key 'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System\Audit' -ValueName 'ProcessCreationIncludeCmdLine_Enabled' -Type DWord -Value 1 | Out-Null
        New-GPLink -Guid $g3.Id -Target $ou | Out-Null
        Note 'Escenario del dia 7 creado en la OU del alumno.' 'Day 7 scenario created in the student OU.'

        Send-Test -Sam $target.Sam -Value (Get-FlagValue -Id 'D2-01' -Slot $target.Slot) -Name 'own'
        $other = @(Get-Students) | Where-Object { $_.Slot -ne $target.Slot } | Select-Object -First 1
        if ($other) { Send-Test -Sam $target.Sam -Value (Get-FlagValue -Id 'D2-02' -Slot $other.Slot) -Name 'copy' }
        Send-Test -Sam $target.Sam -Value (Get-CanaryValue -Id 'CAN-KIT' -Slot $target.Slot) -Name 'canary'
        Send-Test -Sam $target.Sam -Value ('{0}{{not_a_flag}}' -f $c.FlagPrefix) -Name 'wrong'

        & (Join-Path $root 'engine\Invoke-Scorer.ps1') -NoShow
        $data = Read-JsonFile -Path $db
        $card = $data.Alumnos.($target.Slot)
        $solved = @($card.Resueltos.PSObject.Properties | ForEach-Object { $_.Name })
        $expect = @('D2-01', 'D4-02', 'D7-G1', 'D7-G2', 'D7-G3', 'D7-CREA')
        if ($created -contains $map) { $expect += 'D1-MAPA' }
        foreach ($id in $expect) {
            if ($solved -contains $id) { Ok "$id puntua." "$id scores." } else { Bad "$id no puntuo." "$id did not score." }
        }
        if ($other) {
            if (@($card.Copias | Where-Object { $_ -and $_.De -eq $other.Slot }).Count -ge 1) { Ok 'La bandera ajena se detecto como copia.' 'The foreign flag was detected as a copy.' }
            else { Bad 'La copia no se detecto.' 'The copy was not detected.' }
        } else { Note 'Solo hay un alumno: se omite la prueba de copia.' 'Only one student exists: the copy test is skipped.' }
        if (@($card.Alertas | Where-Object { $_ -and $_.Canario -eq 'CAN-KIT' }).Count -ge 1) { Ok 'El canario se detecto.' 'The canary was detected.' } else { Bad 'El canario no se detecto.' 'The canary was not detected.' }
        if ([int]$card.Fallos -ge 1) { Ok 'La cadena falsa conto como fallo.' 'The fake string counted as a failure.' } else { Bad 'La cadena falsa no conto como fallo.' 'The fake string did not count as a failure.' }
    }
    finally {
        try { Remove-TestObjects -Target $target } catch { Write-LabLog $_.Exception.Message 'WARN' }
        foreach ($f in @($db, $cal, (Join-Path $studentHome '.progreso.json'), (Join-Path $studentHome '.entregas.json'))) {
            $b = Join-Path $backup ((Split-Path -Leaf $f) + '.bak')
            if (Test-Path -LiteralPath $b) {
                if (Test-Path -LiteralPath $f) { (Get-Item -LiteralPath $f -Force).Attributes = 'Normal' }
                Copy-Item -LiteralPath $b -Destination $f -Force
            } elseif ((Split-Path -Leaf $f) -eq 'db.json' -and (Test-Path -LiteralPath $f)) { Remove-Item -LiteralPath $f -Force }
        }
        foreach ($f in @(Get-ChildItem -LiteralPath $processed -File -ErrorAction SilentlyContinue)) {
            if ($before.ContainsKey($f.Name)) { continue }
            if ($f.Name -like "$tag*") { Remove-Item -LiteralPath $f.FullName -Force; continue }
            Move-Item -LiteralPath $f.FullName -Destination $c.Paths.Dropbox -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
        if ($task) { Enable-ScheduledTask -TaskName 'Lab-Scorer' | Out-Null }
        Note 'Laboratorio devuelto a su estado anterior.' 'Lab restored to its previous state.'
    }
    if ($script:Fails -eq 0) { Ok 'Todas las vias de puntuacion funcionan.' 'Every scoring path works.' }
    else { Bad "$($script:Fails) comprobacion(es) fallaron." "$($script:Fails) check(s) failed." }
}

try { Invoke-Main }
catch {
    Write-LabLog ((L 'Fallo de la prueba: ' 'Test failed: ') + $_.Exception.Message) 'ERROR'
    if ($NoShow) { throw }
    Show-LabOutput
    exit 1
}
if (-not $NoShow) { Show-LabOutput }
