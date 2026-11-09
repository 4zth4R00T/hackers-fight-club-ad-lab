<p align="center"><a href="README.md">Español</a> · <b>English</b> · <a href="README.ru.md">Русский</a></p>

# Student material

Guides, cheat sheets and templates the lab publishes for students. Every document exists in Spanish, English and Russian, and this table maps each one to its translations.

## Where students see it

When `..\engine\Initialize-Challenges.ps1` runs, the material in the lab language (`Language` in `config/lab.config.psd1`) is copied to the root of the domain's public share (`Public` or `Publico`, depending on the naming language). All three languages are also published in full under `lang\es`, `lang\en` and `lang\ru` on that same share, so everyone can read them in the language they prefer.

## Documents

| Document | Español | English | Русский |
|---|---|---|---|
| Student guide | [GUIA-ALUMNO.md](es/GUIA-ALUMNO.md) | [STUDENT-GUIDE.md](en/STUDENT-GUIDE.md) | [STUDENT-GUIDE.md](ru/STUDENT-GUIDE.md) |
| Connection guide | [GUIA-CONEXION.md](es/GUIA-CONEXION.md) | [CONNECTION-GUIDE.md](en/CONNECTION-GUIDE.md) | [CONNECTION-GUIDE.md](ru/CONNECTION-GUIDE.md) |
| Public share index | [LEEME.txt](es/LEEME.txt) | [README.txt](en/README.txt) | [README.txt](ru/README.txt) |
| Scripts to join a computer | [LEEME.txt](es/Scripts/LEEME.txt) | [README.txt](en/Scripts/README.txt) | [README.txt](ru/Scripts/README.txt) |
| How to submit | [00-como-entregar.md](es/Material/00-como-entregar.md) | [00-how-to-submit.md](en/Material/00-how-to-submit.md) | [00-how-to-submit.md](ru/Material/00-how-to-submit.md) |
| Cheat sheet day 2: command prompt | [chuleta-dia2-cmd.md](es/Material/chuleta-dia2-cmd.md) | [cheatsheet-day2-cmd.md](en/Material/cheatsheet-day2-cmd.md) | [cheatsheet-day2-cmd.md](ru/Material/cheatsheet-day2-cmd.md) |
| Cheat sheet day 3: Linux and Windows | [chuleta-dia3-linux-windows.md](es/Material/chuleta-dia3-linux-windows.md) | [cheatsheet-day3-linux-windows.md](en/Material/cheatsheet-day3-linux-windows.md) | [cheatsheet-day3-linux-windows.md](ru/Material/cheatsheet-day3-linux-windows.md) |
| Cheat sheet day 4: PowerShell | [chuleta-dia4-powershell.md](es/Material/chuleta-dia4-powershell.md) | [cheatsheet-day4-powershell.md](en/Material/cheatsheet-day4-powershell.md) | [cheatsheet-day4-powershell.md](ru/Material/cheatsheet-day4-powershell.md) |
| Cheat sheet day 5: network | [chuleta-dia5-red.md](es/Material/chuleta-dia5-red.md) | [cheatsheet-day5-network.md](en/Material/cheatsheet-day5-network.md) | [cheatsheet-day5-network.md](ru/Material/cheatsheet-day5-network.md) |
| Cheat sheet day 6: Active Directory | [chuleta-dia6-ad.md](es/Material/chuleta-dia6-ad.md) | [cheatsheet-day6-ad.md](en/Material/cheatsheet-day6-ad.md) | [cheatsheet-day6-ad.md](ru/Material/cheatsheet-day6-ad.md) |
| Cheat sheet day 7: GPO | [chuleta-dia7-gpo.md](es/Material/chuleta-dia7-gpo.md) | [cheatsheet-day7-gpo.md](en/Material/cheatsheet-day7-gpo.md) | [cheatsheet-day7-gpo.md](ru/Material/cheatsheet-day7-gpo.md) |
| Template day 1: map | [dia1-mapa.md](es/Templates/dia1-mapa.md) | [day1-map.md](en/Templates/day1-map.md) | [day1-map.md](ru/Templates/day1-map.md) |
| Template day 2: writeup | [dia2-writeup.md](es/Templates/dia2-writeup.md) | [day2-writeup.md](en/Templates/day2-writeup.md) | [day2-writeup.md](ru/Templates/day2-writeup.md) |
| Template day 3: writeup | [dia3-writeup.md](es/Templates/dia3-writeup.md) | [day3-writeup.md](en/Templates/day3-writeup.md) | [day3-writeup.md](ru/Templates/day3-writeup.md) |
| Template day 4: writeup | [dia4-writeup.md](es/Templates/dia4-writeup.md) | [day4-writeup.md](en/Templates/day4-writeup.md) | [day4-writeup.md](ru/Templates/day4-writeup.md) |
| Template day 5: writeup | [dia5-writeup.md](es/Templates/dia5-writeup.md) | [day5-writeup.md](en/Templates/day5-writeup.md) | [day5-writeup.md](ru/Templates/day5-writeup.md) |
| Template day 6: writeup | [dia6-writeup.md](es/Templates/dia6-writeup.md) | [day6-writeup.md](en/Templates/day6-writeup.md) | [day6-writeup.md](ru/Templates/day6-writeup.md) |
| Template day 7: writeup | [dia7-writeup.md](es/Templates/dia7-writeup.md) | [day7-writeup.md](en/Templates/day7-writeup.md) | [day7-writeup.md](ru/Templates/day7-writeup.md) |

## How to edit it

- Each language lives in its own folder: `es`, `en` and `ru`. When you change a document, change its other two versions too so they say the same thing.
- Text in braces, such as `{ORG}`, `{DOMAIN}`, `{DC}` or `{DELIVER_DIR}`, is filled in at publish time from the configuration. Leave it as it is.
- Commands, paths and file names in code blocks must match what the lab seeds. The grader looks for the templates by name: `dia1-mapa` and `diaN-writeup` in a Spanish lab, `day1-map` and `dayN-writeup` in an English or Russian one.
- Save files as UTF-8.
- To publish your changes to a server that is already installed, run `..\engine\Initialize-Challenges.ps1 -SkipStudents` from `C:\Lab\setup`. Flags do not change unless you use `-Rotate`.
