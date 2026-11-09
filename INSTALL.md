# tinyStats installieren und aktualisieren

Voraussetzungen: macOS 14 oder neuer, Apple Xcode Command Line Tools (`xcode-select --install`), Git. Für das private GitHub-Repo außerdem GitHub CLI und `gh auth login` mit Zugriff auf `tschnorpfeil/tinyStats`.

Installation in einer Terminal-Zeile:

```sh
gh repo clone tschnorpfeil/tinyStats && ./tinyStats/install.sh
```

Aus einem vorhandenen Checkout genügt `./install.sh`. Der Installer baut lokal, installiert nach `~/Applications/tinyStats.app` und legt einen verwalteten Quellcode-Checkout unter `~/.local/share/tinystats/source` an. Der ursprüngliche Download-Ordner wird danach nicht mehr benötigt. Er legt `~/.local/bin/tinystats` an und ergänzt diesen Ordner bei Bedarf für neue zsh-Terminals in `~/.zprofile`. Ein vorhandener fremder `tinystats`-Befehl wird nicht überschrieben. Kein sudo, keine zusätzlichen Laufzeitabhängigkeiten, kein Autostart.

```sh
tinystats          # starten
tinystats status   # läuft die installierte App?
tinystats stop     # die installierte App beenden
tinystats version  # installierter Quellcode-Commit
tinystats update   # main abrufen, bauen, installieren und neu starten
```

Ist das aktuelle Terminal noch ohne `~/.local/bin` im PATH, ein neues Terminal öffnen oder die vom Installer ausgegebene `export PATH=…`-Zeile ausführen.

Updates erfolgen per Fast-forward von `origin/main`. Änderungen im verwalteten Checkout brechen das Update ab; es gibt keinen Reset oder Force-Push. Der Build erfolgt vor dem Austausch der App. Scheitert er, bleibt die installierte Version erhalten. Ein erneuter Startbefehl startet keine zweite Instanz der installierten App.

Test des Installers ohne Eingriff in die echte Installation:

```sh
./Tests/install.sh
```

Installationspfade lassen sich für Tests mit `TINYSTATS_HOME`, `TINYSTATS_APP_DIR` und `TINYSTATS_BIN_DIR` überschreiben. Dieselben Variablen gelten beim späteren CLI-Aufruf.
