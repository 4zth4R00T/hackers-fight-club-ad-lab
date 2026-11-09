# Chuleta del día 5: la red

## Los puertos que verás una y otra vez

| Puerto | Servicio | Para qué |
|---|---|---|
| 53 | DNS | Traducir nombres en direcciones |
| 80, 443 | HTTP, HTTPS | Web |
| 88 | Kerberos | Autenticación del dominio |
| 110 | POP3 | Leer correo |
| 25, 587 | SMTP | Enviar correo |
| 389, 636 | LDAP, LDAPS | Consultar Active Directory |
| 445 | SMB | Archivos e impresoras |
| 3268 | Catálogo global | Búsquedas en el bosque |
| 3389 | RDP | Escritorio remoto |
| 5985 | WinRM | PowerShell remoto |

Si ves abiertos 445, 3389, 389 y 88, hay Windows y hay dominio.

## Diagnóstico

| Comando | Para qué |
|---|---|
| `ipconfig /all` | **Todo**: MAC, DNS, dominio y sufijos. Muchas cosas solo salen aquí |
| `ipconfig /flushdns` | Vacía la caché de nombres |
| `ping host` | Comprueba si responde, aunque el firewall puede bloquearlo |
| `tracert host` | La ruta salto por salto |
| `nslookup nombre servidor` | Pregunta a un DNS concreto |
| `netstat -ano` | Conexiones y puertos en escucha con su PID |
| `arp -a` | Vecinos de la red local |
| `route print` | Tabla de rutas |

## PowerShell

```powershell
Test-NetConnection {DCFQDN} -Port 445
Resolve-DnsName {DCFQDN}
Resolve-DnsName _ldap._tcp.dc._msdcs.{DOMAIN} -Type SRV
Invoke-WebRequest http://servidor/ -UseBasicParsing
```

## SMB

```cmd
net use Z: \\servidor\recurso /user:{NETBIOS}\usuario contraseña
dir Z:
net use Z: /delete
```

## Resolución de nombres, en orden

1. Caché
2. Archivo `hosts`
3. DNS

Si el DNS falla, Windows pregunta a gritos por la red con LLMNR y NBT-NS, y ahí es donde herramientas como Responder se hacen pasar por el destino. Por eso se apagan.

> El archivo `hosts` no publica registros SRV. Sirve para nombres sueltos, no para localizar un controlador de dominio.

## Los dos que abren Active Directory

**LDAP (389)** es el idioma para consultar el directorio: todo `Get-ADUser` es LDAP por debajo. **Kerberos (88)** autentica con boletos: al entrar recibes un **TGT** y para cada servicio lo cambias por un **TGS**. Tu contraseña no viaja.

```cmd
klist
```
