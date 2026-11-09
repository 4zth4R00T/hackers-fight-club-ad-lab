# Шпаргалка ко дню 4: PowerShell

## Грамматика

Всё строится по схеме **Глагол-Существительное**, поэтому команды можно угадывать.

```powershell
Get-Verb
Get-Command *process*
Get-Help Get-Process -Examples
Get-Process | Get-Member
```

Последние три команды образуют связку для исследования: с их помощью PowerShell сам рассказывает о себе.

## Переменные

```powershell
$name = "текст"
$list = @(1, 2, 3)
$map  = @{ os = "win" }
$_
$env:USERNAME
```

## Конвейер

```powershell
Get-Process |
    Where-Object { $_.CPU -gt 100 } |
    Sort-Object CPU -Descending |
    Select-Object -First 5 Name, CPU
```

`ForEach-Object { $_ }` выполняет действие с каждым элементом.

## Сравнение: в PowerShell нет `==`

| Оператор | Значение |
|---|---|
| `-eq`, `-ne` | Равно, не равно |
| `-gt`, `-lt` | Больше, меньше |
| `-ge`, `-le` | Больше или равно, меньше или равно |
| `-match` | Соответствует шаблону |
| `-and`, `-or`, `-not` | Объединяет условия |

## Ветвления и циклы

```powershell
if ($x -gt 100) { "много" } elseif ($x -gt 10) { "нормально" } else { "мало" }
foreach ($f in $files) { Write-Host $f.Name }
function Get-Double { param([int]$Number) $Number * 2 }
```

## Файлы

| Командлет | Что делает |
|---|---|
| `Get-ChildItem` | Выводит список |
| `Get-Content` | Читает |
| `Set-Content`, `Add-Content` | Записывает или дописывает |
| `New-Item -ItemType Directory` | Создаёт |
| `Test-Path` | Проверяет, существует ли объект |
| `Select-String` | Аналог `grep` в PowerShell |

## Экспорт

```powershell
Get-Process | Select-Object Name, Id, CPU | Export-Csv процессы.csv -NoTypeInformation
Get-Process | Select-Object Name, Id | ConvertTo-Json | Set-Content процессы.json
```

## Пять привычек

1. В комментариях объясняйте, зачем, а не что.
2. `$textFiles` говорит больше, чем `$x`.
3. Сначала `Get-Help` и `Get-Member`, потом интернет.
4. `-WhatIf` имитирует выполнение, ничего не запуская. Используйте его перед удалением.
5. Добейтесь, чтобы скрипт работал с одним файлом, прежде чем запускать его на тысяче.

```powershell
Set-ExecutionPolicy -Scope Process RemoteSigned
.\мой-скрипт.ps1
```

> `Get-ChildItem` не всегда возвращает файлы в ожидаемом порядке. Если порядок важен, используйте `Sort-Object`.
