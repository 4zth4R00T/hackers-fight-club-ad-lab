#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
repo="$(dirname "$here")"
profile="es-MX"
media=""
index="2"
firmware="uefi"
productkey=""
timezone=""
autostart="no"
generate="no"
out="$PWD/lab-answers.iso"

usage() {
    cat <<'TXT'
Uso / Usage: new-answer-iso.sh [opciones / options]

  -p REGION     en-US, es-MX, es-ES o ru-RU (idioma regional y teclado / regional format and keyboard). Default: es-MX
  -m MEDIO      idioma del ISO de Windows Server: en-US, es-ES o ru-RU / Windows Server ISO language. Default: segun el perfil / by profile
  -i INDICE     imagen dentro de install.wim (2 = Standard con escritorio) / image index (2 = Standard Desktop Experience)
  -f FIRMWARE   uefi o bios. Default: uefi
  -k CLAVE      clave de producto opcional / optional product key
  -z ZONA       zona horaria de Windows / Windows time zone id
  -a            arrancar la instalacion del laboratorio sola al primer inicio / start the lab installation on first logon
  -g            generar la contrasena del administrador / generate the administrator password
  -o ARCHIVO    ISO de salida / output ISO. Default: ./lab-answers.iso
TXT
}

while getopts ":p:m:i:f:k:z:o:agh" opt; do
    case "$opt" in
        p) profile="$OPTARG" ;;
        m) media="$OPTARG" ;;
        i) index="$OPTARG" ;;
        f) firmware="$OPTARG" ;;
        k) productkey="$OPTARG" ;;
        z) timezone="$OPTARG" ;;
        o) out="$(readlink -f "$OPTARG")" ;;
        a) autostart="yes" ;;
        g) generate="yes" ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

case "$profile" in
    en-US) ui="en-US"; input="0409:00000409"; locale="en-US"; tz="Central Standard Time" ;;
    es-MX) ui="es-ES"; input="080a:0000080a"; locale="es-MX"; tz="Central Standard Time (Mexico)" ;;
    es-ES) ui="es-ES"; input="0c0a:0000040a"; locale="es-ES"; tz="Romance Standard Time" ;;
    ru-RU) ui="ru-RU"; input="0409:00000409;0419:00000419"; locale="ru-RU"; tz="Russian Standard Time" ;;
    *) echo "Perfil no valido / invalid profile: $profile"; exit 1 ;;
esac
[ -n "$media" ] && ui="$media"
[ -n "$timezone" ] && tz="$timezone"
case "$ui" in
    en-US) admin="Administrator" ;;
    es-ES|es-MX) admin="Administrador"; ui="es-ES" ;;
    ru-RU) admin="$(printf '\320\220\320\264\320\274\320\270\320\275\320\270\321\201\321\202\321\200\320\260\321\202\320\276\321\200')" ;;
    *) echo "Idioma de medio no valido / invalid media language: $ui"; exit 1 ;;
esac
case "$firmware" in
    uefi) layout="$here/disk-uefi.xml"; part="3" ;;
    bios) layout="$here/disk-bios.xml"; part="2" ;;
    *) echo "Firmware no valido / invalid firmware: $firmware"; exit 1 ;;
esac

isotool=""
for t in xorriso genisoimage mkisofs; do
    if command -v "$t" >/dev/null 2>&1; then isotool="$t"; break; fi
done
[ -z "$isotool" ] && { echo "Instala xorriso o genisoimage / install xorriso or genisoimage"; exit 1; }

cfg="$repo/config/lab.config.psd1"
getcfg() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*'\{0,1\}\([^']*\)'\{0,1\}[[:space:]]*$/\1/p" "$cfg" | head -n1; }
prefix="$(getcfg DcHostPrefix)"; prefix="${prefix:-DC}"
number="$(getcfg DcHostNumber)"; number="${number:-1}"
org="$(getcfg Organization)"; org="${org:-Lab}"
computer="$(printf '%s%02d' "${prefix^^}" "$number")"
org_xml="$(printf '%s' "$org" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"

