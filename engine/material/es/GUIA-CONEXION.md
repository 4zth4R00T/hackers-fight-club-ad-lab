# Conexión y entregas

Cómo entrar, qué tienes montado y **cómo sabe el servidor que terminaste cada actividad**. Los tres tipos de reto se marcan de forma distinta y ninguno avisa: si haces el trabajo en el lugar equivocado, no puntúa.

## 1. Llegar al laboratorio

El controlador de dominio es `{DCFQDN}`. Tu instructor eligió una de estas cuatro formas de llegar a él:

| Modo | Qué necesitas en tu equipo |
|---|---|
| Tailscale | Tailscale instalado y con sesión en la red del curso. `Join-Lab.ps1 -Prepare` deja el túnel en modo desatendido para que suba antes de iniciar sesión |
| VPN | El cliente de la VPN (WireGuard, OpenVPN u otro) conectado antes de iniciar sesión en Windows |
| VMnet | Tu máquina virtual en la misma red virtual de VMware que el servidor |
| LAN | Tu equipo en la misma red local que el servidor |

En los cuatro casos el script hace lo mismo: crea una regla NRPT para que solo las consultas de `{DOMAIN}` vayan al DNS del laboratorio y el resto de tu navegación siga igual.

```powershell
.\Join-Lab.ps1                                   # comprueba, no cambia nada
.\Join-Lab.ps1 -Prepare                          # deja el equipo listo
.\Join-Lab.ps1 -Join -User nombre.apellido       # prepara y une
.\Join-Lab.ps1 -Leave -User nombre.apellido      # lo deshace todo
```

**Espera a tener red antes de escribir la contraseña.** Si entras sin conexión al laboratorio, Windows no falla: te deja pasar con credenciales guardadas. Pero entras sin ticket de Kerberos, sin `H:` y sin que nada de lo que hagas quede registrado. Para comprobar que tu sesión es real:

```powershell
klist                    # debe aparecer krbtgt
Get-Progress             # si responde, estás dentro de verdad
```

## 2. Tu slot

Tu cuenta es `nombre.apellido`, pero el laboratorio también te identifica con un **slot**: `{STUDENT_PREFIX}1`, `{STUDENT_PREFIX}2` y así. Son dos nombres para la misma persona y hacen falta los dos.

```powershell
(Get-Item H:).Target      # la última parte de la ruta es tu slot
```

Anótalo. Lo necesitas el día 7.

## 3. Lo que tienes montado

| Qué | Dónde | Puedes |
|---|---|---|
| Tu carpeta personal | `H:` en `\\{DC}\{SHARE_HOME}\<slot>` | Leer y escribir |
| Tus entregas | `H:\{DELIVER_DIR}` | Leer y escribir |
| Tu laboratorio | `%USERPROFILE%\{KIT_DIR}` | Leer y escribir |
| Material del curso | `\\{DC}\{SHARE_PUBLIC}` | Solo leer |
| Buzón de banderas | `\\{DC}\{SHARE_DROPBOX}` | Solo escribir |
| Tu correo | `H:\{MAIL_DIR}\Inbox` | Leer y escribir |
| La tabla | {WEB_URL} | Consultar y entregar |

El buzón de banderas es ciego a propósito: puedes dejar cosas, pero no listarlo ni leer lo de nadie. No lo abras a mano, usa `Submit-Flag`.

## 4. Cómo se marca cada actividad

### Bandera que entregas tú

Encuentras una cadena `{FLAG}{...}` y la entregas con `Submit-Flag` o desde la web. Las banderas son tuyas: entregar una ajena resta 10 puntos y queda registrado. Cópiala completa, con las llaves y sin espacios.

### Writeup en `H:\{DELIVER_DIR}`

No se entrega con ningún comando. Basta con que el archivo exista con el nombre exacto: `dia1-mapa`, `dia2-writeup`, `dia3-writeup` y así hasta `dia7-writeup`. La extensión puede ser cualquiera de estas, y cada formato tiene un tamaño mínimo distinto:

| Formato | Mínimo |
|---|---|
| `.txt` `.md` | 500 bytes |
| `.excalidraw` | 800 bytes |
| `.rtf` `.html` | 1,5 KB |
| `.svg` | 2 KB |
| `.pdf` `.odt` | 8 KB |
| `.docx` | 9 KB |
| `.png` `.jpg` | 20 KB |

Los mínimos no son iguales porque no miden lo mismo: 500 bytes de texto plano son media página escrita, pero 500 bytes de `.docx` son un documento vacío. Y se comprueba la firma de los bytes, no la extensión: renombrar un `.txt` a `.pdf` no funciona.

### Trabajo que el servidor revisa solo

Aquí no hay nada que entregar. El corrector inspecciona AD y tu carpeta. Si lo haces en otra ruta u otra OU, no cuenta.

| Reto | Qué se comprueba |
|---|---|
| D4-02 | En `H:\{WORK_DIR}\{K_DAY4}\{K_CH2}`: al menos 3 carpetas con al menos 3 archivos cada una |
| D4-OPT1 | En `H:\{WORK_DIR}\{K_DAY4}`: un CSV y un JSON válidos |
| D7-G1 | Una GPO de horario vinculada a tu OU, o `logonHours` en una cuenta de tu OU |
| D7-G2 | Una GPO vinculada a tu OU con auditoría de creación de procesos o registro de bloques de script |
| D7-G3 | Una GPO de fondo bloqueado vinculada a tu OU **y** filtrada a un grupo que no sea Usuarios autenticados |
| D7-CREA | Un usuario en tu OU que pertenezca a un grupo distinto del primario |

## 5. Dos tropiezos frecuentes

**Error 1219 al montar un recurso con otra cuenta.** Windows no permite dos conexiones al mismo servidor con usuarios distintos. Si ya tienes `H:` montada, usa la IP del DC en lugar del nombre para la segunda conexión, o desmonta primero con `net use * /delete`.

**El archivo hosts no basta.** Resuelve nombres sueltos, pero no publica los registros SRV que Windows necesita para encontrar el controlador. Para unirte hace falta el DNS del laboratorio.
