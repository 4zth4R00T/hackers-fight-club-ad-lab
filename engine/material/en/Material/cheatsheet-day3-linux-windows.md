# Day 3 cheat sheet: Linux and Windows side by side

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

## Where things live

| Purpose | Windows | Linux |
|---|---|---|
| The system | `C:\Windows` | `/` |
| Configuration | The registry | `/etc` |
| User folders | `C:\Users` | `/home` |
| Programs | `C:\Program Files` | `/usr/bin` |
| Logs and data | `ProgramData` and the event viewer | `/var` |
| Temporary files | `%TEMP%` | `/tmp` |

## Identity

`Administrator` is close to `root`. The **SID** is to Windows what the **UID** is to Linux: the real identity behind the name. The name can change; the SID cannot.

## The registry

```cmd
reg query HKCU\Software /s
reg add HKCU\Software\MyTest /v data /d value
```

```powershell
Get-ChildItem HKCU:\Software
Get-ItemProperty HKCU:\{REG_ROOT}
```

## Alternate streams, NTFS only

A file can carry more than one data stream and its size **does not change**.

```cmd
dir /r
more < file.txt:hidden
type secret > file.txt:hidden
```

## Links

| Type | Windows | Linux |
|---|---|---|
| Symbolic | `mklink link target` | `ln -s target link` |
| Directory | `mklink /D link target` | `ln -s target/ link` |
| Hard | `mklink /H link target` | `ln target link` |
| Junction | `mklink /J link target` | Bind mount |

## Permissions

Windows uses access control lists with inheritance; Linux uses `rwx` for owner, group and others.

```cmd
icacls file.txt
```