if [ "$generate" = "yes" ]; then
    password="$(python3 -I -c 'import secrets; a="ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"; print("".join(secrets.choice(a) for _ in range(16)) + "#7q")')"
else
    read -r -s -p "Contrasena del administrador / Administrator password: " password; echo
    read -r -s -p "Repitela / Repeat it: " password2; echo
    [ "$password" = "$password2" ] || { echo "No coinciden / they do not match"; exit 1; }
    [ "${#password}" -ge 12 ] || { echo "Minimo 12 caracteres / at least 12 characters"; exit 1; }
fi
enc() { printf '%s%s' "$1" "$2" | iconv -f UTF-8 -t UTF-16LE | base64 -w0; }
adminpw="$(enc "$password" "AdministratorPassword")"
autopw="$(enc "$password" "Password")"
keyline=""
[ -n "$productkey" ] && keyline="          <Key>$productkey</Key>
"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/lab"
UI="$ui" INPUT="$input" LOCALE="$locale" INDEX="$index" PART="$part" ORG="$org_xml" KEYLINE="$keyline" COMPUTER="$computer" TZ_ID="$tz" ADMINPW="$adminpw" AUTOPW="$autopw" ADMIN="$admin" \
python3 -I - "$here/autounattend.template.xml" "$layout" "$work/autounattend.xml" <<'PY'
import os, sys
tpl = open(sys.argv[1], encoding='utf-8').read()
layout = open(sys.argv[2], encoding='utf-8').read().rstrip('\n')
e = os.environ
vals = {
    '{{UI_LANGUAGE}}': e['UI'], '{{INPUT_LOCALE}}': e['INPUT'], '{{USER_LOCALE}}': e['LOCALE'],
    '{{DISK_LAYOUT}}': layout, '{{IMAGE_INDEX}}': e['INDEX'], '{{INSTALL_PARTITION}}': e['PART'],
    '{{ORGANIZATION}}': e['ORG'], '{{PRODUCT_KEY_LINE}}': e['KEYLINE'], '{{COMPUTER_NAME}}': e['COMPUTER'],
    '{{TIME_ZONE}}': e['TZ_ID'], '{{ADMIN_PASSWORD}}': e['ADMINPW'], '{{AUTOLOGON_PASSWORD}}': e['AUTOPW'], '{{ADMIN_NAME}}': e['ADMIN'],
}
for k, v in vals.items():
    tpl = tpl.replace(k, v)
open(sys.argv[3], 'w', encoding='utf-8', newline='\r\n').write(tpl)
PY
for d in setup engine services web client assets config examples lang; do
    [ -d "$repo/$d" ] || continue
    rsync -a --exclude node_modules --exclude dist --exclude dist-astro --exclude .astro --exclude certs "$repo/$d" "$work/lab/"
done
cp "$here/Start-LabSetup.ps1" "$work/lab/"
[ "$autostart" = "yes" ] && printf 'yes\r\n' > "$work/lab/autostart.txt"

rm -f "$out"
if [ "$isotool" = "xorriso" ]; then
    xorriso -as mkisofs -quiet -iso-level 3 -J -joliet-long -R -V LAB_ANSWERS -o "$out" "$work" >/dev/null 2>&1
else
    "$isotool" -quiet -iso-level 3 -J -joliet-long -R -V LAB_ANSWERS -o "$out" "$work" >/dev/null 2>&1
fi

creds="${out%.iso}.credentials.txt"
summary="ISO: $out
Region: $profile   Medio / media: $ui   Firmware: $firmware   Indice / index: $index
Equipo / computer: $computer   Zona / time zone: $tz
Cuenta / account: $admin
Arranque automatico / autostart: $autostart"
if [ "$generate" = "yes" ]; then
    umask 077
    printf '%s\nContrasena / password: %s\n' "$summary" "$password" > "$creds"
    summary="$summary
Contrasena guardada en / password saved to: $creds"
fi
printf '\n%s\n\n' "$summary"
printf 'Adjunta esta ISO como segunda unidad de CD junto al ISO original de Windows Server 2025.\nAttach this ISO as a second CD drive next to the original Windows Server 2025 ISO.\n\n'
