# Day 2 cheat sheet: CMD

## Moving around

| Command | What it does |
|---|---|
| `dir` | Lists the current folder |
| `dir /a` | Includes **hidden** items |
| `dir /s` | Walks subfolders |
| `dir /r` | Shows **alternate streams** |
| `cd folder` | Goes in |
| `cd ..` | Goes up one level |
| `cd \` | Goes to the drive root |
| `D:` | Switches drive |

## Files

| Command | What it does |
|---|---|
| `md folder` | Creates a folder |
| `type file` | Shows the content |
| `copy a b`, `move a b`, `ren a b` | Copies, moves and renames |
| `del file`, `rd /s folder` | Deletes, **carefully** |

## Chaining, the key idea of the day

| Symbol | What it does |
|---|---|
| `>` | Saves the output to a file, replacing it |
| `>>` | Appends to the end |
| `\|` | Passes the output to the next command |
| `findstr text` | Keeps the lines that contain something |

```cmd
findstr /s /i "{FLAG}{" *.*
tasklist | findstr /i chrome
ipconfig > network.txt
```

`dir` searches **names**. `findstr` searches **inside**. That is the leap of the day.

## Questioning the system

| Command | What it tells you |
|---|---|
| `hostname`, `whoami`, `ver` | Who and where you are |
| `whoami /priv`, `whoami /groups`, `whoami /user` | Privileges, groups and your SID |
| `systeminfo` | Full profile: version, domain, memory, patches |
| `net user` | Local users |
| `net user <name> /domain` | Record of a **domain** account |
| `tasklist /svc` | Processes and the service behind each |
| `sc query`, `net start` | Services |
| `schtasks /query /fo LIST /v` | Scheduled tasks in full detail |

## Variables and PATH

```cmd
set
echo %USERNAME%
echo %PATH%
where notepad
```

## The best reflex

```cmd
command /?
```

Before searching online, ask the command.
