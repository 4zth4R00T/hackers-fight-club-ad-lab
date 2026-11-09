# Chuleta del día 6: Active Directory

## Las capas

| Nivel | Qué es |
|---|---|
| Bosque | El contenedor de todo y la frontera de seguridad real |
| Árbol | Dominios con nombres relacionados |
| Dominio | La unidad administrativa, aquí `{DOMAIN}` |
| OU | Carpetas para organizar y aplicar políticas |
| Objetos | Usuarios, equipos y grupos |

Una **OU** organiza y aplica GPO. Un **grupo** otorga permisos. No son lo mismo.

## Enumerar

```powershell
Get-ADUser     -Filter * -Properties *
Get-ADComputer -Filter * -Properties *
Get-ADGroup    -Filter * -Properties *
Get-ADGroupMember "Nombre del grupo"
Get-ADPrincipalGroupMembership $env:USERNAME
Get-ADDomain
```

> Lo más importante del día: `Get-ADUser` devuelve unos pocos campos de los treinta que tiene un objeto. Todo lo interesante está en `-Properties *`.

Campos que casi nadie revisa y que suelen guardar cosas: `Description`, `info`, `comment`, `OperatingSystem`, `ServicePrincipalName`, `LastLogonDate`, `employeeNumber`, `mail`.

## Filtrar

```powershell
Get-ADUser -Filter { Enabled -eq $true }
Get-ADUser -Filter { ServicePrincipalName -like "*" } -Properties ServicePrincipalName
Get-ADUser -Filter * -Properties Description | Where-Object { $_.Description -match "algo" }
```

## Tus propios privilegios

```cmd
whoami /groups
whoami /priv
whoami /user
```

## Lo que sostiene el directorio

| Pieza | Papel |
|---|---|
| DNS | Los clientes localizan el DC con registros SRV. Sin DNS, AD no funciona |
| LDAP (389) | Leer y escribir el directorio |
| Kerberos (88) | Autenticar con boletos |
| Catálogo global (3268) | Índice de todo el bosque |

> En un Windows en español los grupos integrados están traducidos: si un script busca `Domain Admins`, no encuentra nada. La identidad estable es el **SID**.
