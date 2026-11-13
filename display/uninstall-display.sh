#!/bin/bash
# Macht install-display.sh rueckgaengig (stellt die gesicherten Dateien wieder her).
# Aufruf: sudo bash uninstall-display.sh
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Bitte mit sudo starten." >&2; exit 1; }
BOOT=/boot/firmware; [ -f "$BOOT/config.txt" ] || BOOT=/boot
BAK=".bak-octoprint-lcd"

systemctl disable --now fbcp.service octoscreen.service 2>/dev/null || true
rm -f /etc/systemd/system/fbcp.service /usr/local/bin/fbcp
rm -f /etc/X11/xorg.conf.d/99-fbdev.conf /etc/X11/xorg.conf.d/99-calibration.conf /etc/udev/rules.d/95-ads7846.rules
rm -f "$BOOT/overlays/waveshare35a.dtbo"
for f in "$BOOT/config.txt" "$BOOT/cmdline.txt" /etc/octoscreen/config; do
    [ -e "$f$BAK" ] && mv -f "$f$BAK" "$f"
done
systemctl daemon-reload
echo "Zurueckgesetzt. OctoScreen bleibt als Paket installiert (sudo apt remove octoscreen zum Entfernen). Bitte neu starten."
