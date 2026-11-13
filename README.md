# OctoPrint: Waveshare-3.5"-Display, OctoScreen und Bootlogo auf dem Raspberry Pi

Skripte und Anleitung, um an einem Raspberry Pi mit **OctoPrint** (OctoPi) ein **Waveshare 3.5" SPI-Display (A, 480x320)** mit **OctoScreen** als Touch-Oberfläche zu betreiben, und beim Start das **3D-Artmaker-Logo** statt Konsolentext zu zeigen.

Getestet mit: Raspberry Pi 2 Model B, OctoPi auf Raspberry Pi OS **Bookworm 32 Bit** (Kernel 6.6), OctoPrint 1.11.8, OctoScreen 2.7.4, Waveshare 3.5" LCD (A) mit ILI9486 und ADS7846-Touch.
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

## 2. Bootlogo

Voraussetzung: Abschnitt 1 ist erledigt und das Display läuft.

```bash
cd Octoprint
sudo bash bootlogo/install-bootlogo.sh
sudo reboot
```

Das Logo stammt aus dem Paket **rf-bootlogo** von 3D-Artmaker (Version 1.5.9). Das Paket ist für Klipper und KlipperScreen gebaut und lässt sich auf OctoPrint nicht direkt installieren. Das Skript lädt es, prüft die Prüfsumme und nimmt daraus nur Logo, `show-logo`, udev-Regel und Dienst.

Was angepasst wird:

- `cmdline.txt`: `fbcon=map:10` wird zu `fbcon=map:9` und `vt.global_cursor_default=0` kommt dazu. Dadurch erscheint kein Konsolentext auf dem LCD.
- `fbcp.service` startet erst nach `octoscreen.service`, damit das Logo stehen bleibt, bis OctoScreen erscheint.
- `/etc/rf-bootlogo/config` wird angelegt. Ohne diese Datei bricht `show-logo` ab.

Ablauf beim Start: Zuerst ist der Bildschirm kurz weiß, während der Display-Treiber lädt. Dann erscheint das Logo, und danach OctoScreen.

Das Logo passt nur auf ein 480x320-Display im Querformat mit 16 Bit Farbtiefe. Das Skript prüft das vor der Installation.

Rückgängig machen: `sudo bash bootlogo/uninstall-bootlogo.sh`.

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
