# tinyStats installieren und aktualisieren

Voraussetzungen: macOS 14 oder neuer, Apple Xcode Command Line Tools (`xcode-select --install`), Git. Kein GitHub-Konto erforderlich.

Installation in einer Terminal-Zeile:

```sh
git clone https://github.com/tschnorpfeil/tinyStats.git && ./tinyStats/install.sh
```

Aus einem vorhandenen Checkout genügt `./install.sh`. Der Installer baut lokal, installiert nach `~/Applications/tinyStats.app` und legt einen verwalteten Quellcode-Checkout unter `~/.local/share/tinystats/source` an. Der ursprüngliche Download-Ordner wird danach nicht mehr benötigt. Er legt `~/.local/bin/tinystats` an und ergänzt diesen Ordner bei Bedarf für neue zsh-Terminals in `~/.zprofile`. Ein vorhandener fremder `tinystats`-Befehl wird nicht überschrieben. Kein sudo, keine zusätzlichen Laufzeitabhängigkeiten, kein Autostart.

```sh
tinystats          # starten
tinystats status   # läuft die installierte App?
tinystats stop     # die installierte App beenden
tinystats version  # Commit der tatsächlich installierten App
tinystats update   # main abrufen, bauen, installieren und neu starten
```

Ist das aktuelle Terminal noch ohne `~/.local/bin` im PATH, ein neues Terminal öffnen oder die vom Installer ausgegebene `export PATH=…`-Zeile ausführen.

Updates erfolgen per Fast-forward von `origin/main`. Änderungen im verwalteten Checkout brechen das Update ab; es gibt keinen Reset oder Force-Push. Der Build erfolgt vor dem Austausch der App. Scheitert er, bleibt die installierte Version erhalten. Ein erneuter Startbefehl startet keine zweite Instanz der installierten App.

Test des Installers ohne Eingriff in die echte Installation:

```sh
./Tests/install.sh
```

Installationspfade lassen sich für Tests mit `TINYSTATS_HOME`, `TINYSTATS_APP_DIR` und `TINYSTATS_BIN_DIR` überschreiben. Dieselben Variablen gelten beim späteren CLI-Aufruf.

## Wenn etwas nicht klappt

- **`command not found: tinystats`:** Ein neues Terminal öffnen. Sofortiger Start geht mit `~/.local/bin/tinystats`.
- **Build fehlgeschlagen:** Fehlermeldung von Swift prüfen; `xcode-select --install` installiert die benötigten Apple-Werkzeuge. Die bisherige App bleibt erhalten. Nach Behebung `tinystats update` wiederholen.
- **Lokale Änderungen im Installations-Checkout:** Änderungen unter `~/.local/share/tinystats/source` zuerst prüfen und bewusst sichern oder committen. Der Updater verwirft sie nicht automatisch.
- **Installation läuft bereits:** Den laufenden Vorgang beenden lassen. Nach einem Rechnerabsturz kann ein leeres `~/.local/share/tinystats/install.lock` zurückbleiben. Nur wenn sicher kein Installer/Updater mehr läuft, dieses leere Verzeichnis mit `rmdir ~/.local/share/tinystats/install.lock` entfernen.
- **App erscheint nicht:** `tinystats status` prüfen. Eine schon laufende Entwicklungsversion zunächst beenden; tinyStats verhindert mehrere App-Instanzen. Auf einem Notch-Display sitzt die Anzeige rechts an der Kameraaussparung.

Der Update-Lock gilt von vor dem Abrufen bis zum Abschluss der Installation.
`tinystats version` liest den Versionsnachweis aus der installierten App, nicht
aus dem möglicherweise bereits weitergeschalteten Quellcode-Checkout. Bei einer
älteren Installation ohne Versionsnachweis hilft einmal `tinystats update`.

## Entfernen

`tinystats stop` beendet die App. Zum Deinstallieren können anschließend
`~/Applications/tinyStats.app`, `~/.local/bin/tinystats` und der verwaltete
Ordner `~/.local/share/tinystats` entfernt werden. Vorher dortige eigene
Quellcodeänderungen sichern. Der mit `# tinyStats CLI` markierte PATH-Eintrag
in `~/.zprofile` ist optional entfernbar; andere Tools können denselben Ordner
nutzen. Es gibt keinen Hintergrunddienst und keinen Autostart-Eintrag.
