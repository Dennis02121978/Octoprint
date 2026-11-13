#!/bin/bash
# Entfernt das Bootlogo wieder (Skript-Installation). Aufruf: sudo bash uninstall-bootlogo.sh
# Wurde das Paket octoprint-bootlogo installiert, entfernst du es stattdessen mit: sudo apt remove octoprint-bootlogo
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Bitte mit sudo starten." >&2; exit 1; }
BOOT=/boot/firmware; [ -f "$BOOT/cmdline.txt" ] || BOOT=/boot
BAK=".bak-octoprint-bootlogo"

rm -f /etc/udev/rules.d/70-octoprint-boot-logo.rules /etc/systemd/system/octoprint-boot-logo@.service
rm -rf /usr/lib/octoprint-bootlogo /usr/share/octoprint-bootlogo
for f in "$BOOT/cmdline.txt" /etc/systemd/system/fbcp.service; do
    [ -e "$f$BAK" ] && mv -f "$f$BAK" "$f"
done
systemctl daemon-reload
udevadm control --reload
echo "Bootlogo entfernt. Bitte neu starten."
