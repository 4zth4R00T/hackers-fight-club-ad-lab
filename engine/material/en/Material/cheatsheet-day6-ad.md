# Day 6 cheat sheet: Active Directory

## The layers

| Level | What it is |
|---|---|
| Forest | The container of everything and the real security boundary |
| Tree | Domains with related names |
| Domain | The administrative unit, here `{DOMAIN}` |
| OU | Folders to organize and apply policy |
| Objects | Users, computers and groups |

An **OU** organizes and applies GPOs. A **group** grants permissions. They are not the same.

## Enumerating

```powershell
Get-ADUser     -Filter * -Properties *
Get-ADComputer -Filter * -Properties *
Get-ADGroup    -Filter * -Properties *
Get-ADGroupMember "Group name"
Get-ADPrincipalGroupMembership $env:USERNAME
Get-ADDomain
```

> The most important lesson of the day: `Get-ADUser` returns a few fields out of the thirty an object has. Everything interesting is in `-Properties *`.

Fields almost nobody checks that tend to hold things: `Description`, `info`, `comment`, `OperatingSystem`, `ServicePrincipalName`, `LastLogonDate`, `employeeNumber`, `mail`.

## Filtering

```powershell
Get-ADUser -Filter { Enabled -eq $true }
Get-ADUser -Filter { ServicePrincipalName -like "*" } -Properties ServicePrincipalName
Get-ADUser -Filter * -Properties Description | Where-Object { $_.Description -match "something" }
```

## Your own privileges

```cmd
whoami /groups
whoami /priv
whoami /user
```

## What holds the directory up

| Piece | Role |
|---|---|
| DNS | Clients find the DC through SRV records. Without DNS, AD does not work |
| LDAP (389) | Reading and writing the directory |
| Kerberos (88) | Authenticating with tickets |
| Global catalog (3268) | Index of the whole forest |

> On a localized Windows the built in groups are translated: a script looking for `Domain Admins` on a Spanish server finds nothing. The stable identity is the **SID**.
