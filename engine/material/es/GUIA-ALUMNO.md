# {LAB}: guía del alumno

Bienvenida o bienvenido a **{ORG}**. Durante siete días vas a moverte por una empresa Windows de verdad: su dominio, sus usuarios, sus recursos compartidos y sus políticas. Repartidas por ahí hay banderas con el formato `{FLAG}{...}`.

Las banderas son **tuyas**: se calculan a partir de tu cuenta, así que la de tu compañero es distinta de la tuya. Si entregas una que no te corresponde, el scoreboard lo detecta, no suma y queda registrado.

## Antes de empezar

| Necesitas | Por qué |
|---|---|
| Windows 10 u 11 Pro, Enterprise o Education | La edición Home no puede unirse a un dominio |
| Acceso a la red del laboratorio | Puede ser Tailscale, una VPN, la red de VMware o la red local: te lo dice tu instructor |
| Tu usuario y contraseña | Te los entrega tu instructor |

Todo se hace con un solo script, `Join-Lab.ps1`, que está en `\\{DC}\{SHARE_PUBLIC}\Scripts` junto con `lab.json`. Copia los dos a una carpeta de tu equipo y ejecútalo **en PowerShell como administrador**.

Primero comprueba que llegas. Esto no cambia nada: recorre la cadena entera y te dice en qué eslabón se rompe.

```powershell
.\Join-Lab.ps1
```

Si sale limpio, prepara y une el equipo:

```powershell
.\Join-Lab.ps1 -Join -User nombre.apellido
```

Reinicia, inicia sesión con `{NETBIOS}\nombre.apellido` y espera un minuto. Tendrás esto:

| Qué | Dónde |
|---|---|
| Tu laboratorio de los días 2 a 5 | `%USERPROFILE%\{KIT_DIR}` |
| Tu unidad de red | `H:` |
| Tus entregas | `H:\{DELIVER_DIR}` |
| Tu buzón de correo | `H:\{MAIL_DIR}\Inbox` |
| El material del curso | `\\{DC}\{SHARE_PUBLIC}` |

## Los comandos que vas a usar

```powershell
Submit-Flag "{FLAG}{...}"      # entregar una bandera
Get-Progress                   # ver cómo vas
Get-Progress -Detail           # reto por reto
Get-Challenges 2 -Hints        # los retos de un día con su pista pública
Get-Hint D2-03                 # la siguiente pista de un reto, sin restar puntos
```

Las pistas te dicen por dónde, no cómo. La ruta y el comando los pones tú: ese es el ejercicio.

La tabla de la clase está en **{WEB_URL}**. Ahí también puedes entregar banderas con tu usuario y contraseña del dominio, aunque no estés en una máquina unida.

El corrector pasa cada minuto. Si entregas algo, espera un poco antes de mirar.

### También tienes correo

{ORG} te dio buzón: `nombre.apellido@{DOMAIN}`. Es un servidor de verdad.

```powershell
Get-LabMail                    # tu bandeja
Read-LabMail 1                 # leer un mensaje
Send-LabMail -To alguien@{DOMAIN} -Subject "Consulta" -Body "..."
```

Entras con tu usuario y contraseña del dominio. Si prefieres un cliente de correo, el servidor es `{MAIL_HOST}`, SMTP en el 25 o el 587 y POP3 en el 110. Lo más instructivo es hacerlo a mano con `telnet {MAIL_HOST} 25`: verás la autenticación, el sobre y el mensaje como capas separadas.

## Cómo se puntúa

| Concepto | Puntos |
|---|---|
| Cada reto | Los suyos, de 10 a 40 |
| Primera sangre | 5 extra para quien lo resuelve primero |
| Día completo | 25 extra al terminar todos los obligatorios del día |
| Entregar la bandera de otra persona | Resta 10 y queda registrado |

Son 36 retos: 620 puntos obligatorios y 100 opcionales.

No todos los retos se entregan. El reto 2 del día 4 y los cuatro de administración del día 7 los revisa el corrector directamente. Los writeups se dejan en `H:\{DELIVER_DIR}` con el nombre del día, por ejemplo `dia2-writeup.md`. Hay plantillas en `\\{DC}\{SHARE_PUBLIC}\{TEMPLATES_DIR}`.

## El mapa de los siete días

**Día 1. Conocer Windows.** Dibuja tu mapa mental: qué es Windows, el entorno, los archivos y las consolas. Lo que importa es que las piezas queden conectadas.

**Día 2. La consola.** Cinco banderas en tu propio equipo, todas al alcance de CMD, en lugares que existen en cualquier Windows y que casi nadie revisa.

**Día 3. Windows por dentro.** El registro, los flujos alternos de NTFS y los enlaces: tres rincones donde Windows deja esconder cosas.

**Día 4. Automatizar.** Aquí no cazas a mano: escribes el programa que caza por ti.

**Día 5. La red.** Tres partes encadenadas: lo que sacas de una es la llave de la siguiente. Además hay dos opcionales: un puerto del DC que no encaja en ninguna tabla y el servidor de correo de la empresa.

**Día 6. Active Directory.** Un objeto de AD tiene unos treinta campos y las consultas normales te muestran unos pocos. Las banderas viven justo en los que no se muestran.

**Día 7. Administrar.** Cambias de silla. Tienes tu propia OU dentro de `OU={OU_SANDBOX}` donde mandas tú: crea ahí tus GPO y tus usuarios. Y escribe el writeup de máquina con su sección de defensa.

## Reglas

**Tu parcela es tu OU.** Lleva el nombre de tu slot, no de tu usuario. Lo ves con `(Get-Item H:).Target`. Trabajar en la OU equivocada es la forma más común de perder los puntos del día 7.

**No toques el controlador de dominio.** Si lo rompes, se lo rompes a toda la clase.

**Nada de lo que aprendas aquí se prueba fuera.** Ni en tu casa, ni en la red de la escuela, ni para probar. El conocimiento ofensivo solo es ético con autorización expresa y por escrito.

**El laboratorio tiene controles de integridad** y se te dice de frente, porque es lo justo. Documenta mientras trabajas: copiar los comandos según los usas cuesta diez segundos; reconstruirlos de memoria días después, una hora.

## Si algo no funciona

| Síntoma | Qué hacer |
|---|---|
| No aparece `{KIT_DIR}` | Cierra sesión y vuelve a entrar. El registro está en `C:\ProgramData\Lab\deploy.log` |
| `Submit-Flag` no llega al servidor | `Test-NetConnection {DCFQDN} -Port 445` y revisa tu conexión a la red del laboratorio |
| No reconoce `Submit-Flag` | Abre otra ventana de PowerShell o ejecuta `Import-Module Student` |
| Entregué una bandera y no suma | Cópiala completa, con las llaves y sin espacios. Y que sea la tuya |

Desarrollado por Aztharot. Instagram: @its_aztharot.exe. GitHub: github.com/4zth4R00T.
