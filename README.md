# OctoPrint: Waveshare-3.5"-Display, OctoScreen und Bootlogo auf dem Raspberry Pi

Skripte und Anleitung, um an einem Raspberry Pi mit **OctoPrint** (OctoPi) ein **Waveshare 3.5" SPI-Display (A, 480x320)** mit **OctoScreen** als Touch-Oberfläche zu betreiben, und beim Start das **3D-Artmaker-Logo** statt Konsolentext zu zeigen.

Getestet mit: **Raspberry Pi 2 Model B**, OctoPi auf Raspberry Pi OS **Bookworm 32 Bit** (Kernel 6.6), OctoPrint 1.11.8, OctoScreen 2.7.4, Waveshare 3.5" LCD (A) mit ILI9486 und ADS7846-Touch.

**Pi 3:** Mit dem 32-Bit-OctoPi sollte es genauso laufen (gleiche Architektur, gleiche Treiber), ist aber **noch nicht getestet**. Das Display-Skript bricht auf 64-Bit-Systemen ab (OctoScreen gibt es nur als armhf-Paket) und auf Pi 4/5 (dort läuft fbcp nicht). Das Bootlogo-Paket braucht nur Python 3 und ist davon nicht betroffen.
Andere Pi-Modelle oder Displays sind nicht getestet.

> **Wichtig vorab:** Beide Skripte ändern `config.txt`, `cmdline.txt` und Systemdienste. Sie sichern die Originale als `*.bak-octoprint-lcd` bzw. `*.bak-octoprint-bootlogo` und lassen sich mit den `uninstall`-Skripten zurücknehmen.
> Mach vor dem Ausprobieren ein Image deiner SD-Karte. Installiere nicht während eines Drucks, denn am Ende steht ein Neustart.

## Inhalt

| Ordner | Zweck |
|---|---|
| [`display/`](display) | Display-Treiber, Touch, OctoScreen, fbcp |
| [`bootlogo/`](bootlogo) | Logo beim Start statt Konsolentext |

## 1. Display und OctoScreen

Voraussetzung: frisches OctoPi (Bookworm), Internet, SSH-Zugang.

```bash
ssh pi@<IP-DES-PI>
git clone https://github.com/Dennis02121978/Octoprint.git
cd Octoprint
sudo bash display/install-display.sh        # Display wie ab Werk (Drehung 90)
# oder, wenn das Bild auf dem Kopf steht:
sudo ROTATE=270 bash display/install-display.sh
sudo reboot
```

Was das Skript macht:

1. Installiert X11 (fbdev, evdev), GTK, `libraspberrypi-dev` und einen Compiler.
2. Lädt das Waveshare-Overlay `waveshare35a` und prüft die SHA-256-Prüfsumme (Bookworm bringt es nicht mit).
3. Baut `fbcp` aus dem Waveshare-Quellcode (Prüfsumme geprüft). `fbcp` kopiert den HDMI-Framebuffer aufs LCD.
4. Installiert OctoScreen 2.7.4 (Prüfsumme geprüft) und setzt die Auflösung auf 800x533.
5. Schaltet in `config.txt` KMS (`vc4-kms-v3d`) ab und aktiviert SPI und das Overlay. KMS verträgt sich nicht mit dem SPI-Framebuffer-Display.
6. Legt die Touch-Kalibrierung und die X11-Konfiguration an und aktiviert die Dienste `fbcp` und `octoscreen`.

**Drehung:** `ROTATE=90` ist die Standardlage, `ROTATE=270` dreht um 180 Grad. Das Skript passt die Touch-Kalibrierung mit an. Wenn der Touch trotzdem versetzt ist, kalibrierst du neu (`xinput_calibrator`) und trägst die Werte in `/etc/X11/xorg.conf.d/99-calibration.conf` ein.

**Z-Bolt-Plugin:** Für den Zugriff auf Plugin-Funktionen installierst du zusätzlich im OctoPrint Plugin-Manager das Plugin *Z-Bolt OctoScreen*.

Rückgängig machen: `sudo bash display/uninstall-display.sh`.

## 2. Bootlogo (mit Animation)

Voraussetzung: Abschnitt 1 ist erledigt und das Display läuft.

