# Шпаргалка ко дню 3: Linux и Windows бок о бок

| Linux | CMD | PowerShell |
|---|---|---|
| `ls` | `dir` | `Get-ChildItem` |
| `cd` | `cd` | `Set-Location` |
| `cp` | `copy` | `Copy-Item` |
| `mv` | `move` | `Move-Item` |
| `rm` | `del` | `Remove-Item` |
| `cat` | `type` | `Get-Content` |
| `grep` | `findstr` | `Select-String` |
| `ps` | `tasklist` | `Get-Process` |
| `kill` | `taskkill` | `Stop-Process` |
| `systemctl` | `sc` | `Get-Service` |

## Где что находится

| Назначение | Windows | Linux |
|---|---|---|
| Система | `C:\Windows` | `/` |
| Конфигурация | Реестр | `/etc` |
| Папки пользователей | `C:\Users` | `/home` |
| Программы | `C:\Program Files` | `/usr/bin` |
| Журналы и данные | `ProgramData` и Средство просмотра событий | `/var` |
| Временные файлы | `%TEMP%` | `/tmp` |

## Идентификация

`Администратор` примерно соответствует `root`. **SID** для Windows значит то же, что **UID** для Linux: это настоящий идентификатор, стоящий за именем. Имя можно изменить, SID нельзя.

## Реестр

```cmd
reg query HKCU\Software /s
reg add HKCU\Software\МойТест /v данные /d значение
```

```powershell
Get-ChildItem HKCU:\Software
Get-ItemProperty HKCU:\{REG_ROOT}
```

## Альтернативные потоки, только в NTFS

Файл может содержать несколько потоков данных, и его размер при этом **не меняется**.

```cmd
dir /r
more < файл.txt:скрытый
type секрет > файл.txt:скрытый
```

## Ссылки

| Тип | Windows | Linux |
|---|---|---|
| Символическая | `mklink ссылка цель` | `ln -s цель ссылка` |
| Для каталога | `mklink /D ссылка цель` | `ln -s цель/ ссылка` |
| Жёсткая | `mklink /H ссылка цель` | `ln цель ссылка` |
| Точка соединения | `mklink /J ссылка цель` | Монтирование через bind |

## Разрешения

Windows использует списки управления доступом с наследованием; Linux использует `rwx` для владельца, группы и остальных.

```cmd
icacls файл.txt
```
