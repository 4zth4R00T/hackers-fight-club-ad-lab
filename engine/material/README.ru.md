<p align="center"><a href="README.md">Español</a> · <a href="README.en.md">English</a> · <b>Русский</b></p>

# Материалы для учащихся

Руководства, шпаргалки и шаблоны, которые лаборатория публикует для учащихся. Каждый документ есть на испанском, английском и русском, а эта таблица связывает его с переводами.

## Где их видят учащиеся

При запуске `..\engine\Initialize-Challenges.ps1` материалы на языке лаборатории (`Language` в `config/lab.config.psd1`) копируются в корень общего ресурса домена (`Public` или `Publico`, в зависимости от языка имён). Кроме того, все три языка полностью публикуются в папках `lang\es`, `lang\en` и `lang\ru` того же ресурса, чтобы каждый мог читать их на удобном языке.

## Документы

| Документ | Español | English | Русский |
|---|---|---|---|
| Руководство учащегося | [GUIA-ALUMNO.md](es/GUIA-ALUMNO.md) | [STUDENT-GUIDE.md](en/STUDENT-GUIDE.md) | [STUDENT-GUIDE.md](ru/STUDENT-GUIDE.md) |
| Руководство по подключению | [GUIA-CONEXION.md](es/GUIA-CONEXION.md) | [CONNECTION-GUIDE.md](en/CONNECTION-GUIDE.md) | [CONNECTION-GUIDE.md](ru/CONNECTION-GUIDE.md) |
| Оглавление общего ресурса | [LEEME.txt](es/LEEME.txt) | [README.txt](en/README.txt) | [README.txt](ru/README.txt) |
| Скрипты для присоединения компьютера | [LEEME.txt](es/Scripts/LEEME.txt) | [README.txt](en/Scripts/README.txt) | [README.txt](ru/Scripts/README.txt) |
| Как сдавать работы | [00-como-entregar.md](es/Material/00-como-entregar.md) | [00-how-to-submit.md](en/Material/00-how-to-submit.md) | [00-how-to-submit.md](ru/Material/00-how-to-submit.md) |
| Шпаргалка, день 2: командная строка | [chuleta-dia2-cmd.md](es/Material/chuleta-dia2-cmd.md) | [cheatsheet-day2-cmd.md](en/Material/cheatsheet-day2-cmd.md) | [cheatsheet-day2-cmd.md](ru/Material/cheatsheet-day2-cmd.md) |
| Шпаргалка, день 3: Linux и Windows | [chuleta-dia3-linux-windows.md](es/Material/chuleta-dia3-linux-windows.md) | [cheatsheet-day3-linux-windows.md](en/Material/cheatsheet-day3-linux-windows.md) | [cheatsheet-day3-linux-windows.md](ru/Material/cheatsheet-day3-linux-windows.md) |
| Шпаргалка, день 4: PowerShell | [chuleta-dia4-powershell.md](es/Material/chuleta-dia4-powershell.md) | [cheatsheet-day4-powershell.md](en/Material/cheatsheet-day4-powershell.md) | [cheatsheet-day4-powershell.md](ru/Material/cheatsheet-day4-powershell.md) |
| Шпаргалка, день 5: сеть | [chuleta-dia5-red.md](es/Material/chuleta-dia5-red.md) | [cheatsheet-day5-network.md](en/Material/cheatsheet-day5-network.md) | [cheatsheet-day5-network.md](ru/Material/cheatsheet-day5-network.md) |
| Шпаргалка, день 6: Active Directory | [chuleta-dia6-ad.md](es/Material/chuleta-dia6-ad.md) | [cheatsheet-day6-ad.md](en/Material/cheatsheet-day6-ad.md) | [cheatsheet-day6-ad.md](ru/Material/cheatsheet-day6-ad.md) |
| Шпаргалка, день 7: GPO | [chuleta-dia7-gpo.md](es/Material/chuleta-dia7-gpo.md) | [cheatsheet-day7-gpo.md](en/Material/cheatsheet-day7-gpo.md) | [cheatsheet-day7-gpo.md](ru/Material/cheatsheet-day7-gpo.md) |
| Шаблон, день 1: карта | [dia1-mapa.md](es/Templates/dia1-mapa.md) | [day1-map.md](en/Templates/day1-map.md) | [day1-map.md](ru/Templates/day1-map.md) |
| Шаблон, день 2: отчёт | [dia2-writeup.md](es/Templates/dia2-writeup.md) | [day2-writeup.md](en/Templates/day2-writeup.md) | [day2-writeup.md](ru/Templates/day2-writeup.md) |
| Шаблон, день 3: отчёт | [dia3-writeup.md](es/Templates/dia3-writeup.md) | [day3-writeup.md](en/Templates/day3-writeup.md) | [day3-writeup.md](ru/Templates/day3-writeup.md) |
| Шаблон, день 4: отчёт | [dia4-writeup.md](es/Templates/dia4-writeup.md) | [day4-writeup.md](en/Templates/day4-writeup.md) | [day4-writeup.md](ru/Templates/day4-writeup.md) |
| Шаблон, день 5: отчёт | [dia5-writeup.md](es/Templates/dia5-writeup.md) | [day5-writeup.md](en/Templates/day5-writeup.md) | [day5-writeup.md](ru/Templates/day5-writeup.md) |
| Шаблон, день 6: отчёт | [dia6-writeup.md](es/Templates/dia6-writeup.md) | [day6-writeup.md](en/Templates/day6-writeup.md) | [day6-writeup.md](ru/Templates/day6-writeup.md) |
| Шаблон, день 7: отчёт | [dia7-writeup.md](es/Templates/dia7-writeup.md) | [day7-writeup.md](en/Templates/day7-writeup.md) | [day7-writeup.md](ru/Templates/day7-writeup.md) |

## Как их редактировать

- Каждый язык лежит в своей папке: `es`, `en` и `ru`. Если вы меняете документ, измените и две другие версии, чтобы они говорили одно и то же.
- Текст в фигурных скобках, например `{ORG}`, `{DOMAIN}`, `{DC}` или `{DELIVER_DIR}`, заполняется при публикации значениями из конфигурации. Оставляйте его как есть.
- Команды, пути и имена файлов в блоках кода должны совпадать с тем, что создаёт лаборатория. Проверка ищет шаблоны по имени: `dia1-mapa` и `diaN-writeup` в испанской лаборатории, `day1-map` и `dayN-writeup` в английской или русской.
- Сохраняйте файлы в UTF-8.
- Чтобы опубликовать изменения на уже установленном сервере, запустите `..\engine\Initialize-Challenges.ps1 -SkipStudents` из `C:\Lab\setup`. Флаги не меняются, пока вы не используете `-Rotate`.