**Variante A: fertiges Paket (empfohlen).** Das Paket `octoprint-bootlogo` liegt unter [Releases](https://github.com/Dennis02121978/Octoprint/releases/latest):

```bash
cd ~
wget https://github.com/Dennis02121978/Octoprint/releases/download/v1.0.0/octoprint-bootlogo_1.0.0_all.deb
echo "801554332550420c3b43b24f234fed7a19e8005aba34ccbf82e153222ce0a957  octoprint-bootlogo_1.0.0_all.deb" | sha256sum -c
sudo apt install ./octoprint-bootlogo_1.0.0_all.deb
sudo reboot
```

Am Ende der Prüfsummen-Ausgabe muss `OK` stehen. Entfernen: `sudo apt remove octoprint-bootlogo` (stellt `cmdline.txt` und `fbcp.service` wieder her).

**Variante B: Skript.** Macht dasselbe ohne Paket:

```bash
cd Octoprint
sudo bash bootlogo/install-bootlogo.sh
sudo reboot
```

Rückgängig machen: `sudo bash bootlogo/uninstall-bootlogo.sh`.

**Animation:** Das Logo erscheint zuerst ohne die Linie durch die 3D und ohne den Schwung unter „Artmaker“. Dann läuft die Linie einmal von links nach rechts durch, danach wird der Schwung unter „Artmaker“ gezeichnet. Am Ende steht das unveränderte Original-Logo auf dem Display. Das Ganze dauert etwa zwei Sekunden. Das Abspielen braucht nur Python 3 und schreibt nur die geänderten Bildzeilen aufs Display.

Logo, fertige Animation und Abspielprogramm stammen aus dem 3D-Artmaker-Paket **rf-bootlogo 1.7.0**. Das ist für Klipper und KlipperScreen gebaut und lässt sich auf OctoPrint nicht direkt installieren. Das Skript und das Paket in diesem Repo nehmen daraus nur diese Dateien (die Prüfsumme wird geprüft) und richten sie für OctoScreen ein.

Was angepasst wird:

- `cmdline.txt`: `fbcon=map:10` wird zu `fbcon=map:9` und `vt.global_cursor_default=0` kommt dazu. Dadurch erscheint kein Konsolentext auf dem LCD.
- `fbcp.service` startet erst nach `octoscreen.service`, damit das Logo stehen bleibt, bis OctoScreen erscheint.
- Ein udev-Dienst zeigt die Animation, sobald sich das Display meldet.

Ablauf beim Start: Zuerst ist der Bildschirm kurz weiß, während der Display-Treiber lädt. Dann erscheint das Logo mit der Animation, und danach OctoScreen.

Das Logo passt nur auf ein 480x320-Display im Querformat mit 16 Bit Farbtiefe. Skript und Paket prüfen das vor der Installation. Das Paket gibt es nicht für das Display selbst (Abschnitt 1): Dort müssen Dateien von Waveshare und Z-Bolt geladen werden, die ich nicht mit ausliefere.

**Paket selbst bauen** (auf einem Linux-System mit `dpkg-deb`): `bootlogo/packaging/build_deb.sh 1.0.0`

## Fehlersuche

| Problem | Was du tun kannst |
|---|---|
| Display bleibt schwarz | `ls /dev/fb*` muss `fb0` und `fb1` zeigen. `dmesg \| grep -i ili9486` zeigt, ob der Treiber lädt. Prüfe, dass SPI aktiv ist und `vc4-kms-v3d` in der `config.txt` auskommentiert ist. |
| Bild steht auf dem Kopf | Skript mit `ROTATE=270` (oder `90`) erneut ausführen. |
| Touch trifft die falsche Stelle | Kalibrierung in `/etc/X11/xorg.conf.d/99-calibration.conf` anpassen. |
| OctoScreen startet nicht | `journalctl -u octoscreen -n 30`. Fehlt `xset`, hilft `sudo apt install x11-xserver-utils`. |
| Prüfsumme stimmt nicht | Abbruch ist Absicht. Die Datei am Download-Ort wurde geändert, melde das hier. |

## Hinweise

- Die Skripte laden Dateien aus dem Internet (Waveshare, Z-Bolt, 3D-Artmaker) und prüfen sie gegen feste SHA-256-Werte. Lies die Skripte vor dem Ausführen.
- Das Overlay, `fbcp` und OctoScreen gehören ihren jeweiligen Autoren. Dieses Repo enthält nur die Skripte, keine fremden Binärdateien.
- Ein Update dieser Skripte ändert die Versionen und Prüfsummen nur, wenn du sie hier aktualisierst.
