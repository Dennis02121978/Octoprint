#!/bin/bash
# Entfernt das Bootlogo wieder. Aufruf: sudo bash uninstall-bootlogo.sh
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Bitte mit sudo starten." >&2; exit 1; }
BOOT=/boot/firmware; [ -f "$BOOT/cmdline.txt" ] || BOOT=/boot
BAK=".bak-octoprint-bootlogo"

rm -f /etc/udev/rules.d/70-rf-boot-logo.rules /etc/systemd/system/rf-boot-logo@.service
rm -rf /usr/lib/rf-bootlogo /usr/share/rf-bootlogo /etc/rf-bootlogo
for f in "$BOOT/cmdline.txt" /etc/systemd/system/fbcp.service; do
    [ -e "$f$BAK" ] && mv -f "$f$BAK" "$f"
done
systemctl daemon-reload
udevadm control --reload
echo "Bootlogo entfernt. Bitte neu starten."
