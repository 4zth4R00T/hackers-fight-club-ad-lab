# Chuleta del día 2: CMD

## Moverse

| Comando | Qué hace |
|---|---|
| `dir` | Lista la carpeta actual |
| `dir /a` | Incluye los **ocultos** |
| `dir /s` | Baja por las subcarpetas |
| `dir /r` | Muestra los **flujos alternos** |
| `cd carpeta` | Entra |
| `cd ..` | Sube un nivel |
| `cd \` | Va a la raíz de la unidad |
| `D:` | Cambia de unidad |

## Archivos

| Comando | Qué hace |
|---|---|
| `md carpeta` | Crea una carpeta |
| `type archivo` | Muestra el contenido |
| `copy a b`, `move a b`, `ren a b` | Copia, mueve y renombra |
| `del archivo`, `rd /s carpeta` | Borra, con **cuidado** |

## Encadenar, lo importante del día

| Símbolo | Qué hace |
|---|---|
| `>` | Guarda la salida en un archivo y lo reemplaza |
| `>>` | Agrega al final |
| `\|` | Pasa la salida al siguiente comando |
| `findstr texto` | Filtra las líneas que contienen algo |

```cmd
findstr /s /i "{FLAG}{" *.*
tasklist | findstr /i chrome
ipconfig > red.txt
```

`dir` busca en los **nombres**. `findstr` busca **dentro**. Ese es el salto del día.

## Interrogar al sistema

| Comando | Qué te dice |
|---|---|
| `hostname`, `whoami`, `ver` | Quién eres y dónde estás |
| `whoami /priv`, `whoami /groups`, `whoami /user` | Privilegios, grupos y tu SID |
| `systeminfo` | Ficha completa: versión, dominio, memoria, parches |
| `net user` | Usuarios locales |
| `net user <nombre> /domain` | Ficha de una cuenta **del dominio** |
| `tasklist /svc` | Procesos y el servicio de cada uno |
| `sc query`, `net start` | Servicios |
| `schtasks /query /fo LIST /v` | Tareas programadas con todo el detalle |

## Variables y PATH

```cmd
set
echo %USERNAME%
echo %PATH%
where notepad
```

## El reflejo que más vale

```cmd
comando /?
```

Antes de buscar en internet, pregúntale al comando.
