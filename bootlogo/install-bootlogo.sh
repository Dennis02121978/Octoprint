#!/bin/bash
# Bootlogo (3D-Artmaker) auf dem SPI-Display bei OctoPrint + OctoScreen.
# Voraussetzung: display/install-display.sh ist gelaufen und das Display funktioniert.
#
# Das Logo stammt aus dem 3D-Artmaker-Paket rf-bootlogo (eigentlich fuer Klipper/KlipperScreen).
# Dieses Skript nimmt daraus nur Logo, show-logo, udev-Regel und Dienst und passt den Rest an OctoScreen an.
#
# Aufruf: sudo bash install-bootlogo.sh
set -euo pipefail

DEB_URL="https://github.com/Dennis02121978/3D-Artmaker/releases/download/v1.5.9/rf-bootlogo_1.5.9_all.deb"
DEB_SHA="e99352adfe5ce186951872e2d518b5605856f71a21ae0ef08451b49f13935b5f"
BAK=".bak-octoprint-bootlogo"

fail() { echo "FEHLER: $1" >&2; exit 1; }
[ "$(id -u)" = 0 ] || fail "Bitte mit sudo starten."
BOOT=/boot/firmware; [ -f "$BOOT/cmdline.txt" ] || BOOT=/boot
[ -f "$BOOT/cmdline.txt" ] || fail "cmdline.txt nicht gefunden."
grep -q 'root=' "$BOOT/cmdline.txt" || fail "cmdline.txt ohne root= - Abbruch."
[ -f /etc/systemd/system/fbcp.service ] || fail "fbcp.service fehlt - zuerst display/install-display.sh ausfuehren."

PANEL=""
for fb in /sys/class/graphics/fb[0-9]*; do
    case "$(cat "$fb/name" 2>/dev/null)" in fb_*) PANEL=$fb; break ;; esac
done
[ -n "$PANEL" ] || fail "Kein SPI-Display gefunden (Display muss schon laufen)."
[ "$(cat "$PANEL/virtual_size")" = "480,320" ] || fail "Das Logo passt nur auf 480x320, gefunden: $(cat "$PANEL/virtual_size")."
[ "$(cat "$PANEL/bits_per_pixel")" = "16" ] || fail "Das Logo braucht 16 Bit Farbtiefe."

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
echo "==> Paket laden und pruefen"
curl -fsSL -o "$TMP/rf-bootlogo.deb" "$DEB_URL"
echo "$DEB_SHA  $TMP/rf-bootlogo.deb" | sha256sum -c --quiet - || fail "Pruefsumme stimmt nicht."
dpkg-deb -x "$TMP/rf-bootlogo.deb" "$TMP/x"

echo "==> Dateien installieren"
mkdir -p /usr/lib/rf-bootlogo /usr/share/rf-bootlogo /etc/rf-bootlogo
install -m 755 "$TMP/x/usr/lib/rf-bootlogo/show-logo" /usr/lib/rf-bootlogo/show-logo
install -m 644 "$TMP/x/usr/share/rf-bootlogo/logo.rgb565" /usr/share/rf-bootlogo/logo.rgb565
install -m 644 "$TMP/x/usr/share/rf-bootlogo/logo.png" /usr/share/rf-bootlogo/logo.png
install -m 644 "$TMP/x/lib/systemd/system/rf-boot-logo@.service" /etc/systemd/system/rf-boot-logo@.service
install -m 644 "$TMP/x/lib/udev/rules.d/70-rf-boot-logo.rules" /etc/udev/rules.d/70-rf-boot-logo.rules
# show-logo liest diese Datei ein; ohne sie bricht es ab
printf 'LOGO_DIR=/nonexistent\n' > /etc/rf-bootlogo/config

echo "==> Animation berechnen (Linie laeuft durch die 3D, danach wird der Schwung gezeichnet)"
HERE=$(cd "$(dirname "$0")" && pwd)
[ -f "$HERE/rf-logo-anim.py" ] || fail "rf-logo-anim.py fehlt neben diesem Skript."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-pil python3-numpy
install -m 755 "$HERE/rf-logo-anim.py" /usr/lib/rf-bootlogo/rf-logo-anim.py
python3 /usr/lib/rf-bootlogo/rf-logo-anim.py build "$TMP/x/usr/share/rf-bootlogo/logo.png" /usr/share/rf-bootlogo/anim.bin
# Dienst: spielt die Animation ab; ohne anim.bin wird das statische Logo gezeigt
cat > /etc/systemd/system/rf-boot-logo@.service <<'EOF'
[Unit]
Description=Logo auf dem Display %i anzeigen
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /usr/lib/rf-bootlogo/rf-logo-anim.py play /dev/%i /usr/share/rf-bootlogo/anim.bin /usr/share/rf-bootlogo/logo.rgb565
EOF

echo "==> Konsolentext ausblenden (cmdline.txt)"
[ -e "$BOOT/cmdline.txt$BAK" ] || cp -a "$BOOT/cmdline.txt" "$BOOT/cmdline.txt$BAK"
LINE=$(head -n 1 "$BOOT/cmdline.txt" | sed 's/fbcon=map:10/fbcon=map:9/')
case "$LINE" in *fbcon=map:*) ;; *) LINE="$LINE fbcon=map:9" ;; esac
case "$LINE" in *vt.global_cursor_default=0*) ;; *) LINE="$LINE vt.global_cursor_default=0" ;; esac
printf '%s\n' "$LINE" > "$BOOT/cmdline.txt"

echo "==> fbcp erst nach OctoScreen starten (Logo bleibt bis dahin stehen)"
[ -e "/etc/systemd/system/fbcp.service$BAK" ] || cp -a /etc/systemd/system/fbcp.service "/etc/systemd/system/fbcp.service$BAK"
sed -i 's/^After=.*/After=octoscreen.service/; s|^ExecStartPre=.*|ExecStartPre=/bin/sleep 3|' /etc/systemd/system/fbcp.service

systemctl daemon-reload
udevadm control --reload
python3 /usr/lib/rf-bootlogo/rf-logo-anim.py play "/dev/${PANEL##*/}" /usr/share/rf-bootlogo/anim.bin /usr/share/rf-bootlogo/logo.rgb565 || true

echo
echo "Fertig. Das Logo erscheint nach dem naechsten Neustart:  sudo reboot"
