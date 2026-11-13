#!/bin/bash
# OctoPrint + Waveshare 3.5" LCD (A) + OctoScreen auf dem Raspberry Pi (Raspberry Pi OS Bookworm, 32 Bit)
#
# Aufruf:   sudo bash install-display.sh            (Display wie ab Werk, rotate=90)
#           sudo ROTATE=270 bash install-display.sh (Display um 180 Grad gedreht)
#
# Das Skript kann mehrmals laufen. Geaenderte Dateien werden vorher als *.bak-octoprint-lcd gesichert.
set -euo pipefail

ROTATE="${ROTATE:-90}"
OCTOSCREEN_URL="https://github.com/Z-Bolt/OctoScreen/releases/download/v2.7.4/octoscreen_2.7.4_armhf.deb"
OCTOSCREEN_SHA="9f6a8342d8085b3ad4808ea663f807972bbd9ed8c7b439024dd494bc3e9c2d22"
OVERLAY_URL="https://raw.githubusercontent.com/waveshare/LCD-show/master/waveshare35a-overlay.dtb"
OVERLAY_SHA="4e879f464dd97387282e68de9ab66b9cc85627fb0b02618ca44cc0a94644ee7d"
FBCP_URL="https://raw.githubusercontent.com/waveshare/LCD-show/master/rpi-fbcp/main.c"
FBCP_SHA="cda8a0c4af2e687515ba45bb2d517f32b2d0ae1bc34e0c72ee78629987d0e131"
RESOLUTION="800x533"
BAK=".bak-octoprint-lcd"

fail() { echo "FEHLER: $1" >&2; exit 1; }
[ "$(id -u)" = 0 ] || fail "Bitte mit sudo starten."
[ "$ROTATE" = 90 ] || [ "$ROTATE" = 270 ] || fail "ROTATE muss 90 oder 270 sein."
MODEL=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || true)
echo "$MODEL" | grep -qi raspberry || fail "Nur fuer den Raspberry Pi."
# OctoScreen gibt es nur als 32-Bit-Paket (armhf), und fbcp braucht den alten Grafikstack (Pi Zero bis Pi 3).
[ "$(dpkg --print-architecture)" = "armhf" ] || fail "Dieses Skript braucht ein 32-Bit-System (armhf), gefunden: $(dpkg --print-architecture). Nimm das 32-Bit-OctoPi."
if echo "$MODEL" | grep -qE 'Raspberry Pi (4|5)|Compute Module (4|5)'; then
    [ "${FORCE:-0}" = 1 ] || fail "Pi 4/5 ('$MODEL'): fbcp laeuft dort nicht (kein alter Grafikstack). Mit FORCE=1 trotzdem versuchen."
fi
echo "Modell: $MODEL"

BOOT=/boot/firmware; [ -f "$BOOT/config.txt" ] || BOOT=/boot
[ -f "$BOOT/config.txt" ] && [ -f "$BOOT/cmdline.txt" ] || fail "config.txt/cmdline.txt nicht gefunden."
grep -q 'root=' "$BOOT/cmdline.txt" || fail "cmdline.txt ohne root= - Abbruch."
OWNER="${SUDO_USER:-pi}"

# Touch-Kalibrierung (Werte vom Waveshare-Display; bei 270 sind beide Achsen umgekehrt)
if [ "$ROTATE" = 90 ]; then CAL="3932 300 294 3801"; else CAL="300 3932 3801 294"; fi

backup() { [ -e "$1$BAK" ] || cp -a "$1" "$1$BAK"; }
download() { # url, ziel, sha256
    curl -fsSL -o "$2" "$1"
    echo "$3  $2" | sha256sum -c --quiet - || fail "Pruefsumme von $1 stimmt nicht."
}

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export DEBIAN_FRONTEND=noninteractive

echo "==> Pakete installieren"
apt-get update -qq
apt-get install -y -qq xinit xserver-xorg xserver-xorg-video-fbdev xserver-xorg-input-evdev \
    xserver-xorg-legacy x11-xserver-utils libgtk-3-0 libgdk-pixbuf-2.0-0 libraspberrypi-dev gcc libc6-dev curl ca-certificates \
    || apt-get install -y -qq xinit xserver-xorg xserver-xorg-video-fbdev xserver-xorg-input-evdev \
    xserver-xorg-legacy x11-xserver-utils libgtk-3-0 libgdk-pixbuf2.0-0 libraspberrypi-dev gcc libc6-dev curl ca-certificates

echo "==> Display-Overlay (Waveshare 3.5\" A)"
download "$OVERLAY_URL" "$TMP/waveshare35a.dtbo" "$OVERLAY_SHA"
install -m 644 "$TMP/waveshare35a.dtbo" "$BOOT/overlays/waveshare35a.dtbo"

