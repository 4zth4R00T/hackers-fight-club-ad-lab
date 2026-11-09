# Cómo entregar y ver cómo vas

```powershell
Submit-Flag "{FLAG}{...}"      # entregar una bandera
Get-Progress                   # tu marcador
Get-Progress -Detail           # reto por reto
Get-Challenges 2 -Hints        # si te atoras
Get-Hint D2-03                 # pista escalonada, no resta puntos
```

El corrector pasa cada minuto. Tabla de la clase: **{WEB_URL}**. Desde la web también puedes entregar banderas y subir tu writeup en `.txt`, `.md`, `.pdf`, `.docx` o `.excalidraw`.

## No todo se entrega

Algunos retos se comprueban solos: el reto 2 del día 4 y los cuatro de administración del día 7. Ahí no hay bandera que buscar, hay trabajo que hacer, y el corrector revisa tu unidad `H:` y tu OU.

## Los writeups puntúan

Van en `H:\{DELIVER_DIR}` con el nombre del día: `dia1-mapa.md`, `dia2-writeup.md` y así hasta `dia7-writeup.md`. Hay una plantilla por día en `\\{DC}\{SHARE_PUBLIC}\{TEMPLATES_DIR}`. Un archivo de dos líneas no cuenta: se pide contenido real.

## Tu correo

```powershell
Get-LabMail
Read-LabMail 1
Send-LabMail -To alguien@{DOMAIN} -Subject "..." -Body "..."
```

Servidor `{MAIL_HOST}`, SMTP 25 o 587 y POP3 110, con tu usuario del dominio.

## Reglas

Tu parcela es tu OU dentro de `OU={OU_SANDBOX}`. Fuera de ahí eres un usuario común. No toques el controlador de dominio. Nada de lo que aprendas aquí se prueba fuera sin autorización expresa y por escrito.
