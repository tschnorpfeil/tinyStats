# tinyStats

CPU, GPU, RAM und Netzwerk direkt neben der MacBook-Notch. Ohne Notch in der Menüleiste. Ein Klick öffnet die Details.

<img src="docs/images/notch-collapsed.png" alt="tinyStats eingeklappt neben der Notch" width="480">

| Mit Notch | Ohne Notch |
| :---: | :---: |
| ![tinyStats neben der Notch mit geöffneten Details](docs/images/notch.png) | ![tinyStats in der Menüleiste mit geöffneter Karte](docs/images/menu-bar.png) |

*Native Renderings mit Beispielwerten.*

Die drei Balken zeigen von links nach rechts CPU, GPU und RAM. Daneben: Upload ↑ und Download ↓. RAM ist eine Schätzung; GPU-Werte sind nicht auf jeder Hardware verfügbar.

## Installieren

macOS 14+ und Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/tschnorpfeil/tinyStats.git && ./tinyStats/install.sh
```

Danach ein neues Terminal öffnen:

```sh
tinystats          # starten
tinystats stop     # beenden
tinystats update   # aktualisieren
tinystats status   # läuft die App?
tinystats version  # installierte Version
```

Kein Autostart. Kein Dock-Symbol. Falls die Anzeige andere Menüs verdeckt, in den Details „Notch“ ausschalten.

[Installation, Fehlerhilfe und Deinstallation](INSTALL.md)

## Entwickeln

```sh
./build.sh
open tinyStats.app
./Tests/run.sh
./Tests/install.sh
```
