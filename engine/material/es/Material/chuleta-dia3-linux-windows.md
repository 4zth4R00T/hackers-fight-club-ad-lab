# Chuleta del día 3: Linux y Windows lado a lado

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

## Dónde vive cada cosa

| Para qué | Windows | Linux |
|---|---|---|
| El sistema | `C:\Windows` | `/` |
| Configuración | El registro | `/etc` |
| Carpetas de usuario | `C:\Users` | `/home` |
| Programas | `C:\Program Files` | `/usr/bin` |
| Registros y datos | `ProgramData` y el visor de eventos | `/var` |
| Temporales | `%TEMP%` | `/tmp` |

## Identidad

`Administrador` se parece a `root`. El **SID** es para Windows lo que el **UID** para Linux: la identidad real detrás del nombre. El nombre se puede cambiar; el SID no.

## El registro

```cmd
reg query HKCU\Software /s
reg add HKCU\Software\MiPrueba /v dato /d valor
```

```powershell
Get-ChildItem HKCU:\Software
Get-ItemProperty HKCU:\{REG_ROOT}
```

## Flujos alternos, solo en NTFS

Un archivo puede llevar más de un flujo de datos y su tamaño **no cambia**.

```cmd
dir /r
more < archivo.txt:oculto
type secreto > archivo.txt:oculto
```

## Enlaces

| Tipo | Windows | Linux |
|---|---|---|
| Simbólico | `mklink enlace destino` | `ln -s destino enlace` |
| De carpeta | `mklink /D enlace destino` | `ln -s destino/ enlace` |
| Físico | `mklink /H enlace destino` | `ln destino enlace` |
| Unión | `mklink /J enlace destino` | Montaje con bind |

## Permisos

Windows usa listas de control de acceso con herencia; Linux usa `rwx` para dueño, grupo y otros.

```cmd
icacls archivo.txt
```
