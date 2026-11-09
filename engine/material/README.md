<p align="center"><b>Español</b> · <a href="README.en.md">English</a> · <a href="README.ru.md">Русский</a></p>

# Material del alumnado

Guías, chuletas y plantillas que el laboratorio publica para el alumnado. Cada documento existe en español, inglés y ruso, y esta tabla relaciona cada uno con sus traducciones.

## Dónde lo ve el alumnado

Al ejecutar `..\engine\Initialize-Challenges.ps1`, el material del idioma del laboratorio (`Language` en `config/lab.config.psd1`) se copia a la raíz del recurso público del dominio (`Publico` o `Public`, según el idioma de los nombres). Además, los tres idiomas completos quedan en las carpetas `lang\es`, `lang\en` y `lang\ru` de ese mismo recurso, para que cada persona pueda leerlos en el idioma que prefiera.

## Documentos

| Documento | Español | English | Русский |
|---|---|---|---|
| Guía del alumno | [GUIA-ALUMNO.md](es/GUIA-ALUMNO.md) | [STUDENT-GUIDE.md](en/STUDENT-GUIDE.md) | [STUDENT-GUIDE.md](ru/STUDENT-GUIDE.md) |
| Guía de conexión | [GUIA-CONEXION.md](es/GUIA-CONEXION.md) | [CONNECTION-GUIDE.md](en/CONNECTION-GUIDE.md) | [CONNECTION-GUIDE.md](ru/CONNECTION-GUIDE.md) |
| Índice del recurso público | [LEEME.txt](es/LEEME.txt) | [README.txt](en/README.txt) | [README.txt](ru/README.txt) |
| Scripts para unir el equipo | [LEEME.txt](es/Scripts/LEEME.txt) | [README.txt](en/Scripts/README.txt) | [README.txt](ru/Scripts/README.txt) |
| Cómo entregar | [00-como-entregar.md](es/Material/00-como-entregar.md) | [00-how-to-submit.md](en/Material/00-how-to-submit.md) | [00-how-to-submit.md](ru/Material/00-how-to-submit.md) |
| Chuleta día 2: consola | [chuleta-dia2-cmd.md](es/Material/chuleta-dia2-cmd.md) | [cheatsheet-day2-cmd.md](en/Material/cheatsheet-day2-cmd.md) | [cheatsheet-day2-cmd.md](ru/Material/cheatsheet-day2-cmd.md) |
| Chuleta día 3: Linux y Windows | [chuleta-dia3-linux-windows.md](es/Material/chuleta-dia3-linux-windows.md) | [cheatsheet-day3-linux-windows.md](en/Material/cheatsheet-day3-linux-windows.md) | [cheatsheet-day3-linux-windows.md](ru/Material/cheatsheet-day3-linux-windows.md) |
| Chuleta día 4: PowerShell | [chuleta-dia4-powershell.md](es/Material/chuleta-dia4-powershell.md) | [cheatsheet-day4-powershell.md](en/Material/cheatsheet-day4-powershell.md) | [cheatsheet-day4-powershell.md](ru/Material/cheatsheet-day4-powershell.md) |
| Chuleta día 5: red | [chuleta-dia5-red.md](es/Material/chuleta-dia5-red.md) | [cheatsheet-day5-network.md](en/Material/cheatsheet-day5-network.md) | [cheatsheet-day5-network.md](ru/Material/cheatsheet-day5-network.md) |
| Chuleta día 6: Active Directory | [chuleta-dia6-ad.md](es/Material/chuleta-dia6-ad.md) | [cheatsheet-day6-ad.md](en/Material/cheatsheet-day6-ad.md) | [cheatsheet-day6-ad.md](ru/Material/cheatsheet-day6-ad.md) |
| Chuleta día 7: GPO | [chuleta-dia7-gpo.md](es/Material/chuleta-dia7-gpo.md) | [cheatsheet-day7-gpo.md](en/Material/cheatsheet-day7-gpo.md) | [cheatsheet-day7-gpo.md](ru/Material/cheatsheet-day7-gpo.md) |
| Plantilla día 1: mapa | [dia1-mapa.md](es/Templates/dia1-mapa.md) | [day1-map.md](en/Templates/day1-map.md) | [day1-map.md](ru/Templates/day1-map.md) |
| Plantilla día 2: writeup | [dia2-writeup.md](es/Templates/dia2-writeup.md) | [day2-writeup.md](en/Templates/day2-writeup.md) | [day2-writeup.md](ru/Templates/day2-writeup.md) |
| Plantilla día 3: writeup | [dia3-writeup.md](es/Templates/dia3-writeup.md) | [day3-writeup.md](en/Templates/day3-writeup.md) | [day3-writeup.md](ru/Templates/day3-writeup.md) |
| Plantilla día 4: writeup | [dia4-writeup.md](es/Templates/dia4-writeup.md) | [day4-writeup.md](en/Templates/day4-writeup.md) | [day4-writeup.md](ru/Templates/day4-writeup.md) |
| Plantilla día 5: writeup | [dia5-writeup.md](es/Templates/dia5-writeup.md) | [day5-writeup.md](en/Templates/day5-writeup.md) | [day5-writeup.md](ru/Templates/day5-writeup.md) |
| Plantilla día 6: writeup | [dia6-writeup.md](es/Templates/dia6-writeup.md) | [day6-writeup.md](en/Templates/day6-writeup.md) | [day6-writeup.md](ru/Templates/day6-writeup.md) |
| Plantilla día 7: writeup | [dia7-writeup.md](es/Templates/dia7-writeup.md) | [day7-writeup.md](en/Templates/day7-writeup.md) | [day7-writeup.md](ru/Templates/day7-writeup.md) |

## Cómo editarlo

- Cada idioma vive en su carpeta: `es`, `en` y `ru`. Si cambias un documento, cambia también sus otras dos versiones para que digan lo mismo.
- Los textos entre llaves, como `{ORG}`, `{DOMAIN}`, `{DC}` o `{DELIVER_DIR}`, se rellenan solos al publicar con los valores de la configuración. Déjalos tal cual.
- Los comandos, rutas y nombres de archivo de los bloques de código tienen que coincidir con lo que siembra el laboratorio. El corrector busca las plantillas por su nombre: `dia1-mapa` y `diaN-writeup` en un laboratorio en español, `day1-map` y `dayN-writeup` en inglés o ruso.
- Guarda los archivos en UTF-8.
- Para publicar los cambios en un servidor ya instalado, ejecuta `..\engine\Initialize-Challenges.ps1 -SkipStudents` desde `C:\Lab\setup`. Las banderas no cambian mientras no uses `-Rotate`.
