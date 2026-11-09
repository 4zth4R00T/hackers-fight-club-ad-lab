# Chuleta del día 4: PowerShell

## La gramática

Todo es **Verbo-Sustantivo**, por eso los comandos se adivinan.

```powershell
Get-Verb
Get-Command *process*
Get-Help Get-Process -Examples
Get-Process | Get-Member
```

Los tres últimos son el trío de descubrimiento: con ellos PowerShell se explora solo.

## Variables

```powershell
$nombre = "texto"
$lista  = @(1, 2, 3)
$mapa   = @{ os = "win" }
$_
$env:USERNAME
```

## La tubería

```powershell
Get-Process |
    Where-Object { $_.CPU -gt 100 } |
    Sort-Object CPU -Descending |
    Select-Object -First 5 Name, CPU
```

`ForEach-Object { $_ }` hace algo con cada elemento.

## Comparar: en PowerShell no existe `==`

| Operador | Qué es |
|---|---|
| `-eq`, `-ne` | Igual, distinto |
| `-gt`, `-lt` | Mayor, menor |
| `-ge`, `-le` | Mayor o igual, menor o igual |
| `-match` | Coincide con un patrón |
| `-and`, `-or`, `-not` | Combina condiciones |

## Decidir y repetir

```powershell
if ($x -gt 100) { "mucho" } elseif ($x -gt 10) { "normal" } else { "poco" }
foreach ($f in $archivos) { Write-Host $f.Name }
function Get-Doble { param([int]$Numero) $Numero * 2 }
```

## Archivos

| Cmdlet | Qué hace |
|---|---|
| `Get-ChildItem` | Lista |
| `Get-Content` | Lee |
| `Set-Content`, `Add-Content` | Escribe o agrega |
| `New-Item -ItemType Directory` | Crea |
| `Test-Path` | Comprueba si existe |
| `Select-String` | El `grep` de PowerShell |

## Exportar

```powershell
Get-Process | Select-Object Name, Id, CPU | Export-Csv procesos.csv -NoTypeInformation
Get-Process | Select-Object Name, Id | ConvertTo-Json | Set-Content procesos.json
```

## Cinco hábitos

1. Comenta el porqué, no el qué.
2. `$archivosTxt` dice más que `$x`.
3. `Get-Help` y `Get-Member` antes que internet.
4. `-WhatIf` simula sin ejecutar. Úsalo antes de borrar.
5. Haz que funcione con un archivo antes de lanzarlo contra mil.

```powershell
Set-ExecutionPolicy -Scope Process RemoteSigned
.\mi-script.ps1
```

> `Get-ChildItem` no siempre devuelve los archivos en el orden que esperas. Si el orden importa, usa `Sort-Object`.
