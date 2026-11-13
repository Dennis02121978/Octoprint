#!/bin/bash
# Baut das Paket octoprint-bootlogo auf einem Linux-System mit dpkg-deb.
# Logo, Animation und Abspielprogramm kommen aus dem veroeffentlichten Paket rf-bootlogo (3D-Artmaker).
#
# Aufruf: ./build_deb.sh [Version]      Ergebnis: dist/octoprint-bootlogo_<Version>_all.deb
set -euo pipefail
cd "$(dirname "$0")"
VERSION=${1:-1.0.0}
SRC_URL="https://github.com/Dennis02121978/3D-Artmaker/releases/download/v1.7.0/rf-bootlogo_1.7.0_all.deb"
SRC_SHA="e33f0345c20f3923f71cf5b0b9f1a89ac4caee8eac2e4fdb12382b902f2a1890"
OUT="dist/octoprint-bootlogo_${VERSION}_all.deb"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
chmod 755 "$WORK"   # mktemp legt 700 an, das wuerde als Rechte fuer / im Paket landen

curl -fsSL -o "$WORK/src.deb" "$SRC_URL"
echo "$SRC_SHA  $WORK/src.deb" | sha256sum -c --quiet - || { echo "Pruefsumme von rf-bootlogo stimmt nicht"; exit 1; }
dpkg-deb -x "$WORK/src.deb" "$WORK/src"

ROOT="$WORK/root"
mkdir -p "$ROOT/DEBIAN" "$ROOT/usr/lib/octoprint-bootlogo" "$ROOT/usr/share/octoprint-bootlogo" \
         "$ROOT/lib/systemd/system" "$ROOT/lib/udev/rules.d" dist
chmod 755 "$ROOT"

install -m 755 "$WORK/src/usr/lib/rf-bootlogo/logo_anim.py" "$ROOT/usr/lib/octoprint-bootlogo/logo_anim.py"
for f in logo.png logo.rgb565 anim.bin; do
    install -m 644 "$WORK/src/usr/share/rf-bootlogo/$f" "$ROOT/usr/share/octoprint-bootlogo/$f"
done
[ "$(stat -c %s "$ROOT/usr/share/octoprint-bootlogo/logo.rgb565")" = "307200" ] || { echo "logo.rgb565 muss 480x320 RGB565 sein"; exit 1; }

install -m 644 octoprint-boot-logo@.service "$ROOT/lib/systemd/system/"
install -m 644 70-octoprint-boot-logo.rules "$ROOT/lib/udev/rules.d/"
install -m 755 preinst postinst postrm "$ROOT/DEBIAN/"
sed "s/@VERSION@/$VERSION/" control > "$ROOT/DEBIAN/control"

dpkg-deb --root-owner-group --build "$ROOT" "$OUT" >/dev/null
echo "Erstellt: $OUT"