echo "==> fbcp bauen (kopiert den HDMI-Bildschirm aufs LCD)"
download "$FBCP_URL" "$TMP/main.c" "$FBCP_SHA"
gcc -O2 -include sys/ioctl.h "$TMP/main.c" -o "$TMP/fbcp" \
    -I/usr/include -I/usr/include/interface/vcos/pthreads -I/usr/include/interface/vmcs_host/linux \
    -lbcm_host -lvcos -lvchiq_arm
install -m 755 "$TMP/fbcp" /usr/local/bin/fbcp

echo "==> OctoScreen installieren"
download "$OCTOSCREEN_URL" "$TMP/octoscreen.deb" "$OCTOSCREEN_SHA"
apt-get install -y -qq "$TMP/octoscreen.deb"
[ -e /etc/octoscreen/config$BAK ] || cp -a /etc/octoscreen/config "/etc/octoscreen/config$BAK"
sed -i "s|^#\?OCTOSCREEN_RESOLUTION=.*|OCTOSCREEN_RESOLUTION=$RESOLUTION|" /etc/octoscreen/config
grep -q '^OCTOSCREEN_RESOLUTION=' /etc/octoscreen/config || echo "OCTOSCREEN_RESOLUTION=$RESOLUTION" >> /etc/octoscreen/config
sed -i "s|^OCTOPRINT_CONFIG_FILE=.*|OCTOPRINT_CONFIG_FILE=/home/$OWNER/.octoprint/config.yaml|" /etc/octoscreen/config

echo "==> config.txt (alter Framebuffer statt KMS, SPI-Display, rotate=$ROTATE)"
backup "$BOOT/config.txt"
sed -i -E 's/^(dtoverlay=vc4-(f)?kms-v3d.*)$/#\1/; s/^(max_framebuffers=.*)$/#\1/; s/^(display_auto_detect=.*)$/#\1/; s/^(disable_fw_kms_setup=.*)$/#\1/' "$BOOT/config.txt"
sed -i '/^# BEGIN octoprint-lcd$/,/^# END octoprint-lcd$/d' "$BOOT/config.txt"
cat >> "$BOOT/config.txt" <<EOF

# BEGIN octoprint-lcd
dtparam=spi=on
dtparam=i2c_arm=on
enable_uart=1
dtoverlay=waveshare35a,rotate=$ROTATE
hdmi_force_hotplug=1
hdmi_group=2
hdmi_mode=87
hdmi_cvt=800 533 60 6 0 0 0
hdmi_drive=2
# END octoprint-lcd
EOF

echo "==> cmdline.txt"
backup "$BOOT/cmdline.txt"
LINE=$(head -n 1 "$BOOT/cmdline.txt")
for arg in "fbcon=map:10" "fbcon=font:ProFont6x11"; do
    key=${arg%%=*}; case " $LINE " in *" $key="*) ;; *) LINE="$LINE $arg" ;; esac
done
printf '%s\n' "$LINE" > "$BOOT/cmdline.txt"

echo "==> X11, Touch"
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/99-fbdev.conf <<'EOF'
Section "Device"
        Identifier      "FBDEV"
        Driver          "fbdev"
        Option          "fbdev" "/dev/fb0"
EndSection
EOF
cat > /etc/X11/xorg.conf.d/99-calibration.conf <<EOF
Section "InputClass"
        Identifier      "calibration"
        MatchProduct    "ADS7846 Touchscreen"
        Option  "Calibration"   "$CAL"
        Option  "SwapAxes"      "1"
        Option "EmulateThirdButton" "1"
        Option "EmulateThirdButtonTimeout" "1000"
        Option "EmulateThirdButtonMoveThreshold" "300"
EndSection
EOF
cat > /etc/udev/rules.d/95-ads7846.rules <<'EOF'
SUBSYSTEM=="input", KERNEL=="event[0-9]*", ATTRS{name}=="ADS7846*", SYMLINK+="input/touchscreen"
EOF

echo "==> fbcp-Dienst"
cat > /etc/systemd/system/fbcp.service <<'EOF'
[Unit]
Description=Copy HDMI framebuffer to LCD (fbcp)
After=multi-user.target

[Service]
ExecStartPre=/bin/sleep 7
ExecStart=/usr/local/bin/fbcp
ExecStartPost=-/usr/bin/con2fbmap 1 0
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable fbcp.service octoscreen.service >/dev/null 2>&1
systemctl set-default graphical.target >/dev/null 2>&1

echo
echo "Fertig. Jetzt neu starten:  sudo reboot"
echo "Plugin 'Z-Bolt OctoScreen' kannst du zusaetzlich im OctoPrint Plugin-Manager installieren."
