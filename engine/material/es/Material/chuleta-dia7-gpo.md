# Chuleta del día 7: administrar el dominio

## Gestionar objetos

```powershell
New-ADUser -Name "a.prueba" -SamAccountName "a.prueba" -Enabled $true -AccountPassword (Read-Host -AsSecureString) -Path "OU=..."
Set-ADUser -Identity a.prueba -Description "..."
New-ADGroup -Name "MiGrupo" -GroupScope Global -GroupCategory Security -Path "OU=..."
Add-ADGroupMember -Identity "MiGrupo" -Members a.prueba
Get-ADGroupMember "MiGrupo"
```

Para altas masivas: un CSV y un `foreach`.

## Las consolas

| Consola | Comando | Para qué |
|---|---|---|
| Usuarios y equipos | `dsa.msc` | Usuarios, grupos, equipos y OU |
| Administración de directivas | `gpmc.msc` | Crear, editar y vincular GPO |
| DNS | `dnsmgmt.msc` | Zonas y registros |
| Visor de eventos | `eventvwr.msc` | Donde quien defiende te encuentra |

## Las GPO

| Mitad | A quién aplica |
|---|---|
| Configuración de equipo | A la máquina, al arrancar |
| Configuración de usuario | A la persona, al iniciar sesión |

El orden de aplicación es local, sitio, dominio y OU. La última en aplicarse gana, así que manda la OU más cercana al objeto. Dos excepciones: **bloquear herencia** corta las de arriba y **exigida** gana pase lo que pase.

```cmd
gpupdate /force
gpresult /r
```

### Filtrado de seguridad

Una GPO se aplica a quien tenga el permiso **Aplicar directiva de grupo**. Si la quieres solo para un grupo, quita Usuarios autenticados y agrega el grupo con ese permiso. Vincular la GPO y filtrarla son dos cosas distintas y hacen falta las dos.

## Lo ofensivo y su freno

| Técnica | Fase | Defensa |
|---|---|---|
| Password spraying | Acceso inicial | MFA, contraseñas largas y detectar el patrón |
| Kerberoasting | Escalada | Cuentas administradas y contraseñas largas en cuentas con SPN |
| Pass the hash | Movimiento lateral | LAPS, mínimo privilegio y menos NTLM |
| Responder | Acceso inicial | Apagar LLMNR y NBT-NS, exigir firma SMB |
| Golden ticket | Dominio | Proteger el DC y rotar `krbtgt` |

**Todo esto solo en laboratorios propios o con autorización expresa por escrito.** Es lo que separa a un profesional de un delincuente.
