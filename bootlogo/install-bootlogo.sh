#!/bin/bash
# Animiertes Bootlogo (3D-Artmaker) auf dem SPI-Display bei OctoPrint + OctoScreen.
# Voraussetzung: display/install-display.sh ist gelaufen und das Display funktioniert.
#
# Logo, fertige Animation und Abspielprogramm stammen aus dem 3D-Artmaker-Paket rf-bootlogo 1.7.0
# (eigentlich fuer Klipper/KlipperScreen). Dieses Skript nimmt daraus nur diese Dateien und richtet
# alles fuer OctoScreen ein. Einfacher: das fertige Paket octoprint-bootlogo aus den Releases dieses Repos.
#
# Aufruf: sudo bash install-bootlogo.sh
set -euo pipefail

DEB_URL="https://github.com/Dennis02121978/3D-Artmaker/releases/download/v1.7.0/rf-bootlogo_1.7.0_all.deb"
DEB_SHA="e33f0345c20f3923f71cf5b0b9f1a89ac4caee8eac2e4fdb12382b902f2a1890"
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
mkdir -p /usr/lib/octoprint-bootlogo /usr/share/octoprint-bootlogo
install -m 755 "$TMP/x/usr/lib/rf-bootlogo/logo_anim.py" /usr/lib/octoprint-bootlogo/logo_anim.py
for f in logo.png logo.rgb565 anim.bin; do
    install -m 644 "$TMP/x/usr/share/rf-bootlogo/$f" "/usr/share/octoprint-bootlogo/$f"
done
cat > /etc/systemd/system/octoprint-boot-logo@.service <<'EOF'
[Unit]
Description=Logo auf dem Display %i anzeigen
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /usr/lib/octoprint-bootlogo/logo_anim.py play /dev/%i /usr/share/octoprint-bootlogo/anim.bin /usr/share/octoprint-bootlogo/logo.rgb565
EOF
cat > /etc/udev/rules.d/70-octoprint-boot-logo.rules <<'EOF'
ACTION=="add", SUBSYSTEM=="graphics", KERNEL=="fb[0-9]*", ATTR{name}=="fb_*", TAG+="systemd", ENV{SYSTEMD_WANTS}+="octoprint-boot-logo@%k.service"
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

echo
echo "Fertig. Das Logo erscheint nach dem naechsten Neustart:  sudo reboot"
