# Day 4 cheat sheet: PowerShell

## The grammar

Everything is **Verb-Noun**, which is why commands can be guessed.

```powershell
Get-Verb
Get-Command *process*
Get-Help Get-Process -Examples
Get-Process | Get-Member
```

The last three are the discovery trio: with them PowerShell explains itself.

## Variables

```powershell
$name = "text"
$list = @(1, 2, 3)
$map  = @{ os = "win" }
$_
$env:USERNAME
```

## The pipeline

```powershell
Get-Process |
    Where-Object { $_.CPU -gt 100 } |
    Sort-Object CPU -Descending |
    Select-Object -First 5 Name, CPU
```

`ForEach-Object { $_ }` does something with every element.

## Comparing: PowerShell has no `==`

| Operator | Meaning |
|---|---|
| `-eq`, `-ne` | Equal, not equal |
| `-gt`, `-lt` | Greater, less |
| `-ge`, `-le` | Greater or equal, less or equal |
| `-match` | Matches a pattern |
| `-and`, `-or`, `-not` | Combines conditions |

## Deciding and repeating

```powershell
if ($x -gt 100) { "a lot" } elseif ($x -gt 10) { "normal" } else { "little" }
foreach ($f in $files) { Write-Host $f.Name }
function Get-Double { param([int]$Number) $Number * 2 }
```

## Files

| Cmdlet | What it does |
|---|---|
| `Get-ChildItem` | Lists |
| `Get-Content` | Reads |
| `Set-Content`, `Add-Content` | Writes or appends |
| `New-Item -ItemType Directory` | Creates |
| `Test-Path` | Checks whether it exists |
| `Select-String` | The `grep` of PowerShell |

## Exporting

```powershell
Get-Process | Select-Object Name, Id, CPU | Export-Csv processes.csv -NoTypeInformation
Get-Process | Select-Object Name, Id | ConvertTo-Json | Set-Content processes.json
```

## Five habits

1. Comment the why, not the what.
2. `$textFiles` says more than `$x`.
3. `Get-Help` and `Get-Member` before the internet.
4. `-WhatIf` simulates without running. Use it before deleting.
5. Make it work on one file before running it against a thousand.

```powershell
Set-ExecutionPolicy -Scope Process RemoteSigned
.\my-script.ps1
```

> `Get-ChildItem` does not always return files in the order you expect. If order matters, use `Sort-Object`.
