<p align="center"><img src="assets/logo/hfc-logo-256.png" width="160" alt="Hackers Fight Club"></p>

<h1 align="center">Hackers Fight Club · Laboratorio de Active Directory</h1>

<p align="center">Windows Server 2025 · siete días de práctica · banderas por alumno · web de puntuación</p>

<p align="center"><a href="README.en.md">English version</a> · <a href="README.ru.md">Версия на русском</a> · <a href="https://4zth4r00t.github.io/hackers-fight-club-ad-lab/">Página del proyecto</a></p>

Este repositorio levanta desde cero un controlador de dominio con Windows Server 2025 preparado para enseñar Windows y Active Directory. El curso cubre siete días: consola, registro, NTFS, PowerShell, red, enumeración del directorio y directivas de grupo. Incluye una web de puntuación, correo interno, una intranet, un fondo de pantalla con el nombre de quien inicia sesión y scripts para dar de alta alumnado e instructores desde un CSV.

Lo desarrolló Aztharot para el Hackers Fight Club. Si te sirve, sígueme en Instagram: [@its_aztharot.exe](https://instagram.com/its_aztharot.exe).

## Fecha de corte

Este laboratorio se escribió y se probó con la información disponible al **9 de noviembre de 2026**, sobre Windows Server 2025 compilación 26100.

Las debilidades del laboratorio vienen de la configuración y no de fallos sin parchear, pero Windows cambia con cada actualización acumulativa. Una actualización posterior puede cerrar un comportamiento que aquí se usa, cambiar un valor por defecto o añadir una protección nueva. Antes de abrir el laboratorio a un grupo, ejecuta `Test-Lab.ps1`, recorre tú mismo cada reto y comprueba que sigue funcionando como se describe. Si algo dejó de reproducirse, revisa las notas de versión de Microsoft posteriores a esa fecha.

## Aviso de uso

Es un entorno vulnerable a propósito. Úsalo solo en una red aislada que controles: una red virtual de VMware, una VPN privada o una LAN de prácticas. No lo conectes a una red de producción ni lo publiques en Internet. Las banderas, las contraseñas y los secretos se generan en cada instalación, así que el repositorio no contiene ninguna respuesta.

## Requisitos mínimos

| Elemento | Mínimo | Recomendado |
|---|---|---|
| ISO | Windows Server 2025 Standard o Datacenter con experiencia de escritorio, compilación 26100. Sirve la de evaluación de 180 días | La misma, actualizada |
| Idioma del ISO | Inglés (en-US), español de España (es-ES) o ruso (ru-RU) | Para Latinoamérica usa el ISO es-ES con la región es-MX |
| Procesador | 2 vCPU de 64 bits | 4 vCPU |
| Memoria | 4 GB | 8 GB, porque la web corre en Node.js |
| Disco | 64 GB | 80 GB |
| Firmware | UEFI o BIOS | UEFI con arranque seguro |
| Red | Un adaptador | Uno en la red del laboratorio |
| Internet | Durante la instalación, para descargar Node.js | Sin Internet, deja el instalador `node-v*-x64.msi` en la carpeta `web` |

Los equipos del alumnado necesitan Windows 10 u 11 Pro, Enterprise o Education, porque la edición Home no se une a un dominio, y Windows PowerShell 5.1.

El laboratorio funciona igual sobre Windows Server en inglés, en español de España, con formato regional de Latinoamérica o en ruso. Los scripts nunca dependen del nombre traducido de un grupo o de una cuenta: los localizan por su SID.

## Qué contiene

| Carpeta | Contenido |
|---|---|
| `config` | `lab.config.psd1` con toda la configuración y `staff.csv` con la plantilla ficticia de la empresa |
| `setup` | Los pasos de instalación del controlador y los scripts de alta por CSV |
| `engine` | El catálogo de retos, la siembra de banderas, el corrector y el informe de integridad |
| `services` | Intranet, servicio del puerto inesperado, correo SMTP y POP3, monitor y su registro |
| `web` | La web de puntuación, retos, entregas, monitor y asistencia |
| `client` | Lo que corre en el equipo del alumno y el fondo de pantalla dinámico |
| `unattend` | La plantilla de instalación desatendida y los generadores de la ISO de respuestas |
| `assets` | Logo del club, fondo base y tipografías con su licencia |
| `lang` | Los textos y los nombres en ruso que usan los scripts del servidor y del alumnado |
| `examples` | CSV de ejemplo con nombres ficticios, en español, inglés y ruso |
| `site` | La página del proyecto en Astro, publicada con GitHub Pages |

## Configuración

Todo sale de `config/lab.config.psd1`. Edítalo antes de instalar.

| Clave | Para qué sirve | Valor por defecto |
|---|---|---|
| `Language` | Idioma de los mensajes y de los textos: `es`, `en`, `ru` o `auto` | `auto` |
| `NamesLanguage` | Idioma de los nombres de OU, grupos, recursos y carpetas: `es`, `en`, `ru` o `auto` para seguir a `Language` | `auto` |
| `Organization` | Nombre de la empresa ficticia | `Atlas Corp` |
| `LabName` | Nombre visible del laboratorio | `Hackers Fight Club` |
| `DomainPrefix` y `DomainSuffix` | Prefijo y sufijo del dominio. Con los valores de ejemplo queda `fightclub.lab` | `fightclub` y `lab` |
| `NetBIOSName` | Nombre corto del dominio | `FIGHTCLUB` |
| `DcHostPrefix` y `DcHostNumber` | Prefijo y número del controlador. Con los valores de ejemplo queda `DC01` | `DC` y `1` |
| `Root` | Carpeta del laboratorio en el servidor | `C:\Lab` |
| `GroupPrefix` | Prefijo de la OU raíz y de los grupos | `Lab` |
| `FlagPrefix` | Prefijo de las banderas, por ejemplo `FLAG{...}` | `FLAG` |
| `StudentPrefix` | Prefijo del identificador permanente de cada alumno | `alumno` en español y `student` en inglés o ruso |
| `NetworkMode` | `Tailscale`, `VPN`, `VMnet` o `LAN` | `VMnet` |
| `LanIPAddress`, `LanPrefixLength`, `LanGateway` | IP fija del controlador en su red local o virtual | `192.168.251.10/24` |
| `DnsForwarders` | Servidores DNS a los que el controlador reenvía lo que no es del dominio | La puerta de enlace de VMware y dos públicos |
| `VpnInterface` y `VpnClientCidr` | Adaptador y red de clientes en modo VPN | `WireGuard*` y `10.9.0.0/24` |
| `ExtraClientCidrs` | Redes adicionales que pueden usar los servicios | vacío |
| `WebPort`, `IntranetPort`, `BannerPort`, `SmtpPorts`, `Pop3Port` | Puertos de los servicios | 8443, 80, 1337, 25 y 587, 110 |
| `MinPasswordLength` y `LockoutThreshold` | Política de contraseñas | 12 y 10 |
| `TimeZone` | Zona horaria de Windows, vacío para no tocarla | vacío |
| `Wallpaper`, `Challenges`, `Mail`, `Web` | Interruptores de cada componente | todos activos |
| `Weaknesses` | Interruptor de cada debilidad deliberada, explicadas más abajo | todas activas |

Con `auto`, el idioma sale del idioma de Windows: un servidor en ruso usa `ru`, uno en español usa `es` y cualquier otro usa `en`. Con `NamesLanguage` en `ru`, las OU, los grupos, los departamentos, los roles y las GPO llevan nombre en ruso, mientras que los recursos compartidos, las carpetas, los archivos de los kits y los buzones de correo quedan en caracteres latinos para escribirlos cómodo en la consola.

### Modos de red

| Modo | Cuándo usarlo | Qué hace |
|---|---|---|
| `VMnet` | El servidor y los equipos del alumnado viven en la misma red virtual de VMware | Los servicios escuchan en la IP fija y solo aceptan esa subred |
| `LAN` | Un salón con equipos físicos en la misma red | Igual que VMnet, sobre la red del salón |
| `Tailscale` | El alumnado se conecta desde su casa por una tailnet | Los servicios escuchan en la IP de Tailscale y solo aceptan `100.64.0.0/10` |
| `VPN` | Usas WireGuard, OpenVPN u otra VPN propia | Los servicios escuchan en la IP del adaptador VPN y solo aceptan `VpnClientCidr` |

El dominio siempre se publica en la IP fija de la red local. En los modos Tailscale y VPN también se publica en la IP del túnel. Puedes cambiar de modo cuando quieras con `Set-NetworkMode.ps1`.

## Instalación paso a paso

### 1. Instala Windows Server 2025

Tienes dos caminos.

**Con la ISO de respuestas.** Genera un disco pequeño con la instalación desatendida y el kit del laboratorio. Desde Linux:

```bash
./unattend/new-answer-iso.sh -p es-MX -o lab-answers.iso
```

Desde Windows:

```powershell
.\unattend\New-AnswerIso.ps1 -Region es-MX -OutFile .\lab-answers.iso
```

La región puede ser `en-US`, `es-MX`, `es-ES` o `ru-RU`. Con `ru-RU` usa el ISO de Windows Server en ruso: el teclado queda en inglés por defecto con el ruso disponible y la hora es la de Moscú. Te pide la contraseña del administrador. Con `-g` en Linux o `-GeneratePassword` en Windows la genera y la guarda junto a la ISO en un archivo que solo tú puedes leer. Con `-a` o `-AutoStart` la instalación del laboratorio arranca sola en el primer inicio de sesión. Usa `-f bios` o `-Firmware bios` si tu máquina virtual no usa UEFI.

Crea la máquina virtual con el ISO original de Windows Server 2025 en la primera unidad de CD y la ISO de respuestas en la segunda. Windows se instala sin preguntar nada, nombra al servidor según tu configuración y copia el kit en `C:\Lab`.

**A mano.** Instala Windows Server 2025 con experiencia de escritorio, inicia sesión como administrador y copia la carpeta del repositorio a `C:\Lab`.

### 2. Ejecuta los pasos en orden

Abre PowerShell como administrador y entra a la carpeta de instalación:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
cd C:\Lab\setup
```

Ejecuta cada script en este orden. Todos muestran un resumen al terminar y te dicen cuál sigue.

| Orden | Comando | Qué hace |
|---|---|---|
| 1 | `.\Set-ServerNetwork.ps1 -Restart` | Fija la IP, crea las reglas de firewall, configura la hora y renombra el servidor. Reinicia |
| 2 | `.\Install-DomainController.ps1 -Restart` | Instala AD DS y DNS y crea el bosque. Genera la clave DSRM. Reinicia |
| 3 | `.\Set-DomainDns.ps1` | Reenviadores, zona inversa y direcciones en las que se publica el dominio |
| 4 | `.\New-DirectoryStructure.ps1` | OUs, grupos, política de contraseñas, delegación, plantilla ficticia, cuentas de servicio e inventario de equipos |
| 5 | `.\New-FileShares.ps1` | Carpetas personales, material público, buzón ciego de banderas y recurso confidencial |
| 6 | `.\Set-GroupPolicies.ps1` | Quién puede iniciar sesión en el controlador y el fondo de pantalla dinámico |
| 7 | `.\Protect-DomainController.ps1` | Blindaje del controlador y auditoría |
| 8 | `..\engine\Initialize-Challenges.ps1` | Genera la sal de las banderas, siembra los retos y prepara los kits |
| 9 | `.\Add-Administrators.ps1 -Path ..\config\admins.csv` | Da de alta a los instructores |
| 10 | `.\Add-Students.ps1 -Path ..\config\alumnos.csv` | Da de alta al alumnado y prepara su kit personal |
| 11 | `..\services\Register-Services.ps1` | Registra intranet, puerto inesperado, correo, monitor y corrector |
| 12 | `..\web\Install-Web.ps1` | Instala Node.js, compila la web, crea el certificado y la publica |
| 13 | `.\Test-Lab.ps1` | Verifica todo y lista las debilidades activas |

Si prefieres que corra todo seguido, `.\Install-Lab.ps1 -Start` ejecuta la misma secuencia, sobrevive a los reinicios y continúa sola. `.\Install-Lab.ps1` sin parámetros muestra en qué paso va, y `-Resume` sigue después de corregir un error. Si pusiste `admins.csv` y `alumnos.csv` dentro de `config` antes de empezar, ese recorrido los da de alta solo.

Las contraseñas generadas quedan en `C:\Lab\data`, que solo leen SYSTEM y los administradores. La clave DSRM y la contraseña del administrador cópialas fuera del servidor.

### 3. Une los equipos del alumnado

En cada equipo, como administrador local, ejecuta `client\Join-Lab.ps1`. Sin parámetros solo diagnostica. Con `-Prepare` ajusta el DNS y la red según el modo, con `-Join -User <usuario>` une el equipo al dominio en la OU de estaciones y con `-Leave` lo saca y deja todo como estaba.

## Altas por CSV

Los CSV aceptan encabezados en español, inglés o ruso, separados por coma o por punto y coma, en UTF-8 o, si salen de un Excel en ruso, en Windows-1251. Las columnas vacías se rellenan solas: el usuario se arma con la inicial y el primer apellido, el correo con el dominio y la contraseña se genera. Los nombres en cirílico se transliteran a caracteres latinos para el usuario, así que Иван Петров queda como `i.petrov`.

Alumnado, con `Add-Students.ps1`:

```csv
nombre,apellidos,usuario,correo,contrasena,grupo
Valeria,Ejemplo Uno,,,,
Diego,Ejemplo Dos,d.ejemplo2,,,
```

Equivalente en inglés: `firstname,lastname,username,email,password,group`. En ruso: `имя,фамилия,пользователь,почта,пароль,группа`.

Instructores y administradores, con `Add-Administrators.ps1`:

```csv
nombre,apellidos,usuario,correo,contrasena,rol
Instructora,Ejemplo,adm.instructora,,,instructor
Dominio,Ejemplo,adm.dominio,,,admin
```

El rol `instructor` administra la OU del laboratorio por delegación y puede entrar por escritorio remoto, sin ser administrador del dominio. El rol `admin` lo agrega además a los administradores del dominio. En un CSV en ruso sirven `преподаватель` y `администратор`. Cada alta deja un CSV con las credenciales en `C:\Lab\data`; bórralo cuando las hayas repartido.

Cada alumno recibe un identificador permanente (`alumno1`, `alumno2` y así), una carpeta personal en la unidad `H:`, una OU propia dentro de `Sandbox` con control total para practicar y su kit de retos. Las banderas personales se derivan de ese identificador, así que puedes renombrar la cuenta sin invalidar nada.

## Fondo de pantalla dinámico

Todo el que inicie sesión en un equipo del dominio, sea alumno, instructor o administrador, ve un fondo con el logo del club, su nombre completo, su rol, su cuenta, el equipo y la fecha. Se genera al vuelo en cada inicio de sesión con la resolución de la pantalla. Si algo falla, queda el fondo base del club. El script vive en `NETLOGON\wallpaper` y lo activa la GPO de fondo de pantalla vinculada al dominio.

## Las actividades

Siete días, 36 retos: 620 puntos obligatorios y 100 opcionales. La primera persona en resolver un reto suma 5 puntos más, completar un día suma 25 y entregar la bandera de otra persona resta 10.

| Día | Tema | Qué se practica |
|---|---|---|
| 1 | Conocer Windows | Un mapa propio de los conceptos básicos |
| 2 | La consola | Variables de entorno, archivos ocultos, búsqueda dentro de archivos, PATH, tareas programadas |
| 3 | Windows por dentro | Registro, flujos alternos de NTFS, enlaces y SID |
| 4 | Automatizar con PowerShell | Búsqueda en registros grandes, creación de estructuras, unión ordenada de partes, exportación a CSV y JSON |
| 5 | La red y el hilo completo | Configuración de red, barrido de DNS, SMB con credenciales encadenadas, un puerto inesperado y correo interno |
| 6 | Active Directory | Enumeración de usuarios, grupos, equipos y cuentas con SPN |
| 7 | Administrar y defender | GPO de horario, auditoría de procesos, fondo filtrado por grupo, altas de usuarios y un writeup con sección de defensa |

Cada día termina con un writeup. Los retos de los días 4 y 7 que no llevan bandera los comprueba el corrector leyendo la carpeta del alumno, su OU y SYSVOL.

El laboratorio incluye controles de integridad: banderas distintas para cada alumno, propietario NTFS de cada entrega, cinco señuelos que solo encuentra quien vuelca archivos enteros y señales de comportamiento. El informe sale con `engine\Get-IntegrityReport.ps1` y nunca aparece en la tabla pública. Un señuelo no prueba nada por sí solo: es motivo para conversar con la persona.

## Debilidades deliberadas

Estas son las debilidades que el laboratorio deja abiertas a propósito. Cada una se apaga en `Weaknesses` dentro de la configuración.

| Interruptor | Debilidad | Lo que enseña |
|---|---|---|
| `ServiceAccountsWithSpn` | Cuentas de servicio con SPN | Enumerar SPN y entender Kerberoasting. Sus claves son largas y aleatorias, que es la defensa |
| `DirectoryNotes` | Datos sensibles en Description e info de usuarios, equipos y grupos | Que el directorio guarda más de lo que muestra un listado normal |
| `TokenInDnsSuffix` | Un secreto repartido en la lista de sufijos DNS por GPO | Que la configuración de red completa revela más que `ipconfig` a secas |
| `SharedSmbAccount` | Una cuenta compartida de SMB cuya contraseña es ese secreto | Reutilización de credenciales y movimiento entre pistas |
| `InternalHttpIntranet` | Intranet HTTP sin cifrar con nombres internos | Barrido de DNS automatizado y lectura de HTML |
| `UnexpectedBannerPort` | Un servicio escuchando donde no debería | Escaneo de puertos y conversación con un servicio desconocido |
| `PlaintextMail` | Correo SMTP y POP3 sin TLS | Protocolos en claro y autenticación expuesta en la red |
| `DelegatedSandboxOUs` | Control total del alumno sobre su propia OU | Delegación en AD y sus riesgos |
| `StudentsCreateGpos` | Alumnado en Propietarios del creador de directivas de grupo | Crear y vincular GPO, y por qué ese grupo es sensible |
| `HighLockoutThreshold` | Bloqueo de cuenta tras 10 intentos | Por qué un umbral alto facilita el rociado de contraseñas |

La delegación para unir equipos en la OU de estaciones también es un riesgo conocido: quien puede unir equipos ahí puede restablecer la contraseña de otros equipos de esa OU.

Lo que sí queda protegido: la cuota de equipos por usuario está en 0, el alumnado no puede iniciar sesión en el controlador, los instructores no son administradores del dominio, el buzón de banderas es ciego, cada expediente confidencial solo lo lee su dueño, el firewall bloquea toda entrada salvo la red del laboratorio, la cola de impresión y NetBIOS están apagados, la LSA corre protegida, WDigest no guarda claves en claro y la auditoría avanzada está activa. La auditoría de creación de procesos queda apagada a propósito porque es un ejercicio del día 7.

## Comandos de operación

| Comando | Para qué |
|---|---|
| `.\Install-Lab.ps1` | Estado de la instalación |
| `.\Test-Lab.ps1` | Verificación completa y debilidades activas |
| `.\Set-NetworkMode.ps1 -Mode Tailscale -ConnectTailscale` | Pasar a Tailscale, instalarlo y conectarlo |
| `.\Set-NetworkMode.ps1 -Mode LAN -LanIPAddress 10.0.0.10 -LanPrefixLength 24 -LanGateway 10.0.0.1` | Pasar a una LAN con otra IP |
| `..\engine\Invoke-Scorer.ps1 -Rebuild` | Recalcular toda la puntuación |
| `..\engine\Get-IntegrityReport.ps1 -Student alumno7` | Informe de integridad de una persona |
| `..\web\Install-Web.ps1 -Status` | Estado de la web, el certificado y el servicio |
| `..\web\Install-Web.ps1 -Restart` | Reiniciar la web |
| `..\services\Register-Services.ps1 -Remove` | Quitar los servicios del laboratorio |

Los registros quedan en `C:\Lab\logs`.

## Página del proyecto

La página vive en `site/` y está hecha con Astro. Se publica sola en GitHub Pages con el flujo `.github/workflows/pages.yml` cada vez que cambia algo dentro de `site/`. Para activarla, en el repositorio entra a Settings, luego Pages, y en Source elige GitHub Actions. Queda en `https://<tu-usuario>.github.io/<nombre-del-repositorio>/` y está en español, inglés y ruso.

Para verla en tu equipo:

```bash
cd site
pnpm install
pnpm dev
```

## Créditos

Desarrollado por Aztharot para el Hackers Fight Club.

Instagram: [@its_aztharot.exe](https://instagram.com/its_aztharot.exe) · GitHub: [4zth4R00T](https://github.com/4zth4R00T)

Las tipografías Cormorant Garamond e IBM Plex Mono se distribuyen bajo la licencia SIL Open Font License 1.1, incluida en `assets/fonts/OFL.txt`. El código se publica bajo la licencia MIT.
